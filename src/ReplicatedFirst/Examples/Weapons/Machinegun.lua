local MachineGunModule = {}
MachineGunModule.__index = MachineGunModule

local path = game.ReplicatedFirst.Packages.Chickynoid
local EffectsModule = require(path.Client.Effects)
local WriteBuffer = require(path.Shared.Vendor.WriteBuffer)
local ReadBuffer = require(path.Shared.Vendor.ReadBuffer)
local ServerMods = nil 
local Enums = require(path.Shared.Enums)

function MachineGunModule.new()
    local self = setmetatable({
        rateOfFire = 0.08,
        serial = nil,
        name = nil,
        client = nil,
        weaponModule = nil,
        clientState = nil,
        serverState = nil,
        preservePredictedStateTimer = 0,
        serverStateDirty = false,
        playerRecord = nil,
        state = {},
        previousState = {},
    }, MachineGunModule)
    return self
end

--This module is cloned per player on client/server
function MachineGunModule:ClientThink(_deltaTime)
    local gui = self.client:GetGui()
    local state = self.clientState

    local counter = gui:FindFirstChild("AmmoCounter", true)
    if counter then
        counter.Text = state.ammo .. " / " .. state.maxAmmo
    end
end

function MachineGunModule:ClientProcessCommand(command)
    local currentTime = self.totalTime
    local state = self.clientState

    --Predict firing a bullet
    if command.f and command.f > 0 and command.fa then
        if state.ammo > 0 and currentTime > state.nextFire then
            --put weapon on cooldown
            state.ammo -= 1
            state.nextFire = currentTime + state.fireDelay
            self:SetPredictedState() --Flag that we predicted the state, this will stop the server value from overriding it for a moment (eg: firing rapidly)

            self.client:DebugMarkAllPlayers(tostring(state.ammo+1))

            local clientChickynoid = self.client:GetClientChickynoid()
            if clientChickynoid then
                local origin = clientChickynoid.simulation.state.pos
                local dest = command.fa

                local vec = (dest - origin).Unit

                --Do some local effects
                local clone = EffectsModule:SpawnEffect("Tracer", origin + vec * 2)
                clone.CFrame = CFrame.lookAt(origin, origin + vec)
            end
        end
    end
end

function MachineGunModule:ClientSetup() end

function MachineGunModule:ClientEquip() end

function MachineGunModule:ClientDequip() end

--Warning! - you might not have this weapon locally
--This is far more akin to a static method, and is provided so you can render client effects
function MachineGunModule:ClientOnBulletImpact(_client, event) 
    
    --WeaponModule
    if event.normal then
        if event.surface == 0 then
            local effect = EffectsModule:SpawnEffect("ImpactWorld", event.position)
            local cframe = CFrame.lookAt(event.position, event.position + event.normal)
            effect.CFrame = cframe
        end
        if event.surface == 1 then
            local effect = EffectsModule:SpawnEffect("ImpactPlayer", event.position)
            local cframe = CFrame.lookAt(event.position, event.position + event.normal)
            effect.CFrame = cframe
        end
    end

    --we didn't fire it, play the fire effect
    if event.player.userId ~= game.Players.LocalPlayer.UserId then
        --Do some local effects
        local origin = event.origin
        local vec = (event.position - event.origin).Unit
        local clone = EffectsModule:SpawnEffect("Tracer", origin + vec * 2)
        clone.CFrame = CFrame.lookAt(origin, origin + vec)
    end
end

function MachineGunModule:ServerSetup()
    self.state.maxAmmo = 30
    self.state.ammo = self.state.maxAmmo
    self.state.fireDelay = self.rateOfFire
    self.state.nextFire = 0 --Questionable about wether client needs this

    self.timeOfLastShot = 0 --Not part of state, doesnt need to go to client
end

function MachineGunModule:ServerThink(_deltaTime)
    --update cooldowns

    local currentTime = self.totalTime
    local state = self.state

    --Auto reload
    if state.ammo == 0 and currentTime > self.timeOfLastShot + 2 then
        state.ammo = 30
    end
end

function MachineGunModule:ServerProcessCommand(command)
    --actually Fire a bullet
    local currentTime = self.totalTime
    local state = self.state

    if command.f and command.f > 0 and command.fa then
        if state.ammo > 0 and currentTime > state.nextFire then
            --put weapon on cooldown
            state.ammo -= 1
            state.nextFire = currentTime + state.fireDelay

            self.timeOfLastShot = currentTime

            local debugText = tostring(state.ammo+1)

            local serverChickynoid = self.playerRecord.chickynoid
            if serverChickynoid then
                local origin = serverChickynoid.simulation.state.pos
                local dest = command.fa
                local vec = (dest - origin).Unit
                local pos, normal, otherPlayer = self.weaponModule:QueryBullet(
                    self.playerRecord,
                    self.server,
                    origin,
                    vec,
                    command.serverTime,
                    debugText
                )
                local surface = 0 --Surface type
                if otherPlayer then
                    surface = 1 --(blood!)
                end

                --Send an event to render this firing
                local event = {}
                event.t = Enums.EventType.BulletImpact --Event identifier
                event.b = self:BuildPacketString(origin, pos, normal, surface)

                self.playerRecord:SendEventToClients(event)

                --Do the damage
                if otherPlayer then
					--Use the hitpoints mod to damage them!
					
					if (ServerMods == nil) then
						ServerMods = require(game.ServerScriptService.Packages.Chickynoid.Server.ServerMods)
					end
					
                    local HitPoints = ServerMods:GetMod("servermods", "Hitpoints")
                    if HitPoints then
                        HitPoints:DamagePlayer(otherPlayer, 10)
                    end
                end
            end
        end
    end
end


function MachineGunModule:BuildPacketString(origin, position, normal, surface)
	
	local buf = WriteBuffer.new()
    
    --these two first always
	buf:WriteI16(self.weaponId)
	buf:WriteU8(self.playerRecord.slot)
		
	buf:WriteVector3(origin)
	buf:WriteVector3(position)
	buf:WriteU8(surface)

    if (normal) then
		buf:WriteU8(1)
		buf:WriteVector3(normal)
    else
		buf:WriteU8(0)
	end	
							
	return buf:GetBuffer()
end

function MachineGunModule:UnpackPacket(event)

	local buf = ReadBuffer.new(event.b)
	
    --these two first always
	event.weaponID = buf:ReadI16()
	event.slot = buf:ReadU8()

	event.origin = buf:ReadVector3()
	event.position = buf:ReadVector3()
	event.surface = buf:ReadU8()

	local hasNormal = buf:ReadU8()
    if (hasNormal > 0) then
		event.normal = buf:ReadVector3()
    end

    return event
end

 

function MachineGunModule:ServerEquip() end

function MachineGunModule:ServerDequip() end

function MachineGunModule:ClientRemoved() end

function MachineGunModule:ServerRemoved() end


return MachineGunModule
