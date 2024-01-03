--!native
--[=[
    @class ServerChickynoid
    @server

    Server-side character which exposes methods for manipulating a player's simulation
    such as teleporting and applying impulses.
]=]

local path = game.ReplicatedFirst.Packages.Chickynoid

local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType
local FastSignal = require(path.Shared.Vendor.FastSignal)

local Simulation = require(path.Shared.Simulation.Simulation)
local TrajectoryModule = require(path.Shared.Simulation.TrajectoryModule)
local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local CommandLayout = require(path.Shared.Simulation.CommandLayout)

local ServerMods = require(script.Parent.ServerMods)

local ServerChickynoid = {}
ServerChickynoid.__index = ServerChickynoid

--[=[
	Constructs a new [ServerChickynoid] and attaches it to the specified player.
	@param playerRecord any -- The player record.
	@return ServerChickynoid
]=]
function ServerChickynoid.new(playerRecord)
    local self = setmetatable({
        playerRecord = playerRecord,

        simulation = Simulation.new(playerRecord.userId),

        unprocessedCommands = {},
        commandSerial = 0,
        lastConfirmedCommand = nil,
        elapsedTime = 0,
		playerElapsedTime = 0,
		 		
		processedTimeSinceLastSnapshot = 0,
		
        errorState = Enums.NetworkProblemState.None,

        speedCheatThreshhold = 150  , --milliseconds
       		
		maxCommandsPerSecond = 400,  --things have gone wrong if this is hit, but it's good server protection against possible uncapped fps
		smoothFactor = 0.9999, --Smaller is smoother

		serverFrames = 0,
		
		hitBoxCreated = FastSignal.new(),
		storedStates = {}, --table of the last few states we've send the client, because we use unreliables, we need to switch to ome of these to delta comrpess against once its confirmed
		
		unreliableCommandSerials = 0, --This number only ever goes up, and discards anything out of order
		lastConfirmedPlayerStateFrame = nil,	--Client tells us they've seen this playerstate, so we delta compress against it 
		
		prevCharacterData = {}, -- Rolling history key'd to serverFrame
		
        debug = {
			processedCommands = 0,
			fakeCommandsThisSecond = 0,
			antiwarpPerSecond = 0,
			timeOfNextSecond = 0,
			ping = 0
        },
    }, ServerChickynoid)
        -- TODO: The simulation shouldn't create a debug model like this.
    -- For now, just delete it server-side.
    if self.simulation.debugModel then
        self.simulation.debugModel:Destroy()
        self.simulation.debugModel = nil
    end

    --Apply the characterMod
    if (self.playerRecord.characterMod) then
        local loadedModule = ServerMods:GetMod("characters", self.playerRecord.characterMod)
        if (loadedModule) then
            loadedModule:Setup(self.simulation)
        end
    end

    return self
end

function ServerChickynoid:Destroy()
    if self.pushPart then
        self.pushPart:Destroy()
        self.pushPart = nil
    end

    if self.hitBox then
        self.hitBox:Destroy()
        self.hitBox = nil
    end

    if self.pushes ~= nil then
        for _, record in pairs(self.pushes) do
            record.attachment:Destroy()
            record.pusher:Destroy()
        end
        self.pushes = {}
    end
end

function ServerChickynoid:HandleEvent(server, event)
    self:HandleClientUnreliableEvent(server, event, false)
end

--[=[
    Sets the position of the character and replicates it to clients.
]=]
function ServerChickynoid:SetPosition(position: Vector3, teleport)
    self.simulation.state.pos = position
    self.simulation.characterData:SetTargetPosition(position, teleport)
end

--[=[
    Returns the position of the character.
]=]
function ServerChickynoid:GetPosition()
    return self.simulation.state.pos
end

