--[=[
    @class ChickynoidClient
    @client

    Client namespace for the Chickynoid package.
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidReplication") :: RemoteEvent

local path = script.Parent
local BitBuffer = require(path.Vendor.BitBuffer)

local ClientChickynoid = require(script.ClientChickynoid)
local CollisionModule = require(path.Simulation.CollisionModule)
local CharacterModel = require(script.CharacterModel)
local CharacterData = require(path.Simulation.CharacterData)
local ClientWeaponModule = require(path.Client.WeaponsClient)
local FastSignal = require(path.Vendor.FastSignal)

local Enums = require(path.Enums)
local MathUtils = require(path.Simulation.MathUtils)

local FpsGraph = require(path.Client.FpsGraph)

local EventType = Enums.EventType
local ChickynoidClient = {}

ChickynoidClient.localChickynoid = nil
ChickynoidClient.snapshots = {}
ChickynoidClient.previouSnapshot = nil -- for delta compression

ChickynoidClient.estimatedServerTime = 0 --This is the time estimated from the snapshots
ChickynoidClient.estimatedServerTimeOffset = 0

ChickynoidClient.validServerTime = false
ChickynoidClient.startTime = tick()
ChickynoidClient.characters = {}
ChickynoidClient.localFrame = 0
ChickynoidClient.worldState = nil
ChickynoidClient.fpsMax = 144 --Think carefully about changing this! Every extra frame clients make, puts load on the server
ChickynoidClient.fpsIsCapped = true --Dynamically sets to true if your fps is fpsMax + 5
ChickynoidClient.fpsMin = 25 --If you're slower than this, your step will be broken up

ChickynoidClient.cappedElapsedTime = 0 --
ChickynoidClient.timeSinceLastThink = 0
ChickynoidClient.frameCounter = 0
ChickynoidClient.frameSimCounter = 0
ChickynoidClient.frameCounterTime = 0
ChickynoidClient.stateCounter = 0 --Num states coming in

ChickynoidClient.accumulatedTime = 0

ChickynoidClient.debugBoxes = {}

ChickynoidClient.useSubFrameInterpolation = false
ChickynoidClient.prevLocalCharacterData = nil
ChickynoidClient.showDebugMovement = true

--This flag can be set to true if we detect we're in a network death spiral, and are going to go quiet for a while
ChickynoidClient.awaitingFullSnapshot = true
ChickynoidClient.timeOfLastData = tick()

--The local character
ChickynoidClient.characterModel = nil

--Milliseconds of *extra* buffer time to account for ping flux
ChickynoidClient.interpolationBuffer = 20

--Signals
ChickynoidClient.OnNetworkEvent = FastSignal.new()

--Mods
ChickynoidClient.modules = {}

function ChickynoidClient:Setup()
    local eventHandler = {}

    eventHandler[EventType.DebugBox] = function(event)
        ChickynoidClient:DebugBox(event.pos)
    end

    --EventType.ChickynoidAdded
    eventHandler[EventType.ChickynoidAdded] = function(event)
        local position = event.position
        print("Chickynoid spawned at", position)

        if self.localChickynoid == nil then
            self.localChickynoid = ClientChickynoid.new(position)
        end
        --Force the position
        self.localChickynoid.simulation.state.pos = position
        self.prevLocalCharacterData = nil
    end

    eventHandler[EventType.ChickynoidRemoving] = function(_event)
        print("Local chickynoid removing")

        if self.localChickynoid ~= nil then
            self.localChickynoid:Destroy()
            self.localChickynoid = nil
        end

        self.prevLocalCharacterData = nil
        self.characterModel:DestroyModel()
        self.characterModel = nil
        game.Players.LocalPlayer.Character = nil :: any
    end

    -- EventType.State
    eventHandler[EventType.State] = function(event)
        if self.localChickynoid and event.lastConfirmed then
            self.localChickynoid:HandleNewState(event.state, event.lastConfirmed, event.serverTime, event.s, event.e)
            self.stateCounter += 1
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

        if self.awaitingFullSnapshot == true and event.full == false then
            print("Discarding snapshot due to network connection recovery")
            return -- just discard this
        end

        --Got first full snapshot or a partial update
        self.awaitingFullSnapshot = false

        self:SetupTime(event.serverTime)

        table.insert(self.snapshots, event)
        self.previousSnapshot = event

        --we need like 2 or 3..
        if #self.snapshots > 10 then
            table.remove(self.snapshots, 1)
        end
    end

    eventHandler[EventType.CollisionData] = function(event)
        local playerSize = Vector3.new(2, 5, 2)
        CollisionModule:MakeWorld(event.data, playerSize)
    end

    RemoteEvent.OnClientEvent:Connect(function(event)
        self.timeOfLastData = tick()

        local func = eventHandler[event.t]
        if func ~= nil then
            func(event)
        else
            ClientWeaponModule:HandleEvent(self, event)
            self.OnNetworkEvent:Fire(self, event)
        end
    end)

    local function Step(deltaTime)
        --  print("deltaTime", deltaTime)
        FpsGraph:Scroll()

        self:DoFpsCount(deltaTime)

        --Do a framerate cap to 144? fps
        self.cappedElapsedTime += deltaTime
        self.timeSinceLastThink += deltaTime
        local fraction = 1 / self.fpsMax

        if self.cappedElapsedTime < fraction and self.fpsIsCapped == true then
            return --If not enough time for a whole frame has elapsed
        end

        local fps = 1 / self.timeSinceLastThink
        FpsGraph:AddBar(fps / 2, Color3.new(0.321569, 0.909804, 0.188235), 0)
        self:ProcessFrame(self.timeSinceLastThink)
        self.timeSinceLastThink = 0

        self.cappedElapsedTime = math.fmod(self.cappedElapsedTime, fraction)

        --Death spiral

        local badConnection = false
        if self.localChickynoid and self.localChickynoid:IsConnectionBad() == true then
            --print("Bad connection: Chickynoid Ping")
            badConnection = true
        end

        if tick() > self.timeOfLastData + 1 then
            --print("Bad connection: Long time between messages")
            badConnection = true
        end

        --Go into recovery mode
        if badConnection == true and self.awaitingFullSnapshot == false then
            self:ResetConnection()
        end

        for _, value in pairs(self.modules) do
            value:Step(self, deltaTime)
        end
    end

    local lastDt = nil
    local fakeDeltaTime = nil
    RunService:BindToRenderStep("Before camera", -100, function()
        if lastDt == nil then
            lastDt = os.clock()
        end
        fakeDeltaTime = os.clock() - lastDt
        lastDt = os.clock()
    end)

    RunService.Heartbeat:Connect(function()
        if fakeDeltaTime == nil then
            fakeDeltaTime = 0
        end
        Step(fakeDeltaTime)
    end)

    --Load the mods
    for _, value in pairs(path.Custom:GetChildren()) do
        if value:IsA("ModuleScript") then
            local mod = require(value)
            self.modules[value.Name] = mod
            mod:Setup(self)
        end
    end

    --WeaponModule
    ClientWeaponModule:Setup(self)
end

function ChickynoidClient:GetMod(name)
    return self.modules[name]
end

function ChickynoidClient:GetClientChickynoid()
    return self.localChickynoid
end

function ChickynoidClient:ResetConnection()
    if self.awaitingFullSnapshot == false then
        --Stop accepting/storing data
        self.awaitingFullSnapshot = true

        --Clear the buffer
        self.snapshots = {}

        local event = {}
        event.t = EventType.ResetConnection
        RemoteEvent:FireServer(event)
        print("Sending event to reset connection")
    end
end

function ChickynoidClient:DoFpsCount(deltaTime)
    self.frameCounter += 1
    self.frameCounterTime += deltaTime

    if self.frameCounterTime > 1 then
        while self.frameCounterTime > 1 do
            self.frameCounterTime -= 1
        end
        --print("FPS: real ", self.frameCounter, "( physics: ",self.frameSimCounter ,")")

        if self.frameCounter > self.fpsMax + 5 then
            FpsGraph:SetWarning("(Cap your fps to " .. self.fpsMax .. ")")
            self.fpsIsCapped = true
        else
            FpsGraph:SetWarning("")

            self.fpsIsCapped = false
        end
        if self.frameCounter == self.frameSimCounter then
            FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " CmdRate: " .. self.stateCounter)
        else
            FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " Sim: " .. self.frameSimCounter)
        end

        self.frameCounter = 0
        self.frameSimCounter = 0
        self.stateCounter = 0
    end
