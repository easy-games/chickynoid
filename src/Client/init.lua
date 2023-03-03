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
local ClientMods = require(path.Client.ClientMods)

local Enums = require(path.Enums)
local MathUtils = require(path.Simulation.MathUtils)

local FpsGraph = require(path.Client.FpsGraph)
local NetGraph = require(path.Client.NetGraph)

local EventType = Enums.EventType
local ChickynoidClient = {}

ChickynoidClient.localChickynoid = nil
ChickynoidClient.snapshots = {}
ChickynoidClient.previousSnapshot = nil -- for delta compression

ChickynoidClient.estimatedServerTime = 0 --This is the time estimated from the snapshots
ChickynoidClient.estimatedServerTimeOffset = 0

ChickynoidClient.validServerTime = false
ChickynoidClient.startTime = tick()
ChickynoidClient.characters = {}
ChickynoidClient.localFrame = 0
ChickynoidClient.worldState = nil
ChickynoidClient.fpsMax = 120 --Think carefully about changing this! Every extra frame clients make, puts load on the server
ChickynoidClient.fpsIsCapped = true --Dynamically sets to true if your fps is fpsMax + 5
ChickynoidClient.fpsMin = 25 --If you're slower than this, your step will be broken up

ChickynoidClient.cappedElapsedTime = 0 --
ChickynoidClient.timeSinceLastThink = 0
ChickynoidClient.timeUntilRetryReset = tick() + 15 -- 15 seconds grace on connection
ChickynoidClient.frameCounter = 0
ChickynoidClient.frameSimCounter = 0
ChickynoidClient.frameCounterTime = 0
ChickynoidClient.stateCounter = 0 --Num states coming in

ChickynoidClient.accumulatedTime = 0

ChickynoidClient.debugBoxes = {}
ChickynoidClient.debugMarkPlayers = false

--Netgraph settings
ChickynoidClient.showFpsGraph = false
ChickynoidClient.showNetGraph = false
ChickynoidClient.showDebugMovement = true

ChickynoidClient.ping = 0
ChickynoidClient.pings = {}

ChickynoidClient.useSubFrameInterpolation = false
ChickynoidClient.prevLocalCharacterData = nil

--This flag can be set to true if we detect we're in a network death spiral, and are going to go quiet for a while
ChickynoidClient.awaitingFullSnapshot = true
ChickynoidClient.timeOfLastData = tick()

--The local character
ChickynoidClient.characterModel = nil

--Server provided collision data
ChickynoidClient.playerSize = Vector3.new(2,5,5)
ChickynoidClient.collisionRoot = game.Workspace           

--Milliseconds of *extra* buffer time to account for ping flux
ChickynoidClient.interpolationBuffer = 20

--Signals
ChickynoidClient.OnNetworkEvent = FastSignal.new()
ChickynoidClient.OnCharacterModelCreated = FastSignal.new()
ChickynoidClient.OnCharacterModelDestroyed = FastSignal.new()

--Callbacks
ChickynoidClient.characterModelCallbacks = {}

ChickynoidClient.flags = {
    HANDLE_CAMERA = false,
    DEBUG_ANTILAG = true
}

 
ChickynoidClient.weaponsClient = ClientWeaponModule;

