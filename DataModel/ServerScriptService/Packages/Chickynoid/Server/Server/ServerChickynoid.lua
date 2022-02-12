--[=[
    @class ServerChickynoid
    @server

    Server-side character which exposes methods for manipulating a player's simulation
    such as teleporting and applying impulses.
]=]

local path = game.ReplicatedFirst.Packages.Chickynoid
local Types = require(path.Types)
local Enums = require(path.Enums)
local EventType = Enums.EventType

local Simulation = require(path.Simulation)


local ServerChickynoid = {}
ServerChickynoid.__index = ServerChickynoid

--[=[
    Constructs a new [ServerChickynoid] and attaches it to the specified player.
    @return ServerChickynoid
]=]
function ServerChickynoid.new(playerRecord, config: Types.IServerConfig)
    local self = setmetatable({
        playerRecord = playerRecord,

        simulation = Simulation.new(),
        
        unprocessedCommands = {},
        commandSerial = 0,
        lastConfirmedCommand = nil,
        elapsedTime = 0,
        playerElapsedTime = 0,
 
        errorState = Enums.NetworkProblemState.None,
        
        speedCheatThreshhold = 150 * 0.001, --milliseconds
        antiwarpThreshhold = 60 * 0.001, --milliseconds
        
        bufferedCommandTime =  20 * 0.001, --ms
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

function ServerChickynoid:GenerateFakeCommand(deltaTime)
    local command = {}
    command.deltaTime = deltaTime
    command.x = 0
    command.y = 0
    command.z = 0
        
    command.serial =self.commandSerial
    self.commandSerial += 1
    
    self.playerElapsedTime += command.deltaTime
    command.totalTime = self.elapsedTime 
    table.insert(self.unprocessedCommands, command)
end

--[=[
    Steps the simulation forward by one frame. This loop handles the simulation
    and replication timings.
]=]

 
function ServerChickynoid:Think(dt: number)
    
    
    --  Anticheat methods
    --  We keep X ms of commands unprocessed, so that if players stop sending upstream, we have some commands to keep going with
    --  We only allow the player to get +150ms ahead of the servers estimated sim time (Speed cheat), if they're over this, we discard commands
    --  We only allow the player to get -60ms behind the servers estimated sim time (Lag cheat), if they're under this, we generate fake commands to catch them up
    --  We only allow 15 commands per server tick (ratio of 5:1) if the user somehow has more than 15 commands that are legitimately needing processing, we discard them all
    

    self.elapsedTime += dt
  
    --Once a player has connected, monitor their total elapsed time
    --If it falls behind, catch them up!
    if (self.playerElapsedTime > 0 and self.playerRecord.dummy == false) then
        if (self.playerElapsedTime < self.elapsedTime - self.antiwarpThreshhold) then
            
            self.errorState  = Enums.NetworkProblemState.TooFarAhead
            --Generate some commands
            local timeToCover = (self.elapsedTime - self.antiwarpThreshhold) - self.playerElapsedTime
            
            while (timeToCover > 0) do
                timeToCover-= 1/60
                self:GenerateFakeCommand(1/60)
            end
        end
    end
    
    --Sort commands by their serial
    table.sort(self.unprocessedCommands,function(a,b)
        return a.serial < b.serial
    end)
    
    local maxCommandsPerFrame = 15
            
    for _, command in pairs(self.unprocessedCommands) do
        
        if (command.totalTime > self.elapsedTime - self.bufferedCommandTime) then
            --Can't process this yet, its our buffer
            continue
        end        
                
        maxCommandsPerFrame-=1
        if (maxCommandsPerFrame < 0) then
            --print("Player send too many commands at once:", self.playerRecord.name)
            self.errorState = Enums.NetworkProblemState.TooManyCommands
            self.playerElapsedTime = self.elapsedTime
            self.unprocessedCommands = {}
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
            
            --Sanitize
            if (command.x == nil or typeof(command.x) ~= "number" or command.x~=command.x) then
                return
            end
            if (command.y == nil or typeof(command.y) ~= "number" or command.y~=command.y) then
                return
            end
            if (command.z == nil or typeof(command.z) ~= "number" or command.z~=command.z) then
                return
            end
            if (command.deltaTime == nil or typeof(command.deltaTime) ~= "number" or command.deltaTime~=command.deltaTime) then
                return
            end
            
            
            command.serial = self.commandSerial
            self.commandSerial += 1
         
            --sanitize
            if (command.deltaTime) then
                if (command.deltaTime > 0.2) then
                    command.deltaTime = 0.2
                end
                
                --500fps cap
                if (command.deltaTime < 1/500) then
                    command.deltaTime = 1/500
                    --print("Player over 500fps:", self.playerRecord.name)
                end
                
                --On the first command, init
                if (self.playerElapsedTime == 0) then
                    self.playerElapsedTime = self.elapsedTime
                end
                
                
                if (self.playerElapsedTime > self.elapsedTime + self.speedCheatThreshhold) then
                    --print("Player too far ahead", self.playerRecord.name) 
                    self.errorState = Enums.NetworkProblemState.TooFarAhead
                else
                    self.playerElapsedTime += command.deltaTime
                    command.totalTime = self.elapsedTime 
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