end

--Use this instead of raw tick()
function ChickynoidClient:LocalTick()
    return tick() - self.startTime
end

function ChickynoidClient:ProcessFrame(deltaTime)
    if self.worldState == nil then
        --Waiting for worldstate
        return
    end
    --Have we at least tried to figure out the server time?
    if self.validServerTime == false then
        return
    end

    --stats
    self.frameSimCounter += 1

    --Do a new frame!!
    self.localFrame += 1

    --Start building the world view, based on us having enough snapshots to do so
    self.estimatedServerTime = self:LocalTick() - self.estimatedServerTimeOffset

    --Calc the SERVER point in time to render out
    --Because we need to be between two snapshots, the minimum search time is "timeBetweenFrames"
    --But because there might be network flux, we add some extra buffer too
    local timeBetweenServerFrames = (1 / self.worldState.serverHz)
    local searchPad = math.clamp(self.interpolationBuffer, 0, 500) * 0.001
    local pointInTimeToRender = self.estimatedServerTime - (timeBetweenServerFrames + searchPad)

    local subFrameFraction = 0

    --Step the chickynoid
    if self.localChickynoid then
        local fixedPhysics = nil
        if self.worldState.fpsMode == Enums.FpsMode.Hybrid then
            if deltaTime >= 1 / 30 then
                fixedPhysics = 30
            end
        elseif self.worldState.fpsMode == Enums.FpsMode.Fixed60 then
            fixedPhysics = 60
        elseif self.worldState.fpsMode == Enums.FpsMode.Uncapped then
            fixedPhysics = nil
        else
            warn("Unhandled FPS Mode")
        end

        if fixedPhysics ~= nil then
            --Fixed physics steps
            local frac = 1 / fixedPhysics

            self.accumulatedTime += deltaTime
            local count = 0

            while self.accumulatedTime > 0 do
                self.accumulatedTime -= frac

                if self.useSubFrameInterpolation == true then
                    --Todo: could do a small (rarely used) optimization here and only copy the 2nd to last one..
                    if self.localChickynoid.simulation.characterData ~= nil then
                        --Capture the state of the client before the current simulation
                        self.prevLocalCharacterData = self.localChickynoid.simulation.characterData:Serialize()
                    end
                end

                --Step!
                local cmd = self.localChickynoid:Heartbeat(pointInTimeToRender, frac)
                ClientWeaponModule:ProcessCommand(cmd)

                count += 1
            end

            if self.useSubFrameInterpolation == true then
                --if this happens, we have over-simulated
                if self.accumulatedTime < 0 then
                    --we need to do a sub-frame positioning
                    local subFrame = math.abs(self.accumulatedTime) --How far into the next frame are we (we've already simulated 100% of this)
                    subFrame /= frac --0..1
                    if subFrame < 0 or subFrame > 1 then
                        warn("Subframe calculation wrong", subFrame)
                    end
                    subFrameFraction = 1 - subFrame
                end
            end

            if count > 0 then
                local pixels = 1000 / fixedPhysics
                FpsGraph:AddPoint((count * pixels), Color3.new(0, 1, 1), 3)
                FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
            else
                FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
            end
        else
            --For this to work, the server has to accept deltaTime from the client
            local cmd = self.localChickynoid:Heartbeat(pointInTimeToRender, deltaTime)
            ClientWeaponModule:ProcessCommand(cmd)
        end

        if self.characterModel == nil and self.localChickynoid ~= nil then
            --Spawn the character in
            print("Creating local model for UserId", game.Players.LocalPlayer.UserId)
            self.characterModel = CharacterModel.new()
            self.characterModel:CreateModel(game.Players.LocalPlayer.UserId)
        end

        if self.characterModel ~= nil then
            --Blend out the mispredict value

            self.localChickynoid.mispredict = MathUtils:VelocityFriction(
                self.localChickynoid.mispredict,
                0.05,
                deltaTime
            )
            self.characterModel.mispredict = self.localChickynoid.mispredict

            if self.fixedPhysicsSteps == true then
                if
                    self.useSubFrameInterpolation == false
                    or subFrameFraction == 0
                    or self.prevLocalCharacterData == nil
                then
                    self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized)
                else
                    --Calculate a sub-frame interpolation
                    local data = CharacterData:Interpolate(
                        self.prevLocalCharacterData,
                        self.localChickynoid.simulation.characterData.serialized,
                        subFrameFraction
                    )
                    self.characterModel:Think(deltaTime, data)
                end
            else
                self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized)
            end

            if self.showDebugMovement == true then
                if self.characterModel and self.characterModel.model then
                    local pos = self.characterModel.model.PrimaryPart.CFrame.Position

                    if self.previousPos ~= nil then
                        local delta = pos - self.previousPos

                        FpsGraph:AddPoint(delta.magnitude * 200, Color3.new(0, 0, 1), 4)
                    end
                    self.previousPos = pos
                end
            end

            -- Bind the camera
            local camera = game.Workspace.CurrentCamera
            camera.CameraSubject = self.characterModel.model
            camera.CameraType = Enum.CameraType.Custom

            --Bind the local character, which activates all the thumbsticks etc
            game.Players.LocalPlayer.Character = self.characterModel.model
        end
    end

    local last = nil
    local prev = self.snapshots[1]
    for _, value in pairs(self.snapshots) do
        if value.serverTime > pointInTimeToRender then
            last = value
            break
        end
        prev = value
    end

    if prev and last and prev ~= last then
        --So pointInTimeToRender is between prev.t and last.t
        local frac = (pointInTimeToRender - prev.serverTime) / timeBetweenServerFrames

        for userId, lastData in pairs(last.charData) do
            local prevData = prev.charData[userId]

            if prevData == nil then
                continue
            end

            local dataRecord = CharacterData:Interpolate(prevData, lastData, frac)
            local character = self.characters[userId]

            --Add the character
            if character == nil then
                local record = {}
                record.userId = userId
                record.characterModel = CharacterModel.new()
                record.characterModel:CreateModel(userId)

                character = record
                self.characters[userId] = record
            end

            character.frame = self.localFrame
            character.position = dataRecord.pos
            --Update it
            character.characterModel:Think(deltaTime, dataRecord)
        end

        --Remove any characters who were not in this snapshot
        for key, value in pairs(self.characters) do
            if value.frame ~= self.localFrame then
                value.characterModel:DestroyModel()
                value.characterModel = nil

                self.characters[key] = nil
            end
        end
    end

    --render in the rockets
    -- local timeToRenderRocketsAt = self.estimatedServerTime
    local timeToRenderRocketsAt = pointInTimeToRender --laggier but more correct

    ClientWeaponModule:Think(timeToRenderRocketsAt, deltaTime)
