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
    RocketDie = 10,
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
	Walk = 1,	
	Run = 2,
	Push = 3,
    Jump = 4,
    Fall = 5,
}

Enums.WeaponData = {
	WeaponAdd = 0,
	WeaponRemove = 1,
	WeaponState = 2,
	Equip = 3,
	Dequip = 4,
	
}


return Enums
