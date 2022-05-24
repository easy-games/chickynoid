local RunService = game:GetService("RunService")

local Chickynoid = {}

local IsServer = RunService:IsServer()
if IsServer then
    local Server = require(script.Server)
    local Antilag = require(script.Antilag)
    Chickynoid.ChickynoidServer = Server
    Chickynoid.Antilag = Antilag
else
    local Client = require(script.Client)
    Chickynoid.ChickynoidClient = Client
end

return Chickynoid
