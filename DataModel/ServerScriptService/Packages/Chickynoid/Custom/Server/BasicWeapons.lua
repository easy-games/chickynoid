local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local serverPath = game.ServerScriptService.Packages.Chickynoid
--local WeaponsModule = require(serverPath.Server.Server.WeaponsServer)

function module:Setup(server)
	
	--Give spawning players a weapon
	server.OnPlayerSpawn:Connect(function(playerRecord)
		--Give a machine gun
		playerRecord:AddWeaponByName("Machinegun", true)	
		
	end)	
	
	server.OnPlayerDespawn:Connect(function(playerRecord)
		--Give a machine gun
		playerRecord:ClearWeapons()	
	end)

end


function module:Step(server, deltaTime)
	
	 
end

 

return module
