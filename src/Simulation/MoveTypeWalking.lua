local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local Enums = require(path.Enums)
local MathUtils = require(script.Parent.MathUtils)

function module.AlwaysThink(simulation, cmd)
    --Check ground
    local onGround = simulation:OnGround()

    --Mark if we were onground at the start of the frame
    local startedOnGround = onGround

    --In air?
    if onGround == nil then
        simulation.state.inAir += cmd.deltaTime
        if simulation.state.inAir > 10 then
            simulation.state.inAir = 10 --Capped just to keep the state var reasonable
        end

        --Jump thrust
        if cmd.y > 0 then
            if simulation.state.jumpThrust > 0 then
                simulation.state.vel += Vector3.new(0, simulation.state.jumpThrust * cmd.deltaTime, 0)
                simulation.state.jumpThrust = MathUtils:Friction(
                    simulation.state.jumpThrust,
                    simulation.constants.jumpThrustDecay,
                    cmd.deltaTime
                )
            end
            if simulation.state.jumpThrust < 0.001 then
                simulation.state.jumpThrust = 0
            end
        else
            simulation.state.jumpThrust = 0
        end

        --gravity
        simulation.state.vel += Vector3.new(0, simulation.constants.gravity * cmd.deltaTime, 0)

        --Switch to falling if we've been off the ground for a bit
        if simulation.state.vel.y <= 0.01 and simulation.state.inAir > 0.5 then
            simulation.characterData:PlayAnimation(Enums.Anims.Fall, false)
        end
    else
        simulation.state.inAir = 0
    end

    --Sweep the player through the world, once flat along the ground, and once "step up'd"
    local stepUpResult = nil
    local walkNewPos, walkNewVel, hitSomething = simulation:ProjectVelocity(
        simulation.state.pos,
        simulation.state.vel,
        cmd.deltaTime
    )

    --Did we crashland
    if onGround == nil and hitSomething == true then
        --Land after jump
        local groundCheck = simulation:DoGroundCheck(walkNewPos)

        if groundCheck ~= nil then
            --Crashland
            walkNewVel = simulation:CrashLand(walkNewVel)
        end
    end

    -- Do we attempt a stepup?                              (not jumping!)
    if onGround ~= nil and hitSomething == true and simulation.state.jump == 0 then
        stepUpResult = simulation:DoStepUp(simulation.state.pos, simulation.state.vel, cmd.deltaTime)
    end

    --Choose which one to use, either the original move or the stepup
    if stepUpResult ~= nil then
        simulation.state.stepUp += stepUpResult.stepUp
        simulation.state.pos = stepUpResult.pos
        simulation.state.vel = stepUpResult.vel
    else
        simulation.state.pos = walkNewPos
        simulation.state.vel = walkNewVel
    end

    --Do stepDown
    if true then
        if startedOnGround ~= nil and simulation.state.jump == 0 and simulation.state.vel.y <= 0 then
            local stepDownResult = simulation:DoStepDown(simulation.state.pos)
            if stepDownResult ~= nil then
                simulation.state.stepUp += stepDownResult.stepDown
                simulation.state.pos = stepDownResult.pos
            end
        end
    end
end

function module.ActiveThink(simulation, cmd)
    --Check ground
    local onGround = simulation:OnGround()

    --Did the player have a movement request?
    local wishDir = nil
    if cmd.x ~= 0 or cmd.z ~= 0 then
        wishDir = Vector3.new(cmd.x, 0, cmd.z).Unit
        simulation.state.pushDir = Vector2.new(cmd.x, cmd.z)
    else
        simulation.state.pushDir = Vector2.new(0, 0)
    end

    --Create flat velocity to operate our input command on
    --In theory this should be relative to the ground plane instead...
    local flatVel = MathUtils:FlatVec(simulation.state.vel)

    --Does the player have an input?
    if wishDir ~= nil then
        if onGround then
            --Moving along the ground under player input

            flatVel = MathUtils:GroundAccelerate(
                wishDir,
                simulation.constants.maxSpeed,
                simulation.constants.accel,
                flatVel,
                cmd.deltaTime
            )

            --Good time to trigger our walk anim
            if simulation.state.pushing > 0 then
                simulation.characterData:PlayAnimation(Enums.Anims.Push, false)
            else
                simulation.characterData:PlayAnimation(Enums.Anims.Walk, false)
            end
        else
            --Moving through the air under player control
            flatVel = MathUtils:Accelerate(
                wishDir,
                simulation.constants.airSpeed,
                simulation.constants.airAccel,
                flatVel,
                cmd.deltaTime
            )
        end
    else
        if onGround ~= nil then
            --Just standing around
            flatVel = MathUtils:VelocityFriction(flatVel, simulation.constants.brakeFriction, cmd.deltaTime)

            --Enter idle
            simulation.characterData:PlayAnimation(Enums.Anims.Idle, false)
            -- else
            --moving through the air with no input
        end
    end

    --Turn out flatvel back into our vel
    simulation.state.vel = Vector3.new(flatVel.x, simulation.state.vel.y, flatVel.z)

    --Do angles
    if wishDir ~= nil then
        simulation.state.targetAngle = MathUtils:PlayerVecToAngle(wishDir)
        simulation.state.angle = MathUtils:LerpAngle(
            simulation.state.angle,
            simulation.state.targetAngle,
            simulation.constants.turnSpeedFrac * cmd.deltaTime
        )
    end
end

return module
