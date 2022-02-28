--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local path = game.ReplicatedFirst.Packages.Chickynoid

local Types = require(path.Types)
local Enums = require(path.Enums)
local EventType = Enums.EventType
local ServerChickynoid = require(script.ServerChickynoid)
local CharacterData = require(path.Simulation.CharacterData)
local BitBuffer = require(path.Vendor.BitBuffer)
local RemoteEvent = game.ReplicatedStorage.Packages.Chickynoid.RemoteEvent

local ChickynoidServer = {}

ChickynoidServer.playerRecords = {}
ChickynoidServer.serverStepTimer = 0
ChickynoidServer.serverTotalFrames = 0
ChickynoidServer.serverSimulationTime = 0
ChickynoidServer.framesPerSecondCounter = 0 --Purely for stats
ChickynoidServer.framesPerSecondTimer = 0 --Purely for stats
ChickynoidServer.framesPerSecond = 0 --Purely for stats

ChickynoidServer.startTime = tick()
ChickynoidServer.slots = {}
ChickynoidServer.slotsCounter = 0
ChickynoidServer.maxPlayers = 255   --Theoretical max, use a byte for player id

local SERVER_HZ = 20

function ChickynoidServer:Setup()
    
    RemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        
        local playerRecord = self:GetPlayerByUserId(player.UserId)
        
        if (playerRecord) then
            playerRecord.chickynoid:HandleEvent(event)
        end
        
    end)
    
end

function ChickynoidServer:AssignSlot(playerRecord)
    for j=1,self.maxPlayers do
        if (self.slots[j] == nil) then
            self.slots[j] = playerRecord
            playerRecord.slot = j
            return true
        end
    end
    warn("Slot not found!")
    return false
    
end

function ChickynoidServer:AddConnection(userId, player)
    if (self.playerRecords[userId]~= nil) then
        warn("Player was already connected.", userId)
        self:PlayerDisconnected(userId)
    end
    
    
    local playerRecord = {}
    self.playerRecords[userId] = playerRecord

    playerRecord.userId = userId
    playerRecord.spawned = false
 
    
    playerRecord.previousCharacterData = {}
    playerRecord.chickynoid = nil    
    playerRecord.frame = 0
    
    self:AssignSlot(playerRecord)
    
    playerRecord.player = player
    if (playerRecord.player ~= nil) then
        playerRecord.dummy = false
        playerRecord.name = player.name
    else
        --Is a bot
        playerRecord.dummy = true
    end

    
    function playerRecord:SendEventToClient(event)
        if (playerRecord.player) then
            RemoteEvent:FireClient(playerRecord.player, event)
        end
    end
    
    for key,data in pairs(self.playerRecords) do
        self:SendWorldstate(data)
    end
    
        
    return playerRecord    
end

function ChickynoidServer:SendWorldstate(playerRecord)
    local event = {}
    event.t = Enums.EventType.WorldState
    event.worldState = {}
    event.worldState.players = {}
    for key,data in pairs(self.playerRecords) do
        local info = {}
        info.name = data.name
        info.userId = data.userId
        
        event.worldState.players[data.slot] = info
    end
    
    event.worldState.serverHz = SERVER_HZ
    playerRecord:SendEventToClient(event)   
end

function ChickynoidServer:PlayerDisconnected(userId)
    
    local playerRecord = self.playerRecords[userId]
    
    if (playerRecord) then
        print("Player disconnected")
        
        self.playerRecords[userId] = nil
        
        --Clear this out        
        for key,playerRecord in pairs(self.playerRecords) do
            playerRecord.previousCharacterData[userId] = nil
        end
        
        self.slots[playerRecord.slot] = nil
    end
    
    --Tell everyone
    for key,data in pairs(self.playerRecords) do
        self:SendWorldstate(data)
    end
end


function ChickynoidServer:GetPlayerByUserId(userId)
    
    return self.playerRecords[userId]
end

--[=[
    Spawns a new Chickynoid for the specified player.

    @param player Player -- The player to spawn this Chickynoid for.
    @return ServerCharacter -- New chickynoid instance made for this player.
]=]
function ChickynoidServer:CreateChickynoidAsync(playerRecord)

    local chickynoid = ServerChickynoid.new(playerRecord)
    playerRecord.chickynoid = chickynoid
    
    return chickynoid
end

function ChickynoidServer:Think(deltaTime)
    
    
    self.framesPerSecondCounter += 1
    self.framesPerSecondTimer += deltaTime
    if (self.framesPerSecondTimer > 1) then
        self.framesPerSecondTimer = math.fmod(self.framesPerSecondTimer,1)
        self.framesPerSecond = self.framesPerSecondCounter
        self.framesPerSecondCounter = 0
    end
    

    self.serverSimulationTime = tick() - self.startTime

    --1st stage, pump the commands
    --Many many todos on this!
    for userId,playerRecord in pairs(self.playerRecords) do
        
        if (playerRecord.dummy == true) then
            playerRecord.BotThink(deltaTime)
        end
        
        if (playerRecord.chickynoid) then

         
            playerRecord.chickynoid:Think(self.serverSimulationTime, deltaTime)
            
            if (playerRecord.chickynoid.simulation.state.pos.y < -2000) then
                playerRecord.chickynoid:SpawnChickynoid()
            end
        end
    end


    
    -- 2nd stage: Replicate character state to the player
    self.serverStepTimer += deltaTime
    self.serverTotalFrames += 1    
  
    local fraction =  (1 / SERVER_HZ)
    if self.serverStepTimer > fraction then
        
        while (self.serverStepTimer > fraction) do -- -_-'
            self.serverStepTimer -= fraction 
        end
        
        for userId,playerRecord in pairs(self.playerRecords) do
            
            if (playerRecord.dummy == true) then
                continue
            end
            
            --Send results of server move
            if (playerRecord.chickynoid ~= nil) then

                local event = {}
                event.t = EventType.State
                event.lastConfirmed = playerRecord.chickynoid.lastConfirmedCommand
                event.e = playerRecord.chickynoid.errorState
                event.s = self.framesPerSecond
                event.serverTime = self.serverSimulationTime
                event.state = playerRecord.chickynoid.simulation:WriteState()
                
                playerRecord:SendEventToClient(event)
                playerRecord.chickynoid.errorState = Enums.NetworkProblemState.None
            end
            
            --Send snapshot
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
                    bitBuffer.writeByte(otherPlayerRecord.slot)
                    
                    if (playerRecord.firstSnapshot == nil) then
                        --Make sure the first write is always a full packet
                        otherPlayerRecord.chickynoid.simulation.characterData:SerializeToBitBuffer(nil, bitBuffer)
                    else
                        local previousRecord = playerRecord.previousCharacterData[otherUserId]
                        otherPlayerRecord.chickynoid.simulation.characterData:SerializeToBitBuffer(previousRecord, bitBuffer)
                    end
                    
                    --Make a copy for delta compression against
                    local previousRecord = CharacterData.new()
                    previousRecord:CopySerialized(otherPlayerRecord.chickynoid.simulation.characterData.serialized)
                    playerRecord.previousCharacterData[otherUserId] = previousRecord
                end 
            end
            
            
            playerRecord.firstSnapshot = true
                        
            snapshot.b = bitBuffer.dumpString()
            snapshot.f = self.serverTotalFrames 
            snapshot.serverTime = self.serverSimulationTime
            playerRecord:SendEventToClient(snapshot)
        end
       
    end
    
    
end

return ChickynoidServer
