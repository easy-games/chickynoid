local module = {}

--Implements basic killbrick functionality
--Any collidable part tagged with kill==true will instantly drop your HP to 0, calculated on the server
local path = game.ReplicatedFirst.Packages.Chickynoid
local ServerMods = require(path.Server.ServerMods)

function module:Setup(_server) end

function module:Step(server, _deltaTime)
    local playerRecords = server:GetPlayers()

    for _, playerRecord in pairs(playerRecords) do
        --No character at the moment
        if playerRecord.chickynoid == nil then
            continue
        end

        local simulation = playerRecord.chickynoid.simulation
        local part = simulation:GetStandingPart()

        if part then
            if part:GetAttribute("kill") == true then
                --kill!
                local HitPoints = ServerMods:GetMod("servermods","Hitpoints")
                if HitPoints then
                    HitPoints:SetPlayerHitPoints(playerRecord, 0)
                end
            end
        end
    end
end

return module
