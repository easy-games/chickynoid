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
        elapsedTime = 0,
        playerElapsedTime = 0,
        tooFarAhead = false,
        
        speedCheatThreshhold = 150 * 0.001, --milliseconds
        bufferedCommandTime = 30, --ms
        serverFrames = 0,
    }, ServerChickynoid)
    
    
    
    -- TODO: The simulation shouldn't create a debug model like this.
    -- For now, just delete it server-side.
    if (self.simulation.debugModel) then
        self.simulation.debugModel:Destroy()
        self.simulation.debugModel = nil
    end
    
 
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
    self.elapsedTime += dt
    
    
    if (#self.unprocessedCommands == 0) then
        --This is a problem, the player has no commands (are they freezing?)
        
    end 
    

    table.sort(self.unprocessedCommands,function(a,b)
        return a.serial < b.serial
    end)
    
    local maxCommandsPerFrame = 5
            
    for _, command in pairs(self.unprocessedCommands) do
        
        maxCommandsPerFrame-=1
        if (maxCommandsPerFrame < 0) then
            print("Player lagged:", self.playerRecord.name)
            self.playerElapsedTime = self.elapsedTime
            break --Discard all buffered commands
        end
        
                
        self.simulation:ProcessCommand(command)
        command.processed = true
        
        if (command.l and tonumber(command.l) ~= nil) then
            self.lastConfirmedCommand = command.l
        end
    end
    
    local newList = {}
    for _, command in pairs(self.unprocessedCommands) do
        if (command.processed ~= true) then
            table.insert(newList,command)
        end
    end
    
    self.unprocessedCommands = newList
    
 
    
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
         
            --sanitize
            if (command.deltaTime) then
                if (command.deltaTime > 0.2) then
                    command.deltaTime = 0.2
                end
                
                --On the first command, init
                if (self.playerElapsedTime == 0) then
                    self.playerElapsedTime = self.elapsedTime
                end
                
                
                if (self.playerElapsedTime > self.elapsedTime + self.speedCheatThreshhold) then
                    print("Player too far ahead", self.playerRecord.name) 
                             
                else
                    self.playerElapsedTime += command.deltaTime
                    command.totalTime = self.playerElapsedTime 
                    table.insert(self.unprocessedCommands, command)
                end
            else
                --discard
            end
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
    self.simulation.state.vel = Vector3.zero
    
    if (self.playerRecord.dummy == false) then
        
        local event = {}
        event.t = EventType.ChickynoidAdded
        event.position = self.simulation.state.pos
       
        self.playerRecord:SendEventToClient(event)
        
    end
    print("Spawned character and sent event for player:", self.playerRecord.name)
    
end

return ServerChickynoid
