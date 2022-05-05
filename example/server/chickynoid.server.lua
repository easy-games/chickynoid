local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Chickynoid = require(Packages.Chickynoid).ChickynoidServer

Chickynoid:RecreateCollisions(workspace:FindFirstChild("GameArea"))
Chickynoid:Setup()
