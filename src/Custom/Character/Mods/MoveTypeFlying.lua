local module = {}

local path = game.ReplicatedStorage.Packages.Chickynoid
local MathUtils = require(path.Simulation.MathUtils)
local Enums = require(path.Enums)

--Call this on both the client and server!
function module:ModifySimulation(simulation)

    simulation:RegisterMoveState("Flying", self.ActiveThink, self.AlwaysThink, self.StartState, nil)
	simulation.constants.flyFriction = 0.2
	simulation.state.flyingCooldown = 0
end

--Imagine this is inside Simulation...
function module:AlwaysThink(cmd)
	
	if (self.state.flyingCooldown > 0) then
		self.state.flyingCooldown = math.max(self.state.flyingCooldown - cmd.deltaTime, 0)
	end
	
	if (self.state.flyingCooldown == 0 and cmd.flying == 1) then
		
		if (self:GetMoveState().name == "Flying") then
			self.state.flyingCooldown = 0.5
			self:SetMoveState("Walking")
		else
			self.state.flyingCooldown = 0.5
			self:SetMoveState("Flying")
		end
    end
end

function module:StartState(cmd)

    --pop us up when we enter this state
    self.state.vel = Vector3.new(0,100,0)
end

--Imagine this is inside Simulation...
function module:ActiveThink(cmd)
	
    --Did the player have a movement request?
    local wishDir = nil
    if cmd.x ~= 0 or cmd.y ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, cmd.y, cmd.z).Unit
        self.state.pushDir = Vector2.new(cmd.x, cmd.z)
    else
        self.state.pushDir = Vector2.new(0, 0)
    end
   
    --Does the player have an input?
    if wishDir ~= nil then

        self.state.vel = MathUtils:GroundAccelerate(
            wishDir,
            self.constants.maxSpeed,
            self.constants.accel,
            self.state.vel,
            cmd.deltaTime
        )

        self.characterData:PlayAnimation(Enums.Anims.Walk, false)
    else
        self.characterData:PlayAnimation(Enums.Anims.Idle, false)
    end

    self.state.vel = MathUtils:VelocityFriction(self.state.vel, self.constants.flyFriction, cmd.deltaTime)

    local walkNewPos, walkNewVel, hitSomething = self:ProjectVelocity(self.state.pos, self.state.vel, cmd.deltaTime)
    self.state.pos = walkNewPos
    self.state.vel = walkNewVel
    
    --Do angles
    if wishDir ~= nil then
        self.state.targetAngle = MathUtils:PlayerVecToAngle(wishDir)
        self.state.angle = MathUtils:LerpAngle(
            self.state.angle,
            self.state.targetAngle,
            self.constants.turnSpeedFrac * cmd.deltaTime
        )
    end
end

return module