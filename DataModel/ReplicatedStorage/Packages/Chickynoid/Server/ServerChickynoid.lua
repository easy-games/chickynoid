--[=[
    @class ServerChickynoid
    @server

    Server-side character which exposes methods for manipulating a player's simulation
    such as teleporting and applying impulses.
]=]

local Types = require(script.Parent.Parent.Types)
local Enums = require(script.Parent.Parent.Enums)
local EventType = Enums.EventType

local Simulation = require(script.Parent.Parent.Simulation)


local ServerChickynoid = {}
ServerChickynoid.__index = ServerChickynoid

--[=[
    Constructs a new [ServerChickynoid] and attaches it to the specified player.
    @return ServerChickynoid
]=]
function ServerChickynoid.new(playerRecord, config: Types.IServerConfig)
    local self = setmetatable({
        playerRecord = playerRecord,

        simulation = Simulation.new(config.simulationConfig),
        
        unprocessedCommands = {},
        commandSerial = 0,
        lastConfirmedCommand = nil,

        serverFrames = 0,
    }, ServerChickynoid)
    
    
    
    -- TODO: The simulation shouldn't create a debug model like this.
    -- For now, just delete it server-side.
    if (self.simulation.debugModel) then
        self.simulation.debugModel:Destroy()
        self.simulation.debugModel = nil
    end
    
    self.simulation.whiteList = { workspace.GameArea, workspace.Terrain }

    
    
    self:SpawnChickynoid()

    return self
end


function ServerChickynoid:HandleEvent(event)
    self:HandleClientEvent(event)
end


--[=[
    Sets the position of the character and replicates it to clients.
]=]
function ServerChickynoid:SetPosition(position: Vector3)
    self.simulation.state.pos = position
end

--[=[
    Returns the position of the character.
]=]
function ServerChickynoid:GetPosition()
    return self.simulation.state.pos
end

--[=[
    Steps the simulation forward by one frame. This loop handles the simulation
    and replication timings.
]=]

 
function ServerChickynoid:Think(dt: number)
    -- 1st stage: Step the simulation
    -- Simple version, just process all of their commands:
    --  No antiwarp (if no commands, synth one, or players wont fall/will freeze in air)
    --  No buffering (keep X ms of commands unprocessed)
    --  No speedcheat detection (monitor sum of dt)
    
    --This should be sorted
    
    table.sort(self.unprocessedCommands,function(a,b)
        return a.serial < b.serial
    end)
    
    for _, command in pairs(self.unprocessedCommands) do
                
        --sanity check for deltatime
        if (command.deltaTime > 0.2) then
            command.deltaTime = 0.2
        end
        
        self.simulation:ProcessCommand(command)
        
        if (command.l and tonumber(command.l) ~= nil) then
            self.lastConfirmedCommand = command.l
        end
       
    end
 
    table.clear(self.unprocessedCommands)
end



--[=[
    Callback for handling all events from the client.

    @param event table -- The event sent by the client.
    @private
]=]
function ServerChickynoid:HandleClientEvent(event)
    if event.t == EventType.Command then
        local command = event.command
        if command and typeof(command) == "table" then
            
            command.serial = self.commandSerial
            self.commandSerial += 1
            table.insert(self.unprocessedCommands, command)
        end
        
    end
end

--[=[
    Picks a location to spawn the character and replicates it to the client.
    @private
]=]
function ServerChickynoid:SpawnChickynoid()
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
    
    if (self.playerRecord.dummy == false) then
        
        local event = {}
        event.t = EventType.ChickynoidAdded
        event.position = self.simulation.state.pos
       
        self.playerRecord:SendEventToClient(event)
        
    end
    print("Spawned character and sent event for player:", self.playerRecord.name)
    
end

return ServerChickynoid
