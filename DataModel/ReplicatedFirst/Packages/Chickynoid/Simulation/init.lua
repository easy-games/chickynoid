--[=[
    @class Simulation
    Simulation handles physics for characters on both the client and server.
]=]

local Types = require(script.Parent.Types)

local Simulation = {}
Simulation.__index = Simulation

local CollisionModule = require(script.CollisionModule)
local CharacterData = require(script.CharacterData)
local MathUtils = require(script.MathUtils)
local Enums = require(script.Parent.Enums)

--This is currently baked into the collision system.
local playerSize = Vector3.new(3,5,3)


function Simulation.new()
    local self = setmetatable({}, Simulation)

    self.state = {}
     
    self.state.pos = Vector3.new(0, 5, 0)
    self.state.vel = Vector3.new(0, 0, 0)
    self.state.jump = 0
    self.state.angle = 0
    self.state.targetAngle = 0
    self.state.stepUp = 0
    self.state.inAir = 0
    
    self.characterData = CharacterData.new()
    
    --players feet height - height goes from -2.5 to +2.5
    --So any point below this number is considered the players feet
    --the distance between middle and feetHeight is "ledge"
    self.feetHeight = -1.9

    -- How big an object we can step over
    self.stepSize = 2.1
 
    
    --THIS DOES NOT GO HERE LOL
    if (#CollisionModule.hullRecords == 0) then
        CollisionModule:MakeWorld(game.Workspace.GameArea, playerSize )
    end

    
    return self
end

--	It is very important that this method rely only on whats in the cmd object
--	and no other client or server state can "leak" into here
--	or the server and client state will get out of sync.
--	You'll have to manage it so clients/server see the same thing in workspace.GameArea for collision...
 
function Simulation:ProcessCommand(cmd)
 
    debug.profilebegin("Chickynoid Simulation")

    --Ground parameters, for stock "Humanoid" recreation
    local maxSpeed = 16                 --Units per second
    local airSpeed = 16                 --Units per second
    local accel =  40                   --Units per second per second 
    local airAccel = 40                 --Uses a different function than ground accel! 
    local jumpPunch = 55                --Raw velocity, just barely enough to climb on a 7 unit tall block
    local turnSpeedFrac = 12            --seems about right? Very fast.
    local brakeFriction = 0.02          --Lower is brake harder, dont use 0
    
    --Regarding Humanoid: Best guess is real humanoids are manipulating position+velocity at the same time via critically dampened springs
    --                    This means they don't really have the concept of acceleration
    --                    So best approx is just jacking accel and friction through the roof!
        
    --Check ground
    local onGround = nil
    onGround = self:DoGroundCheck(self.state.pos)

    --Did the player have a movement request?
    local wishDir = nil

    if (cmd.x ~= 0 or cmd.z ~= 0) then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
    end
    
    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(self.state.vel)
    
    --Does the player have an input?
    if (wishDir ~= nil) then
       
        if (onGround) then
            --Moving along the ground under player input
            
            
            flatVel = MathUtils:VelocityFriction(flatVel, brakeFriction, cmd.deltaTime) --Error! This function is failing at really tiny Dt.
            flatVel = self:Accelerate(wishDir, maxSpeed, accel, flatVel, cmd.deltaTime)
          
            --Good time to trigger our walk anim
            self.characterData:PlayAnimation(Enums.Anims.Run, false)
        else
            --Moving through the air under player control
            flatVel = self:Accelerate(wishDir, airSpeed, airAccel, flatVel, cmd.deltaTime)
        end
    else
        if (onGround ~= nil) then
            --Just standing around
            flatVel = MathUtils:VelocityFriction(flatVel, brakeFriction, cmd.deltaTime)
            
            --Enter idle
            self.characterData:PlayAnimation(Enums.Anims.Idle, false)
        else
            --moving through the air with no input
            
        end
    end
    
    --Turn out flatvel back into our vel
    self.state.vel = Vector3.new(flatVel.x, self.state.vel.y, flatVel.z)
    
    
    --Do jumping?
    if (self.state.jump > 0) then
        self.state.jump -= cmd.deltaTime
        if (self.state.jump < 0) then
            self.state.jump = 0
        end
    end
    
    if (onGround ~= nil) then
        --jump!
        if (cmd.y > 0 and self.state.jump <= 0) then
            self.state.vel = Vector3.new(self.state.vel.x, jumpPunch, self.state.vel.z)
            self.state.jump = 0.2 --jumping has a cooldown (think jumping up a staircase)
            self.characterData:PlayAnimation(Enums.Anims.Jump, true, 0.2)
        end
  
        --Check jumpPads
        if (onGround.hullRecord) then
            local instance = onGround.hullRecord.instance
            
            local vec3 = instance:GetAttribute("launch")
            if (vec3) then
                local dir = instance.CFrame:VectorToWorldSpace(vec3)
                self.state.vel = dir 
                self.state.jump = 0.2
                self.characterData:PlayAnimation(Enums.Anims.Jump, true, 0.2)
            end
        end
    end

    --In air?
    if (onGround == nil) then
        
        self.state.inAir += cmd.deltaTime
        if (self.state.inAir > 10) then
            self.state.inAir = 10 --Capped just to keep the state var reasonable
        end
        
        --gravity
        self.state.vel += Vector3.new(0, -198 * cmd.deltaTime, 0)
        
        --Switch to falling if we've been off the ground for a bit
        if (self.state.vel.y <=0.01 and self.state.inAir > 0.5) then
            self.characterData:PlayAnimation(Enums.Anims.Fall, false)
        end

    else
        --Land after jump
        if (self.state.inAir > 0) then
            --We don't do anything special here atm
           
        end
        self.state.inAir = 0
    end
 
    
    --Sweep the player through the world, once flat along the ground, and once "step up'd"
    local stepupResult = nil
    local walkNewPos, walkNewVel, hitSomething = self:ProjectVelocity(self.state.pos, self.state.vel, cmd.deltaTime  )
    
    -- Do we attempt a stepup?                              (not jumping!)
    if (onGround ~= nil and hitSomething == true and self.state.jump == 0) then
        stepupResult = self:DoStepUp(self.state.pos, self.state.vel, cmd.deltaTime)
    end
    
    --Choose which one to use, either the original move or the stepup
    if (stepupResult ~= nil) then
        self.state.stepUp = stepupResult.stepUp
        self.state.pos = stepupResult.pos
        self.state.vel = stepupResult.vel
    else
        self.state.pos = walkNewPos
        self.state.vel = walkNewVel
    end
    
    
    --Input/Movement is done, do the update of timers and write out values
    
    --Adjust stepup
    self:DecayStepUp(cmd.deltaTime)
    
    --position the debug visualizer
    if (self.debugModel ~= nil) then
        self.debugModel:PivotTo(CFrame.new(self.state.pos))
    end
    
    --Do angles
    if (wishDir ~= nil) then
        self.state.targetAngle = MathUtils:PlayerVecToAngle(wishDir)
        self.state.angle = MathUtils:LerpAngle( self.state.angle,  self.state.targetAngle, turnSpeedFrac * cmd.deltaTime)
    end
    
    --Write this to the characterData
    self.characterData:SetPosition(self.state.pos)  
    self.characterData:SetAngle(self.state.angle)
    self.characterData:SetStepUp(self.state.stepUp)    
    self.characterData:SetFlatSpeed(flatVel.Magnitude)
 
    debug.profileend()
    
end


--STEPUP - the magic that lets us traverse uneven world geometry
--the idea is that you redo the player movement but "if I was x units higher in the air"

function Simulation:DoStepUp(pos, vel, deltaTime)
    
    local flatVel = MathUtils:FlatVec(vel)

    --first move upwards as high as we can go
    local headHit = CollisionModule:Sweep(pos, pos + Vector3.new(0, self.stepSize, 0))

    --Project forwards
    local stepUpNewPos, stepUpNewVel, stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel, deltaTime)

    --Trace back down
    local traceDownPos = stepUpNewPos

    local hitResult = CollisionModule:Sweep(
        traceDownPos,
        traceDownPos - Vector3.new(0, self.stepSize, 0)
    )

    stepUpNewPos = hitResult.endPos

    --See if we're mostly on the ground after this? otherwise rewind it
    local ground = self:DoGroundCheck(stepUpNewPos, (-2.5 + self.stepSize))

    if (ground ~= nil) then

        local step = self.state.pos.y - stepUpNewPos.y
        
        local result = {
            stepUp = step,
            pos = stepUpNewPos,
            vel = stepUpNewVel
        }
        return result
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
    local results = CollisionModule:Sweep(pos, pos + Vector3.new(0, -0.1, 0))
    
    if (results.fraction < 1) then
        return results 
    end
    return nil 
