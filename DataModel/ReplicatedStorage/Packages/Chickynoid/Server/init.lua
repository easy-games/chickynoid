--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local DefaultConfigs = require(script.Parent.DefaultConfigs)
local Types = require(script.Parent.Types)
local TableUtil = require(script.Parent.Vendor.TableUtil)
local Enums = require(script.Parent.Enums)
local EventType = Enums.EventType
local ServerChickynoid = require(script.ServerChickynoid)
local ServerConfig = TableUtil.Copy(DefaultConfigs.DefaultServerConfig, true)
local BitBuffer = require(script.Parent.Vendor.BitBuffer)
local ChickynoidServer = {}

ChickynoidServer.playerRecords = {}
ChickynoidServer.serverStepTimer = 0
ChickynoidServer.serverTotalFrames = 0
ChickynoidServer.serverTotalTime = 0
ChickynoidServer.startTime = tick()

local SERVER_HZ = 20

function ChickynoidServer:Setup()
    
    script.Parent.RemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        
        local playerRecord = self:GetPlayerByUserId(player.UserId)
        
        if (playerRecord) then
            playerRecord.chickynoid:HandleEvent(event)
        end
        
    end)
    
end

function ChickynoidServer:PlayerDisconnected(userId)
    
    local playerRecord = self.playerRecords[userId]
    
    if (playerRecord) then
        print("Player disconnected")
        
        self.playerRecords[userId] = nil
    end
end


function ChickynoidServer:GetPlayerByUserId(userId)
    
    return self.playerRecords[userId]
end

function ChickynoidServer:SetConfig(config: Types.IServerConfig)
    local newConfig = TableUtil.Reconcile(config, DefaultConfigs.DefaultServerConfig)
    ServerConfig = newConfig
    print("Set server config to:", ServerConfig)
end

--[=[
    Spawns a new Chickynoid for the specified player.

    @param player Player -- The player to spawn this Chickynoid for.
    @return ServerCharacter -- New chickynoid instance made for this player.
]=]
function ChickynoidServer:SpawnForPlayerAsync(playerRecord)
  

    function playerRecord:SendEventToClient(event)
        if (playerRecord.dummy == false) then
            script.Parent.RemoteEvent:FireClient(playerRecord.player, event)
        end
    end
    
    --Send worldstate
    local event = {}
    event.t = Enums.EventType.WorldState
    event.worldState = {}
    event.worldState.serverHz = SERVER_HZ
    playerRecord:SendEventToClient(event)    
    
    
    --Todo: dont just spawn a character like this, handle the connection and wait for the game to ask
    local chickynoid = ServerChickynoid.new(playerRecord, ServerConfig)
    self.playerRecords[playerRecord.userId] = playerRecord 
    playerRecord.chickynoid = chickynoid
    
    return chickynoid
end

function ChickynoidServer:Think(deltaTime)

    --1st stage, pump the commands
    --Many many todos on this!
    for userId,playerRecord in pairs(self.playerRecords) do
        
        if (playerRecord.dummy==true) then
            playerRecord.BotThink(deltaTime)
        end
        playerRecord.chickynoid:Think(deltaTime)
    end    
    
    -- 2nd stage: Replicate character state to the player
    self.serverStepTimer += deltaTime
    self.serverTotalFrames += 1
    self.serverTotalTime = tick() - self.startTime
    
    local fraction =  (1 / SERVER_HZ)
    if self.serverStepTimer > fraction then
        
        while (self.serverStepTimer > fraction) do -- -_-'
            self.serverStepTimer -= fraction 
        end
        
  
        
        for userId,playerRecord in pairs(self.playerRecords) do
            --Not for you, bot!
            if (playerRecord.dummy == true) then
                continue
            end
            
            local event = {}
            event.t = EventType.State
            event.lastConfirmed = playerRecord.chickynoid.lastConfirmedCommand
            event.state = playerRecord.chickynoid.simulation:WriteState()
            playerRecord:SendEventToClient(event)
            
            
            local snapshot = {}
            snapshot.t = EventType.Snapshot
            
            
            local count = 0
            for otherUserId,otherPlayerRecord in pairs(self.playerRecords) do
                if (otherUserId ~= userId) then
                    count += 1
                end
            end
            
            local bitBuffer = BitBuffer()
            bitBuffer.writeByte(count)
            
            for otherUserId,otherPlayerRecord in pairs(self.playerRecords) do
                if (otherUserId ~= userId) then
                    --Todo: delta compress , bitwise compress, etc etc    
                    bitBuffer.writeSigned(48, otherUserId)
                    otherPlayerRecord.chickynoid.simulation.characterData:SerializeToBitBuffer(bitBuffer)
                end 
            end
                        
            snapshot.b = bitBuffer.dumpString()
            snapshot.f = self.serverTotalFrames 
            snapshot.serverTime = self.serverTotalTime
            playerRecord:SendEventToClient(snapshot)
        end
       
    end
    
    
end

return ChickynoidServer
