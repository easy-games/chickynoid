--[=[
    @class Simulation
    Simulation handles physics for characters on both the client and server.
]=]

local RunService = game:GetService("RunService")
local IsClient = RunService:IsClient()

local Simulation = {}
Simulation.__index = Simulation

local CollisionModule = require(script.CollisionModule)
local CharacterData = require(script.CharacterData)
local MathUtils = require(script.MathUtils)
local Enums = require(script.Parent.Enums)
local DeltaTable = require(script.Parent.Vendor.DeltaTable)

function Simulation.new(userId)
    local self = setmetatable({}, Simulation)

    self.userId = userId

    self.moveStates = {}
    self.moveStateNames = {}

    self.state = {}

    self.state.pos = Vector3.new(0, 5, 0)
    self.state.vel = Vector3.new(0, 0, 0)
    self.state.pushDir = Vector2.new(0, 0)

    self.state.jump = 0
    self.state.angle = 0
    self.state.targetAngle = 0
    self.state.stepUp = 0
    self.state.inAir = 0
    self.state.jumpThrust = 0
    self.state.pushing = 0 --External flag comes from server (ungh >_<')
    self.state.moveState = 0 --Walking!

    self.characterData = CharacterData.new()

    self.lastGround = nil --Used for platform stand on servers only

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

    self:RegisterMoveState("Walking", self.MovetypeWalking, nil, nil, nil)
    self:SetMoveState("Walking")
    return self
end

function Simulation:GetMoveState()
    local record = self.moveStates[self.state.moveState]
    return record
end

function Simulation:RegisterMoveState(name, updateState, alwaysThink, startState, endState)
    local index = 0
    for key,value in pairs(self.moveStateNames) do
        index+=1
    end
    self.moveStateNames[name] = index

    local record = {}
    record.name = name
    record.updateState = updateState
    record.alwaysThink = alwaysThink
    record.startState = startState
    record.endState = endState


    self.moveStates[index] = record
end

function Simulation:SetMoveState(name)

    local index = self.moveStateNames[name]
    if (index) then

        local record = self.moveStates[index]
        if (record) then
            
            local prevRecord = self.moveStates[self.state.moveState]
            if (prevRecord and prevRecord.endState) then
                prevRecord.endState(self, name)
            end
            if (record.startState) then
                if (prevRecord) then
                    record.startState(self, prevRecord.name)
                else
                    record.startState(self, "")
                end
            end
            self.state.moveState = index
        end
    end
end


--	It is very important that this method rely only on whats in the cmd object
--	and no other client or server state can "leak" into here
--	or the server and client state will get out of sync.

function Simulation:ProcessCommand(cmd)
    debug.profilebegin("Chickynoid Simulation")

    for key,record in pairs(self.moveStates) do
        if (record.alwaysThink) then
            record.alwaysThink(self, cmd)
        end
    end

    local record = self.moveStates[self.state.moveState]
    if (record and record.updateState) then
        record.updateState(self, cmd)
    else
        warn("No such updateState: ", self.state.moveState)
    end
   
  
    --Input/Movement is done, do the update of timers and write out values

    --Adjust stepup
    self:DecayStepUp(cmd.deltaTime)

    --position the debug visualizer
    if self.debugModel ~= nil then
        self.debugModel:PivotTo(CFrame.new(self.state.pos))
    end

    --Do pushing animation timer
    self:DoPushingTimer(cmd)

    --Do Platform move
    --self:DoPlatformMove(self.lastGround, cmd.deltaTime)

    --Write this to the characterData
    self.characterData:SetTargetPosition(self.state.pos)
    self.characterData:SetAngle(self.state.angle)
    self.characterData:SetStepUp(self.state.stepUp)
    self.characterData:SetFlatSpeed( MathUtils:FlatVec(self.state.vel).Magnitude)

    debug.profileend()
end

function Simulation:SetAngle(angle, teleport)
    self.state.angle = angle
    if (teleport == true) then
        self.state.targetAngle = angle
        self.characterData:SetAngle(self.state.angle, true)
    end
end

function Simulation:SetPosition(position, teleport)
    self.state.position = position
    self.characterData:SetTargetPosition(self.state.pos, teleport)
end

function Simulation:CrashLand(vel)
    --Current behaviour, cap velocity
    local returnVel = Vector3.new(vel.x, 0, vel.z)
    returnVel = MathUtils:CapVelocity(returnVel, self.constants.maxSpeed)
    return vel
end


--STEPUP - the magic that lets us traverse uneven world geometry
--the idea is that you redo the player movement but "if I was x units higher in the air"

function Simulation:DoStepUp(pos, vel, deltaTime)
    local flatVel = MathUtils:FlatVec(vel)

    local stepVec = Vector3.new(0, self.constants.stepSize, 0)
    --first move upwards as high as we can go

    local headHit = CollisionModule:Sweep(pos, pos + stepVec)

    --Project forwards
    local stepUpNewPos, stepUpNewVel, _stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel, deltaTime)

    --Trace back down
    local traceDownPos = stepUpNewPos
    local hitResult = CollisionModule:Sweep(traceDownPos, traceDownPos - stepVec)

    stepUpNewPos = hitResult.endPos

    --See if we're mostly on the ground after this? otherwise rewind it
    local ground = self:DoGroundCheck(stepUpNewPos)

    --Slope check
    if ground ~= nil then
        if ground.normal.Y < self.constants.maxGroundSlope or ground.startSolid == true then
            return nil
        end
    end

    if ground ~= nil then
        local result = {
            stepUp = self.state.pos.y - stepUpNewPos.y,
            pos = stepUpNewPos,
            vel = stepUpNewVel,
        }
        return result
    end

    return nil
