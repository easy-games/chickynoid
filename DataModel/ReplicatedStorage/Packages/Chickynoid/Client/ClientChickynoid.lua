--[=[
    @class ClientChickynoid
    @client

    A Chickynoid class that handles character simulation and command generation for the client
    There is only one of these for the local player
]=]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Simulation = require(script.Parent.Parent.Simulation)

local Types = require(script.Parent.Parent.Types)
local Enums = require(script.Parent.Parent.Enums)
local EventType = Enums.EventType

local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local PlayerModule = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
local ControlModule = require(PlayerModule:WaitForChild("ControlModule"))

local DebugParts = Instance.new("Folder")
DebugParts.Name = "DebugParts"
DebugParts.Parent = workspace

local SKIP_RESIMULATION = true
local DEBUG_SPHERES = false
local PRINT_NUM_CASTS = false

local ClientChickynoid = {}
ClientChickynoid.__index = ClientChickynoid

--[=[
    Constructs a new ClientChickynoid for the local player, spawning it at the specified
    position. The position is just to prevent a mispredict.

    @param position Vector3 -- The position to spawn this character, provided by the server.
    @return ClientChickynoid
]=]
function ClientChickynoid.new(position: Vector3, config: Types.IClientConfig)
    local self = setmetatable({
        
        simulation = Simulation.new(config.simulationConfig),

        predictedCommands = {},
        stateCache = {},

        localFrame = 0,
    }, ClientChickynoid)

    self.simulation.state.pos = position
    self.simulation.whiteList = { workspace.GameArea, workspace.Terrain }

   
    self:HandleLocalPlayer()   

    return self
end

function ClientChickynoid:HandleLocalPlayer()

end

function ClientChickynoid:MakeCommand(dt: number)
    local command = {}
    command.l = self.localFrame

    command.x = 0
    command.y = 0
    command.z = 0
    command.deltaTime = dt
    
  

    local moveVector = ControlModule:GetMoveVector() :: Vector3
    if moveVector.Magnitude > 0 then
        moveVector = moveVector.Unit
        command.x = moveVector.X
        command.y = moveVector.Y
        command.z = moveVector.Z
    end

    -- This approach isn't ideal but it's the easiest right now
    if not UserInputService:GetFocusedTextBox() then
        command.y = UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or 0
        
        --Cheat #1 - speed cheat!
        if (UserInputService:IsKeyDown(Enum.KeyCode.P)) then
            command.deltaTime *= 3
        end
 

    end
    if (self:GetIsJumping() == true) then
        command.y = 1
    end
 
    local rawMoveVector = self:CalculateRawMoveVector(Vector3.new(command.x, 0, command.z))
    command.x = rawMoveVector.X
    command.z = rawMoveVector.Z

    return command
end

function ClientChickynoid:CalculateRawMoveVector(cameraRelativeMoveVector: Vector3)
    local _, yaw = Camera.CFrame:ToEulerAnglesYXZ()
    return CFrame.fromEulerAnglesYXZ(0, yaw, 0) * Vector3.new(cameraRelativeMoveVector.X, 0, cameraRelativeMoveVector.Z)
end

function ClientChickynoid:GetIsJumping()
    
    if (ControlModule == nil) then
        return false
    end
    if (ControlModule.activeController == nil) then
        return false
    end
    
    return ControlModule.activeController:GetIsJumping() or (ControlModule.touchJumpController and ControlModule.touchJumpController:GetIsJumping())
end

--[=[
    The server sends each client an updated world state on a fixed timestep. This
    handles state updates for this character.

    @param state table -- The new state sent by the server.
    @param lastConfirmed number -- The serial number of the last command confirmed by the server.
]=]
function ClientChickynoid:HandleNewState(state, lastConfirmed)
    self:ClearDebugSpheres()

    -- Build a list of the commands the server has not confirmed yet
    local remainingCommands = {}
    for _, cmd in pairs(self.predictedCommands) do
        -- event.lastConfirmed = serial number of last confirmed command by server
        if cmd.l > lastConfirmed then
            -- Server hasn't processed this yet
            table.insert(remainingCommands, cmd)
        end
    end
    self.predictedCommands = remainingCommands

    local resimulate = true

    -- Check to see if we can skip simulation
    if SKIP_RESIMULATION then
        local record = self.stateCache[lastConfirmed]
        if record then
            -- This is the state we were in, if the server agrees with this, we dont have to resim
            
            if (record.state.pos - state.pos).magnitude < 0.01 and (record.state.vel - state.vel).magnitude < 0.01 then
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
        print("resimulating")

        -- Record our old state
        local oldPos = self.simulation.state.pos

        -- Reset our base simulation to match the server
        self.simulation:ReadState(state)

        -- Marker for where the server said we were
        self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 170, 0))

        -- Resimulate all of the commands the server has not confirmed yet
        -- print("winding forward", #remainingCommands, "commands")
        for _, cmd in pairs(remainingCommands) do
            self.simulation:ProcessCommand(cmd)

            -- Resimulated positions
            self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 255, 0))
        end

        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
        if delta.magnitude > 0.2 then
            print("Mispredict:", delta)
        end
    end
end

 
function ClientChickynoid:Heartbeat(dt: number)
    self.localFrame += 1

    -- Read user input
    local cmd = self:MakeCommand(dt)
    table.insert(self.predictedCommands, cmd)

    -- Step this frame
    self.simulation:ProcessCommand(cmd)
 
 
    -- Marker for positions added since the last server update
    self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(44, 140, 39))

    if SKIP_RESIMULATION then
        -- Add to our state cache, which we can use for skipping resims
        local cacheRecord = {}
        cacheRecord.l = cmd.l
        cacheRecord.state = self.simulation:WriteState()

        self.stateCache[cmd.l] = cacheRecord
    end

    -- Pass to server
    local event = {}
    event.t = EventType.Command
    event.command = cmd
    script.Parent.Parent.RemoteEvent:FireServer(event)
   

    if PRINT_NUM_CASTS then
        print("casts", self.simulation.sweepModule.raycastsThisFrame)
    end
    
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

return ClientChickynoid
