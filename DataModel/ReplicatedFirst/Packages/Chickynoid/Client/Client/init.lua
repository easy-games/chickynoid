--[=[
    @class ChickynoidClient
    @client

    Client namespace for the Chickynoid package.
]=]

local RemoteEvent = game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Chickynoid"):WaitForChild("RemoteEvent")

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")


local path = game.ReplicatedFirst.Packages.Chickynoid
local BitBuffer = require(path.Vendor.BitBuffer)

local ClientChickynoid = require(script.ClientChickynoid)
local CharacterModel = require(script.CharacterModel)
local CharacterData = require(path.Simulation.CharacterData)
local Types = require(path.Types)
local Enums = require(path.Enums)
local FpsGraph = require(path.Client.Client.FpsGraph)

local EventType = Enums.EventType
local ChickynoidClient = {}

ChickynoidClient.localChickynoid = nil
ChickynoidClient.snapshots = {}
ChickynoidClient.previouSnapshot = nil -- for delta compression
ChickynoidClient.estimatedServerTime = 0
ChickynoidClient.estimatedServerTimeOffset = 0
ChickynoidClient.validServerTime = false
ChickynoidClient.startTime = tick()
ChickynoidClient.characters = {}
ChickynoidClient.localFrame = 0
ChickynoidClient.worldState = nil
ChickynoidClient.fpsMax = 144  --Think carefully about changing this! Every extra frame clients make, puts load on the server
ChickynoidClient.fpsCap = true  --Dynamically sets to true if your fps is fpsMax + 5
 

ChickynoidClient.cappedElapsedTime = 0 --
ChickynoidClient.timeSinceLastThink = 0
ChickynoidClient.frameCounter = 0
ChickynoidClient.frameSimCounter = 0
ChickynoidClient.frameCounterTime = 0


--The local character
ChickynoidClient.characterModel = nil

--Milliseconds of *extra* buffer time to account for ping flux
ChickynoidClient.interpolationBuffer = 20 




