local ValidateInstall = require(game.ServerScriptService.Packages.Chickynoid.ServerScript.Utils.InstallValidation)
local validInstall = ValidateInstall:Validate()

if (validInstall == true) then
	
	local Server = require(game.ServerScriptService.Packages.Chickynoid.Server.Server)

	--Setup the collision
	Server:RecreateCollisions(game.Workspace.GameArea)

	--Launch the server
	Server:Setup()
	
	--Make some bots! Actually, make lots of bots!
	local Bots = require(game.ServerScriptService.Packages.Chickynoid.Server.Bots)
	
	local numBots = script:GetAttribute("bots")
	if (numBots ~= nil) then
		Bots:MakeBots(Server, numBots)
	end
end



 