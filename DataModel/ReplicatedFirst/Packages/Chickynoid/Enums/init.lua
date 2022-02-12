local Enums = {}

Enums.EventType = {
    ChickynoidAdded = 0,
    ChickynoidRemoving = 1,
    Command = 2,
    State = 3,
    Snapshot = 4,
    WorldState = 5,
}
Enums.NetworkProblemState = {
    None = 0,
    TooFarBehind = 1,
    TooFarAhead = 2,
    TooManyCommands = 3,    
    
}


Enums.Anims = {
    Idle = 0,
    Run = 1,
    Jump = 2,
    Fall = 3,
    
}

return Enums
