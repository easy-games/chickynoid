local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Packages = ReplicatedFirst.Packages
local Chickynoid = require(Packages.Chickynoid).ChickynoidServer
local ServerMods = require(Packages.Chickynoid.Server.ServerMods)

Chickynoid:RecreateCollisions(workspace:FindFirstChild("GameArea"))

ServerMods:RegisterMods("servermods", game.ServerScriptService.Examples.ServerMods)
ServerMods:RegisterMods("characters", game.ReplicatedFirst.Examples.Characters)
ServerMods:RegisterMods("weapons", game.ReplicatedFirst.Examples.Weapons)

Chickynoid:Setup()

--bots? 
local Bots = require(script.Parent.Bots)
Bots:MakeBots(Chickynoid, 10)