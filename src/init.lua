local RunService = game:GetService("RunService")

local Chickynoid = {}

local IsServer = RunService:IsServer()
if IsServer then
    local Server = require(script.Server)
    Chickynoid.ChickynoidServer = Server
else
    local Client = require(script.Client)
    Chickynoid.ChickynoidClient = Client
end

return Chickynoid