function ChickynoidClient:Setup()
    local eventHandler = {}

    eventHandler[EventType.DebugBox] = function(event)
        ChickynoidClient:DebugBox(event.pos, event.text)
    end

    --EventType.ChickynoidAdded
    eventHandler[EventType.ChickynoidAdded] = function(event)
        local position = event.position
        print("Chickynoid spawned at", position)

        if self.localChickynoid == nil then
            self.localChickynoid = ClientChickynoid.new(position, event.characterMod)
        end
        --Force the state
        self.localChickynoid.simulation:ReadState(event.state)
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
		
		self.characters[game.Players.LocalPlayer.UserId] = nil
    end

    -- EventType.State
    eventHandler[EventType.State] = function(event)
        if self.localChickynoid then
                   
            local resimulate, ping = self.localChickynoid:HandleNewState(event.stateDelta, event.lastConfirmed, event.serverTime)

            if (ping) then
                --Keep a rolling history of pings
                table.insert(self.pings, ping)
                if #self.pings > 20 then
                    table.remove(self.pings, 1)
                end

                self.stateCounter += 1
                
                if (self.showNetGraph == true) then
                    self:AddPingToNetgraph(resimulate, event.s, event.e, ping)
                end
            end
        end
    end

    -- EventType.WorldState
    eventHandler[EventType.WorldState] = function(event)
        print("Got worldstate")
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
        self.playerSize = event.playerSize
        self.collisionRoot = event.data
        CollisionModule:MakeWorld(self.collisionRoot, self.playerSize)
	end
	
	eventHandler[EventType.PlayerDisconnected] = function(event)
		local characterRecord = self.characters[event.userId]
        if (characterRecord and characterRecord.characterModel) then
            characterRecord.characterModel:DestroyModel()
        end
        --Final Cleanup
        CharacterModel:PlayerDisconnected(event.userId)
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

        if (self.showFpsGraph == false) then
            FpsGraph:Hide()
        end
        if (self.showNetGraph == false) then
            NetGraph:Hide()
        end

        self:DoFpsCount(deltaTime)
  
        --Do a framerate cap to 144? fps
        self.cappedElapsedTime += deltaTime
        self.timeSinceLastThink += deltaTime
        local fraction = 1 / self.fpsMax
		
		--Do we process a frame?
        if self.cappedElapsedTime < fraction and self.fpsIsCapped == true then
            return --If not enough time for a whole frame has elapsed
        end
		self.cappedElapsedTime = math.fmod(self.cappedElapsedTime, fraction)
		
		
		--Netgraph
        if (self.showFpsGraph == true) then
            FpsGraph:Scroll()
            local fps = 1 / self.timeSinceLastThink
            FpsGraph:AddBar(fps / 2, Color3.new(0.321569, 0.909804, 0.188235), 0)
        end
		
		--Think
		self:ProcessFrame(self.timeSinceLastThink)

		--Do Client Mods
        local modules = ClientMods:GetMods("clientmods")
        for _, value in pairs(modules) do
			value:Step(self, self.timeSinceLastThink)
		end
		
		self.timeSinceLastThink = 0

		--Death spiral
		local badConnection = false
		if self:IsConnectionBad() == true then
			--print("Bad connection: Chickynoid Ping")
			badConnection = true
		end

		if tick() > self.timeOfLastData + 2 then
			--print("Bad connection: Long time between messages")
			badConnection = true
		end

		--Go into recovery mode
		if badConnection == true and self.awaitingFullSnapshot == false and tick() > self.timeUntilRetryReset then
			self:ResetConnection()
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
    local mods = ClientMods:GetMods("clientmods")
    for _, mod in pairs(mods) do
        mod:Setup(self)
		print("Loaded", _)
    end

    --WeaponModule
    ClientWeaponModule:Setup(self)
end

function ChickynoidClient:GetClientChickynoid()
    return self.localChickynoid
end

