local ReplicatedFirst = game:GetService("ReplicatedFirst")
local module = {}

-- FIXME: These should be surfaced to top-level APIs
local WeaponsClient = require(ReplicatedFirst.Packages.Chickynoid.Client.WeaponsClient)
local EffectsModule = require(ReplicatedFirst.Packages.Chickynoid.Client.Effects)

function module:Setup(_client)
    --You can also handle this directly in the weapon, if you feel like it
    WeaponsClient.OnBulletImpact:Connect(function(_client, event)
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
    end)

 
end

function module:Step(_client, _deltaTime) end

return module
