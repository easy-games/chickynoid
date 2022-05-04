local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Chickynoid = require(Packages.Chickynoid.Server)

Chickynoid:RecreateCollisions(workspace:FindFirstChild("GameArea"))
Chickynoid:Setup()
