local Packages = game.ReplicatedFirst.Packages.Chickynoid
local ClientModule = require(Packages.Client.ClientModule)
local ClientMods = require(Packages.Client.ClientMods)

ClientMods:RegisterMods("clientmods", game.ReplicatedFirst.Examples.ClientMods)
ClientMods:RegisterMods("characters", game.ReplicatedFirst.Examples.Characters)
ClientMods:RegisterMods("weapons", game.ReplicatedFirst.Examples.Weapons)
 
ClientModule:Setup()
