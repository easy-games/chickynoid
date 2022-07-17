local module = {}

local path = script.Parent.Parent
local EffectsModule = require(path.Client.Effects)
local Enums = require(path.Enums)

local FastSignal = require(path.Vendor.FastSignal)
local DeltaTable = require(path.Vendor.DeltaTable)
local ClientMods = require(path.Client.ClientMods)
local BitBuffer = require(path.Vendor.BitBuffer)

module.rockets = {}
module.weapons = {}
module.customWeapons = {}
module.currentWeapon = nil
module.OnBulletImpact = FastSignal.new()
module.OnBulletFire = FastSignal.new()

function module:HandleEvent(client, event)
	if event.t == Enums.EventType.BulletImpact then
		
        --partially decode this packet so we can route it..
        local bitBuffer = BitBuffer(event.b)

        --these two first!
        event.weaponId = bitBuffer:readInt16()
        event.slot = bitBuffer:readByte()

        event.weaponModule = self:GetWeaponModuleByWeaponId(event.weaponId)
        if (event.weaponModule == nil) then
            return
        end
        if (event.weaponModule.UnpackPacket) then
            event = event.weaponModule:UnpackPacket(event)
        end
        
        --Append player
		local player = client:GetPlayerDataBySlotId(event.slot)
        if player == nil then
            return
        end
        event.player = player
        self.OnBulletImpact:Fire(client, event)

        if event.weaponModule and event.weaponModule.ClientOnBulletImpact then
            event.weaponModule:ClientOnBulletImpact(client, event)
        end

        return
    end

    if event.t == Enums.EventType.BulletFire then
		
        --partially decode this packet so we can route it..
        local bitBuffer = BitBuffer(event.b)

        --these two first!
        event.weaponId = bitBuffer:readInt16()
        event.slot = bitBuffer:readByte()

        event.weaponModule = self:GetWeaponModuleByWeaponId(event.weaponId)
        if (event.weaponModule == nil) then
            return
        end
        if (event.weaponModule.UnpackPacket) then
            event = event.weaponModule:UnpackPacket(event)
        end
        
        --Append player
		local player = client:GetPlayerDataBySlotId(event.slot)
        if player == nil then
            return
        end
        event.player = player
        self.OnBulletFire:Fire(client, event)

        if event.weaponModule and event.weaponModule.ClientOnBulletFire then
            event.weaponModule:ClientOnBulletFire(client, event)
        end

        return
    end

    if event.t == Enums.EventType.WeaponDataChanged then
        if event.s == Enums.WeaponData.WeaponAdd then
            print("Added weapon:", event.name)

            local existingWeaponRecord = self.weapons[event.serial]
            if existingWeaponRecord then
                error("Weapon already added: " .. event.name .. " " .. event.serial)
                return
            end
            
            local sourceModule = ClientMods:GetMod("weapons", event.name)
            local weaponRecord = sourceModule.new()
            weaponRecord.serial = event.serial
            weaponRecord.name = event.name
            weaponRecord.client = client
            weaponRecord.weaponModule = module
            weaponRecord.clientState = DeltaTable:DeepCopy(event.serverState)
            weaponRecord.serverState = DeltaTable:DeepCopy(event.serverState)
            weaponRecord.preservePredictedStateTimer = 0
            weaponRecord.serverStateDirty = false
            weaponRecord.totalTime = 0

			-- selene: allow(shadowing)
            function weaponRecord:SetPredictedState()
                --Call this to delay the server from stomping on our state: eg: when firing rapidly
                --when you let off the trigger this will allow the server state to take priority
                weaponRecord.preservePredictedStateTimer = tick() + 0.5 --500ms
            end

            weaponRecord:ClientSetup()

            --Add to inventory
            self.weapons[weaponRecord.serial] = weaponRecord
        end

        --Remove
        if event.s == Enums.WeaponData.WeaponRemove then
            if event.serial ~= nil then
                local weaponRecord = self.weapons[event.serial]
                if weaponRecord == nil then
                    warn("Requested remove weapon not found")
                    return
                end
                print("Removed ", weaponRecord.name)
              
                weaponRecord:ClientRemoved()
              
                self.weapons[weaponRecord.serial] = nil
            end
        end

        if event.s == Enums.WeaponData.WeaponState then
            local weaponRecord = self.weapons[event.serial]
            if weaponRecord == nil then
                warn("Got state for a weapon we dont have.")
                return
            end
            weaponRecord.serverStateDirty = true
            --Apply the delta compressed packet
            weaponRecord.serverState = DeltaTable:ApplyDeltaTable(weaponRecord.serverState, event.deltaTable)
        end

        --Dequip
        if event.s == Enums.WeaponData.Dequip then
            if self.currentWeapon ~= nil then
                self.currentWeapon:ClientDequip()
                self.currentWeapon = nil
            end
        end

        --Equip
        if event.s == Enums.WeaponData.Equip then
            if event.serial ~= nil then
                local weaponRecord = self.weapons[event.serial]
                if weaponRecord == nil then
                    warn("Requested Equip weapon not found")
                    return
                end
                print("Equipped ", weaponRecord.name)
                weaponRecord:ClientEquip();
                self.currentWeapon = weaponRecord
            end
        end

        return
    end
end

function module:ProcessCommand(command)
    --Don't get tricked, this can be invoked multiple times in a single frame if the framerate is low
    if self.currentWeapon ~= nil then
        self.currentWeapon.totalTime += command.deltaTime
        self.currentWeapon:ClientProcessCommand(command)
    end
end

function module:Think(_predictedServerTime, deltaTime)
    --Copy the new server states over?
    for _, weapon in pairs(self.weapons) do
        if weapon.serverStateDirty == true then
            if tick() > weapon.preservePredictedStateTimer then
                weapon.serverStateDirty = false

                weapon.clientState = DeltaTable:DeepCopy(weapon.serverState)
                if self.NewServerState then
                    self:NewServerState()
                end
            end
        end
    end

    if self.currentWeapon ~= nil then
        self.currentWeapon:ClientThink(deltaTime)
    end

end

function module:GetWeaponModuleByWeaponId(weaponId)
    return self.customWeapons[weaponId]
end

function module:Setup(_client)

    local priorities = ClientMods:GetMods("weapons")
    for priority = 0, #(Enums.Priority) - 1 do
        local modules = priorities[priority]
        for name,module in pairs(modules) do
            local customWeapon = module.new()
            table.insert(self.customWeapons, customWeapon)
            --set the id
            customWeapon.weaponId = #self.customWeapons
        end
    end
end


return module