end

--Magic to stick to the ground instead of falling on every stair
function Simulation:DoStepDown(pos)
    local stepVec = Vector3.new(0, self.constants.stepSize, 0)
    local hitResult = CollisionModule:Sweep(pos, pos - stepVec)

    if
        hitResult.startSolid == false
        and hitResult.fraction < 1
        and hitResult.normal.Y >= self.constants.maxGroundSlope
    then
        local delta = pos.y - hitResult.endPos.y

        if delta > 0.001 then
            local result = {

                pos = hitResult.endPos,
                stepDown = delta,
            }
            return result
        end
    end

    return nil
end

function Simulation:Destroy()
    if self.debugModel then
        self.debugModel:Destroy()
    end
end

function Simulation:DecayStepUp(deltaTime)
    self.state.stepUp = MathUtils:Friction(self.state.stepUp, 0.05, deltaTime) --higher == slower
end

function Simulation:DoGroundCheck(pos)
    local results = CollisionModule:Sweep(pos + Vector3.new(0, 0.1, 0), pos + Vector3.new(0, -0.1, 0))

    if results.allSolid == true or results.startSolid == true then
        --We're stuck, pretend we're in the air

        results.fraction = 1
        return results
    end

    if results.fraction < 1 then
        return results
    end
    return nil
end

