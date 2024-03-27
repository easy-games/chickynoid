--!native
--[=[
    @class ChickynoidServer
    @server

    Server namespace for the Chickynoid package.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local path = game.ReplicatedFirst.Packages.Chickynoid

local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType
local ServerChickynoid = require(script.Parent.ServerChickynoid)
local CharacterData = require(path.Shared.Simulation.CharacterData)


local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local WeaponsModule = require(script.Parent.WeaponsServer)
local CollisionModule = require(path.Shared.Simulation.CollisionModule)
local Antilag = require(script.Parent.Antilag)
local FastSignal = require(path.Shared.Vendor.FastSignal)
local ServerMods = require(script.Parent.ServerMods)
local Animations = require(path.Shared.Simulation.Animations)

local Profiler = require(path.Shared.Vendor.Profiler)

local RemoteEvent = Instance.new("RemoteEvent")
RemoteEvent.Name = "ChickynoidReplication"
RemoteEvent.Parent = ReplicatedStorage

local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
UnreliableRemoteEvent.Name = "ChickynoidUnreliableReplication"
UnreliableRemoteEvent.Parent = ReplicatedStorage

local ServerSnapshotGen = require(script.Parent.ServerSnapshotGen)

local ServerModule = {}

ServerModule.playerRecords = {}
ServerModule.loadingPlayerRecords = {}
ServerModule.serverStepTimer = 0
ServerModule.serverLastSnapshotFrame = -1 --Frame we last sent snapshots on
ServerModule.serverTotalFrames = 0
ServerModule.serverSimulationTime = 0
ServerModule.framesPerSecondCounter = 0 --Purely for stats
ServerModule.framesPerSecondTimer = 0 --Purely for stats
ServerModule.framesPerSecond = 0 --Purely for stats
ServerModule.accumulatedTime = 0 --fps

ServerModule.startTime = tick()
ServerModule.slots = {}
ServerModule.collisionRootFolder = nil
ServerModule.absoluteMaxSizeOfBuffer = 4096

ServerModule.playerSize = Vector3.new(2, 5, 2)


--[=[
	@interface ServerConfig
	@within ChickynoidServer
	.maxPlayers number -- Theoretical max, use a byte for player id
	.fpsMode FpsMode
	.serverHz number
	Server config for Chickynoid.
]=]
ServerModule.config = {
    maxPlayers = 255,
	fpsMode = Enums.FpsMode.Uncapped,
	serverHz = 20,
	antiWarp = false,
}

--API
ServerModule.OnPlayerSpawn = FastSignal.new()
ServerModule.OnPlayerDespawn = FastSignal.new()
ServerModule.OnBeforePlayerSpawn = FastSignal.new()
ServerModule.OnPlayerConnected = FastSignal.new()	--Technically this is OnPlayerLoaded


ServerModule.flags = {}
ServerModule.flags.DEBUG_ANTILAG = false
ServerModule.flags.DEBUG_BOT_BANDWIDTH = false
 
--[=[
	Creates connections so that Chickynoid can run on the server.
]=]
function ServerModule:Setup()
    self.worldRoot = self:GetDoNotReplicate()

    Players.PlayerAdded:Connect(function(player)
        self:PlayerConnected(player)
    end)

    --If there are any players already connected, push them through the connection function
    for _, player in pairs(game.Players:GetPlayers()) do
        self:PlayerConnected(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        self:PlayerDisconnected(player.UserId)
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        self:RobloxHeartbeat(deltaTime)
    end)

    RunService.Stepped:Connect(function(_, deltaTime)
        self:RobloxPhysicsStep(deltaTime)
    end)

    UnreliableRemoteEvent.OnServerEvent:Connect(function(player: Player, event)
        local playerRecord = self:GetPlayerByUserId(player.UserId)

        if playerRecord then
            if playerRecord.chickynoid then
                playerRecord.chickynoid:HandleEvent(self, event)
            end
        end
	end)
	
	RemoteEvent.OnServerEvent:Connect(function(player: Player, event: any)
		
		--Handle events from loading players
		local loadingPlayerRecord = ServerModule.loadingPlayerRecords[player.UserId]
		
		if (loadingPlayerRecord ~= nil) then
			if (event.id == "loaded") then
				if (loadingPlayerRecord.loaded == false) then
					loadingPlayerRecord:HandlePlayerLoaded()
				end
			end
			return
		end
		
	end)
	
	Animations:ServerSetup()	

    WeaponsModule:Setup(self)

    Antilag:Setup(self)

    --Load the mods
    local modules = ServerMods:GetMods("servermods")
    for _, mod in pairs(modules) do
        mod:Setup(self)
		-- print("Loaded", _)
    end
end

function ServerModule:PlayerConnected(player)
    local playerRecord = self:AddConnection(player.UserId, player)
	
	if (playerRecord) then
	    --Spawn the gui
	    for _, child in pairs(game.StarterGui:GetChildren()) do
	        local clone = child:Clone() :: ScreenGui
	        if clone:IsA("ScreenGui") then
	            clone.ResetOnSpawn = false
	        end
	        clone.Parent = playerRecord.player.PlayerGui
		end
	end

end

function ServerModule:AssignSlot(playerRecord)
	
	--Only place this is assigned
    for j = 1, self.config.maxPlayers do
        if self.slots[j] == nil then
            self.slots[j] = playerRecord
            playerRecord.slot = j
            return true
        end
    end
    warn("Slot not found!")
    return false
end

function ServerModule:AddConnection(userId, player)
    if self.playerRecords[userId] ~= nil or self.loadingPlayerRecords[userId] ~= nil then
        warn("Player was already connected.", userId)
        self:PlayerDisconnected(userId)
    end

    --Create the players server connection record
    local playerRecord = {}
    self.loadingPlayerRecords[userId] = playerRecord

    playerRecord.userId = userId
	
	playerRecord.slot = 0 -- starts 0, 0 is an invalid slot.
	playerRecord.loaded = false
	
    playerRecord.previousCharacterData = nil
    playerRecord.chickynoid = nil
    playerRecord.frame = 0
	
	playerRecord.pendingWorldState = true
    
    playerRecord.allowedToSpawn = true
    playerRecord.respawnDelay = Players.RespawnTime
    playerRecord.respawnTime = tick() + playerRecord.respawnDelay

	playerRecord.OnBeforePlayerSpawn = FastSignal.new()
	playerRecord.visHistoryList = {}

    playerRecord.characterMod = "HumanoidChickynoid"
	 	
	playerRecord.lastConfirmedSnapshotServerFrame = nil --Stays nil til a player confirms they've seen a whole snapshot, for delta compression purposes
		
	local assignedSlot = self:AssignSlot(playerRecord)
    self:DebugSlots()
    if (assignedSlot == false) then
		if (player ~= nil) then
			player:Kick("Server full, no free chickynoid slots")
		end
		self.loadingPlayerRecords[userId] = nil
		return nil
	end


    playerRecord.player = player
    if playerRecord.player ~= nil then
        playerRecord.dummy = false
        playerRecord.name = player.name
    else
        --Is a bot
        playerRecord.dummy = true
    end

    -- selene: allow(shadowing)
	function playerRecord:SendEventToClient(event)
		if (playerRecord.loaded == false) then
			print("warning, player not loaded yet")
		end
        if playerRecord.player then
            RemoteEvent:FireClient(playerRecord.player, event)
        end
	end
	
	-- selene: allow(shadowing)
	function playerRecord:SendUnreliableEventToClient(event)
		if (playerRecord.loaded == false) then
			print("warning, player not loaded yet")
		end
		if playerRecord.player then
			UnreliableRemoteEvent:FireClient(playerRecord.player, event)
		end
	end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToClients(event)
        if playerRecord.player then
			for _, record in ServerModule.playerRecords do
				if record.loaded == false or record.dummy == true then
					continue
				end
				RemoteEvent:FireClient(record.player, event)
			end
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendEventToOtherClients(event)
		for _, record in ServerModule.playerRecords do
			if record.loaded == false or record.dummy == true then
				continue
			end
            if record == playerRecord then
                continue
            end
            RemoteEvent:FireClient(record.player, event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:SendCollisionData()
       
		if ServerModule.collisionRootFolder ~= nil then
			local event = {}
			event.t = Enums.EventType.CollisionData
            event.playerSize = ServerModule.playerSize
			event.data = ServerModule.collisionRootFolder
			self:SendEventToClient(event)
        end
    end

    -- selene: allow(shadowing)
    function playerRecord:Despawn()
        if self.chickynoid then
            ServerModule.OnPlayerDespawn:Fire(self)

            print("Despawned!")
            self.chickynoid:Destroy()
            self.chickynoid = nil
            self.respawnTime = tick() + self.respawnDelay

            local event = { t = EventType.ChickynoidRemoving }
            playerRecord:SendEventToClient(event)
        end
    end

    function playerRecord:SetCharacterMod(characterModName)
		self.characterMod = characterModName
		ServerModule:SetWorldStateDirty()
    end

    -- selene: allow(shadowing)
	function playerRecord:Spawn()
		
		if (playerRecord.loaded == false) then
			warn("Spawn() called before player loaded")
			return
		end
        self:Despawn()

        local chickynoid = ServerChickynoid.new(playerRecord)
        self.chickynoid = chickynoid
        chickynoid.playerRecord = self

        local list = {}
        for _, obj: SpawnLocation in pairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") and obj.Enabled == true then
                table.insert(list, obj)
            end
        end

        if #list > 0 then
            local spawn = list[math.random(1, #list)]
            self.chickynoid:SetPosition(Vector3.new(spawn.Position.x, spawn.Position.y + 5, spawn.Position.z), true)
        else
            self.chickynoid:SetPosition(Vector3.new(0, 10, 0), true)
        end

        self.OnBeforePlayerSpawn:Fire()
        ServerModule.OnBeforePlayerSpawn:Fire(self, playerRecord)

        chickynoid:SpawnChickynoid()

        ServerModule.OnPlayerSpawn:Fire(self, playerRecord)
        return self.chickynoid
    end
	
	function playerRecord:HandlePlayerLoaded()

		print("Player loaded:", playerRecord.name)
		playerRecord.loaded = true

		--Move them from loadingPlayerRecords to playerRecords
		ServerModule.playerRecords[playerRecord.userId] = playerRecord		
		ServerModule.loadingPlayerRecords[playerRecord.userId] = nil

		self:SendCollisionData()

		WeaponsModule:OnPlayerConnected(ServerModule, playerRecord)

		ServerModule.OnPlayerConnected:Fire(ServerModule, playerRecord)
		ServerModule:SetWorldStateDirty()
	end

	
    return playerRecord
end

function ServerModule:SendEventToClients(event)
    RemoteEvent:FireAllClients(event)
end

function ServerModule:SetWorldStateDirty()
	for _, data in pairs(self.playerRecords) do
		data.pendingWorldState = true
	end
end

function ServerModule:SendWorldState(playerRecord)
	
	if (playerRecord.loaded == false) then
		return
	end
	
    local event = {}
    event.t = Enums.EventType.WorldState
    event.worldState = {}
    event.worldState.flags = self.flags

    event.worldState.players = {}
    for _, data in pairs(self.playerRecords) do
        local info = {}
        info.name = data.name
		info.userId = data.userId
		info.characterMod = data.characterMod
        event.worldState.players[tostring(data.slot)] = info
    end

    event.worldState.serverHz = self.config.serverHz
    event.worldState.fpsMode = self.config.fpsMode
	event.worldState.animations = Animations.animations
		
	playerRecord:SendEventToClient(event)
	
	playerRecord.pendingWorldState = false
end

function ServerModule:PlayerDisconnected(userId)
	
	local loadingPlayerRecord = self.loadingPlayerRecords[userId]
	if (loadingPlayerRecord ~= nil) then
		print("Player ".. loadingPlayerRecord.player.Name .. " disconnected")
		self.loadingPlayerRecords[userId] = nil
	end
		
	local playerRecord = self.playerRecords[userId]
    if playerRecord then
        print("Player ".. playerRecord.player.Name .. " disconnected")

		playerRecord:Despawn()
		
		--nil this out
		playerRecord.previousCharacterData = nil
		self.slots[playerRecord.slot] = nil
		playerRecord.slot = nil
		
        self.playerRecords[userId] = nil

        self:DebugSlots()
    end

    --Tell everyone
    for _, data in pairs(self.playerRecords) do
		local event = {}
		event.t = Enums.EventType.PlayerDisconnected
		event.userId = userId
		data:SendEventToClient(event)
	end
	self:SetWorldStateDirty()
end

function ServerModule:DebugSlots()
    --print a count
    local free = 0
    local used = 0
    for j = 1, self.config.maxPlayers do
        if self.slots[j] == nil then
            free += 1
            
        else
            used += 1
        end
    end
    print("Players:", used, " (Free:", free, ")")
end

function ServerModule:GetPlayerByUserId(userId)
    return self.playerRecords[userId]
end

function ServerModule:GetPlayers()
    return self.playerRecords
end

function ServerModule:RobloxHeartbeat(deltaTime)

    if (false) then
	    self.accumulatedTime += deltaTime
	    local frac = 1 / 60
	    local maxSteps = 0
	    while self.accumulatedTime > 0 do
	        self.accumulatedTime -= frac
	        self:Think(frac)
	        
	        maxSteps+=1
	        if (maxSteps > 2) then
	            self.accumulatedTime = 0
	            break
	        end
	    end

	      --Discard accumulated time if its a tiny fraction
	    local errorSize = 0.001 --1ms
	    if self.accumulatedTime > -errorSize then
	        self.accumulatedTime = 0
	    end
	else
    
	    --Much simpler - assumes server runs at 60.
	    self.accumulatedTime = 0
	    local frac = 1 / 60
		self:Think(deltaTime)
	end

  
end

function ServerModule:RobloxPhysicsStep(deltaTime)
    for _, playerRecord in pairs(self.playerRecords) do
        if playerRecord.chickynoid then
            playerRecord.chickynoid:RobloxPhysicsStep(self, deltaTime)
        end
    end
end

function ServerModule:GetDoNotReplicate()
    local camera = game.Workspace:FindFirstChild("DoNotReplicate")
    if camera == nil then
        camera = Instance.new("Camera")
        camera.Name = "DoNotReplicate"
        camera.Parent = game.Workspace
    end
    return camera
end

function ServerModule:UpdateTiming(deltaTime)
	--Do fps work
	self.framesPerSecondCounter += 1
	self.framesPerSecondTimer += deltaTime
	if self.framesPerSecondTimer > 1 then
		self.framesPerSecondTimer = math.fmod(self.framesPerSecondTimer, 1)
		self.framesPerSecond = self.framesPerSecondCounter
		self.framesPerSecondCounter = 0
	end

	self.serverSimulationTime = tick() - self.startTime
end

function ServerModule:Think(deltaTime)

	self:UpdateTiming(deltaTime)
	
	self:SendWorldStates()
		
	self:SpawnPlayers()

    CollisionModule:UpdateDynamicParts()

	self:UpdatePlayerThinks(deltaTime)

	self:UpdatePlayerPostThinks(deltaTime)
    
    WeaponsModule:Think(self, deltaTime)
	
	self:StepServerMods(deltaTime)
	
	self:Do20HzOperations(deltaTime)
end

function ServerModule:StepServerMods(deltaTime)
	--Step the server mods
	local modules = ServerMods:GetMods("servermods")
	for _, mod in pairs(modules) do
		if (mod.Step) then
			mod:Step(self, deltaTime)
		end
	end
end


function ServerModule:Do20HzOperations(deltaTime)
	
	--Calc timings
	self.serverStepTimer += deltaTime
	self.serverTotalFrames += 1

	local fraction = (1 / self.config.serverHz)
	
	--Too soon
	if self.serverStepTimer < fraction then
		return
	end
		
	while self.serverStepTimer > fraction do -- -_-'
		self.serverStepTimer -= fraction
	end
	
	
	self:WriteCharacterDataForSnapshots()
	
	--Playerstate, for reconciliation of client prediction
	self:UpdatePlayerStatesToPlayers()
	
	--we write the antilag at 20hz, to match when we replicate snapshots to players
	Antilag:WritePlayerPositions(self.serverSimulationTime)
	
	--Figures out who can see who, for replication purposes
	self:DoPlayerVisibilityCalculations()
	
	--Generate the snapshots for all players
	self:WriteSnapshotsForPlayers()
 
end


function ServerModule:WriteCharacterDataForSnapshots()
	
	for userId, playerRecord in pairs(self.playerRecords) do
		if (playerRecord.chickynoid == nil) then
			continue
		end
		
		--Grab a copy at this serverTotalFrame, because we're going to be referencing this for building snapshots with
		playerRecord.chickynoid.prevCharacterData[self.serverTotalFrames] = DeltaTable:DeepCopy( playerRecord.chickynoid.simulation.characterData)
		
		--Toss it out if its over a second old
		for timeStamp, rec in playerRecord.chickynoid.prevCharacterData do
			if (timeStamp < self.serverTotalFrames - 60) then
				playerRecord.chickynoid.prevCharacterData[timeStamp] = nil
			end
		end
	end
end

function ServerModule:UpdatePlayerStatesToPlayers()
	
	for userId, playerRecord in pairs(self.playerRecords) do

		--Bots dont generate snapshots, unless we're testing for performance
		if (self.flags.DEBUG_BOT_BANDWIDTH ~= true) then
			if playerRecord.dummy == true then
				continue
			end
		end			

		if playerRecord.chickynoid ~= nil then

			--see if we need to antiwarp people

			if (self.config.antiWarp == true) then
				local timeElapsed = playerRecord.chickynoid.processedTimeSinceLastSnapshot

				local possibleStep = playerRecord.chickynoid.elapsedTime - playerRecord.chickynoid.playerElapsedTime

				if (timeElapsed == 0 and playerRecord.chickynoid.lastProcessedCommand ~= nil) then
					--This player didn't move this snapshot
					playerRecord.chickynoid.errorState = Enums.NetworkProblemState.CommandUnderrun

					local timeToPatchOver = 1 / self.config.serverHz
					playerRecord.chickynoid:GenerateFakeCommand(self, timeToPatchOver)

					--print("Adding fake command ", timeToPatchOver)

					--Move them.
					playerRecord.chickynoid:Think(self, self.serverSimulationTime, 0)
				end
				--print("e:" , timeElapsed * 1000)
			end

			playerRecord.chickynoid.processedTimeSinceLastSnapshot = 0

			--Send results of server move
			local event = {}
			event.t = EventType.State
			
			
			--bonus fields
			event.e = playerRecord.chickynoid.errorState
			event.s = self.framesPerSecond
			
			--required fields
			event.lastConfirmedCommand = playerRecord.chickynoid.lastConfirmedCommand
			event.serverTime = self.serverSimulationTime
			event.serverFrame = self.serverTotalFrames
			event.playerStateDelta, event.playerStateDeltaFrame = playerRecord.chickynoid:ConstructPlayerStateDelta(self.serverTotalFrames)

			playerRecord:SendUnreliableEventToClient(event)
			
			--Clear the error state flag 
			playerRecord.chickynoid.errorState = Enums.NetworkProblemState.None
		end


	end
 	
end

function ServerModule:SendWorldStates()
	--send worldstate
	for _, playerRecord in pairs(self.playerRecords) do
		if (playerRecord.pendingWorldState == true) then
			self:SendWorldState(playerRecord)
		end	
	end
end

function ServerModule:SpawnPlayers()
	--Spawn players
	for _, playerRecord in self.playerRecords do
		if (playerRecord.loaded == false) then
			continue
		end
		
		if (playerRecord.chickynoid ~= nil and playerRecord.reset == true) then
			playerRecord.reset = false
			playerRecord:Despawn()
		end
				
		if playerRecord.chickynoid == nil and playerRecord.allowedToSpawn == true then
			if tick() > playerRecord.respawnTime then
				playerRecord:Spawn()
			end
		end
	end
end

function ServerModule:UpdatePlayerThinks(deltaTime)
	
	debug.profilebegin("UpdatePlayerThinks")
	--1st stage, pump the commands
	for _, playerRecord in self.playerRecords do
		if playerRecord.dummy == true then
			playerRecord.BotThink(deltaTime)
		end

		if playerRecord.chickynoid then
			playerRecord.chickynoid:Think(self, self.serverSimulationTime, deltaTime)

			if playerRecord.chickynoid.simulation.state.pos.y < -2000 then
				playerRecord:Despawn()
			end
		end
	end
	debug.profileend()
end

function ServerModule:UpdatePlayerPostThinks(deltaTime)
	
	
	for _, playerRecord in self.playerRecords do
		if playerRecord.chickynoid then
			playerRecord.chickynoid:PostThink(self, deltaTime)
		end
	end
	
end

function ServerModule:DoPlayerVisibilityCalculations()
	
	debug.profilebegin("DoPlayerVisibilityCalculations")
	
	--This gets done at 20hz
	local modules = ServerMods:GetMods("servermods")
	
	for key,mod in modules do
		if (mod.UpdateVisibility ~= nil) then
			mod:UpdateVisibility(self, self.flags.DEBUG_BOT_BANDWIDTH)
		end
	end
	
	
	--Store the current visibility table for the current server frame
	for userId, playerRecord in self.playerRecords do
		playerRecord.visHistoryList[self.serverTotalFrames] = playerRecord.visibilityList
		
		--Store two seconds tops
		local cutoff = self.serverTotalFrames - 120
		if (playerRecord.lastConfirmedSnapshotServerFrame ~= nil) then
			cutoff = math.max(playerRecord.lastConfirmedSnapshotServerFrame, cutoff)
		end
		
		for timeStamp, rec in playerRecord.visHistoryList do
			if (timeStamp < cutoff) then
				playerRecord.visHistoryList[timeStamp] = nil
			end
		end
	end
	
	debug.profileend()
end

 
function ServerModule:WriteSnapshotsForPlayers()
 	
	ServerSnapshotGen:DoWork(self.playerRecords, self.serverTotalFrames, self.serverSimulationTime, self.flags.DEBUG_BOT_BANDWIDTH)
	
	self.serverLastSnapshotFrame = self.serverTotalFrames
	
end
	
function ServerModule:RecreateCollisions(rootFolder)
    self.collisionRootFolder = rootFolder

    for _, playerRecord in self.playerRecords do
        playerRecord:SendCollisionData()
    end

    CollisionModule:MakeWorld(self.collisionRootFolder, self.playerSize) 
end

return ServerModule
