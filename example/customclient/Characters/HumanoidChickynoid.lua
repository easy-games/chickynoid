local ChickynoidStyle = {}

--Gets called on both client and server
function ChickynoidStyle:Setup(simulation)

    --Roblox Humanoid defaultish
    self.constants = {}
    self.constants.maxSpeed = 16 --Units per second
    self.constants.airSpeed = 16 --Units per second
    self.constants.accel = 40 --Units per second per second
    self.constants.airAccel = 10 --Uses a different function than ground accel!
    self.constants.jumpPunch = 60 --Raw velocity, just barely enough to climb on a 7 unit tall block
    self.constants.turnSpeedFrac = 8 --seems about right? Very fast.
    self.constants.runFriction = 0.01 --friction applied after max speed
    self.constants.brakeFriction = 0.02 --Lower is brake harder, dont use 0
    self.constants.maxGroundSlope = 0.05 --about 89o
    self.constants.jumpThrustPower = 0    --No variable height jumping
    self.constants.jumpThrustDecay = 0
	self.constants.gravity = -198

    self.constants.pushSpeed = 16 --set this lower than maxspeed if you want stuff to feel heavy
	self.constants.stepSize = 2.2
	self.constants.gravity = -198
end



return ChickynoidStyle