local module = {}

function module:Setup(_server) end


--Basic example of visibility culling, 350 unit radius
function module:CanPlayerSee(sourcePlayer, otherPlayer)
    
    if (sourcePlayer.chickynoid == nil) then
        return true
    end
    if (otherPlayer.chickynoid == nil) then
        return true
    end

    local posA = sourcePlayer.chickynoid.simulation.state.pos
    local posB = otherPlayer.chickynoid.simulation.state.pos

    if ((posA-posB).Magnitude > 350) then
        return false
    end
    return true
end

return module