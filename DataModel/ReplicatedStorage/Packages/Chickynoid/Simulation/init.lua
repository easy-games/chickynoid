--[=[
    @class Simulation
    Simulation handles physics for characters on both the client and server.
]=]

local Types = require(script.Parent.Types)

local Simulation = {}
Simulation.__index = Simulation

local playerSize = Vector3.new(3,5,3)

Simulation.collisionModule = require(script.CollisionModule)
Simulation.characterData = require(script.CharacterData)
local Enums = require(script.Parent.Enums)

function Simulation.new(config: Types.ISimulationConfig)
    local self = setmetatable({}, Simulation)

    self.state = {}
     
    self.state.pos = Vector3.new(0, 5, 0)
    self.state.vel = Vector3.new(0, 0, 0)
    self.state.jump = 0
    self.state.angle = 0
    self.state.targetAngle = 0
    self.state.stepUp = 0
    
    
    self.characterData = self.characterData.new()
    self.whiteList = config.raycastWhitelist

    --players feet height - height goes from -2.5 to +2.5
    --So any point below this number is considered the players feet
    --the distance between middle and feetHeight is "ledge"
    self.feetHeight = config.feetHeight

    -- How big an object we can step over
    self.stepSize = config.stepSize
 
    local buildDebugSphereModelThing = false

    if buildDebugSphereModelThing == true then
        local model = Instance.new("Model")
        model.Name = "Chickynoid"

        local part = Instance.new("Part")
        self.debugMarker = part
        part.Size = playerSize
        part.Shape = Enum.PartType.Block
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Parent = model
        part.Anchored = true
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Transparency = 0.4
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Color3.new(0, 1, 1)

        model.PrimaryPart = part
        model.Parent = game.Workspace
        self.debugModel = model

    
    end
    
    --THIS DOES NOT GO HERE LOL
    
    if (#Simulation.collisionModule.hullRecords == 0) then
        Simulation.collisionModule:MakeWorld(game.Workspace.GameArea, playerSize )
    end

    
    return self
end

--	It is very important that this method rely only on whats in the cmd object
--	and no other client or server state can "leak" into here
--	or the server and client state will get out of sync.
--	You'll have to manage it so clients/server see the same thing in workspace.GameArea for raycasts...

function Simulation:ProcessCommand(cmd)
    
    debug.profilebegin("Chickynoid Simulation")

    --Ground parameters
    local maxSpeed = 20 --Units per second
    local airSpeed = 20
    local accel = 4.5   --Units per second per second
    local airAccel = 5.0  --Different than ground accel!
    local jumpPunch = 70  -- Raw velocity
    local brakeFriction = 0.05  -- Lower is brake harder, dont use 0
    local turnSpeedFrac = 5
    local onGround = nil
   
    --Check ground
    onGround = self:DoGroundCheck(self.state.pos)

    --Figure out our acceleration (airmove vs on ground)
    if onGround == nil then
        --different if we're in the air?
    end

    --Did the player have a movement request?
    local wishDir = nil
    local flatVel = Vector3.new(self.state.vel.x, 0, self.state.vel.z)

    if cmd.x ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
    end

    
    local shouldBrake = false
    
    --see if we're accelerating back against our current flatvel (eg: turning around/strafing)
    if(onGround ~= nil) then
        
        --Are we just standing still?
        if wishDir == nil then
            shouldBrake = true
        end
        if wishDir ~= nil and wishDir:Dot(flatVel.Unit) < -0.1 then
            --This makes things much more snappy!
            --shouldBrake = true
        end 
    end

    --Apply braking
    if shouldBrake == true then
        flatVel = self:Friction(flatVel, brakeFriction, cmd.deltaTime) 
    end

    --movement acceleration (walking/running/airmove)
    --Does nothing if we don't have an input
    if wishDir ~= nil then
        
        --Also trigger walking
        if (onGround) then
            self.characterData:PlayAnimation(Enums.Anims.Run, false,0.3) --make run animation a tiny bit sticky
            
            local inVec = flatVel
            flatVel = self:GroundAccelerate(wishDir, maxSpeed, accel, flatVel, cmd.deltaTime)
        else
            self.characterData:PlayAnimation(Enums.Anims.Fall, false) --Airmove
            flatVel = self:AirAccelerate(wishDir, airSpeed, airAccel, flatVel, cmd.deltaTime)
        end
        
        
    else
        if (onGround) then
            self.characterData:PlayAnimation(Enums.Anims.Idle, false)
        else
            self.characterData:PlayAnimation(Enums.Anims.Fall, false)
        end
        
    end

    self.state.vel = Vector3.new(flatVel.x, self.state.vel.y, flatVel.z)
    
    --Do jumping?
    
    if self.state.jump > 0 then
        self.state.jump -= cmd.deltaTime
        if (self.state.jump < 0) then
            self.state.jump = 0
        end
    end
    
    if onGround ~= nil then

        --jump!
        if cmd.y > 0 and self.state.jump <= 0 then
            self.state.vel = Vector3.new( self.state.vel.x, jumpPunch, self.state.vel.z)
            self.state.jump = 0.2
            self.characterData:PlayAnimation(Enums.Anims.Jump, true, 0.1)
        end
        
        
        --Check jumpPads
        if (onGround.hullRecord) then
            local instance = onGround.hullRecord.instance
            
            local vec3 = instance:GetAttribute("launch")
            if (vec3) then
                print("Voosh!")
                local dir = instance.CFrame:VectorToWorldSpace(vec3)
                self.state.vel = dir 
            end
        end
    end

    --Gravity
    if onGround == nil then
        --gravity
        self.state.vel += Vector3.new(0, -198 * cmd.deltaTime, 0)
    end
    
    
    --Sweep the player through the world
    local walkNewPos, walkNewVel, hitSomething = self:ProjectVelocity(self.state.pos, self.state.vel, cmd.deltaTime  )
  
   
    --STEPUP - the magic that lets us traverse uneven world geometry
    --the idea is that you redo the player movement but "if I was x units higher in the air"
    --it adds a lot of extra casts...
    local flatVel = Vector3.new(self.state.vel.x, 0, self.state.vel.z)
    
    -- Do we even need to?                               (not jumping!)
    if (onGround ~= nil  and hitSomething == true and self.state.jump == 0) then
        
        --first move upwards as high as we can go
        local headHit = self.collisionModule:Sweep(self.state.pos, self.state.pos + Vector3.new(0, self.stepSize, 0))
        
        --Project forwards
        local stepUpNewPos, stepUpNewVel, stepHitSomething = self:ProjectVelocity(headHit.endPos, flatVel, cmd.deltaTime)

        --Trace back down
        local traceDownPos = stepUpNewPos

        local hitResult = self.collisionModule:Sweep(
            traceDownPos,
            traceDownPos - Vector3.new(0, self.stepSize, 0)
        )

        stepUpNewPos = hitResult.endPos

        --See if we're mostly on the ground after this? otherwise rewind it
        local ground = self:DoGroundCheck(stepUpNewPos, (-2.5 + self.stepSize))

        if ground ~= nil then
            
            local step = self.state.pos.y - stepUpNewPos.y
            self.state.stepUp += step
            
            self.state.pos = stepUpNewPos
            self.state.vel = stepUpNewVel
        else
            --cancel the whole thing
            --NO STEPUP
            self.state.pos = walkNewPos
            self.state.vel = walkNewVel
        end
    else
        --NO STEPUP
        self.state.pos = walkNewPos
        self.state.vel = walkNewVel
    end
 
    
    --position the debug visualizer
    if self.debugModel then
        self.debugModel:PivotTo(CFrame.new(self.state.pos))
    end
    
    --Do angles
    if (wishDir ~= nil) then
        self.state.targetAngle = math.atan2(-wishDir.z, wishDir.x) - math.rad(90)
        self.state.angle = self:LerpAngle( self.state.angle,  self.state.targetAngle, turnSpeedFrac * cmd.deltaTime)
    end
    
    
    --Adjust stepup
    self:DecayStepUp(cmd.deltaTime)
    
    --Write this to the characterData
    self.characterData:SetPosition(self.state.pos)
    self.characterData:SetAngle(self.state.angle)
    self.characterData:SetStepUp(self.state.stepUp)    
    -- print(self.state.vel ,cmd.deltaTime)

    debug.profileend()
end


function Simulation:Destroy()
    if self.debugModel then
        self.debugModel:Destroy()
    end
end


function Simulation:DecayStepUp(deltaTime)
    self.state.stepUp *= 45 * deltaTime 
end

function Simulation:FlatVec(vec)
    return Vector3.new(vec.x,0,vec.z)
end


function Simulation:DoGroundCheck(pos)
    local results = self.collisionModule:Sweep(pos, pos + Vector3.new(0, -0.1, 0))
    
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
        local result = self.collisionModule:Sweep(movePos, movePos + (moveVel * timeLeft))
        
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


local THETA = math.pi * 2
function Simulation:AngleAbs(angle)
    while angle < 0 do
        angle = angle + THETA
    end
    while angle > THETA do
        angle = angle - THETA
    end
    return angle
end

function Simulation:AngleShortest(a0, a1)
    local d1 = self:AngleAbs(a1 - a0)
    local d2 = -self:AngleAbs(a0 - a1)
    return math.abs(d1) > math.abs(d2) and d2 or d1
end

function Simulation:LerpAngle(a0, a1, frac)
    return a0 + self:AngleShortest(a0, a1) * frac
end

function Simulation:GroundAccelerate(wishDir, wishSpeed, accel, velocity, dt)
    
    local dot = wishDir:Dot(velocity)
    
    
    
    local wishVel = wishDir * wishSpeed
    local pushDir = wishVel - velocity
    local pushLen = pushDir.magnitude
    
    local canPush = accel * dt * wishSpeed
    if (canPush > pushLen) then
        canPush = pushLen
    end
    velocity += pushDir * canPush 
    
    --Because we're on the ground, make sure we can never go faster than our feet allow
    --(this prevents direction deflection on crash lands too)   
    if (velocity.magnitude > wishSpeed) then
        velocity = velocity.unit * wishSpeed
    end
    
    return velocity
end

function Simulation:AirAccelerate(wishDir, wishSpeed, accel, velocity, dt)
    
    --This was difficult to derive!
    --first we calculate a "allowedChange" scalar
    --Essentially, in situations like boost pads we want an allowed change of 1 for orthogonal or behind, and 0..1 up to max speed    
    --So you can't accelerate "faster" than maxspeed 
    
    local dot = wishDir:Dot(velocity)
    local projected = self:VectorProject( velocity,(wishDir*wishSpeed)).magnitude
 
    if (dot < 0) then --back the other way?
        projected = - projected
    end
    
    local allowedChange = wishSpeed - projected  
    allowedChange = math.clamp(allowedChange, 0, wishSpeed)
    allowedChange/= wishSpeed

    local change = accel * dt * wishSpeed * allowedChange
    velocity += wishDir * change
    
    return velocity

end

function Simulation:VectorProject(vector, onNormal)

    local sqrMag = onNormal:Dot(onNormal)
    if (sqrMag < 0.00001) then
        return Vector3.zero
    end
    
    local dot = vector:Dot(onNormal)
    
    return Vector3.new(onNormal.x * dot / sqrMag,
                       onNormal.y * dot / sqrMag,
                       onNormal.z * dot / sqrMag)
end

--dt variable friction function
function Simulation:Friction(val, fric, deltaTime)
    return	(1 / (1 + (deltaTime / fric)) ) * val
end

--This could be a lot more classy!
function Simulation:WriteState()
    local record = {}
    record.pos = self.state.pos
    record.vel = self.state.vel
    record.jump = self.state.jump
    record.angle = self.state.angle
    record.wishAngle = self.state.wishAngle
    record.stepUp = self.state.stepUp
    return record
end

--This too!
function Simulation:ReadState(record)
    
    self.state.pos = record.pos 
    self.state.vel = record.vel
    self.state.jump = record.jump
    self.state.angle = record.angle
    self.state.wishAngle = record.wishAngle
    self.state.stepUp = record.stepUp
end

return Simulation