--[=[
    Setup default connections for the client-side Chickynoid. This mostly
    includes handling character spawns/despawns, for both the local player
    and other players.

    Everything done:
    - Listen for our own character spawn event and construct a LocalChickynoid
    class.
    - TODO

    @error "Remote cannot be found" -- Thrown when the client cannot find a remote after waiting for it for some period of time.
    @yields
]=]
function ChickynoidClient:Setup()
    
    
    local eventHandler = {}
    eventHandler[EventType.ChickynoidAdded] = function(event)
        local position = event.position
        print("Chickynoid spawned at", position)

        if (self.localChickynoid == nil) then
            self.localChickynoid = ClientChickynoid.new(position)
        end
        --Force the position
        self.localChickynoid.simulation.state.pos = position
    end
    
    -- EventType.State
    eventHandler[EventType.State] = function(event)
        
        if self.localChickynoid and event.lastConfirmed then
            self.localChickynoid:HandleNewState(event.state, event.lastConfirmed)
        end
    end
        
    -- EventType.WorldState
    eventHandler[EventType.WorldState] = function(event)
        print("Got worldstate")
        --This would be a good time to run the collision setup
        self.worldState = event.worldState    
    end
        
    -- EventType.Snapshot
    eventHandler[EventType.Snapshot] = function(event)
        
 
        event = self:DeserializeSnapshot(event, self.previousSnapshot)
        self:SetupTime(event.serverTime)
        
        table.insert(self.snapshots, event)
        self.previousSnapshot = event
        
        --we need like 2 or 3..
        if (#self.snapshots > 10) then
            table.remove(self.snapshots,1)
        end        
        
    end

    RemoteEvent.OnClientEvent:Connect(function(event)
        local func = eventHandler[event.t]
        if (func~=nil) then
            func(event)
        end
    end)
    
    
    
    --ALL OF THE CODE IN HERE IS ASTONISHINGLY TEMPORARY!
    
    RunService.Heartbeat:Connect(function(deltaTime)
        
        FpsGraph:Scroll()
        self:DoFpsCount(deltaTime)
        
        --Do a framerate cap to 144? fps
        self.cappedElapsedTime += deltaTime
        self.timeSinceLastThink += deltaTime
        local fraction = 1/self.fpsMax
        
        if (self.cappedElapsedTime < fraction and self.fpsCap == true) then
            return    --If not enough time for a whole frame has elapsed
        end
        
        local fps = 1 / self.timeSinceLastThink 
        FpsGraph:AddBar(fps / 2, Color3.new(0.239216, 0.678431, 0.141176), 0)
        self:ProcessFrame(self.timeSinceLastThink)
        self.timeSinceLastThink = 0
        
        self.cappedElapsedTime = math.fmod(self.cappedElapsedTime, fraction)
        
    end)
end

function ChickynoidClient:DoFpsCount(deltaTime)
    self.frameCounter+=1
    self.frameCounterTime += deltaTime
    
 
    
    if (self.frameCounterTime > 1) then
        
        while (self.frameCounterTime > 1) do
            self.frameCounterTime -= 1
        end
        --print("FPS: real ", self.frameCounter, "( physics: ",self.frameSimCounter ,")")

        
        if (self.frameCounter > self.fpsMax+5) then
            FpsGraph:SetWarning("Cap your FPS to 144!")
            self.fpsCap = true
        else
            FpsGraph:SetWarning("Fps: " .. self.frameCounter .. " Sim: " .. self.frameSimCounter )
            self.fpsCap = false
        end
        
        self.frameCounter = 0
        self.frameSimCounter = 0        
        
    end
  
  
    
end

--Use this instead of raw tick()
function ChickynoidClient:LocalTick()
    return tick() - self.startTime
end

function ChickynoidClient:ProcessFrame(deltaTime)
    if (self.worldState == nil) then
        --Waiting for worldstate
        return
    end
    --Have we at least tried to figure out the server time?        
    if (self.validServerTime == false) then
        return
    end
    
    --stats
    self.frameSimCounter+=1
    
    --Do a new frame!!        
    self.localFrame += 1

    --Step the chickynoid
    if (self.localChickynoid) then
        self.localChickynoid:Heartbeat(deltaTime)

        if (self.characterModel == nil) then
            self.characterModel = CharacterModel.new()
            self.characterModel:CreateModel(game.Players.LocalPlayer.UserId)
        end

        self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized)

        -- Bind the camera
        local camera = game.Workspace.CurrentCamera
        camera.CameraSubject = self.characterModel.model
        camera.CameraType = Enum.CameraType.Custom

        --Bind the local character, which activates all the thumbsticks etc
        game.Players.LocalPlayer.Character = self.characterModel.model
    end

    --Start building the world view, based on us having enoug snapshots to do so
    self.estimatedServerTime = self:LocalTick() - self.estimatedServerTimeOffset 

    --Calc the SERVER point in time to render out
    --Because we need to be between two snapshots, the minimum search time is "timeBetweenFrames"
    --But because there might be network flux, we add some extra buffer too
    local timeBetweenServerFrames = (1 / self.worldState.serverHz)
    local searchPad = math.clamp(self.interpolationBuffer,0,500) * 0.001
    local pointInTimeToRender = self.estimatedServerTime - (timeBetweenServerFrames + searchPad)

    local last = nil
    local prev = self.snapshots[1]
    for key,value in pairs(self.snapshots) do

        if (value.serverTime > pointInTimeToRender) then
            last = value
            break
        end
        prev = value
    end

    if (prev and last and prev ~= last) then

        --So pointInTimeToRender is between prev.t and last.t
        local frac = (pointInTimeToRender-prev.serverTime) / timeBetweenServerFrames

        for userId,lastData in pairs(last.charData) do

            local prevData = prev.charData[userId]

            if (prevData == nil) then
                continue
            end

            local dataRecord = CharacterData:Interpolate(prevData, lastData, frac)
            local character = self.characters[userId]

            --Add the character
            if (character == nil) then

                local record = {}
                record.userId = userId
                record.characterModel = CharacterModel.new()
                record.characterModel:CreateModel(userId)

                character = record
                self.characters[userId] = record
            end

            character.frame = self.localFrame

            --Update it
            character.characterModel:Think(deltaTime, dataRecord)
        end

        --Remove any characters who were not in this snapshot
        for key,value in pairs(self.characters) do
            if value.frame ~= self.localFrame then
                value.characterModel:DestroyModel()
                value.characterModel = nil

                self.characters[key] = nil
            end
        end
    end
end


-- This tries to figure out a correct delta for the server time
-- Better to update this infrequently as it will cause a "pop" in prediction
-- Thought: Replace with roblox solution or converging solution?
function ChickynoidClient:SetupTime(serverActualTime)
    
    local oldDelta = self.estimatedServerTimeOffset
    local newDelta = self:LocalTick() - serverActualTime
    self.validServerTime = true
    
    local delta = oldDelta - newDelta
    if (math.abs(delta * 1000) > 50) then --50ms out? try again
        self.estimatedServerTimeOffset = newDelta
    end
end

function ChickynoidClient:DeserializeSnapshot(event, previousSnapshot)
    
    local bitBuffer = BitBuffer(event.b)
    local count = bitBuffer.readByte()
    
    event.charData = {}
    
    for j=1,count do
        local record = CharacterData.new()
       
        --CharacterData.CopyFrom(self.previous)
        local userId = bitBuffer.readSigned(48)
        
        if (previousSnapshot ~= nil) then
            local previousRecord = previousSnapshot.charData[userId]
            if (previousRecord) then
                record:CopySerialized(previousRecord)
            end
        end
        record:DeserializeFromBitBuffer(bitBuffer)
            
        event.charData[userId] = record.serialized
    end
    
    return event
end

return ChickynoidClient
