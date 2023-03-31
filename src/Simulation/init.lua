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
    self.state.playerSize = Vector3.new(3, 5, 3)

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
	self.constants.crashLandBehavior = Enums.Crashland.FULL_BHOP_FORWARD

    self.constants.pushSpeed = 16 --set this lower than maxspeed if you want stuff to feel heavy
	self.constants.stepSize = 2.2
	self.constants.gravity = -198

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
    self.state.pos = position
    self.characterData:SetTargetPosition(self.state.pos, teleport)
end

function Simulation:CrashLand(vel, cmd, ground)
	

	if (self.constants.crashLandBehavior == Enums.Crashland.FULL_BHOP) then
		 
		return Vector3.new(vel.x, 0, vel.z)
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.CAPPED_BHOP) then
		--cap velocity if you're contining into a jump
		 
		if (cmd.y > 0) then
			local returnVel = Vector3.new(vel.x, 0, vel.z)
			returnVel = MathUtils:CapVelocity(returnVel, self.constants.maxSpeed)
			return returnVel
		end
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.CAPPED_BHOP_FORWARD) then
		--bhop forward if the slope is the way we're facing
		 
		if (cmd.y > 0) then
			local flat = Vector3.new(ground.normal.x, 0, ground.normal.z).Unit
			local forward = MathUtils:PlayerAngleToVec(self.state.angle)
						
			if (forward:Dot(flat) < 0) then 
				
				local returnVel = Vector3.new(vel.x, 0, vel.z)
				returnVel = MathUtils:CapVelocity(returnVel, self.constants.maxSpeed)
				return returnVel
			else
				return Vector3.zero
			end
		end
	end
	
	if (self.constants.crashLandBehavior == Enums.Crashland.FULL_BHOP_FORWARD) then
		--bhop forward if the slope is the way we're facing
		 
		if (cmd.y > 0) then
			local flat = Vector3.new(ground.normal.x, 0, ground.normal.z).Unit
			local forward = MathUtils:PlayerAngleToVec(self.state.angle)

			if (ground.normal.y > 0.99 or forward:Dot(flat) < 0) then
				return vel
			else
				return Vector3.zero
			end
		end
	end
	
    --pass through
	return vel
end


--STEPUP - the magic that lets us traverse uneven world geometry
--the idea is that you redo the player movement but "if I was x units higher in the air"

-- TODO: Change to only apply our smooth rolling on non-walking movesets ("NicerHumanoid" characterMod)
function Simulation:DoStepUp(pos, vel, deltaTime)
    local flatVel = MathUtils:FlatVec(vel)

    local stepVec = Vector3.new(0, self.constants.stepSize, 0)
    --first move upwards as high as we can go

    local headHit = CollisionModule:Sweep(pos, pos + stepVec, self.state.playerSize)

    --Project forwards
    local stepUpNewPos, stepUpNewVel, _stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel, deltaTime)

    --Trace back down
    local traceDownPos = stepUpNewPos
    local hitResult = CollisionModule:Sweep(traceDownPos, traceDownPos - Vector3.new(0, self.constants.aggressiveStep, 0), self.state.playerSize)

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
    local hitResult = CollisionModule:Sweep(pos, pos - stepVec, self.state.playerSize)

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
    local results = CollisionModule:Sweep(pos + Vector3.new(0, 0.1, 0), pos + Vector3.new(0, -0.1, 0), self.state.playerSize)

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
        local result = CollisionModule:Sweep(movePos, movePos + (moveVel * timeLeft), self.state.playerSize)

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
	local result = CollisionModule:Sweep(movePos, movePos + moveDir, self.state.playerSize)

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
	local result = CollisionModule:Sweep(movePos, movePos + moveDir, self.state.playerSize)
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

return Simulation