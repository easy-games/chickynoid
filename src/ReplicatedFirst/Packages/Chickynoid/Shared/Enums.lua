local Enums = {}

Enums.EventType = {
	ChickynoidAdded = 0,
	ChickynoidRemoving = 1,
	Command = 2,
	State = 3,
	Snapshot = 4,
	WorldState = 5,
	CollisionData = 6,
	
	WeaponDataChanged = 8,
	BulletFire = 9,
	BulletImpact = 10,

	DebugBox = 11,

	PlayerDisconnected = 12,
}
table.freeze(Enums.EventType)

Enums.NetworkProblemState = {
	None = 0,
	TooFarBehind = 1,
	TooFarAhead = 2,
	TooManyCommands = 3,
	DroppedPacketGood = 4,
	DroppedPacketBad = 5
}
table.freeze(Enums.NetworkProblemState)

Enums.FpsMode = {
	Uncapped = 0,
	Hybrid = 1,
	Fixed60 = 2,
}
table.freeze(Enums.FpsMode)

Enums.AnimChannel = {
	Channel0 = 0,
	Channel1 = 1,
	Channel2 = 2,
	Channel3 = 3,
}
table.freeze(Enums.AnimChannel)

Enums.WeaponData = {
	WeaponAdd = 0,
	WeaponRemove = 1,
	WeaponState = 2,
	Equip = 3,
	Dequip = 4,
}
table.freeze(Enums.WeaponData)

Enums.Crashland = {
	STOP = 0,
	FULL_BHOP = 1,
	FULL_BHOP_FORWARD = 2,
	CAPPED_BHOP = 3,
	CAPPED_BHOP_FORWARD = 4,

}
table.freeze(Enums.Crashland)

return Enums