function ChickynoidClient:GetCollisionRoot()
    return self.collisionRoot 
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
		self.timeUntilRetryReset = tick() + 15
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
            if (self.showFpsGraph == true) then
                FpsGraph:SetWarning("(Cap your fps to " .. self.fpsMax .. ")")
            end
            self.fpsIsCapped = true
        else
            if (self.showFpsGraph == true) then
                FpsGraph:SetWarning("")
            end
            self.fpsIsCapped = false
        end
        if (self.showFpsGraph == true) then
            if self.frameCounter == self.frameSimCounter then
                FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " CmdRate: " .. self.stateCounter)
            else
                FpsGraph:SetFpsText("Fps: " .. self.frameCounter .. " Sim: " .. self.frameSimCounter)
            end
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

    local bulkMoveToList = { parts = {}, cframes = {} }

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
                local command = self:GenerateCommand(pointInTimeToRender, frac)    
                self.localChickynoid:Heartbeat(command, pointInTimeToRender, frac)
                ClientWeaponModule:ProcessCommand(command)

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

            if (self.showFpsGraph == true) then
                if count > 0 then
                    local pixels = 1000 / fixedPhysics
                    FpsGraph:AddPoint((count * pixels), Color3.new(0, 1, 1), 3)
                    FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
                else
                    FpsGraph:AddBar(math.abs(self.accumulatedTime * 1000), Color3.new(1, 1, 0), 2)
                end
            end
        else
            --For this to work, the server has to accept deltaTime from the client
            local command = self:GenerateCommand(pointInTimeToRender, deltaTime) 
            self.localChickynoid:Heartbeat(command, pointInTimeToRender, deltaTime)
            ClientWeaponModule:ProcessCommand(command)
        end

        if self.localChickynoid ~= nil then
            if self.characterModel == nil then
                --Spawn the character in
                print("Creating local model for UserId", game.Players.LocalPlayer.UserId)
                local mod = self:GetPlayerDataByUserId(game.Players.LocalPlayer.UserId)
                self.characterModel = CharacterModel.new( game.Players.LocalPlayer.UserId, mod.characterMod)
                for _, characterModelCallback in ipairs(self.characterModelCallbacks) do
                    self.characterModel:SetCharacterModel(characterModelCallback)
                end
                self.characterModel:CreateModel()
                self.OnCharacterModelCreated:Fire(self.characterModel)

                local record = {}
                record.userId = game.Players.LocalPlayer.UserId
                record.characterModel = self.characterModel
                record.characterMod = mod.characterMod

                record.localPlayer = true
                self.characters[record.userId] = record

            elseif self.characters[game.Players.LocalPlayer.UserId] then
                local record = self.characters[game.Players.LocalPlayer.UserId]
                local lastMod = record.characterMod
                local mod = self:GetPlayerDataByUserId(game.Players.LocalPlayer.UserId).characterMod
                if lastMod ~= mod and record.characterModel ~= nil then -- check to see if the characterMod changed
                    print("Changed mod from " .. lastMod .. " to " .. mod)
                    -- set PlayerData's record to new characterMod
                    record.characterMod = mod
                    self.characters[game.Players.LocalPlayer.UserId] = record

                    -- load new characterMod's setup
                    local loadedModule = ClientMods:GetMod("characters", mod)
                    if loadedModule then
                        loadedModule:Setup(self.localChickynoid.simulation)
                    end
                    
                    -- create new model
                    record.characterModel:ChangeCharacterMod(mod)
                end
            end
        end

        if self.characterModel ~= nil then
            --Blend out the mispredict value

            self.localChickynoid.mispredict = MathUtils:VelocityFriction(
                self.localChickynoid.mispredict,
                0.1,
                deltaTime
            )
            self.characterModel.mispredict = self.localChickynoid.mispredict
			
			local localRecord = self.characters[game.Players.LocalPlayer.UserId]
						
            if self.fixedPhysicsSteps == true then
                if
                    self.useSubFrameInterpolation == false
                    or subFrameFraction == 0
                    or self.prevLocalCharacterData == nil
                then
					self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized, bulkMoveToList)
					localRecord.characterData = self.localChickynoid.simulation.characterData
                else
                    --Calculate a sub-frame interpolation
                    local data = CharacterData:Interpolate(
                        self.prevLocalCharacterData,
                        self.localChickynoid.simulation.characterData.serialized,
                        subFrameFraction
                    )
					self.characterModel:Think(deltaTime, data)
					localRecord.characterData = data
                end
            else
				self.characterModel:Think(deltaTime, self.localChickynoid.simulation.characterData.serialized, bulkMoveToList)
				localRecord.characterData = self.localChickynoid.simulation.characterData
            end
			
			--store local data
			localRecord.frame = self.localFrame
			localRecord.position = localRecord.characterData.pos
				
            if (self.showFpsGraph == true) then
                if self.showDebugMovement == true then
					local pos = localRecord.position
                    if self.previousPos ~= nil then
                        local delta = pos - self.previousPos
                        FpsGraph:AddPoint(delta.magnitude * 200, Color3.new(0, 0, 1), 4)
                    end
                    self.previousPos = pos
                end
            end

            -- Bind the camera
            if (self.flags.HANDLE_CAMERA ~= false) then
                local camera = game.Workspace.CurrentCamera
                if camera.CameraSubject ~= self.characterModel._camPart then
                    camera.CameraSubject = self.characterModel._camPart
                    camera.CameraType = Enum.CameraType.Custom

                    -- bind camera function
                    print("boound")
                end
            end

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
	
	local debugData = {}

    if prev and last and prev ~= last then
        --So pointInTimeToRender is between prev.t and last.t
        local frac = (pointInTimeToRender - prev.serverTime) / timeBetweenServerFrames
		
		debugData.frac = frac
		debugData.prev = prev.t
		debugData.last = last.t
		
		
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
				local mod = self:GetPlayerDataByUserId(userId)
				record.characterModel = CharacterModel.new(userId, mod.characterMod)
                record.characterMod = mod.characterMod

                record.characterModel:CreateModel()
                self.OnCharacterModelCreated:Fire(record.characterModel)

                character = record
                self.characters[userId] = character
            else
                local lastMod = character.characterMod
                local record = self:GetPlayerDataByUserId(userId)
                local mod = record.characterMod
                if lastMod ~= mod and character.characterModel ~= nil then -- check to see if the characterMod changed
                    print("Changed OTHER mod from " .. lastMod .. " to " .. mod)
                    -- set PlayerData's record to new characterMod
                    character.characterMod = mod
                    self.characters[userId] = character
                    
                    -- create new model
                    character.characterModel:ChangeCharacterMod(mod)
                end
            end

            character.frame = self.localFrame
			character.position = dataRecord.pos
            character.characterData = dataRecord
			
            --Update it
            if character.characterModel then
                character.characterModel:Think(deltaTime, dataRecord, bulkMoveToList)
            else
                print("could not get characterModel...")
            end
        end

        --Remove any characters who were not in this snapshot
		for key, value in pairs(self.characters) do
			
			if (key == game.Players.LocalPlayer.UserId) then
				continue
			end
			
            if value.frame ~= self.localFrame then
                if value.characterModel then
                    self.OnCharacterModelDestroyed:Fire(value.characterModel)
                    value.characterModel:DestroyModel()
                    value.characterModel = nil

                    self.characters[key] = nil
                end
            end
        end
    end

    --bulkMoveTo
    if (bulkMoveToList) then
        game.Workspace:BulkMoveTo(bulkMoveToList.parts, bulkMoveToList.cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end

    --render in the rockets
    -- local timeToRenderRocketsAt = self.estimatedServerTime
    local timeToRenderRocketsAt = pointInTimeToRender --laggier but more correct

	ClientWeaponModule:Think(timeToRenderRocketsAt, deltaTime)
	
	if (self.debugMarkPlayers ~= nil) then
		self:DrawBoxOnAllPlayers(self.debugMarkPlayers)
        self.debugMarkPlayers = nil
	end
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

-- Register a callback that will determine a character model
function ChickynoidClient:SetCharacterModel(callback)
    table.insert(self.characterModelCallbacks, callback)
end

function ChickynoidClient:GetPlayerDataBySlotId(slotId)
	local slotString = tostring(slotId)
	if (self.worldState == nil) then
		return nil
	end
	--worldState.players is indexed by a *STRING* not a int
	return self.worldState.players[slotString]
end

function ChickynoidClient:GetPlayerDataByUserId(userId)

	if (self.worldState == nil) then
        warn("GetPlayerDataByUserId did not find a worldState")
		return nil
	end
	for key,value in pairs(self.worldState.players) do
		if (value.userId == userId) then
			return value
		end
	end

	return nil
end


function ChickynoidClient:DeserializeSnapshot(event, previousSnapshot)
    local bitBuffer = BitBuffer(event.b)
    local count = bitBuffer.readByte()

    event.charData = {}

    for _ = 1, count do
        local record = CharacterData.new()

        --CharacterData.CopyFrom(self.previous)
        local slotId = bitBuffer.readByte()

		local user = self:GetPlayerDataBySlotId(slotId)
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
			warn("UserId for slot", slotId, "not found!")
            record:DeserializeFromBitBuffer(bitBuffer)
        end
    end

    return event
end

function ChickynoidClient:GetGui()
    local gui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
    return gui
end

function ChickynoidClient:DebugMarkAllPlayers(text)
	self.debugMarkPlayers = text
end

function ChickynoidClient:DrawBoxOnAllPlayers(text)
    if self.worldState == nil then
        return
    end
    if self.worldState.flags.DEBUG_ANTILAG ~= true then
        return
    end

    local models = self:GetCharacters()
	for _, record in pairs(models) do
		
		if (record.localPlayer == true) then
			continue
		end
		
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

        self:AdornText(instance, Vector3.new(0,3,0), text, Color3.new(0.5,1,0.5))

        self.debugBoxes[instance] = tick() + 5
    end

    for key, value in pairs(self.debugBoxes) do
        if tick() > value then
            key:Destroy()
            self.debugBoxes[key] = nil
        end
    end
end

function ChickynoidClient:DebugBox(pos, text)
    local instance = Instance.new("Part")
    instance.Size = Vector3.new(3, 5, 3)
    instance.Transparency = 1
    instance.Color = Color3.new(1, 0, 0)
    instance.Anchored = true
    instance.CanCollide = false
    instance.CanTouch = false
    instance.CanQuery = false
    instance.Position = pos
    instance.name = game.Players.LocalPlayer.Name
    instance.Parent = game.Workspace

    local adornment = Instance.new("SelectionBox")
    adornment.Adornee = instance
    adornment.Parent = instance

    self.debugBoxes[instance] = tick() + 5

    self:AdornText(instance, Vector3.new(0,6,0), text, Color3.new(0, 0.501960, 1))
end

function ChickynoidClient:AdornText(part, offset, text, color)

    local attachment = Instance.new("Attachment")
    attachment.Parent = part
    attachment.Position = offset

    local billboard = Instance.new("BillboardGui")
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0,50,0,20)
    billboard.Adornee = attachment
    billboard.Parent = attachment
    
    local textLabel = Instance.new("TextLabel")
    textLabel.TextScaled = true
    textLabel.TextColor3 = color
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.new(1,0,1,0)
    textLabel.Text = text
    textLabel.Parent = billboard
