
--[=[
    @class ClientChickynoid
    @client

    A Chickynoid class that handles character simulation and command generation for the client
    There is only one of these for the local player
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidReplication") :: RemoteEvent
local UnreliableRemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidUnreliableReplication") :: UnreliableRemoteEvent

local path = game.ReplicatedFirst.Packages.Chickynoid
local Simulation = require(path.Shared.Simulation.Simulation)
local ClientMods = require(path.Client.ClientMods)
local CollisionModule = require(path.Shared.Simulation.CollisionModule)
local DeltaTable = require(path.Shared.Vendor.DeltaTable)

local CommandLayout = require(path.Shared.Simulation.CommandLayout)

local TrajectoryModule = require(path.Shared.Simulation.TrajectoryModule)
local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType

local ClientChickynoid = {}
ClientChickynoid.__index = ClientChickynoid

--[=[
    Constructs a new ClientChickynoid for the local player, spawning it at the specified
    position. The position is just to prevent a mispredict.

    @param position Vector3 -- The position to spawn this character, provided by the server.
    @return ClientChickynoid
]=]
function ClientChickynoid.new(position: Vector3, characterMod: string)
    local self = setmetatable({

        simulation = Simulation.new(game.Players.LocalPlayer.UserId),
		predictedCommands = {},
		commandTimes = {}, --for ping calcs
        localStateCache = {},
        characterMod = characterMod,
        localFrame = 0,
 
		lastSeenPlayerStateFrame = 0,	--For the last playerState we got - the serverFrame the server was on when it was sent
		prevNetworkStates = {},

        mispredict = Vector3.new(0, 0, 0),
		
		commandPacketlossPrevention = true, -- set this to true to duplicate packets
		
        debug = {
            processedCommands = 0,
            showDebugSpheres = false,
            useSkipResimulationOptimization = false,
            debugParts = nil,
        },
    }, ClientChickynoid)

    self.simulation.state.pos = position
    
    --Apply the characterMod
    if (self.characterMod) then
        local loadedModule = ClientMods:GetMod("characters", self.characterMod)
        loadedModule:Setup(self.simulation)
    end

    self:HandleLocalPlayer()
	

    return self
end

function ClientChickynoid:HandleLocalPlayer() end


--[=[
    The server sends each client an updated world state on a fixed timestep. This
    handles state updates for this character.

    @param state table -- The new state sent by the server.
    @param stateDeltaFrame -- The serverFrame this  delta compressed against - due to packetloss the server can't just send you the newest stuff.
    @param lastConfirmed number -- The serial number of the last command confirmed by the server - can be nil!
    @param serverTime - Time when command was confirmed
    @param playerStateFrame -- Current frame on the server, used for tracking playerState
]=]
function ClientChickynoid:HandleNewPlayerState(stateDelta, stateDeltaTime, lastConfirmed, serverTime, playerStateFrame)
    self:ClearDebugSpheres()
	
	local stateRecord = nil
    
	--Find the one we delta compressed against
	if (stateDeltaTime ~= nil) then
		
		local previousConfirmedState = self.prevNetworkStates[stateDeltaTime]
				
		if (previousConfirmedState == nil) then
			print("Previous confirmed time not found" , stateDeltaTime)
			stateRecord = DeltaTable:DeepCopy(stateDelta)
		else
			stateRecord = DeltaTable:ApplyDeltaTable(previousConfirmedState, stateDelta)
		end
		
		self.prevNetworkStates[playerStateFrame] = DeltaTable:DeepCopy(stateRecord)
		
		--Delete the older ones
		for timeStamp, record in self.prevNetworkStates do
			if (timeStamp < stateDeltaTime) then
				self.prevNetworkStates[timeStamp] = nil
			end
		end
	else
		stateRecord = DeltaTable:DeepCopy(stateDelta)
		self.prevNetworkStates[playerStateFrame] =  DeltaTable:DeepCopy(stateRecord)
	end
	
	--Set the last server frame we saw a command from
	self.lastSeenPlayerStateFrame = playerStateFrame
		
    -- Build a list of the commands the server has not confirmed yet
    local remainingCommands = {}
	
	if (lastConfirmed ~= nil) then
	    for _, cmd in self.predictedCommands do
	        -- event.lastConfirmed = serial number of last confirmed command by server
			if cmd.localFrame > lastConfirmed then
	            -- Server hasn't processed this yet
	            table.insert(remainingCommands, cmd)
	        end
			if cmd.localFrame == lastConfirmed then
				local pingTick = self.commandTimes[cmd]
				if (pingTick ~= nil) then
					self.ping = (tick() - pingTick) * 1000
					
					for key,timeStamp in self.commandTimes do
						if (timeStamp < pingTick) then
							self.commandTimes[key] = nil
						end
					end
				end
				
	        end
		end
	end

    self.predictedCommands = remainingCommands
	local resimulate = true
	local mispredicted = false

	--Check to see if we can skip simulation
	--Todo: This needs to check a lot more than position and velocity - the server should always be able to force a reconcile/resim
	if (self.debug.useSkipResimulationOptimization == true) then
		
		if (lastConfirmed ~= nil) then
			local cacheRecord = self.localStateCache[lastConfirmed]
			if cacheRecord then
	            -- This is the state we were in, if the server agrees with this, we dont have to resim
				if (cacheRecord.stateRecord.state.pos - stateRecord.state.pos).magnitude < 0.05 and (cacheRecord.stateRecord.state.vel - stateRecord.state.vel).magnitude < 0.1 then
	                resimulate = false
	                -- print("skipped resim")
	            end
	        end

	        -- Clear all the ones older than lastConfirmed
			for key, _ in pairs(self.localStateCache) do
	            if key < lastConfirmed then
					self.localStateCache[key] = nil
	            end
			end
		end
    end

    if resimulate == true and stateRecord ~= nil then
        local extrapolatedServerTime = serverTime

        -- Record our old state
        local oldPos = self.simulation.state.pos

        -- Reset our base simulation to match the server
        self.simulation:ReadState(stateRecord)

        -- Marker for where the server said we were
        self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 170, 0))

        CollisionModule:UpdateDynamicParts()

        self.simulation.characterData:SetIsResimulating(true)

        -- Resimulate all of the commands the server has not confirmed yet
        -- print("winding forward", #remainingCommands, "commands")
        for _, command in remainingCommands do
            extrapolatedServerTime += command.deltaTime

            TrajectoryModule:PositionWorld(extrapolatedServerTime, command.deltaTime)
            self.simulation:ProcessCommand(command)

            -- Resimulated positions
            self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 255, 0))

            if (self.debug.useSkipResimulationOptimization == true) then
                -- Add to our state cache, which we can use for skipping resims
                local cacheRecord = {}
				cacheRecord.localFrame = command.localFrame
                cacheRecord.stateRecord = self.simulation:WriteState()
        
				self.localStateCache[command.localFrame] = cacheRecord
            end
        end

        self.simulation.characterData:SetIsResimulating(false)

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
		--Add the offset to mispredict so we can blend it off
		
		self.mispredict += delta
		
		if (delta.magnitude > 0.1) then
			--Mispredicted
			mispredicted = true
		end
    end
    
    return mispredicted, self.ping
