local module = {}

--Jump Pads

function module:Setup(_server) end

function module:Step(server, _deltaTime)
    local playerRecords = server:GetPlayers()

    for _, playerRecord in pairs(playerRecords) do
        --No character at the moment
        if playerRecord.chickynoid == nil then
            continue
        end

        local simulation = playerRecord.chickynoid.simulation
        local onGround = simulation:GetStandingPart()

        if onGround ~= nil then
            --Check jumpPads
            if onGround.hullRecord then
                local instance = onGround.hullRecord.instance

                if instance then
                    local vec3 = instance:GetAttribute("launch")
                    --Jump!
                    if vec3 then
                        simulation.state.vel = instance.CFrame:VectorToWorldSpace(vec3)

                        simulation:SetMoveState("Jumping")
                    end

                    --For platform standing
                    if simulation.state.jump == 0 then
                        simulation.lastGround = onGround
                    end
                end
            end
        end
    end
end

return module
