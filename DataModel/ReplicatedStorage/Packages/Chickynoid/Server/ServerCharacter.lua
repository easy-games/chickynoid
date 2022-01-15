--!strict

--[=[
    @class ServerCharacter
    @server

    Server-side character which exposes methods for manipulating a player's character,
    such as teleporting and applying impulses.
]=]

local Transport = require(script.Parent.ServerTransport)

local Types = require(script.Parent.Parent.Types)
local Enums = require(script.Parent.Parent.Enums)
local EventType = Enums.EventType

local Simulation = require(script.Parent.Parent.Simulation)

local SERVER_HZ = 5

local ServerCharacter = {}
ServerCharacter.__index = ServerCharacter

--[=[
    Constructs a new [ServerCharacter] and attaches it to the specified player.
    @return ServerCharacter
]=]
function ServerCharacter.new(player: Player, config: Types.IServerConfig)
    local self = setmetatable({
        player = player,

        _transport = Transport.new(player),
        _simulation = Simulation.new(config.simulationConfig),

        _unprocessedCommands = {},
        _lastConfirmedCommand = nil,

        _serverFrames = 0,
    }, ServerCharacter)

    -- TODO: The simulation shouldn't create a debug model like this.
    -- For now, just delete it server-side.
    self._simulation.debugModel:Destroy()
    self._simulation.whiteList = { workspace.GameArea, workspace.Terrain }

    self._transport.OnEventReceived:Connect(function(event)
        self:_handleClientEvent(event)
    end)

    self:_spawnCharacter()

    return self
end

--[=[
    Sets the position of the character and replicates it to clients.
]=]
function ServerCharacter:SetPosition(position: Vector3)
    self._simulation.pos = position
end

--[=[
    Returns the position of the character.
]=]
function ServerCharacter:GetPosition()
    return self._simulation.pos
end

--[=[
    Steps the simulation forward by one frame. This loop handles the simulation
    and replication timings.
]=]
function ServerCharacter:Heartbeat(_dt: number)
    -- 1st stage: Step the simulation
    -- Simple version, just process all of their commands:
    --  No antiwarp (if no commands, synth one, or players wont fall/will freeze in air)
    --  No buffering (keep X ms of commands unprocessed)
    --  No speedcheat detection (monitor sum of dt)
    for _, command in ipairs(self._unprocessedCommands) do
        self._simulation:ProcessCommand(command)
        self._lastConfirmedCommand = command.l
    end
    table.clear(self._unprocessedCommands)

    -- 2nd stage: Replicate to the player
    self._serverFrames += 1
    if self._serverFrames > (60 / SERVER_HZ) then
        self._serverFrames = 0

        self._transport:QueueEvent(EventType.State, {
            player = self.player,
            lastConfirmed = self._lastConfirmedCommand,
            state = self._simulation:WriteState(),
        })

        -- Send that event and any others which have occured since the last
        -- replication (character spawns, etc).
        self._transport:Flush()
    end
end

--[=[
    Callback for handling all events from the client.

    @param event table -- The event sent by the client.
    @private
]=]
function ServerCharacter:_handleClientEvent(event: table)
    if event.type == EventType.Command then
        local command = event.data.command
        if command and typeof(command) == "table" then
            table.insert(self._unprocessedCommands, command)
        end
    end
end

--[=[
    Picks a location to spawn the character and replicates it to the client.
    @private
]=]
function ServerCharacter:_spawnCharacter()
    local list = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") and obj.Enabled == true then
            table.insert(list, obj)
        end
    end

    if #list > 0 then
        local spawn = list[math.random(1, #list)]
        self:SetPosition(Vector3.new(spawn.Position.x, spawn.Position.y + 5, spawn.Position.z))
    else
        self:SetPosition(Vector3.new(0, 10, 0))
    end

    self._transport:QueueEvent(EventType.CharacterAdded, {
        position = self._simulation.pos,
    })
    self._transport:Flush()

    print("Spawned character and sent event for player:", self.player)
end

return ServerCharacter