function ServerChickynoid:GenerateFakeCommand(server, deltaTime)
	
	if (self.lastProcessedCommand == nil) then
		return
	end

	local command = DeltaTable:DeepCopy(self.lastProcessedCommand)
	command.deltaTime = deltaTime
	
	local event = {}
	event.t = EventType.Command
	event.command = command
	self:HandleClientUnreliableEvent(server, event, true)
	
	
	self.debug.fakeCommandsThisSecond += 1
end

--[=[
	Steps the simulation forward by one frame. This loop handles the simulation
	and replication timings.
]=]
function ServerChickynoid:Think(server, _serverSimulationTime, deltaTime)
    --  Anticheat methods
    --  We keep X ms of commands unprocessed, so that if players stop sending upstream, we have some commands to keep going with
    --  We only allow the player to get +150ms ahead of the servers estimated sim time (Speed cheat), if they're over this, we discard commands
    --  The server will generate a fake command if you underrun (do not have any commands during time between snapshots)
    --  todo: We only allow 15 commands per server tick (ratio of 5:1) if the user somehow has more than 15 commands that are legitimately needing processing, we discard them all

	self.elapsedTime += deltaTime
 
    --Sort commands by their serial
    table.sort(self.unprocessedCommands, function(a, b)
        return a.serial < b.serial
	end)
	
    local maxCommandsPerFrame = math.ceil(self.maxCommandsPerSecond * deltaTime)
    
	local processCounter = 0
	for _, command in pairs(self.unprocessedCommands) do
 	
		processCounter += 1
		
		--print("server", command.l, command.serverTime)
		TrajectoryModule:PositionWorld(command.serverTime, command.deltaTime)
		self.debug.processedCommands += 1
		
		--Check for reset
		self:CheckForReset(server, command)
				
		--Step simulation!
		self.simulation:ProcessCommand(command)

		--Fire weapons!
		self.playerRecord:ProcessWeaponCommand(command)

		command.processed = true

		if command.localFrame and tonumber(command.localFrame) ~= nil then
			self.lastConfirmedCommand = command.localFrame
			self.lastProcessedCommand = command
		end
		
		self.processedTimeSinceLastSnapshot += command.deltaTime

		if (processCounter > maxCommandsPerFrame and false) then
			--dump the remaining commands
			self.errorState = Enums.NetworkProblemState.TooManyCommands
			self.unprocessedCommands = {}
			break
		end
	end
 
    local newList = {}
    for _, command in pairs(self.unprocessedCommands) do
        if command.processed ~= true then
            table.insert(newList, command)
        end
    end

	self.unprocessedCommands = newList
	
	
	--debug stuff, too many commands a second stuff
	if (tick() > self.debug.timeOfNextSecond) then
		
		self.debug.timeOfNextSecond = tick() + 1
		self.debug.antiwarpPerSecond = self.debug.fakeCommandsThisSecond
		self.debug.fakeCommandsThisSecond = 0
		
		if (self.debug.antiwarpPerSecond  > 0) then
			print("Lag: ",self.debug.antiwarpPerSecond )
		end
	end
end



--[=[
	Callback for handling movement commands from the client

	@param event table -- The event sent by the client.
	@private
]=]
function ServerChickynoid:HandleClientUnreliableEvent(server, event, fakeCommand)

	if (event[2] ~= nil) then
		local prevCommand = CommandLayout:DecodeCommand(event[2])
		self:ProcessCommand(server, prevCommand, fakeCommand, true)
	end
	
	if (event[1] ~= nil) then
		local command = CommandLayout:DecodeCommand(event[1])		
		self:ProcessCommand(server, command, fakeCommand, false)
	end
end

function ServerChickynoid:CheckForReset(server, command)
	if (command.reset == true) then
		self.playerRecord.reset = true
	end
end