end

function ChickynoidClient:GetCharacters()
    return self.characters
end

-- This tries to figure out a correct delta for the server time
-- Better to update this infrequently as it will cause a "pop" in prediction
-- Thought: Replace with roblox solution or converging solution?
function ChickynoidClient:SetupTime(serverActualTime)
    local oldDelta = self.estimatedServerTimeOffset
    local newDelta = self:LocalTick() - serverActualTime
    self.validServerTime = true

    local delta = oldDelta - newDelta
    if math.abs(delta * 1000) > 50 then --50ms out? try again
        self.estimatedServerTimeOffset = newDelta
    end
end

function ChickynoidClient:DeserializeSnapshot(event, previousSnapshot)
    local bitBuffer = BitBuffer(event.b)
    local count = bitBuffer.readByte()

    event.charData = {}

    for _ = 1, count do
        local record = CharacterData.new()

        --CharacterData.CopyFrom(self.previous)
        local slotByte = bitBuffer.readByte()

        local user = self.worldState.players[slotByte]
        if user then
            if previousSnapshot ~= nil then
                local previousRecord = previousSnapshot.charData[user.userId]
                if previousRecord then
                    record:CopySerialized(previousRecord)
                end
            end
            record:DeserializeFromBitBuffer(bitBuffer)

            event.charData[user.userId] = record.serialized
        else
            --So things line up
            warn("UserId for slot", slotByte, "not found!")
            record:DeserializeFromBitBuffer(bitBuffer)
        end
    end

    return event
