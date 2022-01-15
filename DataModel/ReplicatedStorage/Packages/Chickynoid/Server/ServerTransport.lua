--!strict

--[=[
    @class ServerTransport
    @private
    @server

    Handles communication to and from individual clients on the server. Each
    player gets their own Transport and replication packets are customized
    to them based on factors like distances from other players.

    TODO: In the future this should be implemented with some kind of BitBuffer
    to minimize network usage.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vendor = script.Parent.Parent.Vendor
local Signal = require(Vendor.Signal)

local REMOTE_NAME = "Chickynoid_Replication"
local CachedRemote: RemoteEvent

local ServerTransport = {}
ServerTransport.__index = ServerTransport

--[=[
    Constructs a new [ServerTransport] for the specified player.
    @return ServerTransport
]=]
function ServerTransport.new(player: Player)
    local self = setmetatable({
        OnEventReceived = Signal.new(),

        _player = player,
        _eventQueue = {},
    }, ServerTransport)

    local event = self:_getRemoteEvent()
    event.OnServerEvent:Connect(function(eventPlayer, events)
        if eventPlayer ~= player then
            return
        end

        for _, eventObj in ipairs(events) do
            self.OnEventReceived:Fire(eventObj)
        end
    end)

    return self
end

--[=[
    Inserts a new event into the queue along with the event type to be handled by the client.

    @param eventType number -- Numeric ID of the event, this should be an enum.
    @param event table -- The event object.
]=]
function ServerTransport:QueueEvent(eventType: number, event: table)
    table.insert(self._eventQueue, {
        type = eventType,
        data = event,
    })
end

--[=[
    Constructs a packet from all events in the queue and sends it to the client.

    TODO: Currently this implementation is just an array of events. In the future
    it should be implemented as a BitBuffer to reduce network usage.
]=]
function ServerTransport:Flush()
    local remote = self:_getRemoteEvent()

    -- local eventCount = #self._eventQueue
    -- print(("Flushing %s events"):format(eventCount))

    local packet = self._eventQueue
    remote:FireClient(self._player, packet)

    table.clear(self._eventQueue)
end

--[=[
    Gets the existing replication remote or creates a new one.

    @return RemoteEvent
    @private
]=]
function ServerTransport:_getRemoteEvent()
    if CachedRemote then
        return CachedRemote
    end

    -- Remote hasn't been found in a previous Transport instance, check if it exists first
    local existingRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if existingRemote then
        CachedRemote = existingRemote
        return existingRemote :: RemoteEvent
    end

    -- Remote doesn't exist, create a new one
    local remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage

    CachedRemote = remote
    return remote
end

return ServerTransport