function ServerChickynoid:ProcessCommand(server, command, fakeCommand, resent)
	
	
	if command and typeof(command) == "table" then
		
		if (command.localFrame == nil or typeof(command.localFrame) ~= "number" or command.localFrame ~= command.localFrame) then
			return
		end
		
		if (command.localFrame <= self.unreliableCommandSerials) then
			return
		end
		
		if (command.localFrame - self.unreliableCommandSerials > 1) then
			--warn("Skipped a packet", command.l - self.unreliableCommandSerials)
			
			if (resent) then
				self.errorState = Enums.NetworkProblemState.DroppedPacketGood
			else
				self.errorState = Enums.NetworkProblemState.DroppedPacketBad
			end
		end
		
		self.unreliableCommandSerials = command.localFrame
	
		--Sanitize
		--todo: clean this into a function per type
		if command.x == nil or typeof(command.x) ~= "number" or command.x ~= command.x then
			return
		end
		if command.y == nil or typeof(command.y) ~= "number" or command.y ~= command.y then
			return
		end
		if command.z == nil or typeof(command.z) ~= "number" or command.z ~= command.z then
			return
		end

		if command.serverTime == nil or typeof(command.serverTime) ~= "number" 	or command.serverTime ~= command.serverTime then
			return
		end

		if command.playerStateFrame == nil or typeof(command.playerStateFrame) ~= "number" or command.playerStateFrame ~= command.playerStateFrame then
			return				
		end
		
		if (command.snapshotServerFrame ~= nil) then
			
			--0 is nil
			if (command.snapshotServerFrame > 0) then
				self.playerRecord.lastConfirmedSnapshotServerFrame = command.snapshotServerFrame
			end
		end

		if  command.deltaTime == nil
			or typeof(command.deltaTime) ~= "number"
			or command.deltaTime ~= command.deltaTime
		then
			return
		end

		if command.fa and (typeof(command.fa) == "Vector3") then
			local vec = command.fa
			if vec.x == vec.x and vec.y == vec.y and vec.z == vec.z then
				command.fa = vec
			else
				command.fa = nil
			end
		else
			command.fa = nil
		end
		
		--sanitize
		if (fakeCommand == false) then
	
			self:SetLastSeenPlayerStateToServerFrame(command.playerStateFrame)

			if server.config.fpsMode == Enums.FpsMode.Uncapped then
				--Todo: really slow players need to be penalized harder.
				if command.deltaTime > 0.5 then
					command.deltaTime = 0.5
				end

				--500fps cap
				if command.deltaTime < 1 / 500 then
					command.deltaTime = 1 / 500
					--print("Player over 500fps:", self.playerRecord.name)
				end
			elseif server.config.fpsMode == Enums.FpsMode.Hybrid then
				--Players under 30fps are simualted at 30fps
				if command.deltaTime > 1 / 30 then
					command.deltaTime = 1 / 30
				end

				--500fps cap
				if command.deltaTime < 1 / 500 then
					command.deltaTime = 1 / 500
					--print("Player over 500fps:", self.playerRecord.name)
				end
			elseif server.config.fpsMode == Enums.FpsMode.Fixed60 then
				command.deltaTime = 1 / 60
			else
				warn("Unhandled FPS mode")
			end
		end

		if command.deltaTime then
			--On the first command, init
			if self.playerElapsedTime == 0 then
				self.playerElapsedTime = self.elapsedTime
			end
			local delta = self.playerElapsedTime - self.elapsedTime

			--see if they've fallen too far behind
			if (delta < -(self.speedCheatThreshhold / 1000)) then
				self.playerElapsedTime = self.elapsedTime
				self.errorState = Enums.NetworkProblemState.TooFarBehind
			end

			--test if this is wthin speed cheat range?
			--print("delta", self.playerElapsedTime - self.elapsedTime)
			if self.playerElapsedTime > self.elapsedTime + (self.speedCheatThreshhold / 1000) then
				--print("Player too far ahead", self.playerRecord.name)
				--Skipping this command
				self.errorState = Enums.NetworkProblemState.TooFarAhead
			else


				--write it!
				self.playerElapsedTime += command.deltaTime

				command.elapsedTime = self.elapsedTime --Players real time when this was written.

				command.playerElapsedTime = self.playerElapsedTime
				command.fakeCommand = fakeCommand
				command.serial = self.commandSerial
				self.commandSerial += 1

				--This is the only place where commands get written for the rest of the system
				table.insert(self.unprocessedCommands, command)
			end

			--Debug ping
			if (command.serverTime ~= nil and fakeCommand == false and self.playerRecord.dummy == false) then
				self.debug.ping = math.floor((server.serverSimulationTime - command.serverTime) * 1000)
				self.debug.ping -= ( (1 / server.config.serverHz) * 1000)
			end
		end
	end

