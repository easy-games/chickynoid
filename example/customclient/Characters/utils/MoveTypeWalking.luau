local module = {}
local path = game.ReplicatedFirst.Packages.Chickynoid
local MathUtils = require(path.Simulation.MathUtils)
local Enums = require(path.Enums)

function module:Setup(simulation)
    self:ModifySimulation(simulation)
end

function module:ModifySimulation(simulation)
    simulation:RegisterMoveState("Walking", self.ActiveThink, nil, nil, nil)
    simulation:SetMoveState("Walking")

    simulation.state.up = Vector3.yAxis
end

function module:ActiveThink(cmd)
    --Check ground
    local onGround = nil
    onGround = self:DoGroundCheck(self.state.pos)

    --If the player is on too steep a slope, its not ground
	if (onGround ~= nil and onGround.normal.Y < self.constants.maxGroundSlope) then
		
		--See if we can move downwards?
		if (self.state.vel.y < 0.1) then
			local stuck = self:CheckGroundSlopes(self.state.pos)
			
			if (stuck == false) then
				--we moved, that means the player is on a slope and can free fall
				onGround = nil
			else
				--we didn't move, it means the ground we're on is sloped, but we can't fall any further
				--treat it like flat ground
				onGround.normal = Vector3.new(0,1,0)
			end
		else
			onGround = nil
		end
	end
	
	 
    --Mark if we were onground at the start of the frame
    local startedOnGround = onGround
	
	--Simplify - whatever we are at the start of the frame goes.
	self.lastGround = onGround
	

    --Did the player have a movement request?
    local wishDir = nil
    if cmd.x ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
        self.state.pushDir = Vector2.new(cmd.x, cmd.z)
    else
        self.state.pushDir = Vector2.new(0, 0)
    end

    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(self.state.vel)

    --Does the player have an input?
    if wishDir ~= nil then
        if onGround then
            --Moving along the ground under player input

            flatVel = MathUtils:GroundAccelerate(
                wishDir,
                self.constants.maxSpeed,
                self.constants.accel,
                flatVel,
                cmd.deltaTime
            )

            --Good time to trigger our walk anim
            if self.state.pushing > 0 then
                self.characterData:PlayAnimation(Enums.Anims.Push, Enums.AnimChannel.Channel0, false)
            else
                self.characterData:PlayAnimation(Enums.Anims.Walk, Enums.AnimChannel.Channel0, false)
            end
        else
            --Moving through the air under player control
            flatVel = MathUtils:Accelerate(wishDir, self.constants.airSpeed, self.constants.airAccel, flatVel, cmd.deltaTime)
        end
    else
        if onGround ~= nil then
            --Just standing around
            flatVel = MathUtils:VelocityFriction(flatVel, self.constants.brakeFriction, cmd.deltaTime)

            --Enter idle
            self.characterData:PlayAnimation(Enums.Anims.Idle, Enums.AnimChannel.Channel0, false)
        -- else
            --moving through the air with no input
        end
    end

    --Turn out flatvel back into our vel
    self.state.vel = Vector3.new(flatVel.x, self.state.vel.y, flatVel.z)

    --Do jumping?
    if self.state.jump > 0 then
        self.state.jump -= cmd.deltaTime
        if self.state.jump < 0 then
            self.state.jump = 0
        end
    end

    if onGround ~= nil then
        --jump!
        if cmd.y > 0 and self.state.jump <= 0 then
            self.state.vel = Vector3.new(self.state.vel.x, self.constants.jumpPunch, self.state.vel.z)
            self.state.jump = 0.2 --jumping has a cooldown (think jumping up a staircase)
            self.state.jumpThrust = self.constants.jumpThrustPower
            self.characterData:PlayAnimation(Enums.Anims.Jump, Enums.AnimChannel.Channel0, true, 0.2)
        end

        --Check jumpPads
        if onGround.hullRecord then
            local instance = onGround.hullRecord.instance

            if instance then
                local vec3 = instance:GetAttribute("launch")
                if vec3 then
                    local dir = instance.CFrame:VectorToWorldSpace(vec3)
                    self.state.vel = dir
                    self.state.jump = 0.2
                    self.characterData:PlayAnimation(Enums.Anims.Jump, Enums.AnimChannel.Channel0, true, 0.2)
                end
            end
        end
    end

    --In air?
    if onGround == nil then
        self.state.inAir += cmd.deltaTime
        if self.state.inAir > 10 then
            self.state.inAir = 10 --Capped just to keep the state var reasonable
        end

        --Jump thrust
        if cmd.y > 0 then
            if self.state.jumpThrust > 0 then
                self.state.vel += Vector3.new(0, self.state.jumpThrust * cmd.deltaTime, 0)
                self.state.jumpThrust = MathUtils:Friction(
                    self.state.jumpThrust,
                    self.constants.jumpThrustDecay,
                    cmd.deltaTime
                )
            end
            if self.state.jumpThrust < 0.001 then
                self.state.jumpThrust = 0
            end
        else
            self.state.jumpThrust = 0
        end

        --gravity
        self.state.vel += Vector3.new(0, self.constants.gravity * cmd.deltaTime, 0)

        --Switch to falling if we've been off the ground for a bit
        if self.state.vel.y <= 0.01 and self.state.inAir > 0.5 then
            self.characterData:PlayAnimation(Enums.Anims.Fall, Enums.AnimChannel.Channel0, false)
        end
    else
        self.state.inAir = 0
    end

    --Sweep the player through the world, once flat along the ground, and once "step up'd"
    local stepUpResult = nil
    local walkNewPos, walkNewVel, hitSomething = self:ProjectVelocity(self.state.pos, self.state.vel, cmd.deltaTime)

    --Did we crashland
    if onGround == nil and hitSomething == true then
        --Land after jump
        local groundCheck = self:DoGroundCheck(walkNewPos)

        if groundCheck ~= nil then
            --Crashland
            walkNewVel = self:CrashLand(walkNewVel, cmd, groundCheck)
        end
    end

    -- Do we attempt a stepup?                              (not jumping!)
    if onGround ~= nil and hitSomething == true and self.state.jump == 0 then
        stepUpResult = self:DoStepUp(self.state.pos, self.state.vel, cmd.deltaTime)
    end

    --Choose which one to use, either the original move or the stepup
    if stepUpResult ~= nil then
        self.state.stepUp += stepUpResult.stepUp
        self.state.pos = stepUpResult.pos
        self.state.vel = stepUpResult.vel
    else
        self.state.pos = walkNewPos
        self.state.vel = walkNewVel
    end

    --Do stepDown
    if true then
        if startedOnGround ~= nil and self.state.jump == 0 and self.state.vel.y <= 0 then
            local stepDownResult = self:DoStepDown(self.state.pos)
            if stepDownResult ~= nil then
                self.state.stepUp += stepDownResult.stepDown
                self.state.pos = stepDownResult.pos
            end
        end
    end

    --Do angles
    if (self.constants.aimlock == 1) then
        
        if (cmd.fa) then
            local vec = cmd.fa - self.state.pos

			self.state.targetAngle  = MathUtils:PlayerVecToAngle(vec)
			self.state.angle = MathUtils:LerpAngle(
				self.state.angle,
				self.state.targetAngle,
				self.constants.turnSpeedFrac * cmd.deltaTime
			)
        end
    else    
        if wishDir ~= nil then
            self.state.targetAngle = MathUtils:PlayerVecToAngle(wishDir)
            self.state.angle = MathUtils:LerpAngle(
                self.state.angle,
                self.state.targetAngle,
                self.constants.turnSpeedFrac * cmd.deltaTime
            )
        end
    end
end

return module