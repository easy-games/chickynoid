local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Packages = ReplicatedFirst.Packages
local Chickynoid = require(Packages.Chickynoid).ChickynoidClient
local ClientMods = require(Packages.Chickynoid.Client.ClientMods)

ClientMods:RegisterMods("clientmods", game.ReplicatedFirst.Examples.ClientMods)
ClientMods:RegisterMods("characters", game.ReplicatedFirst.Examples.Characters)
ClientMods:RegisterMods("weapons", game.ReplicatedFirst.Examples.Weapons)

Chickynoid:Setup()
