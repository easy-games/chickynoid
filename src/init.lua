local RunService = game:GetService("RunService")

local Chickynoid = {}

local IsServer = RunService:IsServer()
if IsServer then
    local Server = require(script.Server)
    local Antilag = require(script.Server.Antilag)
    Chickynoid.ChickynoidServer = Server
    Chickynoid.Antilag = Antilag
    Chickynoid.ServerMods = require(script.Server.ServerMods)
else
    local Client = require(script.Client)
    Chickynoid.ChickynoidClient = Client
    chickynoid.ClientMods = require(script.Client.ClientMods)
end

return Chickynoid
