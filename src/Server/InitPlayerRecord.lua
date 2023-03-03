--[=[
    @class InitCharacter
    @server

    Initialize new player records and connect them with character mod hotswap example
]=]
local module = {}

function module:Setup(_server)
	local initialized = {}

	local function initPlayerRecord(serv, playerRecord)
		if initialized[playerRecord.userId] == nil then
			playerRecord:SetCharacterMod("NicerHumanoid")
			initialized[playerRecord.userId] = playerRecord
			print("initialized with characterMod", playerRecord.characterMod)
		end
		print("init playerRecord")
	end

	_server.OnPlayerConnected:Connect(initPlayerRecord)

	-- init already connected players
	for _, playerRecord in _server:GetPlayers() do
		initPlayerRecord(_server, playerRecord)
	end

	local function ToggleMoveset(player: Player)
		local playerRecord = initialized[player.UserId]
		if playerRecord then
			if playerRecord.characterMod == "NicerHumanoid" then
				playerRecord:SetCharacterMod("ChickynoidHumanoid")
			else
				playerRecord:SetCharacterMod("NicerHumanoid")
			end
			print("swapping characterMod to", playerRecord.characterMod)
			return true
		end
		return false
	end
	
	-- create a binding to call ToggleMoveset elsewhere i.e. from the client using RbxUtil/Comm (https://sleitnick.github.io/RbxUtil/api/Comm/)
	--[[
		local ChickynoidComm = ServerComm.new(game.ReplicatedStorage:WaitForChild("Comms"), "ChickynoidComm")
		ChickynoidComm:BindFunction("ToggleMoveset", ToggleMoveset)
	]]
end

return module