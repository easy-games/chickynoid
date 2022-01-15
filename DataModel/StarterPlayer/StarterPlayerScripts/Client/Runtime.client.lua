local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Chickynoid = require(Packages:WaitForChild("Chickynoid"):WaitForChild("Client"))

Chickynoid.SetConfig({
    simulationConfig = {
        -- stepSize = 3,
    },
})

Chickynoid.Setup()
