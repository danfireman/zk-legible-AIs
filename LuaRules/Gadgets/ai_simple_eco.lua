function gadget:GetInfo()
    return {
		name    = "Economist AI",
		desc    = "An simple Cyclops spammer",
		author  = "dyth68",
		date    = "2023-01-23",
		license = "Public Domain",

        layer   = 83,
        enabled = true
    }
end
------------------------------------------------------------
-- TODO 
-- Build close to should not build something already being build nearby, should instead assist
-- -- Define assist build
-- Consider current E plus under construction E
-- Make grid
-- Move build close to to lib


include("LuaRules/Configs/customcmds.h.lua")
include("LuaRules/Configs/constants.lua")
------------------------------------------------------------
-- START INCLUDE
------------------------------------------------------------

local hard = true

local ai_lib_UnitDestroyed, ai_lib_UnitCreated, ai_lib_UnitGiven, ai_lib_Initialize, ai_lib_GameFrame, sqDistance, HandleAreaMex, GetMexSpotsFromGameRules, GetClosestBuildableMetalSpot, GetClosestBuildableMetalSpots = VFS.Include("LuaRules/Gadgets/ai_simple_lib.lua")

local storageDefID = UnitDefNames["staticstorage"].id
local conjurerDefID = UnitDefNames["cloakcon"].id
local pylonDefID = UnitDefNames["energypylon"].id
local solarDefID = UnitDefNames["energysolar"].id
local fusionDefID = UnitDefNames["energyfusion"].id
local singuDefID = UnitDefNames["energysingu"].id
local caretakerDefID = UnitDefNames["staticcon"].id
local cloakfacDefID = UnitDefNames["factorycloak"].id
local mexDefID = UnitDefNames["staticmex"].id

local floor = math.floor
local max = math.max


------------------------------------------------------------
-- Vars
------------------------------------------------------------
local teamdata = {}

local conDefs = {}
local next = next
local Echo = Spring.Echo
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHealth = Spring.GetUnitHealth
local spTestBuildOrder = Spring.TestBuildOrder
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetTeamUnits = Spring.GetTeamUnits
local spGetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitNearestEnemy = Spring.GetUnitNearestEnemy
local spGetFactoryCommands = Spring.GetFactoryCommands
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamUnitDefCount = Spring.GetTeamUnitDefCount
local spGetTeamResources = Spring.GetTeamResources
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetUnitIsDead = Spring.GetUnitIsDead

------------------------------------------------------------
-- Debug
------------------------------------------------------------
local function printThing(theKey, theTable, indent)
	indent = indent or ""
	if (type(theTable) == "table") then
		Echo(indent .. theKey .. ":")
		for a, b in pairs(theTable) do
			printThing(tostring(a), b, indent .. "  ")
		end
	else
		Echo(indent .. theKey .. ": " .. tostring(theTable))
	end
end

------------------------------------------------------------
-- AI
------------------------------------------------------------

-- Eco constants
local MEXER = "mexer"
local GRIDDER = "grider"
local E_MAKER = "emaker"