end

function Simulation:ClipVelocity(input, normal, overbounce)
    local backoff = input:Dot(normal)

    if backoff < 0 then
        backoff = backoff * overbounce
    else
        backoff = backoff / overbounce
    end

    local changex = normal.x * backoff
    local changey = normal.y * backoff
    local changez = normal.z * backoff

    return Vector3.new(input.x - changex, input.y - changey, input.z - changez)
end

function Simulation:ProjectVelocity(startPos, startVel, deltaTime)
    local movePos = startPos
    local moveVel = startVel
    local hitSomething = false
    
  
    --Project our movement through the world
    local planes = {}
    local timeLeft = deltaTime 
      
    for bumps = 0, 3 do
   
        if moveVel.magnitude < 0.001 then
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
        if (result.fraction > 0) then
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
            moveVel = Vector3.new(0,0,0)
            break
        end
        
        --Hit!
        timeLeft -= (timeLeft * result.fraction)
        
        if (planes[result.planeNum] == nil) then
            
            planes[result.planeNum] = true
            --Deflect the velocity and keep going
            moveVel = self:ClipVelocity(moveVel, result.normal, 1.0)
        end
    end

    return movePos, moveVel, hitSomething
end

function Simulation:Accelerate(wishDir, wishSpeed, accel, velocity, dt)
    
    local speed = velocity.magnitude
    
    local currentSpeed = velocity:Dot(wishDir)
    local addSpeed = wishSpeed - currentSpeed
    
    if (addSpeed <= 0) then
        return velocity
    end
    
    local accelSpeed = accel * dt * wishSpeed
    if (accelSpeed > addSpeed) then
        accelSpeed = addSpeed
    end
    
    velocity = velocity + (accelSpeed * wishDir)
    
    --if we're already going over max speed, don't go any faster than that
    --Or you'll get strafe jumping!
    if (speed > wishSpeed and velocity.magnitude > speed) then
        velocity = velocity.unit * speed        
    end
    return velocity
end


--Todo: Compress?
function Simulation:WriteState()
    local record = {}
    
    for key,value in pairs(self.state) do
        record[key] = value
    end
    
    return record
end

function Simulation:ReadState(record)
    
    for key,value in pairs(record) do
        self.state[key] = value
    end
end

return Simulation
