local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local Enums = require(path.Enums)

local Simulation = game.ReplicatedFirst.Packages.Chickynoid.Simulation
local MoveTypeJumping = require(Simulation.MoveTypeJumping)
--Jump Pads

function module:ModifySimulation(simulation)
    simulation:RegisterMoveState("JumpPadDetection", nil, module.AlwaysThink, nil, nil, nil)
end

function module.AlwaysThink(simulation, cmd)
    local onGround = simulation:OnGround()

    if onGround ~= nil then
        --Check jumpPads
        if onGround.hullRecord then
            local instance = onGround.hullRecord.instance

            if instance then
                local vec3 = instance:GetAttribute("launch")
                --Jump!
                if vec3 then
                    simulation.state.vel = instance.CFrame:VectorToWorldSpace(vec3)

                    MoveTypeJumping.StartJump(simulation)
                end

                --For platform standing
                if simulation.state.jump == 0 then
                    simulation.lastGround = onGround
                end
            end
        end
    end
end

return module
