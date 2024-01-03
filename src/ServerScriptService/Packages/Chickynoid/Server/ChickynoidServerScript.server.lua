local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Packages = game.ServerScriptService.Packages.Chickynoid.Server
local ServerModule = require(Packages.ServerModule)
local ServerMods = require(Packages.ServerMods)

ServerModule:RecreateCollisions(workspace:FindFirstChild("GameArea"))

ServerMods:RegisterMods("servermods", game.ServerScriptService.Examples.ServerMods)
ServerMods:RegisterMods("characters", game.ReplicatedFirst.Examples.Characters)
ServerMods:RegisterMods("weapons", game.ReplicatedFirst.Examples.Weapons)

ServerModule:Setup()

--bots? 
local Bots = require(script.Parent.Bots)
Bots:MakeBots(ServerModule,100)