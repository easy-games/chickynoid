--[=[
    @class ServerChickynoid
    @server

    Server-side character which exposes methods for manipulating a player's simulation
    such as teleporting and applying impulses.
]=]

local path = script.Parent.Parent

local Enums = require(path.Enums)
local EventType = Enums.EventType
local FastSignal = require(path.Vendor.FastSignal)

local Simulation = require(path.Simulation)
local TrajectoryModule = require(path.Simulation.TrajectoryModule)
local DeltaTable = require(path.Vendor.DeltaTable)

local ServerMods = require(path.Server.ServerMods)

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

        simulation = Simulation.new(),

        unprocessedCommands = {},
        commandSerial = 0,
        lastConfirmedCommand = nil,
        elapsedTime = 0,
        playerElapsedTime = 0,

        errorState = Enums.NetworkProblemState.None,

        speedCheatThreshhold = 150 * 0.001, --milliseconds
        antiwarpThreshhold = 150 * 0.001, --milliseconds  (was 60)

        bufferedCommandTime = 20 * 0.001, --ms
        serverFrames = 0,

        hitBoxCreated = FastSignal.new(),

        debug = {
            processedCommands = 0,
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
    self:HandleClientEvent(server, event)
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
    command.f = 0

    command.serial = self.commandSerial
    self.commandSerial += 1

    self.playerElapsedTime += command.deltaTime
    command.serverTime = self.elapsedTime --this is wrong
    command.totalTime = self.elapsedTime
    table.insert(self.unprocessedCommands, command)
end

--[=[
	Steps the simulation forward by one frame. This loop handles the simulation
	and replication timings.
]=]
function ServerChickynoid:Think(_server, _serverSimulationTime, deltaTime)
    --  Anticheat methods
    --  We keep X ms of commands unprocessed, so that if players stop sending upstream, we have some commands to keep going with
    --  We only allow the player to get +150ms ahead of the servers estimated sim time (Speed cheat), if they're over this, we discard commands
    --  We only allow the player to get -150ms behind the servers estimated sim time (Lag cheat), if they're under this, we generate fake commands to catch them up
    --  We only allow 15 commands per server tick (ratio of 5:1) if the user somehow has more than 15 commands that are legitimately needing processing, we discard them all

    self.elapsedTime += deltaTime

    --Once a player has connected, monitor their total elapsed time
    --If it falls behind, catch them up!
    if self.playerElapsedTime > 0 and self.playerRecord.dummy == false then
        if self.playerElapsedTime < self.elapsedTime - self.antiwarpThreshhold then
            self.errorState = Enums.NetworkProblemState.TooFarAhead
            --Generate some commands
            local timeToCover = (self.elapsedTime - self.antiwarpThreshhold) - self.playerElapsedTime

            while timeToCover > 0 do
                timeToCover -= 1 / 60
                self:GenerateFakeCommand(1 / 60)
            end
        end
    end

    --Sort commands by their serial
    table.sort(self.unprocessedCommands, function(a, b)
        return a.serial < b.serial
    end)

    local maxCommandsPerFrame = 15

    for _, command in pairs(self.unprocessedCommands) do
        if command.totalTime > self.elapsedTime - self.bufferedCommandTime then
            --Can't process this yet, its our buffer
            continue
        end

        maxCommandsPerFrame -= 1
        if maxCommandsPerFrame < 0 then
            --print("Player send too many commands at once:", self.playerRecord.name)
            self.errorState = Enums.NetworkProblemState.TooManyCommands
            self.playerElapsedTime = self.elapsedTime
            self.unprocessedCommands = {}
            break --Discard all buffered commands
        end

        --print("server", command.l, command.serverTime)
        TrajectoryModule:PositionWorld(command.serverTime, command.deltaTime)
        self.debug.processedCommands += 1

        --Step simulation!
        self.simulation:ProcessCommand(command)

        --Fire weapons!
        self.playerRecord:ProcessWeaponCommand(command)

        command.processed = true

        if command.l and tonumber(command.l) ~= nil then
            self.lastConfirmedCommand = command.l
        end
    end

    local newList = {}
    for _, command in pairs(self.unprocessedCommands) do
        if command.processed ~= true then
            table.insert(newList, command)
        end
    end

    self.unprocessedCommands = newList
end

--[=[
	Callback for handling all events from the client.

	@param event table -- The event sent by the client.
	@private
]=]
function ServerChickynoid:HandleClientEvent(server, event)
    if event.t == EventType.Command then
        local command = event.command

        if command and typeof(command) == "table" then
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
            if
                command.serverTime == nil
                or typeof(command.serverTime) ~= "number"
                or command.serverTime ~= command.serverTime
            then
                return
            end
            if
                command.deltaTime == nil
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

            command.serial = self.commandSerial
            self.commandSerial += 1

            --sanitize

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

            if command.deltaTime then
                --On the first command, init
                if self.playerElapsedTime == 0 then
                    self.playerElapsedTime = self.elapsedTime
                end

                if self.playerElapsedTime > self.elapsedTime + self.speedCheatThreshhold then
                    --print("Player too far ahead", self.playerRecord.name)
                    self.errorState = Enums.NetworkProblemState.TooFarAhead
                else
                    self.playerElapsedTime += command.deltaTime
                    command.totalTime = self.elapsedTime
                    table.insert(self.unprocessedCommands, command)
                end
            end
        end
    end
end

function ServerChickynoid:WriteStateDelta()

    local currentState = self.simulation:WriteState()
    local stateDelta = DeltaTable:MakeDeltaTable(self.lastSeenState, currentState)
    self.lastSeenState = DeltaTable:DeepCopy(currentState)
    return stateDelta
end


--[=[
    Picks a location to spawn the character and replicates it to the client.
    @private
]=]
function ServerChickynoid:SpawnChickynoid()
    self.simulation.state.vel = Vector3.zero

    if self.playerRecord.dummy == false then
        local event = {}
        event.t = EventType.ChickynoidAdded
        event.position = self.simulation.state.pos
        event.characterMod = self.playerRecord.characterMod
        self.playerRecord:SendEventToClient(event)
    end
    print("Spawned character and sent event for player:", self.playerRecord.name)
end

function ServerChickynoid:PostThink(server)
    self:UpdateServerCollisionBox(server)
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

    local push = false
    if push == true then
        --Check to see what  we're touching, and push them.
        if self.pushPart == nil then
            local box = Instance.new("Part")
            box.Size = Vector3.new(5, 5, 5)
            box.Parent = nil :: any --server.worldRoot
            box.Position = self.simulation.state.pos
            box.Anchored = true
            self.pushPart = box
        end

        local vel = Vector3.new(self.simulation.state.pushDir.x, 0, self.simulation.state.pushDir.y)
            * self.simulation.constants.pushSpeed

        --clear the previous frames velocity objects
        if self.pushes == nil then
            self.pushes = {}
        end

        for _, record in pairs(self.pushes) do
            record.frames -= 1
            if record.frames <= 0 then
                record.pusher.MaxForce = 0
                --table.remove(self.pushes,counter)
                --print("destroy")
            else
                record.pusher.MaxForce = 1000
            end
        end

        if vel.Magnitude > 0.001 then
            self.pushPart.CFrame = CFrame.new(self.simulation.state.pos)
            local list = game.Workspace:GetPartsInPart(self.pushPart)

            if #list > 0 then
                for _, value in pairs(list) do
                    if value.Anchored == false then
                        --Lets do a dotproduct to see if we want this push
                        local dir = value.Position - self.simulation.state.pos

                        local dot = dir:Dot(self.simulation.state.vel)

                        if dot < 0.2 then
                            continue
                        end

                        --We are pushing
                        --Typically you wouldn't ever *ever* write to state like this, but pushing comes from roblox directly so we don't have any choice here
                        self.simulation.state.pushing = 0.5

                        --Push towards the object
                        local mag = vel.Magnitude
                        vel = vel.Unit + dir.Unit
                        vel = (Vector3.new(vel.x, 0, vel.z)).Unit * mag

                        -- local localVel = value.CFrame:VectorToObjectSpace(vel)
                        --value:ApplyImpulseAtPosition(self.pushPart.Position, vel)

                        local found = false
                        for _, record in pairs(self.pushes) do
                            if record.part == value then
                                found = true
                                --recycle existing pusher
                                record.attachment.WorldPosition = self.pushPart.Position
                                record.pusher.VectorVelocity = vel
                                record.frames = 3
                            end
                        end
                        if found == true then
                            continue
                        end

                        local pusher = Instance.new("LinearVelocity")
                        pusher.Parent = value
                        pusher.VectorVelocity = vel
                        pusher.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
                        pusher.RelativeTo = Enum.ActuatorRelativeTo.Attachment0

                        local attachment = Instance.new("Attachment")
                        attachment.Parent = value
                        attachment.WorldPosition = self.pushPart.Position
                        pusher.Parent = attachment
                        pusher.Attachment0 = attachment

                        --Create a record
                        local record = {}
                        record.pusher = pusher
                        record.attachment = attachment
                        record.frames = 3
                        record.part = value

                        table.insert(self.pushes, record)
                    end
                end
            end
        end
    end
end

return ServerChickynoid
