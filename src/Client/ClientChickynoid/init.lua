--[=[
    @class ClientChickynoid
    @client

    A Chickynoid class that handles character simulation and command generation for the client
    There is only one of these for the local player
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvent = ReplicatedStorage:WaitForChild("ChickynoidReplication") :: RemoteEvent

local path = script.Parent.Parent
local Simulation = require(path.Simulation)
local CollisionModule = require(path.Simulation.CollisionModule)
local DeltaTable = require(path.Vendor.DeltaTable)

local TrajectoryModule = require(path.Simulation.TrajectoryModule)
local Enums = require(path.Enums)
local EventType = Enums.EventType

local ClientChickynoid = {}
ClientChickynoid.__index = ClientChickynoid

--[=[
    Constructs a new ClientChickynoid for the local player, spawning it at the specified
    position. The position is just to prevent a mispredict.

    @param position Vector3 -- The position to spawn this character, provided by the server.
    @return ClientChickynoid
]=]
function ClientChickynoid.new(position: Vector3)
    local self = setmetatable({

        simulation = Simulation.new(),
        predictedCommands = {},
        stateCache = {},

        localFrame = 0,

        mispredict = Vector3.new(0, 0, 0),

        debug = {
            processedCommands = 0,
            showDebugSpheres = false,
            useSkipResimulationOptimization = true,
            debugParts = nil,
        },
    }, ClientChickynoid)

    self.simulation.state.pos = position
 
    self:HandleLocalPlayer()

    return self
end

function ClientChickynoid:HandleLocalPlayer() end


--[=[
    The server sends each client an updated world state on a fixed timestep. This
    handles state updates for this character.

    @param state table -- The new state sent by the server.
    @param lastConfirmed number -- The serial number of the last command confirmed by the server - can be nil!
    @param serverTime - Time when command was confirmed
]=]
function ClientChickynoid:HandleNewState(stateDelta, lastConfirmed, serverTime)
    self:ClearDebugSpheres()

    --Handle deltaCompression
    if (self.lastNetworkState == nil) then
        self.lastNetworkState = {}
    end
	local stateRecord = DeltaTable:ApplyDeltaTable(self.lastNetworkState, stateDelta)
	self.lastNetworkState = DeltaTable:DeepCopy(stateRecord)
		
    -- Build a list of the commands the server has not confirmed yet
    local remainingCommands = {}
	
	if (lastConfirmed ~= nil) then
	    for _, cmd in pairs(self.predictedCommands) do
	        -- event.lastConfirmed = serial number of last confirmed command by server
	        if cmd.l > lastConfirmed then
	            -- Server hasn't processed this yet
	            table.insert(remainingCommands, cmd)
	        end
	        if cmd.l == lastConfirmed then
	            self.ping = (tick() - cmd.tick) * 1000
	        end
		end
	end

    self.predictedCommands = remainingCommands

    local resimulate = true

    -- Check to see if we can skip simulation
	if (self.debug.useSkipResimulationOptimization == true) then
		
		if (lastConfirmed ~= nil) then
	        local cacheRecord = self.stateCache[lastConfirmed]
			if cacheRecord then
	            -- This is the state we were in, if the server agrees with this, we dont have to resim

				if (cacheRecord.stateRecord.state.pos - stateRecord.state.pos).magnitude < 0.05 and (cacheRecord.stateRecord.state.vel - stateRecord.state.vel).magnitude < 0.1 then
	                resimulate = false
	                -- print("skipped resim")
	            end
	        end

	        -- Clear all the ones older than lastConfirmed
	        for key, _ in pairs(self.stateCache) do
	            if key < lastConfirmed then
	                self.stateCache[key] = nil
	            end
			end
		end
    end

    if resimulate == true then
        --print("resimulating")

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
        for _, command in pairs(remainingCommands) do
            extrapolatedServerTime += command.deltaTime

            TrajectoryModule:PositionWorld(extrapolatedServerTime, command.deltaTime)
            self.simulation:ProcessCommand(command)

            -- Resimulated positions
            self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 255, 0))

            if (self.debug.useSkipResimulationOptimization == true) then
                -- Add to our state cache, which we can use for skipping resims
                local cacheRecord = {}
                cacheRecord.l = command.l
                cacheRecord.stateRecord = self.simulation:WriteState()
        
                self.stateCache[command.l] = cacheRecord
            end
        end

        self.simulation.characterData:SetIsResimulating(false)

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
        --Add the offset to mispredict so we can blend it off
        self.mispredict += delta
    end
    
    return resimulate, self.ping
end


function ClientChickynoid:Heartbeat(command, serverTime: number, deltaTime: number)
    self.localFrame += 1

    --Write the local frame for prediction later
    command.l = self.localFrame
    --Store it
    table.insert(self.predictedCommands, command)

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
        cacheRecord.l = command.l
        cacheRecord.stateRecord = self.simulation:WriteState()

        self.stateCache[command.l] = cacheRecord
    end

    -- Pass to server
    local event = {}
    event.t = EventType.Command
    event.command = command
    RemoteEvent:FireServer(event)

    --once we've sent it, add localtime
    command.tick = tick()
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
