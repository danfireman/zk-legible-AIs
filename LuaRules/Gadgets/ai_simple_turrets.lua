function gadget:GetInfo()
    return {
        name    = "Tanks AI",
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
-- Stop mex spot cheating
-- magic numbers bad
-- Don't excess
-- Dedup fusion
-- Retreat zones not working
------------------------------------------------------------
-- Other strats:
-- Cloak
-- 1 con naked expand and 1 con 4 solars
-- Glaive swarm rampages, avoid enemy unless overwhelm

------------------------------------------------------------
-- Team AIs:
-- Just eco (grid, singu)
-- Defender (tries to porc mid, starts with 1/2 porc clusters, escalates to Cerb)
-- Silo - rushes silo and uses Widow/Owl to scout. Hits statics with eos, unshielded clusters (definition?) with inferno, hits antis with Shockley if loaded nuke available
-- Air - goes owl -> swift x2 -> Raven -> Phoenix. Employs threat zones to avoid AA
-- Nuke - rushes nuke, then makes airfac (or plate if possible) and then swift scouts for anti. Will scout when nuke is built and will fire at largest undefended area. If none over 5k exists then will wait until one does and scout again in another 4-5 mins
-- Frontliner - Makes skirms and a few riots. Goes where there isn't a friendly Defender or Shieldball. Pressures and avoids stingers
-- Interceptor - Makes glaives along front line, attempts to intercept smaller groups of raiders or hit undefended skirms and assaults
-- Sneak - Rushes Athena, will attempt to rez anything not in range of AA or on front. Will then attempt to sneak to some back area that does not have anything else in visual range, sink an Iris and then make a Djinn, which will pull in interceptor and ravager
-- Ravager - Makes ravager swarms, attempting to attack lightly defended areas. Will build up 5 for first run, then doubles size each time
-- Shieldball - Makes Felon->4 Thug->Outlaw->Aspis. Outlaw at enemy-facing part of ball. Retreats when shield is under 1/2 of total. Will make lobfac (or plate) and use lobster to retreat at >4000m. Will upgrade to second lobster for attack and retreat.
-- Snitch - Will make Snitch and Iris. Tries to find balls of enemy units and kill them
-- Arti-king - Makes Mace->Lance->Halberd. Scouts with buttoned down Halberd. Has Mace near Lance

------------------------------------------------------------
-- Standard behaviours:
-- Basic eco - takes mexes and makes one solar next to each
-- Area avoidance - Manages areas to avoid
--- Cerberus, desolator, lucifer avoidance - Avoids range of these things
-- Pathfinding cancelling - States whether a location is reachable and cancels impossible orders


include("LuaRules/Configs/customcmds.h.lua")
include("LuaRules/Configs/constants.lua")
------------------------------------------------------------
-- START INCLUDE
------------------------------------------------------------

local hard = true

local ai_lib_UnitDestroyed, ai_lib_UnitCreated, ai_lib_UnitGiven, ai_lib_Initialize, ai_lib_GameFrame, sqDistance, HandleAreaMex, GetMexSpotsFromGameRules, GetClosestBuildableMetalSpot = VFS.Include("LuaRules/Gadgets/ai_simple_lib.lua")

local storageDefID = UnitDefNames["staticstorage"].id
local blitzDefID = UnitDefNames["tankheavyraid"].id
local cyclopsDefID = UnitDefNames["tankheavyassault"].id
local welderDefID = UnitDefNames["tankcon"].id
local fusionDefID = UnitDefNames["energyfusion"].id
local caretakerDefID = UnitDefNames["staticcon"].id
local platetankDefID = UnitDefNames["platetank"].id
local tankfacDefID = 410 -- UnitDefNames["factorytank"].id
local lotusDefID = UnitDefNames["turretlaser"].id

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
local spGetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitNearestEnemy = Spring.GetUnitNearestEnemy
local spGetFactoryCommands = Spring.GetFactoryCommands
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamUnitDefCount = Spring.GetTeamUnitDefCount
local spGetTeamResources = Spring.GetTeamResources
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
------------------------------------------------------------
-- Debug
------------------------------------------------------------
local function printThing(theKey, theTable, indent)
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
			teamdata[t] = {cons = {}}
        end
    end
end

for unitDefID, def in pairs(UnitDefs) do
	if def.isBuilder and (def.canMove or not def.canPatrol) then
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

local function unitVec(x,y)
	return x/sqrt(x*x+y*y), y/sqrt(x*x+y*y)
end

local function isBeingBuilt(unitId)
	local _, _, _, _, buildProgress = spGetUnitHealth(unitId)
	return buildProgress < 1
end

local startpos = {}
local function placeFac(facDefID, teamId)
	local data = teamdata[teamId]
	if spGetTeamUnitDefCount(teamId, facDefID) == 0 then
		for unitId,_ in pairs(data.cons) do
			local x, y, z = spGetUnitPosition(unitId)
			local xx = x - 100
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

local function retreatPos(startpos)
	local xx, yy, zz = startpos[1] - 100, 0, startpos[2]
	yy = max(0, spGetGroundHeight(xx, zz))
	return xx, yy, zz
end

local function newWelderOrders(teamId, unitId, data)
	local current, storage, _, income = spGetTeamResources(teamId, "metal")
	local facs = spGetTeamUnitsByDefs(teamId, tankfacDefID)
	local x, y, z = spGetUnitPosition(unitId)
	local facX, facY, facZ = spGetUnitPosition(facs[1])
	-- Keep existing orders
	if spGetUnitCommands(unitId, 0) > 0 then
		return
	end
	--Echo("Storage " .. storage)
	if storage < HIDDEN_STORAGE + 100 and not isXInRange(teamId, facX, facZ, 9000, storageDefID, true)  then
		local xx = x - 100
		local zz = z
		local yy = max(0, spGetGroundHeight(xx, zz))

		buildCloseTo(unitId, storageDefID, xx, yy, zz)
		return
	end

	-- Assist fac
	if (spGetTeamUnitDefCount(teamId, welderDefID) > 3) then -- not sure why this is needed, but autoassist doesn't always work
		local numCaretakers = spGetTeamUnitDefCount(teamId, caretakerDefID)
		if income > 30  + 10 * numCaretakers then
			local startpos = data.startpos
			if startpos then
				local rx, ry, rz = retreatPos(startpos)
				buildCloseTo(unitId, caretakerDefID, rx + 50, ry, rz - 100)
				return
			end
		end
		if (current > 200) then
			if income > 40 and spGetTeamUnitDefCount(teamId, platetankDefID) < 8 then
				local posX = facX + ((income > 80) and -150 or 150)
				local posZ = facZ + ((income%40 > 20) and -250 or 250)
				buildCloseTo(unitId, platetankDefID, posX, y, posZ)
				return
			end
			for _,facId in ipairs(facs) do
				spGiveOrderToUnit(unitId, 25, {facId}, {right=true, coded=16})
			end
			for _,facId in ipairs(spGetTeamUnitsByDefs(teamId, platetankDefID)) do
				spGiveOrderToUnit(unitId, 25, {facId}, {right=true, coded=16})
			end
			return

		end
	end
	-- Make lotus
	if (spGetTeamUnitDefCount(teamId, welderDefID) > 1) and not isXInRange(teamId, facX, facZ, 200, lotusDefID, true) then
		buildCloseTo(unitId, lotusDefID, facX + 100, y, facZ - 150)
		return
	end
	--fusion building
	local currentE, _, _, incomeE, expenseE = spGetTeamResources(teamId, "enery")
	if hard and (unitId%4 == 0) and (income > 40) then
		if ((incomeE - income < income) or currentE < 400) then
			local x, y, z = spGetUnitPosition(unitId)
			buildCloseTo(unitId, fusionDefID, x + 100, y, z - 250)
			return
		end
	end
end

local function oldWelderOrders(teamId, cmdQueue, unitId, thisTeamData)
	local facs = spGetTeamUnitsByDefs(teamId, tankfacDefID)
	local x, y, z = spGetUnitPosition(unitId)
	-- Rebuild fac
	if #facs == 0 then
		-- TODO
		buildCloseTo(unitId, tankfacDefID, x + 50, y, z + 50)
		return
	end

	-- First try heal nearby Cyclops
	local cyclopsToHeal
	for _,cyclopsId in ipairs(spGetTeamUnitsByDefs(teamId, cyclopsDefID)) do
		local health, maxhealth, _, _, buildProgress = spGetUnitHealth(cyclopsId)
		if (health < maxhealth * 0.3) and buildProgress == 1 then
			cyclopsToHeal = cyclopsId
		end
	end
	if cyclopsToHeal and (unitId%2 == 1) then
		spGiveOrderToUnit(unitId, 40, {cyclopsToHeal}, {right=true, coded=16}) -- repair
		return
	end

	local startpos = thisTeamData.startpos

	if sqDistance(x,z, startpos[1], startpos[2]) < 1000000 then
		--Echo("new con orders")
		newWelderOrders(teamId, unitId, thisTeamData)
	end
	local adjustdX, adjustedZ = x + math.random(-100, 100), z + math.random(-100, 100) -- Slight bunching reduction
	local spot = GetClosestBuildableMetalSpot(adjustdX, adjustedZ, teamId)
	-- Always reclaim
	if hard then
		spGiveOrderToUnit(unitId, 90, {x, y, z, 300}, {shift=true})
	end
	if spot == nil then
		local enemyUnit = spGetUnitNearestEnemy(unitId, 9999, true)
		local xx, yy, zz = spGetUnitPosition(enemyUnit) -- TODO: null check
		spGiveOrderToUnit(unitId, CMD.MOVE, {xx, yy, zz}, {shift=true})
	else
		local xx = spot.x
		local zz = spot.z
		local yy = max(0, spGetGroundHeight(xx, zz))

		HandleAreaMex(nil, xx, yy, zz, 100, {alt=true}, {unitId}, true)
		cmdQueue = spGetUnitCommands(unitId, 2)
		if (#cmdQueue == 0) then
			local startX,startY = thisTeamData.startpos
			local spot = GetClosestBuildableMetalSpot(x, z, teamId)
			--local unitX, unitZ =  unitVec((Game.mapSizeX - x) - x, (Game.mapSizeZ - z) - z)
			xx = spot.x
			zz = spot.z
			yy = max(0, spGetGroundHeight(xx, zz))
			spGiveOrderToUnit(unitId, CMD.MOVE, {xx, y, zz},{shift=true})
		end
	end
end

local function factoryOrders(teamId, unitId, frame)
	if spGetFactoryCommands(unitId, 0) == 0 then
		spGiveOrderToUnit(unitId, -welderDefID, {}, {})
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
		if (spGetFactoryCommands(unitId, 0) == 1) and (spGetTeamUnitDefCount(teamId, welderDefID) > 5) and (income > 20) then
			spGiveOrderToUnit(unitId, -blitzDefID, {}, {})
		end
		if (spGetFactoryCommands(unitId, 0) == 2) and ((spGetTeamUnitDefCount(teamId, welderDefID) > 10) or (income > 50) or frame > 30 * 60 * 6) then  -- Cyclops at 6 minutes
			spGiveOrderToUnit(unitId, -welderDefID, {}, {})
			spGiveOrderToUnit(unitId, -welderDefID, {}, {})
			spGiveOrderToUnit(unitId, -welderDefID, {}, {})
			spGiveOrderToUnit(unitId, -cyclopsDefID, {}, {})
		end
	end
end

local function blitzOrders(unitId, data)
	local health, maxhealth = spGetUnitHealth(unitId)
	local cmdQueue = spGetUnitCommands(unitId, 2)
	if (#cmdQueue == 0) then
		local x, y, z = spGetUnitPosition(unitId)
		--local startPosDist = sqDistance(x,z, thisTeamData.startpos[1], thisTeamData.startpos[2])
		local startpos = data.startpos
		if startpos then
			local startPosDist = sqDistance(x,z, startpos[1], startpos[2])
			if startPosDist > 100000 or (health > maxhealth * 0.95) then
				local enemyUnit = spGetUnitNearestEnemy(unitId, 9999, true)
				--local xx, yy, zz = Game.mapSizeX - thisTeamData.startpos[1], 0, Game.mapSizeZ - thisTeamData.startpos[2]
				local xx, yy, zz = Game.mapSizeX - startpos[1], 0, Game.mapSizeZ - startpos[2]
				yy = max(0, spGetGroundHeight(xx, zz))
				if enemyUnit then
					xx, yy, zz = spGetUnitPosition(enemyUnit)
				end
				spGiveOrderToUnit(unitId, CMD.FIGHT, {xx, yy, zz}, 0)
			end
		else
			Echo("No startpos :(")
			local xx = math.random(1, Game.mapSizeX)
			local zz = math.random(1, Game.mapSizeZ)
			local yy = max(0, spGetGroundHeight(xx, zz))
			spGiveOrderToUnit(unitId, CMD.FIGHT, {xx, 0, zz}, 0)
		end
	end
	if hard then
		--Echo("health " .. health)
		if (health < maxhealth * 0.3) then
			local x, y, z = spGetUnitPosition(unitId)
			--Echo("gadget name: " .. gadget:GetInfo().name )
			--printThing("teamdataAll", teamdata, "")
			--printThing("teamdata", thisTeamData, "")
			--printThing("startpos", thisTeamData.startpos, "")
			--printThing("startpos1", thisTeamData.startpos[1], "")
			-- TODO: Pick better pos
			--local xx, yy, zz = thisTeamData.startpos[1] - 100, 0, thisTeamData.startpos[2]
			local startpos = data.startpos
			if startpos then
				local xx, yy, zz = retreatPos(startpos)
				if not #cmdQueue == 1 or (cmdQueue[1] and not cmdQueue[1].id == CMD.MOVE) then  -- TODO: Why the heck is the middle condition required?
					spGiveOrderToUnit(unitId, CMD.MOVE, {xx, yy, zz}, 0)
				end
			else
				Echo("No startpos :((")
				--printThing("data", data, "")
				--printThing("thisTeamData", thisTeamData, "")
				--printThing("teamdata", teamdata, "")
			end
		end
	end
end

function gadget:GameFrame(frame)
	if not gadgetHandler:IsSyncedCode() then
		return
	end
    for teamId, data in pairs(teamdata) do
		local thisTeamData = teamdata[teamId]
		if frame < 5 then
			placeFac(tankfacDefID, teamId)
		else
			-- Constructors and factories
			for unitId,_ in pairs(data.cons) do
				local cmdQueue = spGetUnitCommands(unitId, 2)
				if not isBeingBuilt(unitId) then
					if (#cmdQueue == 0) then
						local x, y, z = spGetUnitPosition(unitId)
						local unitDef = spGetUnitDefID(unitId)
						-- Factories
						if unitDef == tankfacDefID or unitDef == platetankDefID then
							factoryOrders(teamId, unitId, frame)
						else
							-- Constructors
							oldWelderOrders(teamId, cmdQueue, unitId, thisTeamData)
						end
					end
				else
					-- Orders for under construction welders
					newWelderOrders(teamId, unitId, thisTeamData)
				end
			end
			for _,unitId in ipairs(spGetTeamUnitsByDefs(teamId, blitzDefID)) do
				if not isBeingBuilt(unitId) then
					blitzOrders(unitId, data)
				end
			end
			for _,unitId in ipairs(spGetTeamUnitsByDefs(teamId, cyclopsDefID)) do
				if not isBeingBuilt(unitId) then
					blitzOrders(unitId, data)
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