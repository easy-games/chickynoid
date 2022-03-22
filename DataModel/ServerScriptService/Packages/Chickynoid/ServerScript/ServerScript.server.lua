local Players = game:GetService("Players")
local RunService = game:GetService("RunService")


local Server = require(game.ServerScriptService.Packages.Chickynoid.Server.Server)
local Enums = require(game.ReplicatedFirst.Packages.Chickynoid.Enums)
 

Server:Setup()

Players.PlayerAdded:Connect(function(player)
    
    local playerRecord = Server:AddConnection(player.UserId, player)
    playerRecord.chickynoid = Server:CreateChickynoidAsync(playerRecord)
        
    --Spawn the gui
    for _,child in pairs(game.StarterGui:GetChildren()) do
        local clone = child:Clone()
        if (clone:IsA("ScreenGui")) then
            clone.ResetOnSpawn = false
        end
        clone.Parent = playerRecord.player.PlayerGui 
    end
    
end)

Players.PlayerRemoving:Connect(function(player)

    Server:PlayerDisconnected(player.UserId)

end)



--Step the game along at a rigid 60fps
local elapsedTime = 0
local timeSinceLastThink = 0
local frameCount = 0
local frameCountTime = 0

RunService.Heartbeat:Connect(function(deltaTime)
    
    frameCountTime += deltaTime
    
    if (elapsedTime > 0.5) then
        elapsedTime = 0
    end
    
    elapsedTime += deltaTime
    local frac = 1/60 
    while (elapsedTime > 0) do
        elapsedTime -= frac
        Server:Think(frac)        
    end
end)



--debug harness
local debugPlayers = {}
function MakeDebugPlayers()
    
    --Always the same seed
    math.randomseed(1)
    for counter = 1, 100 do
        
        local userId = -10000-counter
        local playerRecord = Server:AddConnection(userId, nil)
                
        playerRecord.name = "RandomBot" .. counter
        
        playerRecord.waitTime = 0 --Bot AI
        playerRecord.leftOrRight = 1 
        
        if (math.random()>0.5) then
            playerRecord.leftOrRight = -1
        end
            
        playerRecord.chickynoid = Server:CreateChickynoidAsync(playerRecord)
        table.insert(debugPlayers, playerRecord)
        
        playerRecord.chickynoid:SetPosition(Vector3.new(math.random(-150,150), 4000 ,math.random(-150,150) ) + Vector3.new(-150, 0,0)) 
        
        playerRecord.BotThink = function(deltaTime)
            
            
            if (playerRecord.waitTime > 0) then
                playerRecord.waitTime -= deltaTime
            end
            
            local event = {}
            event.t = Enums.EventType.Command
            event.command = {}
            event.command.l = playerRecord.frame
            event.command.x = 0
            event.command.y = 0
            event.command.z = 0
            event.command.serverTime = tick()
            event.command.deltaTime = deltaTime
            
            if (playerRecord.waitTime <=0) then
                event.command.x = math.sin(playerRecord.frame*0.03 * playerRecord.leftOrRight)
                event.command.y = 0
                event.command.z =  math.cos(playerRecord.frame*0.03 * playerRecord.leftOrRight)
      
                if (math.random() < 0.05) then
                    event.command.y = 1
                end
            end
            
            if (math.random() < 0.01) then
                playerRecord.waitTime = math.random() * 5                
            end
            
            playerRecord.frame += 1
            
            playerRecord.chickynoid:HandleEvent(event)
           
        end
    end
    
end

MakeDebugPlayers()


 