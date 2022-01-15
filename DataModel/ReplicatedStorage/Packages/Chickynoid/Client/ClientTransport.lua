--!strict

--[=[
    @class ClientTransport
    @private
    @client

    Handles communication between the server and client through Event objects.
    Unlike the [ServerTransport], the [ClientTransport] is a singleton. Only
    one Transport exists on the client and it is consumed by multiple
    different modules.

    TODO: In the future this should be implemented with some kind of BitBuffer
    to minimize network usage.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vendor = script.Parent.Parent:WaitForChild("Vendor")
local Signal = require(Vendor:WaitForChild("Signal"))

local REMOTE_NAME = "Chickynoid_Replication"
local CachedRemote: RemoteEvent

local ClientTransport = {}
ClientTransport.OnEventReceived = Signal.new()
ClientTransport._eventQueue = {}

--[=[
    Attaches connection to the remote so we can listen for events from the server locally.

    Also caches the replication remote before any consumers of [ClientTransport] try to use
    it. This is required to prevent unexpected yielding or errors when Transport methods
    rely on the remote.

    @error "Remote cannot be found" -- Thrown when the client cannot find a remote after waiting for it for some period of time.
    @yields
]=]
function ClientTransport:PrepareRemote()
    local remote = self:_getRemoteEvent(true)
    remote.OnClientEvent:Connect(function(events)
        for _, event in ipairs(events) do
            self.OnEventReceived:Fire(event)
        end
    end)
end

--[=[
    Inserts a new event into the queue along with the event type to be handled by the server.

    @param eventType number -- Numeric ID of the event, this should be an enum.
    @param event table -- The event object.
]=]
function ClientTransport:QueueEvent(eventType: number?, event: table)
    table.insert(self._eventQueue, {
        type = eventType,
        data = event,
    })
end

--[=[
    Constructs a packet from all events in the queue and sends it to the server.

    TODO: Currently this implementation is just an array of events. In the future
    it should be implemented as a BitBuffer to reduce network usage.
]=]
function ClientTransport:Flush()
    local remote = self:_getRemoteEvent()

    -- local eventCount = #self._eventQueue
    -- print(("Flushing %s events"):format(eventCount))

    local packet = self._eventQueue
    remote:FireServer(packet)

    table.clear(self._eventQueue)
end

--[=[
    Calls the passed callback when any event of the specified type is received on
    the client.

    @param eventType number -- Numeric ID of the event, this should be an enum.
    @param callback (event: table) -> nil -- Callback that is passed the event object..
]=]
function ClientTransport:OnEventTypeReceived(eventType: number, callback: (event: table) -> nil)
    self.OnEventReceived:Connect(function(event)
        if event.type == eventType then
            callback(event.data)
        end
    end)
end

--[=[
    Gets the replication remote and throws if it cannot be found. This could yield
    if no remote is cached, so consumers of [ClientTransport] should cache it before
    using the Transport with [ClientTransport:CacheRemote].

    @error "Remote cannot be found" -- Thrown when the client cannot find a remote after waiting for it for some period of time.
    @private
    @yields
]=]
function ClientTransport:_getRemoteEvent(allowYield: boolean?): RemoteEvent
    if CachedRemote then
        return CachedRemote
    end

    local getMethod = if allowYield
        then ReplicatedStorage.WaitForChild
        else ReplicatedStorage.FindFirstChild

    local existingRemote = getMethod(ReplicatedStorage, REMOTE_NAME) :: RemoteEvent
    if existingRemote then
        CachedRemote = existingRemote
        return existingRemote
    end

    error("Remote cannot be found")
end

return ClientTransport