end

function ChickynoidClient:GetGui()
    local gui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
    return gui
end

function ChickynoidClient:DebugMarkAllPlayers()
    if self.worldState == nil then
        return
    end
    if self.worldState.flags.DEBUG_ANTILAG ~= true then
        return
    end

    local models = self:GetCharacters()
    for _, record in pairs(models) do
        local instance = Instance.new("Part")
        instance.Size = Vector3.new(3, 5, 3)
        instance.Transparency = 0.5
        instance.Color = Color3.new(0, 1, 0)
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        instance.Position = record.position
        instance.Parent = game.Workspace

        self.debugBoxes[instance] = tick() + 5
    end

    for key, value in pairs(self.debugBoxes) do
        if tick() > value then
            key:Destroy()
            self.debugBoxes[key] = nil
        end
    end
end

function ChickynoidClient:DebugBox(pos)
    local instance = Instance.new("Part")
    instance.Size = Vector3.new(3, 5, 3)
    instance.Transparency = 1
    instance.Color = Color3.new(1, 0, 0)
    instance.Anchored = true
    instance.CanCollide = false
    instance.CanTouch = false
    instance.CanQuery = false
    instance.Position = pos
    instance.Parent = game.Workspace

    local adornment = Instance.new("SelectionBox")
    adornment.Adornee = instance
    adornment.Parent = instance

    self.debugBoxes[instance] = tick() + 5
end

return ChickynoidClient
