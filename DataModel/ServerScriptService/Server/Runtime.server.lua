local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages

local Server = require(Packages.Chickynoid.Server)
local Enums = require(Packages.Chickynoid.Enums)

Server:SetConfig({
    simulationConfig = {
        -- stepSize = 3,
    },
})

Server:Setup()

Players.PlayerAdded:Connect(function(player)
    
    local record = {}
    record.player = player
    record.dummy = false
    record.name = player.Name
    record.userId = player.UserId
    local chickynoid = Server:SpawnForPlayerAsync(record)
 
end)

Players.PlayerRemoving:Connect(function(player)

    Server:PlayerDisconnected(player.UserId)

end)



RunService.Heartbeat:Connect(function(deltaTime)
    Server:Think(deltaTime)
end)



--debug harness
local debugPlayers = {}
function MakeDebugPlayers()
    
    for counter = 1, 20 do
        local record = {}
        
        record.player = {}
        record.name = "RandomBot" .. counter
        record.dummy = true
        record.frame = 0
        record.userId = -10000-counter
        
        record.waitTime = 0 --Bot AI
            
        record.chickynoid =  Server:SpawnForPlayerAsync(record)
        table.insert(debugPlayers, record)
        
        record.chickynoid:SetPosition(Vector3.new(math.random(-150,150),60,math.random(-150,150) ))
        
        record.BotThink = function(deltaTime)
            
            
            if (record.waitTime>0) then
                record.waitTime -= deltaTime
            end
            
            local event = {}
            event.t = Enums.EventType.Command
            event.command = {}
            event.command.l = record.frame
            event.command.x = 0
            event.command.y = 0
            event.command.z =  0
            event.command.deltaTime = deltaTime
            
            if (record.waitTime <=0) then
                event.command.x = math.sin(record.frame*0.03)
                event.command.y = 0
                event.command.z =  math.cos(record.frame*0.03)
      
                if (math.random() < 0.05) then
                    event.command.y = 1
                end
            end
            
            if (math.random() < 0.01) then
                record.waitTime = math.random() * 3                
            end
            
            record.frame += 1
            
            record.chickynoid:HandleEvent(event)
           
        end
    end
    
end

--MakeDebugPlayers()


 