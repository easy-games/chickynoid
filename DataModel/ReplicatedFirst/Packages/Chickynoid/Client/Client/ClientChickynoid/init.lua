--[=[
    @class ClientChickynoid
    @client

    A Chickynoid class that handles character simulation and command generation for the client
    There is only one of these for the local player
]=]

local RemoteEvent = game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Chickynoid"):WaitForChild("RemoteEvent")

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local path = game.ReplicatedFirst.Packages.Chickynoid
local Simulation = require(path.Simulation)
local CollisionModule = require(path.Simulation.CollisionModule)

local TrajectoryModule = require(path.Simulation.TrajectoryModule)
local Types = require(path.Types)
local Enums = require(path.Enums)

local EventType = Enums.EventType
local NetGraph = require(path.Client.Client.NetGraph)

local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer

--For access to control vectors
 
local ControlModule = nil --require(PlayerModule:WaitForChild("ControlModule"))

 
local function GetControlModule()
	
	if (ControlModule == nil) then
		
		local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
		if (scripts == nil) then
			return nil
		end
				
		local playerModule = scripts:FindFirstChild("PlayerModule")
		if (playerModule == nil) then
			return nil
		end
		
		local controlModule = playerModule:FindFirstChild("ControlModule")
		if (controlModule == nil) then
			return nil
		end
		
		ControlModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
	end
	
	return ControlModule
end

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
        
        mispredict = Vector3.new(0,0,0),
        debug = {
            processedCommands = 0,
        }
       
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
	
	GetControlModule()
	if (ControlModule ~= nil) then
		local moveVector = ControlModule:GetMoveVector() :: Vector3
	    if moveVector.Magnitude > 0 then
	        moveVector = moveVector.Unit
	        command.x = moveVector.X
	        command.y = moveVector.Y
	        command.z = moveVector.Z
		end
	end

    -- This approach isn't ideal but it's the easiest right now
    if not UserInputService:GetFocusedTextBox() then
        command.y = UserInputService:IsKeyDown(Enum.KeyCode.Space) and 1 or 0
        
        command.f = UserInputService:IsKeyDown(Enum.KeyCode.Q) and 1 or 0
        
        
        
        --Cheat #1 - speed cheat!
        if (UserInputService:IsKeyDown(Enum.KeyCode.P)) then
            command.deltaTime *= 3
		end
		

		--Cheat #2 - suspend!
		if (UserInputService:IsKeyDown(Enum.KeyCode.L)) then
			local function test(f)
				return f
			end
			for j=1,2000000 do
				local a = j * 12
				test(a)
			end
		end
    end
    
    if (self:GetIsJumping() == true) then
        command.y = 1
    end
    
    if (command.f and command.f > 0) then
        --fire angles
        command.fa = self:GetAimPoint()
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
        if (cmd.l == lastConfirmed) then
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
        for _, cmd in pairs(remainingCommands) do
            extrapolatedServerTime += cmd.deltaTime
            
            TrajectoryModule:PositionWorld(extrapolatedServerTime, cmd.deltaTime)
            self.simulation:ProcessCommand(cmd)

            -- Resimulated positions
            self:SpawnDebugSphere(self.simulation.state.pos, Color3.fromRGB(255, 255, 0))
        end
		
		self.simulation.characterData:SetIsResimulating(false)
		
        -- Did we make a misprediction? We can tell if our predicted position isn't the same after reconstructing everything
        local delta = oldPos - self.simulation.state.pos
        --Add the offset to mispredict so we can blend it off
        self.mispredict += delta
    end
    
 
    --Ping graph
    table.insert(self.pings, self.ping)
    if (#self.pings > 20) then
        table.remove(self.pings,1)
    end
    local total = 0
    for _,ping in pairs(self.pings) do
        total+=ping 
    end
    total /= #self.pings
    
    NetGraph:Scroll()
    
    local color1 = Color3.new(1, 1, 1)
    local color2 = Color3.new(1, 1, 0)
    if (resimulate == false) then
    
        NetGraph:AddPoint(self.ping * 0.25, color1,4)
        NetGraph:AddPoint(total * 0.25, color2,3)
    else
      
       
		NetGraph:AddPoint(self.ping * 0.25, color1,4)
		local tint = Color3.new(0.5,1,0.5)
		NetGraph:AddPoint(total * 0.25, tint,3)
		NetGraph:AddBar(10 * 0.25, tint, 1)
    end
       
    --Server fps
    if (serverHealthFps < 60) then
        NetGraph:AddPoint(serverHealthFps, Color3.new(1,0,0),2)
    else
        NetGraph:AddPoint(serverHealthFps, Color3.new(0.5,0.0,0.0),2)
    end
    
    --Blue bar    
    if (networkProblem == Enums.NetworkProblemState.TooFarBehind) then
        NetGraph:AddBar(100, Color3.new(0,0,1) ,0)
    end
    --Yellow bar    
    if (networkProblem == Enums.NetworkProblemState.TooFarAhead) then
        NetGraph:AddBar(100, Color3.new(1,1,0) ,0)
    end
    --Orange bar    
    if (networkProblem == Enums.NetworkProblemState.TooManyCommands) then
        NetGraph:AddBar(100, Color3.new(1,0.5,0) ,0)
    end
    
    NetGraph:SetFpsText("Effective Ping: ".. math.floor(total) .."ms")
end

function ClientChickynoid:IsConnectionBad()
	
	if (#self.pings > 10 and self.ping > 1000) then
		return true
	end
	
	return false
end
 
function ClientChickynoid:Heartbeat(serverTime: number, deltaTime: number)
    self.localFrame += 1

    -- Read user input
    local cmd = self:MakeCommand(deltaTime)
    
    table.insert(self.predictedCommands, cmd)

    -- Step this frame
    cmd.serverTime = serverTime
    
	TrajectoryModule:PositionWorld(serverTime, deltaTime)
	CollisionModule:UpdateDynamicParts()
	
    self.debug.processedCommands+=1
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
    RemoteEvent:FireServer(event)
    
    --once we've sent it, add localtime
    cmd.tick = tick()
  
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

function ClientChickynoid:GetAimPoint()
    local mouse = game.Players.LocalPlayer:GetMouse()
    local ray = game.Workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
    raycastParams.FilterDescendantsInstances = { game.Workspace.GameArea }

    local raycastResults = game.Workspace:Raycast(ray.Origin,ray.Direction * 150, raycastParams)
    if (raycastResults) then
        return raycastResults.Position
    end
    return ray.Origin + (ray.Direction * 150)

end

function ClientChickynoid:Destroy()
	
end

return ClientChickynoid
