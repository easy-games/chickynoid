local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Chickynoid = require(Packages.Chickynoid.Server)

Chickynoid.SetConfig({
    simulationConfig = {
        -- stepSize = 3,
    },
})

Chickynoid.Setup()

Players.PlayerAdded:Connect(function(player)
    local character = Chickynoid.SpawnForPlayerAsync(player)

    RunService.Heartbeat:Connect(function()
        character:Heartbeat()
    end)

    -- while wait(10) do
    --     character:SetPosition(Vector3.new(0, 100, 0))
    -- end
end)
