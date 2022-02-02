--!strict

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

local ChickynoidServer = {}

ChickynoidServer.playerRecords = {}
ChickynoidServer.serverFrames = 0
ChickynoidServer.serverTotalFrames = 0


local SERVER_HZ = 20


function ChickynoidServer:Setup()
    
    script.Parent.RemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        
        local playerRecord = self:GetPlayerByUserId(player.UserId)
        
        if (playerRecord) then
            playerRecord.chickynoid:HandleEvent(event)
        end
        
    end)
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
    self.serverFrames += 1
    self.serverTotalFrames += 1
    if self.serverFrames > (60 / SERVER_HZ) then
        self.serverFrames = 0
        
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
            snapshot.charData = {}
            for otherUserId,otherPlayerRecord in pairs(self.playerRecords) do
                if (otherUserId ~= userId) then
                    --Todo: delta compress , bitwise compress, etc etc    
                    snapshot.charData[otherUserId] = otherPlayerRecord.chickynoid.simulation.characterData:Serialize()
                end 
            end
            snapshot.f = self.serverTotalFrames 
            snapshot.hz = SERVER_HZ
            playerRecord:SendEventToClient(snapshot)
            
        end
        
        
        --build a world snapshot
        
        
    end
    
    
end

return ChickynoidServer
