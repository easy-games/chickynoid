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
--This isn't the same technique clients use, because we want clients to have variable (capped!) fps
local MAX_FPS = 60
local elapsedTime = 0
local timeSinceLastThink = 0
local frameCount = 0
local frameCountTime = 0

RunService.Heartbeat:Connect(function(deltaTime)
    
    frameCountTime += deltaTime
    
    elapsedTime += deltaTime
    timeSinceLastThink += deltaTime
    
    if (elapsedTime < 1/MAX_FPS) then
        return
    end
    
    frameCount+=1
    if (frameCountTime>1) then
        --print("FPS:",frameCount)
        frameCountTime -= 1
        frameCount = 0        
    end
    
    Server:Think(timeSinceLastThink)
    timeSinceLastThink = 0
    
    --Could replace this with a modf
    while(elapsedTime > 1/MAX_FPS) do
        elapsedTime -= 1/MAX_FPS
    end
       
end)



--debug harness
local debugPlayers = {}
function MakeDebugPlayers()
    
    --Always the same seed
    math.randomseed(1)
    for counter = 1, 20 do
        
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
        
        playerRecord.chickynoid:SetPosition(Vector3.new(math.random(-150,150), 60 ,math.random(-150,150) ) + Vector3.new(-150, 0,0)) 
        
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
                playerRecord.waitTime = math.random() * 3                
            end
            
            playerRecord.frame += 1
            
            playerRecord.chickynoid:HandleEvent(event)
           
        end
    end
    
end

MakeDebugPlayers()


 