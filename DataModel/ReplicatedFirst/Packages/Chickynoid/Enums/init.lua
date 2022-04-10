local Enums = {}

Enums.EventType = {
    ChickynoidAdded = 0,
    ChickynoidRemoving = 1,
    Command = 2,
    State = 3,
    Snapshot = 4,
	WorldState = 5,
	CollisionData = 6,
    
    --Just for test
    RocketSpawn = 7,
    RocketDie = 8,
}
Enums.NetworkProblemState = {
    None = 0,
    TooFarBehind = 1,
    TooFarAhead = 2,
    TooManyCommands = 3,    
    
}

Enums.FpsMode = {
    Uncapped = 0,
    Hybrid = 1,
    Fixed60 = 2,
}


Enums.Anims = {
    Idle = 0,
    Run = 1,
    Jump = 2,
    Fall = 3,
}

return Enums
