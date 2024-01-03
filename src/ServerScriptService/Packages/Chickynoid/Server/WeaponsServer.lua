--!native
local module = {}

module.rocketSerial = 0
module.rockets = {}
module.weaponSerials = 0
module.customWeapons = {}

local path = game.ReplicatedFirst.Packages.Chickynoid

local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local Enums = require(path.Shared.Enums)
local Antilag = require(script.Parent.Antilag)
local ServerMods = require(script.Parent.ServerMods)

local requiredMethods = {
    "ClientThink",
    "ServerThink",
    "ClientProcessCommand",
    "ServerProcessCommand",
    "ClientSetup",
    "ServerSetup",
    "ClientEquip",
    "ServerEquip",
    "ClientDequip",
    "ServerDequip",
    "ClientRemoved",
    "ServerRemoved",
}

--Server Lifecycle:
--  ServerSetup
--    ServerEquip
--      ServerProcessCommand (x many?)
--      ServerThink
--    ServerDequip 
--  ServerRemoved

--Client Lifecycle:
--  ClientSetup
--    ClientEquip
--      ClientProcessCommand (x many?)
--      ClientThink
--    ClientDequip
--  ClientRemoved

--Note, ProcesCommand, Think and Dequip all only get called if this is item is equipped

function module:Setup(server)

    local weapons = ServerMods:GetMods("weapons")
    
    for name, module in pairs(weapons) do
       
        local customWeapon = module
		
		local doError = false
        for _, values in pairs(requiredMethods) do
            if customWeapon[values] == nil then
				warn("WeaponModule " .. name .. " missing " .. values .. " implementation.")
				doError = true
            end
		end
		
		if (doError) then
			error("Aborting module")
		end
        table.insert(self.customWeapons, customWeapon)
        --set the id
        customWeapon.weaponId = #self.customWeapons
    end
end

function module:OnPlayerConnected(server, playerRecord)
    playerRecord.weapons = {}

    playerRecord.currentWeapon = nil

	-- selene: allow(shadowing)
    function playerRecord:DequipWeapon()
        if self.currentWeapon ~= nil then
            self.currentWeapon:ServerDequip()

            local event = {}
            event.t = Enums.EventType.WeaponDataChanged
            event.s = Enums.WeaponData.Dequip
            self:SendEventToClient(event)
            
            self.currentWeapon = nil
        end
    end

	-- selene: allow(shadowing)
    function playerRecord:EquipWeapon(serial)
        
        self:DequipWeapon()

        if serial ~= nil then
            local weaponRecord = self.weapons[serial]
            if weaponRecord == nil then
                warn("Weapon not found:", serial)
                return
            end

            self.currentWeapon = weaponRecord
            weaponRecord:ServerEquip()

            local event = {}
            event.t = Enums.EventType.WeaponDataChanged
            event.s = Enums.WeaponData.Equip
            event.serial = serial
            self:SendEventToClient(event)
        end
    end

	-- selene: allow(shadowing)
    function playerRecord:GetWeapons()
        return self.weapons
    end

	-- selene: allow(shadowing)
    function playerRecord:RemoveWeaponRecord(weaponRecord)

        if (self.currentWeapon == weaponRecord) then
            self:DequipWeapon()
        end
        
        weaponRecord:ServerRemoved()

        local event = {}
        event.t = Enums.EventType.WeaponDataChanged
        event.s = Enums.WeaponData.WeaponRemove
        event.serial = weaponRecord.serial
        self:SendEventToClient(event)
        
        self.weapons[weaponRecord.serial] = nil
    end
 
	-- selene: allow(shadowing)
    function playerRecord:ClearWeapons()
        for _, weaponRecord in pairs(self.weapons) do
            self:RemoveWeaponRecord(weaponRecord)
        end
    end

	-- selene: allow(shadowing)
    function playerRecord:AddWeaponByName(name, equip, recordParam)
        local sourceModule = ServerMods:GetMod("weapons", name)
        if sourceModule == nil then
            warn("Weapon ", name, " not found!")
            return
        end

        local weaponRecord = sourceModule.new(recordParam)
        weaponRecord.serial = module.weaponSerials
        module.weaponSerials += 1

        weaponRecord.playerRecord = playerRecord
        weaponRecord.server = server
        weaponRecord.weaponModule = module
        weaponRecord.totalTime = 0
        weaponRecord.state = {}
        weaponRecord.previousState = {}

        weaponRecord:ServerSetup()

        --Add to inventory
        playerRecord.weapons[weaponRecord.serial] = weaponRecord

        local event = {}
        event.t = Enums.EventType.WeaponDataChanged
        event.serial = weaponRecord.serial
        event.name = name
        event.s = Enums.WeaponData.WeaponAdd
        event.serverState = weaponRecord.state
        playerRecord:SendEventToClient(event)

        --Last state, as seen by this client
        weaponRecord.previousState = DeltaTable:DeepCopy(weaponRecord.state)

        --Equip it
        if equip then
            self:EquipWeapon(weaponRecord.serial)
        end

        return weaponRecord;
    end

	-- selene: allow(shadowing)
    function playerRecord:ProcessWeaponCommand(command)
        if self.currentWeapon ~= nil then
            self.currentWeapon.totalTime += command.deltaTime
            self.currentWeapon:ServerProcessCommand(command)
        end
    end

    -- Happens after the command for this frame
	-- selene: allow(shadowing)
    function playerRecord:WeaponThink(deltaTime)
        if self.currentWeapon ~= nil then
            self.currentWeapon:ServerThink(deltaTime)

            --Check if we need updates
            local deltaTable, numChanges = DeltaTable:MakeDeltaTable(self.currentWeapon.previousState, self.currentWeapon.state)

            if numChanges > 0 then
                --Send the client the change to the state
                local event = {}
                event.t = Enums.EventType.WeaponDataChanged
                event.s = Enums.WeaponData.WeaponState
                event.serial = self.currentWeapon.serial
                event.deltaTable = deltaTable
                playerRecord:SendEventToClient(event)

                --Record what they saw
                self.currentWeapon.previousState = DeltaTable:DeepCopy(self.currentWeapon.state)
            end
        end
    end
