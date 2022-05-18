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

local TrajectoryModule = require(path.Simulation.TrajectoryModule)
local Enums = require(path.Enums)

local EventType = Enums.EventType
local NetGraph = require(path.Client.NetGraph)



local DebugParts = Instance.new("Folder")
DebugParts.Name = "DebugParts"
DebugParts.Parent = workspace

local SKIP_RESIMULATION = true
local DEBUG_SPHERES = false

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
        ping = 0,
        pings = {}, --for average

        mispredict = Vector3.new(0, 0, 0),
        debug = {
            processedCommands = 0,
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
    @param lastConfirmed number -- The serial number of the last command confirmed by the server.
    @param serverTime - Time when command was confirmed
]=]
function ClientChickynoid:HandleNewState(state, lastConfirmed, serverTime, serverHealthFps, networkProblem)
    self:ClearDebugSpheres()

    -- Build a list of the commands the server has not confirmed yet
    local remainingCommands = {}

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

    self.predictedCommands = remainingCommands

    local resimulate = true

    -- Check to see if we can skip simulation
    if SKIP_RESIMULATION then
        local record = self.stateCache[lastConfirmed]
        if record then
            -- This is the state we were in, if the server agrees with this, we dont have to resim

            if (record.state.pos - state.pos).magnitude < 0.05 and (record.state.vel - state.vel).magnitude < 0.1 then
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

    if resimulate == true then
        --print("resimulating")

        local extrapolatedServerTime = serverTime

        -- Record our old state
        local oldPos = self.simulation.state.pos

        -- Reset our base simulation to match the server
        self.simulation:ReadState(state)

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

            if SKIP_RESIMULATION then
                -- Add to our state cache, which we can use for skipping resims
                local cacheRecord = {}
                cacheRecord.l = command.l
                cacheRecord.state = self.simulation:WriteState()
        
                self.stateCache[command.l] = cacheRecord
            end
        end

        self.simulation.characterData:SetIsResimulating(false)

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
        --Add the offset to mispredict so we can blend it off
        self.mispredict += delta
    end

    --Ping graph
    table.insert(self.pings, self.ping)
    if #self.pings > 20 then
        table.remove(self.pings, 1)
    end
    local total = 0
    for _, ping in pairs(self.pings) do
        total += ping
    end
    total /= #self.pings

    NetGraph:Scroll()

    local color1 = Color3.new(1, 1, 1)
    local color2 = Color3.new(1, 1, 0)
    if resimulate == false then
        NetGraph:AddPoint(self.ping * 0.25, color1, 4)
        NetGraph:AddPoint(total * 0.25, color2, 3)
    else
        NetGraph:AddPoint(self.ping * 0.25, color1, 4)
        local tint = Color3.new(0.5, 1, 0.5)
        NetGraph:AddPoint(total * 0.25, tint, 3)
        NetGraph:AddBar(10 * 0.25, tint, 1)
    end

    --Server fps
    if serverHealthFps < 60 then
        NetGraph:AddPoint(serverHealthFps, Color3.new(1, 0, 0), 2)
    else
        NetGraph:AddPoint(serverHealthFps, Color3.new(0.5, 0.0, 0.0), 2)
    end

    --Blue bar
    if networkProblem == Enums.NetworkProblemState.TooFarBehind then
        NetGraph:AddBar(100, Color3.new(0, 0, 1), 0)
    end
    --Yellow bar
    if networkProblem == Enums.NetworkProblemState.TooFarAhead then
        NetGraph:AddBar(100, Color3.new(1, 1, 0), 0)
    end
    --Orange bar
    if networkProblem == Enums.NetworkProblemState.TooManyCommands then
        NetGraph:AddBar(100, Color3.new(1, 0.5, 0), 0)
    end

    NetGraph:SetFpsText("Effective Ping: " .. math.floor(total) .. "ms")
end

function ClientChickynoid:IsConnectionBad()
    if #self.pings > 10 and self.ping > 1000 then
        return true
    end

    return false
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

    if SKIP_RESIMULATION then
        -- Add to our state cache, which we can use for skipping resims
        local cacheRecord = {}
        cacheRecord.l = command.l
        cacheRecord.state = self.simulation:WriteState()

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
    if DEBUG_SPHERES then
        local part = Instance.new("Part")
        part.Anchored = true
        part.Color = color
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(5, 5, 5)
        part.Position = pos
        part.Transparency = 0.25
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth

        part.Parent = DebugParts
    end
end

function ClientChickynoid:ClearDebugSpheres()
    if DEBUG_SPHERES then
        DebugParts:ClearAllChildren()
    end
end

function ClientChickynoid:Destroy() end

return ClientChickynoid
