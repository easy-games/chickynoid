local ReplicatedStorage = game:GetService("ReplicatedStorage")
local module = {}

-- FIXME: These should be surfaced to top-level APIs
local WeaponsClient = require(ReplicatedStorage.Packages.Chickynoid.Client.WeaponsClient)
local EffectsModule = require(ReplicatedStorage.Packages.Chickynoid.Client.Effects)

function module:Setup(_client)
    --You can also handle this directly in the weapon, if you feel like it
    WeaponsClient.OnBulletImpact:Connect(function(_client, event)
        --WeaponModule

        if event.n then
            if event.m == 0 then
                local effect = EffectsModule:SpawnEffect("ImpactWorld", event.p)
                local cframe = CFrame.lookAt(event.p, event.p + event.n)
                effect.CFrame = cframe
            end
            if event.m == 1 then
                local effect = EffectsModule:SpawnEffect("ImpactPlayer", event.p)
                local cframe = CFrame.lookAt(event.p, event.p + event.n)
                effect.CFrame = cframe
            end
        end

        --we didn't fire it, play the fire effect
        if event.player.userId ~= game.Players.LocalPlayer.UserId then
            --Do some local effects
            local origin = event.o
            local vec = (event.p - event.o).Unit
            local clone = EffectsModule:SpawnEffect("Tracer", origin + vec * 2)
            clone.CFrame = CFrame.lookAt(origin, origin + vec)
        end
    end)

 
end

function module:Step(_client, _deltaTime) end

return module