end

--We can only delta compress against states that we know for sure the player has seen
function ServerChickynoid:SetLastSeenPlayerStateToServerFrame(serverFrame : number)
	--we have a queue of these, so find the one the player says they've seen and update to that one
	local record = self.storedStates[serverFrame]
	if (record ~= nil) then
		self.lastSeenState = DeltaTable:DeepCopy(record)
		self.lastConfirmedPlayerStateFrame = serverFrame
		
		--delete any older than this
		for timeStamp, record in self.storedStates do
			if (timeStamp < serverFrame) then
				self.storedStates[timeStamp] = nil
			end
		end
	end
end

--Constructs a playerState based on "now" delta'd against the last playerState the player has confirmed seeing (self.lastConfirmedPlayerState) 
--If they have not confirmed anything, return a whole state
function ServerChickynoid:ConstructPlayerStateDelta(serverFrame : number)

	local currentState = self.simulation:WriteState()
	if (self.lastSeenState == nil) then
		self.storedStates[serverFrame] = DeltaTable:DeepCopy(currentState)
		return currentState, nil
	end
	
	--we have one!	
    local stateDelta = DeltaTable:MakeDeltaTable(self.lastSeenState, currentState)
	self.storedStates[serverFrame] = DeltaTable:DeepCopy(currentState)
	return stateDelta, self.lastConfirmedPlayerStateFrame
end


--[=[
    Picks a location to spawn the character and replicates it to the client.
    @private
]=]
function ServerChickynoid:SpawnChickynoid()
    
    --If you need to change anything about the chickynoid initial state like pos or rotation, use OnBeforePlayerSpawn
    if self.playerRecord.dummy == false then
        local event = {}
        event.t = EventType.ChickynoidAdded
        event.state = self.simulation:WriteState()
        event.characterMod = self.playerRecord.characterMod
        self.playerRecord:SendEventToClient(event)
    end
    --@@print("Spawned character and sent event for player:", self.playerRecord.name)
end

function ServerChickynoid:PostThink(server, deltaTime)
    self:UpdateServerCollisionBox(server)

    self.simulation.characterData:SmoothPosition(deltaTime, self.smoothFactor)
end

function ServerChickynoid:UpdateServerCollisionBox(server)
    --Update their hitbox - this is used for raycasts on the server against the player
    if self.hitBox == nil then
        --This box is also used to stop physics props from intersecting the player. Doesn't always work!
        --But if a player does get stuck, they should just be able to move away from it
        local box = Instance.new("Part")
        box.Size = Vector3.new(3, 5, 3)
        box.Parent = server.worldRoot
        box.Position = self.simulation.state.pos
        box.Anchored = true
        box.CanTouch = true
        box.CanCollide = true
        box.CanQuery = true
        box:SetAttribute("player", self.playerRecord.userId)
        self.hitBox = box
        self.hitBoxCreated:Fire(self.hitBox);

        --for streaming enabled games...
        if self.playerRecord.player then
            self.playerRecord.player.ReplicationFocus = self.hitBox
        end
    end
    self.hitBox.CFrame = CFrame.new(self.simulation.state.pos)
    self.hitBox.Velocity = self.simulation.state.vel
end

function ServerChickynoid:RobloxPhysicsStep(server, _deltaTime)
	
	self:UpdateServerCollisionBox(server)
   
end

return ServerChickynoid
