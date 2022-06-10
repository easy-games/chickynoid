local Enums = {}

Enums.EventType = {
    ChickynoidAdded = 0,
    ChickynoidRemoving = 1,
    Command = 2,
    State = 3,
    Snapshot = 4,
    WorldState = 5,
    CollisionData = 6,
    ResetConnection = 7,

    --Just for test
    WeaponDataChanged = 8,
    RocketSpawn = 9,
    BulletImpact = 10,

    RocketDie = 11,

    DebugBox = 12,

    PlayerDisconnected = 13,
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
    Stop = 0,
    Idle = 1,
    Walk = 2,
    Run = 3,
    Push = 4,
    Jump = 5,
    Fall = 6,
}

Enums.AnimChannel = {
    Channel0 = 0,
    Channel1 = 1,
    Channel2 = 2,
    Channel3 = 3,
}

Enums.WeaponData = {
    WeaponAdd = 0,
    WeaponRemove = 1,
    WeaponState = 2,
    Equip = 3,
    Dequip = 4,
}

return Enums