local function starts_with(str, start)
	if not str or not start then
		return false
	end
	return str:sub(1, #start) == start
end

local function initializeTeams()
	Echo("Initializing teams")
    for _,t in ipairs(Spring.GetTeamList()) do
        local _,_,_,isAI,side = Spring.GetTeamInfo(t)
        if starts_with(Spring.GetTeamLuaAI(t), gadget:GetInfo().name) then
            Echo("Team Super "..t.." assigned to "..gadget:GetInfo().name)
            local pos = {}
            local home_x,home_y,home_z = Spring.GetTeamStartPosition(t)
			teamdata[t] = {
				cons = {},
				conRoles = {},
				mexBuildOwners = {},
				numMexers = 0,
				numGridders = 0,
				numEMakers = 0,
				startpos = {home_x,home_y,home_z}
			}
        end
    end
end

for unitDefID, def in pairs(UnitDefs) do
	if def.isBuilder and (def.canMove or not def.canPatrol) then -- TODO: probably want to exclude facs
		conDefs[unitDefID] = true
	end
end


function gadget:UnitCreated(unitID, unitDefID, teamId)
	--Echo("Unit created called")

	if next(teamdata) == nil then
		initializeTeams()
	end
	if not (teamdata[teamId] == nil) and conDefs[unitDefID] then
		--Echo("is con")
		--printThing("teamdata", teamdata, "")
		teamdata[teamId].cons[unitID] = true
	end
	ai_lib_UnitCreated(unitID, unitDefID, teamId)
end

function gadget:UnitDestroyed(unitID, unitDefID, teamId)
	if teamdata[teamId] then
		if teamdata[teamId].cons[unitID] then
			teamdata[teamId].cons[unitID] = nil
		end
	end
	ai_lib_UnitDestroyed(unitID, unitDefID, teamId)
end

function gadget:Initialize()
	Echo("Initialize called")
	GetMexSpotsFromGameRules()
	if next(teamdata) == nil then
		initializeTeams()
	end
    for teamId,_ in pairs(teamdata) do
		local units = Spring.GetTeamUnits(teamId)
		for i=1, #units do
			local unitID = units[i].unitID
			local DefID = spGetUnitDefID(units[i])
			if conDefs[DefID]  then
				teamdata[teamId].cons[unitID] = true
			end
		end
	end
	ai_lib_Initialize()
end

local function buildCloseTo(unitId, buildId, x, y, z)
	local xx = x
	local yy = y
	local zz = z
	local i = 0
	while (spTestBuildOrder(buildId, xx, yy, zz, 0) == 0) and i < 10000 do
		local signx = (i%2 * 2) - 1
		local signz = (floor(i/2)%2 * 2) - 1
		xx = x + 10 * (i % 100) * signx
		zz = z + 10 * (floor(i/100) % 100) * signz
		yy = max(0, spGetGroundHeight(xx, zz))
		i = i + 1
	end
	if i > 100 then
		Echo("ERROR! Could not place building!")
	end
	spGiveOrderToUnit(unitId, -buildId, {xx, yy, zz, 0}, {shift=true})
	return xx, yy, zz
end

local function assistBuild(conId, unitToConsiderId)
	local buildDefId = spGetUnitDefID ( unitToConsiderId)
	local xx, yy, zz = spGetUnitPosition ( unitToConsiderId)
	spGiveOrderToUnit(conId, -buildDefId, {xx, yy, zz, 0}, {shift=true})
end

local function buildOrAssistCloseTo(unitId, buildId, teamId, x, y, z, maxAssistRange)
	local unitsToConsider
	if maxAssistRange == nil or maxAssistRange == -1 then
		unitsToConsider = spGetTeamUnitsByDefs (teamId, buildId)
	else
		local allTypesUnitsToConsider = spGetUnitsInCylinder (x, z, maxAssistRange, teamId )
		unitsToConsider = {}
		local i = 1
		for _,unitToConsiderId in ipairs(allTypesUnitsToConsider) do
			local unitDefId = spGetUnitDefID(unitToConsiderId)
			if unitDefId == buildId then
				unitsToConsider[i] = unitToConsiderId
				i = i + 1
			end
		end
	end
	for _,unitToConsiderId in ipairs(unitsToConsider) do
		local build = select(5, spGetUnitHealth(unitToConsiderId))
		if build and build < 1 then
			assistBuild(unitId, unitToConsiderId)  -- TODO
			return
		end
	end
	buildCloseTo(unitId, buildId, x, y, z)
end

local function unitVec(x,y)
	return x/sqrt(x*x+y*y), y/sqrt(x*x+y*y)
end

local function isBeingBuilt(unitId)
	local _, _, _, _, buildProgress = spGetUnitHealth(unitId)
	return buildProgress < 1
end

local function placeFac(facDefID, teamId)
	local data = teamdata[teamId]
	if spGetTeamUnitDefCount(teamId, facDefID) == 0 then
		for unitId,_ in pairs(data.cons) do
			local x, y, z = spGetUnitPosition(unitId)
			local xx = x - 150
			local zz = z
			local yy = max(0, spGetGroundHeight(xx, zz))
			buildCloseTo(unitId, facDefID, xx, yy, zz)
			data.startpos = {xx, zz}
			--startpos = {xx, zz}
			--printThing("startpos", thisTeamData.startpos, "")
			--printThing("teamdata", thisTeamData, "")
			--printThing("teamdataAll", teamdata, "")
			spSendLuaRulesMsg('sethaven|' .. xx .. '|' .. yy .. '|' .. zz )
		end
	end
end

local function isXInRange(teamId, x, z, radius, unitDefID, beingBuiltCounts)
	local inRangeUnits = spGetUnitsInCylinder (x, z, radius, teamId)
	for _, unitId in pairs(inRangeUnits) do
		if spGetUnitDefID(unitId) == unitDefID and (beingBuiltCounts or not isBeingBuilt(unitId)) then
			return true
		end
	end
	return false
end

local function needMoreE(teamId)
	local _, _, _, mIncome = spGetTeamResources(teamId, "metal")
	local energy, _, _, _ = spGetTeamResources(teamId, "energy")
	Echo("current e: ")
	Echo(energy)
	local eIncome = spGetTeamRulesParam(teamId, "OD_energyIncome") or 0
	local frame = Spring.GetGameFrame()
	local frameMulti = (1 + frame / (30 * 60 * 3) )
	return eIncome <= mIncome * frameMulti or (eIncome < 10 and energy < 300)
end

local function tryClaimNearestMex(teamId, unitId)
	local mexBuildOwners = teamdata[teamId].mexBuildOwners
	local x, y, z = spGetUnitPosition(unitId)
	local adjustdX, adjustedZ = x + math.random(-100, 100), z + math.random(-100, 100) -- Slight bunching reduction
	local spots = GetClosestBuildableMetalSpots(adjustdX, adjustedZ, teamId)
	if #spots == 0 then
		return false
	else
		local cmdQueue = spGetUnitCommands(unitId, 2)
		if (#cmdQueue == 0) then
			printThing("mexBuildOwners", mexBuildOwners)
			for i,spotData in ipairs(spots) do
				local spot = spotData.bestSpot
				local spotKey = tostring(spot.x) .. "_" .. tostring(spot.z)
				if not mexBuildOwners[spotKey] then
					Echo("Found unclaimed mex " .. spotKey)
					local xx = spot.x
					local zz = spot.z
					local yy = max(0, spGetGroundHeight(xx, zz))
					HandleAreaMex(nil, xx, yy, zz, 100, {alt=false}, {unitId})
					Echo("Claimed mex " .. spotKey)
					return true
				end
			end
		end
	end
	return false
end

local function conRoleOrders(teamId, unitId, thisTeamData)
	-- Keep existing orders
	if spGetUnitCommands(unitId, 0) > 0 then
		return
	end
	local role = thisTeamData.conRoles[unitId]
	--Echo("con role orders")
	--Echo(unitId)
	--Echo(role)
	local x, y, z = spGetUnitPosition(unitId)
	if role == GRIDDER then
		-- TODO
		-- TODO
		-- TODO
		-- TODO
		-- TODO
		-- local mexId = getClosestUngriddedMex(teamId, x, y, z)
		-- local pylonId = getClosestPylonToMex(mexId)
		-- local pylonRadius = thePylonRadius
		-- local x, y, z = getOneDistLengthTowardsUnit(pylonRadius*2,pylonId, mexId)
		buildOrAssistCloseTo(unitId, pylonDefID, teamId, x + 100, y, z - 50, 300)
	elseif role == MEXER then
		tryClaimNearestMex(teamId, unitId)
	elseif role == E_MAKER then
		local eIncome = spGetTeamRulesParam(teamId, "OD_energyIncome") or 0
		if eIncome < 40 then
			HandleAreaMex(nil, x, y, z, 600, {alt=true, ctrl=true}, {unitId}, false)
			local cmdQueue = spGetUnitCommands(unitId, 2)
			if #cmdQueue == 0 then
				buildOrAssistCloseTo(unitId, solarDefID, teamId, x + 100, y, z - 50, 300)
				Echo("solar")
			end
		else
			if eIncome < 100 then
				buildOrAssistCloseTo(unitId, fusionDefID, teamId, x + 100, y, z - 50, 1200)
				Echo("fusion")
			else
				buildOrAssistCloseTo(unitId, singuDefID, teamId, x + 100, y, z - 50, 3000)
				Echo("singu")
			end
		end
	end
end

local function newConRoles(unitId, thisTeamData)
	if not thisTeamData.conRoles[unitId] then
		if thisTeamData.numMexers < 2 then
			thisTeamData.conRoles[unitId] = MEXER
			thisTeamData.numMexers = thisTeamData.numMexers + 1
		elseif thisTeamData.numEMakers < 2 then
			thisTeamData.conRoles[unitId] = E_MAKER
			thisTeamData.numEMakers = thisTeamData.numEMakers + 1
		elseif thisTeamData.numMexers < 3 then
			thisTeamData.conRoles[unitId] = MEXER
			thisTeamData.numMexers = thisTeamData.numMexers + 1
		elseif thisTeamData.numEMakers < 4 then
			thisTeamData.conRoles[unitId] = E_MAKER
			thisTeamData.numEMakers = thisTeamData.numEMakers + 1
		elseif thisTeamData.numGridders < 2 then
			thisTeamData.conRoles[unitId] = GRIDDER
			thisTeamData.numGridders = thisTeamData.numGridders + 1
		else
			thisTeamData.conRoles[unitId] = E_MAKER
			thisTeamData.numEMakers = thisTeamData.numEMakers + 1
		end
		printThing("thisTeamData.conRoles", thisTeamData.conRoles)
		local x, y, z = spGetUnitPosition(unitId)
		Spring.MarkerAddPoint ( x, y, z, thisTeamData.conRoles[unitId], true)
	end
end

local function startAreaConOrders(teamId, unitId)
	local current, storage, _, income = spGetTeamResources(teamId, "metal")
	local facs = spGetTeamUnitsByDefs(teamId, cloakfacDefID)
	local x, y, z = spGetUnitPosition(unitId)
	local facX, facY, facZ = spGetUnitPosition(facs[1])
	--Echo("Storage " .. storage)
	if storage < HIDDEN_STORAGE + 100 and not isXInRange(teamId, facX, facZ, 9000, storageDefID, true)  then
		local xx = x - 100
		local zz = z
		local yy = max(0, spGetGroundHeight(xx, zz))

		buildOrAssistCloseTo(unitId, storageDefID, teamId, xx, yy, zz, 2000)
		return
	end
end

local function newWelderOrders(teamId, unitId, thisTeamData)
	startAreaConOrders(teamId, unitId)
	conRoleOrders(teamId, unitId, thisTeamData)
end


local function oldWelderOrders(teamId, cmdQueue, unitId, thisTeamData)
	local facs = spGetTeamUnitsByDefs(teamId, cloakfacDefID)
	local x, y, z = spGetUnitPosition(unitId)
	-- Rebuild fac
	if #facs == 0 then
		-- TODO
		buildOrAssistCloseTo(unitId, cloakfacDefID, teamId, x + 150, y, z + 50, 2000)
		return
	end

	local startpos = thisTeamData.startpos

	if sqDistance(x,z, startpos[1], startpos[2]) < 1000000 then
		--Echo("new con orders")
		startAreaConOrders(teamId, unitId)
	end

	-- Always reclaim
	--if hard then
	--	spGiveOrderToUnit(unitId, 90, {x, y, z, 300}, {shift=true})
	--end
	conRoleOrders(teamId, unitId, thisTeamData)
end

local function factoryOrders(teamId, unitId, frame)
	if spGetFactoryCommands(unitId, 0) == 0 then
		spGiveOrderToUnit(unitId, -conjurerDefID, {}, {})
		spGiveOrderToUnit(unitId, 115, {1}, {}) -- repeat build
		spGiveOrderToUnit(unitId, 34220, {0}, {}) -- priority low
	end
	if frame > 3000 then
		local current, _, _, income = spGetTeamResources(teamId, "metal")
		if current > 200 then
			spGiveOrderToUnit(unitId, 13921, {1}, {})
		else
			spGiveOrderToUnit(unitId, 13921, {0}, {})
		end
	end
end

local function updateRoleList(teamData)
	for unitId,role in pairs(teamData.conRoles) do
		if spGetUnitIsDead ( unitId ) == nil then
			if role == MEXER then
				teamData.numMexers = teamData.numMexers - 1
			elseif role == GRIDDER then
				teamData.numGridders = teamData.numGridders - 1
			elseif role == E_MAKER then
				teamData.numEMakers = teamData.numEMakers - 1
			end
		end
	end
end

local function populateMexBuildClaimList(teamId, teamData)
	local teamMexBuildOwners = {}
	for unitId,_ in pairs(teamData.cons) do
		local cmdQueue = spGetUnitCommands(unitId, -1) -- TODO: very inefficient
		local mexIsClaimed = false
		for _, cmd in pairs(cmdQueue) do
			if cmd.id == -mexDefID then
				mexIsClaimed = cmd
			end
		end
		if mexIsClaimed then
			local params = mexIsClaimed.params
			local x, z = params[1], params[3]
			local spot = GetClosestBuildableMetalSpot(x, z, teamId)
			local spotKey = tostring(spot.x) .. "_" .. tostring(spot.z)
			teamMexBuildOwners[spotKey] = unitId
		end
	end
	teamData.mexBuildOwners = teamMexBuildOwners
end

function gadget:GameFrame(frame)
	if not gadgetHandler:IsSyncedCode() then
		return
	end
    for teamId, data in pairs(teamdata) do
		local thisTeamData = teamdata[teamId]
		if frame < 5 then
			placeFac(cloakfacDefID, teamId)
			for unitId,_ in pairs(data.cons) do
				local unitDef = spGetUnitDefID(unitId)
				if not (unitDef == cloakfacDefID) then
					newConRoles(unitId, thisTeamData)
				end
			end
		else
			populateMexBuildClaimList(teamId, data)
			updateRoleList(data)
			-- Constructors and factories
			for unitId,_ in pairs(data.cons) do
				local cmdQueue = spGetUnitCommands(unitId, 2)
				local unitDef = spGetUnitDefID(unitId)
				if not isBeingBuilt(unitId) then
					if (#cmdQueue == 0) then
						-- Factories
						if unitDef == cloakfacDefID then
							factoryOrders(teamId, unitId, frame)
						else
							-- Constructors
							oldWelderOrders(teamId, cmdQueue, unitId, thisTeamData)
						end
					end
				else
					if unitDef == cloakfacDefID then
					else
						-- Orders for under construction cons
						newWelderOrders(teamId, unitId, thisTeamData)
						newConRoles(unitId, thisTeamData)
					end
				end
			end
			for _,unitId in ipairs(spGetTeamUnitsByDefs(teamId, caretakerDefID)) do
				--Echo("Found caretaker")
				local cmdNum = spGetUnitCommands(unitId, 0)
				if cmdNum == 0 then
					--Echo("Giving caretaker order")
					local x, y, z = spGetUnitPosition(unitId)
					spGiveOrderToUnit(unitId, CMD.PATROL, {x+100, y, z+100}, 0)
				end
			end
		end
	end
	ai_lib_GameFrame(frame)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, teamID)
	ai_lib_UnitGiven(unitID, unitDefID, newTeamID, teamID)
end

function gadget:GameStart() 
    -- Initialise AI for all teams that are set to use it
	Echo("Game start called")
	if next(teamdata) == nil then
		initializeTeams()
	end
end
Echo("Reached EOF3")