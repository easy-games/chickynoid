local module = {}

function module:Setup(server)

    --Give spawning players a weapon
    server.OnPlayerSpawn:Connect(function(playerRecord)
                
        --Give a machine gun
        --playerRecord:AddWeaponByName("Machinegun", true)
        playerRecord:AddWeaponByName("ProjectileSniper", true)
        
    end)

    server.OnBeforePlayerSpawn:Connect(function(playerRecord)
    
        playerRecord.chickynoid.simulation:SetAngle(math.rad(90), true)
    
    end)


    server.OnPlayerDespawn:Connect(function(playerRecord)
        --Remove all guns
        playerRecord:ClearWeapons()
    end)
end

function module:Step(_server, _deltaTime) end

return module