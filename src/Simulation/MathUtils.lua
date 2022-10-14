local MathUtils = {}

local PI = math.pi
local TAU = 2*PI

-- returns 0 <= angle' < TAU such that rotation(angle') == rotation(angle)
function MathUtils:AngleAbs(angle)
    return angle%TAU
end

-- returns angle' closest to referenceAngle or 0 such that rotation(angle') == rotation(angle)
function MathUtils:AngleNormalize(angle, referenceAngle)
    referenceAngle = referenceAngle or 0
    return (angle - referenceAngle + PI)%TAU - PI + referenceAngle
end

function MathUtils:AngleShortest(a0, a1)
    return self:AngleNormalize(a1 - a0)
end

function MathUtils:LerpAngle(a0, a1, frac)
    return a0 + self:AngleShortest(a0, a1) * frac
end

-- returns angleY, angleX such that PlayerAngleToVec(angleY, angleX) == vec.unit
-- and such that angleY and angleX are closest to 0
function MathUtils:PlayerVecToAngle(vec)
    local x, y, z = vec.x, vec.y, vec.z
    local l = math.sqrt(x*x + z*z)
    return
        math.atan2(x, z),
        math.atan2(y, l)
end

-- returns vec such that PlayerVecToAngle(vec) == angleY, angleX
function MathUtils:PlayerAngleToVec(angleY, angleX)
    angleX = angleX or 0
    local sinX = math.sin(angleX)
    local cosX = math.cos(angleX)
    return Vector3.new(math.sin(angleY)*cosX, sinX, math.cos(angleY)*cosX)
end

--dt variable decay function
function MathUtils:Friction(val, fric, deltaTime)
    return (1 / (1 + (deltaTime / fric))) * val
end

function MathUtils:VelocityFriction(vel, fric, deltaTime)
    local speed = vel.magnitude
    speed = self:Friction(speed, fric, deltaTime)

    if speed < 0.001 then
        return Vector3.new(0, 0, 0)
    end
    vel = vel.unit * speed

    return vel
end

function MathUtils:FlatVec(vec)
    return Vector3.new(vec.x, 0, vec.z)
end


--Redirects velocity
function MathUtils:GroundAccelerate(wishDir, wishSpeed, accel, velocity, dt)
    --Cap velocity
    local speed = velocity.Magnitude
    if speed > wishSpeed then
        velocity = velocity.unit * wishSpeed
    end

    local wishVel = wishDir * wishSpeed
    local pushDir = wishVel - velocity

    local pushLen = pushDir.magnitude

    local canPush = accel * dt * wishSpeed

    if canPush > pushLen then
        canPush = pushLen
    end
    if canPush < 0.00001 then
        return velocity
    end
    return velocity + (canPush * pushDir.Unit)
end

function MathUtils:Accelerate(wishDir, wishSpeed, accel, velocity, dt)
    local speed = velocity.magnitude

    local currentSpeed = velocity:Dot(wishDir)
    local addSpeed = wishSpeed - currentSpeed

    if addSpeed <= 0 then
        return velocity
    end

    local accelSpeed = accel * dt * wishSpeed
    if accelSpeed > addSpeed then
        accelSpeed = addSpeed
    end

    velocity = velocity + (accelSpeed * wishDir)

    --if we're already going over max speed, don't go any faster than that
    --Or you'll get strafe jumping!
    if speed > wishSpeed and velocity.magnitude > speed then
        velocity = velocity.unit * speed
    end
    return velocity
end

function MathUtils:CapVelocity(velocity, maxSpeed)
    local mag = velocity.magnitude
    mag = math.min(mag, maxSpeed)
    if mag > 0.01 then
        return velocity.Unit * mag
    end
    return Vector3.zero
end


function MathUtils:ClipVelocity(input, normal, overbounce)
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

--Smoothlerp for lua. "Zeno would be proud!"
--Use it in a feedback loop over multiple frames to converge A towards B, in a deltaTime safe way
--eg:  cameraPos = SmoothLerp(cameraPos, target, 0.5, deltaTime)
--Handles numbers and types that implement Lerp like Vector3 and CFrame

function MathUtils:SmoothLerp(variableA, variableB, fraction, deltaTime)

    local f = 1.0 - math.pow(1.0 - fraction, deltaTime)

    if (type(variableA) == "number") then
        return ((1-f) * variableA) + (variableB * f)
    end

    return variableA:Lerp(variableB, f)
end

return MathUtils