end


function ChickynoidClient:AddPingToNetgraph(resimulate, serverHealthFps, networkProblem, ping)

    --Ping graph
    local total = 0
    for _, ping in pairs(self.pings) do
        total += ping
    end
    total /= #self.pings

    NetGraph:Scroll()

    local color1 = Color3.new(1, 1, 1)
    local color2 = Color3.new(1, 1, 0)
    if resimulate == false then
        NetGraph:AddPoint(ping * 0.25, color1, 4)
        NetGraph:AddPoint(total * 0.25, color2, 3)
    else
        NetGraph:AddPoint(ping * 0.25, color1, 4)
        local tint = Color3.new(0.5, 1, 0.5)
        NetGraph:AddPoint(total * 0.25, tint, 3)
        NetGraph:AddBar(10 * 0.25, tint, 1)
    end

    --Server fps
    if serverHealthFps < 60 then
        NetGraph:AddPoint(serverHealthFps, Color3.new(1, 0, 0), 2)
    else
        NetGraph:AddPoint(serverHealthFps, Color3.new(0, 1, 0), 2)
    end

    --Blue bar
    if networkProblem == Enums.NetworkProblemState.TooFarBehind then
        NetGraph:AddBar(100, Color3.new(0, 0, 1), 0)
    end
    --Yellow bar
    if networkProblem == Enums.NetworkProblemState.TooFarAhead then
        NetGraph:AddBar(100, Color3.new(1, 1, 0), 0)
    end
    --Red bar
    if networkProblem == Enums.NetworkProblemState.TooManyCommands then
        NetGraph:AddBar(100, Color3.new(1, 0, 0), 0)
	end
	--teal bar
	if networkProblem == Enums.NetworkProblemState.CommandUnderrun then
		NetGraph:AddBar(100, Color3.new(0, 1, 1), 0)
	end

    NetGraph:SetFpsText("Effective Ping: " .. math.floor(total) .. "ms")
end

function ChickynoidClient:IsConnectionBad()

    local pings 
    if #self.pings > 10 and self.ping > 2000 then
        return true
    end
    return false
end

function ChickynoidClient:GenerateCommand(serverTime, deltaTime)
    
    local command = {}
    command.serverTime = serverTime
    command.deltaTime = deltaTime
    command.x = 0
    command.y = 0
    command.z = 0
 
    local modules = ClientMods:GetMods("clientmods")

    for key,mod in pairs(modules) do
        if (mod.GenerateCommand) then
            command = mod:GenerateCommand(command, serverTime, deltaTime)
        end
    end

    return command
end

return ChickynoidClient
