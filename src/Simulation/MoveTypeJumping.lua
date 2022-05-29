local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local Enums = require(path.Enums)

function module.AlwaysThink(simulation, cmd)
    --Check ground
    local onGround = simulation:OnGround()

    if simulation.state.jump > 0 then
        simulation.state.jump -= cmd.deltaTime
        if simulation.state.jump < 0 then
            simulation.state.jump = 0
        end
    end

    if onGround ~= nil then
        if cmd.y > 0 and simulation.state.jump <= 0 then
            simulation:SetMoveState("Jumping")
        else
            simulation:SetMoveState("Walking")
        end
    end
end

function module.ActiveThink(simulation, cmd)
    --Check ground
    local onGround = simulation:OnGround()

    --Do jumping?
    if onGround ~= nil then
        --jump!
        if cmd.y > 0 and simulation.state.jump <= 0 then
            simulation.state.vel = Vector3.new(
                simulation.state.vel.x,
                simulation.constants.jumpPunch,
                simulation.state.vel.z
            )
            simulation.state.jump = 0.2 --jumping has a cooldown (think jumping up a staircase)
            simulation.state.jumpThrust = simulation.constants.jumpThrustPower
            simulation.characterData:PlayAnimation(Enums.Anims.Jump, true, 0.2)
        end
    end
end

return module
