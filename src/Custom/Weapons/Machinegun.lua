local MachineGunModule = {}
local MachineGunModule.__index = MachineGunModule

local path = script.Parent.Parent.Parent
local EffectsModule = require(path.Client.Effects)
local Enums = require(path.Enums)

function MachineGunModule.new()
    local self = setmetatable({
        rateOfFire = 0.08,
    }, MachineGunModule)
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
    local currentTime = self.client.estimatedServerTime
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
function MachineGunModule:ClientOnBulletImpact(_client, _event) end

function MachineGunModule:ServerSetup()
    self.state.maxAmmo = 30
    self.state.ammo = self.state.maxAmmo
    self.state.fireDelay = module.rateOfFire
    self.state.nextFire = 0 --Questionable about wether client needs this

    self.timeOfLastShot = 0 --Not part of state, doesnt need to go to client
end

function MachineGunModule:ServerThink(_deltaTime)
    --update cooldowns

    local currentTime = self.server.serverSimulationTime
    local state = self.state

    --Auto reload
    if state.ammo == 0 and currentTime > self.timeOfLastShot + 2 then
        state.ammo = 30
    end
end

function MachineGunModule:ServerProcessCommand(command)
    --actually Fire a bullet
    local currentTime = self.server.serverSimulationTime
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

                --Send an event to render this firing
                --Todo: rewrite this to use packed bytes- this could get very data heavy in a fire fight!
                local event = {}
                event.o = origin --Origin
                event.p = pos --Impact point
                event.n = normal --Impact normal (no normal means we hit the sky)
                event.t = Enums.EventType.BulletImpact --Event identifier
                event.s = self.playerRecord.slot --Which player fired this
                event.w = self.weaponId --Id of this weapon (Machinegun?)

                event.m = 0 --Surface type
                if otherPlayer then
                    event.m = 1 --(blood!)
                end
                self.playerRecord:SendEventToClients(event)

                --Do the damage
                if otherPlayer then
                    --Use the hitpoints mod to damage them!
                    local HitPoints = self.server:GetMod("Hitpoints")
                    if HitPoints then
                        HitPoints:DamagePlayer(otherPlayer, 10)
                    end
                end
            end
        end
    end
end

function MachineGunModule:ServerEquip() end

function MachineGunModule:ServerDequip() end

return MachineGunModule
