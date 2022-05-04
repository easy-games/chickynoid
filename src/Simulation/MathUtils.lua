local MathUtils = {}

local THETA = math.pi * 2
function MathUtils:AngleAbs(angle)
    while angle < 0 do
        angle = angle + THETA
    end
    while angle > THETA do
        angle = angle - THETA
    end
    return angle
end

function MathUtils:AngleShortest(a0, a1)
    local d1 = self:AngleAbs(a1 - a0)
    local d2 = -self:AngleAbs(a0 - a1)
    return math.abs(d1) > math.abs(d2) and d2 or d1
end

function MathUtils:LerpAngle(a0, a1, frac)
    return a0 + self:AngleShortest(a0, a1) * frac
end

function MathUtils:PlayerVecToAngle(vec)
    return math.atan2(-vec.z, vec.x) - math.rad(90)
end

function MathUtils:PlayerAngleToVec(angle)
    return Vector3.new(math.sin(angle), 0, math.cos(angle))
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

return MathUtils
