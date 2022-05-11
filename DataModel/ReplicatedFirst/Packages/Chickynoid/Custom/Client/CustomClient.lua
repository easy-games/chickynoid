local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local WeaponsClient = require(path.Client.Client.WeaponsClient)
local EffectsModule = require(path.Client.Effects)

function module:Setup(client)
	
	
	--You can also handle this directly in the weapon, if you feel like it
	WeaponsClient.OnBulletImpact:Connect(function(client, event)
		
		--WeaponModule		
		
		if (event.n) then
			
			if (event.m == 0) then
				local effect = EffectsModule:SpawnEffect("ImpactWorld",event.p)
				local cframe = CFrame.lookAt(event.p, event.p + event.n)
				effect.CFrame = cframe
			end
			if (event.m == 1) then
				local effect = EffectsModule:SpawnEffect("ImpactPlayer",event.p)
				local cframe = CFrame.lookAt(event.p, event.p + event.n)
				effect.CFrame = cframe
			end

		end
		
		--we didn't fire it, play the fire effect
		if (event.player.userId ~= game.Players.LocalPlayer.UserId) then
			
			--Do some local effects
			local origin = event.o
			local vec = (event.p - event.o).Unit
			local clone = EffectsModule:SpawnEffect("Tracer", origin + vec*2)
			clone.CFrame = CFrame.lookAt(origin, origin + vec)
			
		end
	end)
end

function module:Step(client, deltaTime)
	
end


return module
