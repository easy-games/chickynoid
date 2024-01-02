local module = {}

function module:Setup(server)
    --Give spawning players 100 hp
    server.OnPlayerSpawn:Connect(function(playerRecord)
        playerRecord.hitPoints = 100
    end)
end

function module:Step(server, _deltaTime)
    local playerRecords = server:GetPlayers()

    for _, playerRecord in pairs(playerRecords) do
        --No character at the moment
        if playerRecord.chickynoid == nil then
            continue
        end

        if playerRecord.hitPoints <= 0 then
            playerRecord:Despawn()
        end
    end
end

function module:DamagePlayer(playerRecord, damage)
    playerRecord.hitPoints -= damage
end

function module:GetPlayerHitPoints(playerRecord)
    return playerRecord.hitPoints
end

function module:SetPlayerHitPoints(playerRecord, hp)
    playerRecord.hitPoints = hp
end

return module