end

function module:QueryBullet(playerRecord, server, origin, dir, serverTime, debugText, raycastParams, range)
    Antilag:PushPlayerPositionsToTime(playerRecord, serverTime, debugText)

    if range == nil then
        range = 1000
    end

    local rayCastResult = game.Workspace:Raycast(origin, dir * range, raycastParams)

    local pos = nil
    local normal = nil
    local otherPlayerRecord = nil
    local hitInstance = nil
    if rayCastResult == nil then
        pos = origin + dir * range
    else
        pos = rayCastResult.Position
        normal = rayCastResult.Normal
        hitInstance = rayCastResult.Instance

        --See if its a player
        local userId = rayCastResult.Instance:GetAttribute("player")
        if userId then
            otherPlayerRecord = server:GetPlayerByUserId(userId)
        end
    end

    Antilag:Pop() --Don't forget!

    return pos, normal, otherPlayerRecord, hitInstance
end

function module:QueryShotgun(playerRecord, server, origins, directions, serverTime, debugText, raycastParams, range)

    Antilag:PushPlayerPositionsToTime(playerRecord, serverTime, debugText)

    if range == nil then
        range = 1000
    end
    
    local results = {}
    
    for counter = 1, #origins do 
        local origin = origins[counter]
        local dir = directions[counter]
        if (dir == nil) then 
            continue
        end
    
        local rayCastResult = game.Workspace:Raycast(origin, dir * range, raycastParams)

        if rayCastResult == nil then
            local record = {}
            record.pos =  origin + dir * range
            record.origin = origin
            record.dir = dir
            table.insert(results, record)
        else
            local record = {}
            record.pos = rayCastResult.Position
            record.normal = rayCastResult.Normal
            record.hitInstance = rayCastResult.Instance
            record.origin = origin
            record.dir = dir

            --See if its a player
            local userId = rayCastResult.Instance:GetAttribute("player")
            if userId then
                record.otherPlayerRecord = server:GetPlayerByUserId(userId)
            end
            table.insert(results, record)
        end
    end

    Antilag:Pop() --Don't forget!

    return results
end


function module:Think(server, deltaTime)
	for _, playerRecord in pairs(server:GetPlayers()) do
		playerRecord:WeaponThink(deltaTime)	
    end

    for serial, rocket in pairs(self.rockets) do
        local timePassed = server.serverSimulationTime - rocket.o

        local oldPos = rocket.pos

        if oldPos == nil then
            oldPos = rocket.p
        end
        rocket.pos = rocket.p + (rocket.v * rocket.c * timePassed)

        --Trace a line
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { game.Workspace.Terrain, server:GetCollisionRoot() }
        local results = game.Workspace:Raycast(oldPos, rocket.pos - oldPos, params)
        if results ~= nil then
            timePassed = 1000 --Boom
            rocket.n = results.Normal
        else
            local result = self:RayTestPlayers(oldPos, rocket.pos - oldPos, server)
            if result ~= nil then
                timePassed = 1000
                rocket.n = Vector3.new(0, 1, 0)
            end
        end

        if timePassed > 5 then
            local event = {}
            event.t = Enums.EventType.RocketDie
            event.s = rocket.s
            event.n = rocket.n
            server:SendEventToClients(event)

            self.rockets[serial] = nil
            self:DoExplosion(server, rocket.pos, 15, 60)
        end
    end
end

function module:DoExplosion(server, explosionPos, _radius, force)
    --Get All the players
    for _, playerRecord in pairs(server.playerRecords) do
        local sim = playerRecord.chickynoid.simulation
        local pos = sim.state.pos

        local vec = pos - explosionPos
        if vec.magnitude < 10 then
            --Always upwards
            local dir = vec.unit
            dir = Vector3.new(dir.x, math.abs(dir.y), dir.z)
            sim.state.vel += dir.unit * force
        end
    end
end

function module:RayTestPlayers(rayOrigin, vec, server)
    --[[
    --Get All the players
    for key,playerRecord in pairs(server.playerRecords) do

        local sim = playerRecord.chickynoid.simulation
        local pos = sim.state.pos

        local vec = pos - explosionPos
        if (vec.magnitude < 10) then

            --Always upwards
            local dir = vec.unit
            dir = Vector3.new(dir.x, 1, dir.z)
            sim.state.vel += dir.unit * force
        end  
    end
    ]]
    --
    if server.worldRoot == nil then
        return nil
    end

    local rayCastResult = game.Workspace:Raycast(rayOrigin, vec)
    return rayCastResult
end

return module