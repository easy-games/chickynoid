local Root = script.Parent
local EnumList = require(Root.Parent.EnumList)

local Enums = {}

Enums.EventType = EnumList.new("EventType", {
    "ChickynoidAdded",
    "ChickynoidRemoving",
    "Command",
    "State",
    "Snapshot",
    "WorldState",
    "CollisionData",
    "ResetConnection",

    --Just for test
    "RocketSpawn",
    "RocketDie",
})

Enums.NetworkProblemState = EnumList.new("NetworkProblemState", {
    "None",
    "TooFarBehind",
    "TooFarAhead",
    "TooManyCommands",
})

Enums.FpsMode = EnumList.new("FpsMode", {
    "Uncapped",
    "Hybrid",
    "Fixed60",
})

Enums.Anims = EnumList.new("Animations", {
    "Idle",
    "Walk",
    "Run",
    "Push",
    "Jump",
    "Fall",
})

return Enums