end

--Entry point every "frame"
function ClientChickynoid:Heartbeat(command, serverTime: number, deltaTime: number)
    self.localFrame += 1
	
	--Store it
	table.insert(self.predictedCommands, command)
	self.commandTimes[command] = tick() -- record the time so we have it for ping calcs
		
    --Write the local frame for prediction later
    command.localFrame = self.localFrame
		
    -- Step this frame
    TrajectoryModule:PositionWorld(serverTime, deltaTime)
    CollisionModule:UpdateDynamicParts()

    self.debug.processedCommands += 1
    self.simulation:ProcessCommand(command)

    -- Marker for positions added since the last server update
    self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(44, 140, 39))

    if (self.debug.useSkipResimulationOptimization == true) then
        -- Add to our state cache, which we can use for skipping resims
        local cacheRecord = {}
		cacheRecord.localFrame = command.localFrame
		cacheRecord.stateRecord = self.simulation:WriteState()

		self.localStateCache[command.localFrame] = cacheRecord
    end

    -- Pass to server
    local event = {}
	--event.t = EventType.Command
	
	--Compressed against command-1
	event[1] = CommandLayout:EncodeCommand(command) 
	
	local prevCommand = nil
	if (#self.predictedCommands > 1 and self.commandPacketlossPrevention == true) then
		prevCommand = self.predictedCommands[#self.predictedCommands - 1]
		event[2] = CommandLayout:EncodeCommand(prevCommand)
	end
	
    UnreliableRemoteEvent:FireServer(event)

    --Remove any sort of smoothing accumulating in the characterData
    self.simulation.characterData:ClearSmoothing()
		
    return command
end

function ClientChickynoid:SpawnDebugSphere(pos, color)
    if (self.debug.showDebugSpheres ~= true) then
        return
    end

    if (self.debug.debugParts == nil) then
        self.debug.debugParts = Instance.new("Folder")
        self.debug.debugParts.Name = "ChickynoidDebugSpheres"
        self.debug.debugParts.Parent = workspace
    end

    local part = Instance.new("Part")
    part.Anchored = true
    part.Color = color
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(5, 5, 5)
    part.Position = pos
    part.Transparency = 0.25
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth

    part.Parent = self.debug.debugParts
end

function ClientChickynoid:ClearDebugSpheres()
    if (self.debug.showDebugSpheres ~= true) then
        return
    end
    if (self.debug.debugParts ~= nil) then
        self.debug.debugParts:ClearAllChildren()
    end
end

function ClientChickynoid:Destroy() end

return ClientChickynoid