local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Chickynoid = require(Packages.Chickynoid).ChickynoidServer

Chickynoid:RecreateCollisions(workspace:FindFirstChild("GameArea"))
Chickynoid:RegisterModsInContainer(script.Parent.Mods)
Chickynoid:Setup()

--bots?
local Bots = require(script.Parent.Bots)
Bots:MakeBots(Chickynoid, 0)