function Simulation:ProjectVelocity(startPos, startVel, deltaTime)
    local movePos = startPos
    local moveVel = startVel
    local hitSomething = false

    --Project our movement through the world
    local planes = {}
    local timeLeft = deltaTime

    for _ = 0, 3 do
        if moveVel.Magnitude < 0.001 then
            --done
            break
        end

        if moveVel:Dot(startVel) < 0 then
            --we projected back in the opposite direction from where we started. No.
			moveVel = Vector3.new(0, 0, 0)
            break
        end

        --We only operate on a scaled down version of velocity
        local result = CollisionModule:Sweep(movePos, movePos + (moveVel * timeLeft))

        --Update our position
        if result.fraction > 0 then
            movePos = result.endPos
        end

        --See if we swept the whole way?
        if result.fraction == 1 then
            break
        end

        if result.fraction < 1 then
            hitSomething = true
        end

        if result.allSolid == true then
            --all solid, don't do anything
            --(this doesn't mean we wont project along a normal!)
            moveVel = Vector3.new(0, 0, 0)
            break
        end

        --Hit!
        timeLeft -= (timeLeft * result.fraction)

        if planes[result.planeNum] == nil then
            planes[result.planeNum] = true

            --Deflect the velocity and keep going
            moveVel = MathUtils:ClipVelocity(moveVel, result.normal, 1.0)
        else
            --We hit the same plane twice, push off it a bit
            movePos += result.normal * 0.01
            moveVel += result.normal
            break
        end
    end

    return movePos, moveVel, hitSomething
end

function Simulation:CheckGroundSlopes(startPos)
	
	local movePos = startPos
	local moveDir = Vector3.new(0,-1,0)
	
	--We only operate on a scaled down version of velocity
	local result = CollisionModule:Sweep(movePos, movePos + moveDir)

	--Update our position
	if result.fraction > 0 then
		movePos = result.endPos
	end
	--See if we swept the whole way?
	if result.fraction == 1 then
		return false
	end
	
	if result.allSolid == true then
		return true --stuck
	end
	
	moveDir = MathUtils:ClipVelocity(moveDir, result.normal, 1.0)
	if (moveDir.Magnitude < 0.001) then
		return true --stuck
	end
	
	--Try and move it
	local result = CollisionModule:Sweep(movePos, movePos + moveDir)
	if (result.fraction == 0) then
		return true --stuck
	end
	
	--Not stuck
	return false	
end


--This gets deltacompressed by the client/server chickynoids automatically
function Simulation:WriteState()
    local record = {}
    record.state = DeltaTable:DeepCopy(self.state)
    record.constants = DeltaTable:DeepCopy(self.constants)
    return record
end

function Simulation:ReadState(record)
    self.state = DeltaTable:DeepCopy(record.state)
    self.constants = DeltaTable:DeepCopy(record.constants)
end

function Simulation:DoPlatformMove(lastGround, deltaTime)
    --Do platform move
    if lastGround and lastGround.hullRecord and lastGround.hullRecord.instance then
        local instance = lastGround.hullRecord.instance
        if instance.Velocity.Magnitude > 0 then
            --Calculate the player cframe in localspace relative to the mover
            --local currentStandingPartCFrame = standingPart.CFrame
            --local partDelta = currentStandingPartCFrame * self.previousStandingPartCFrame:Inverse()

            --if (partDelta.p.Magnitude > 0) then

            --   local original = self.character.PrimaryPart.CFrame
            --   local new = partDelta * self.character.PrimaryPart.CFrame

            --   local deltaCFrame = CFrame.new(new.p-original.p)
            --CFrame move it
            --   self.character:SetPrimaryPartCFrame( deltaCFrame * self.character.PrimaryPart.CFrame )
            --end

            --state = self.character.PrimaryPart.CFrame.p
            self.state.pos += instance.Velocity * deltaTime
        end
    end
end

function Simulation:DoPushingTimer(cmd)
    if IsClient == true then
        return
    end

    if self.state.pushing > 0 then
        self.state.pushing -= cmd.deltaTime
        if self.state.pushing < 0 then
            self.state.pushing = 0
        end
    end
end

function Simulation:GetStandingPart()
    if self.lastGround and self.lastGround.hullRecord then
        return self.lastGround.hullRecord.instance
    end
    return nil
end

function Simulation:MovetypeWalking(cmd)

    --Check ground
    local onGround = nil
    self.lastGround = nil
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

                --For platform standing
                if self.state.jump == 0 then
                    self.lastGround = onGround
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
            walkNewVel = self:CrashLand(walkNewVel)
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

return Simulation