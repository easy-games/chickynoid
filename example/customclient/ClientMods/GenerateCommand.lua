local module = {}
module.client = nil

local UserInputService = game:GetService("UserInputService")

--For access to control vectors
local ControlModule = nil --require(PlayerModule:WaitForChild("ControlModule"))

local function GetControlModule()
    if ControlModule == nil then
        local LocalPlayer = game.Players.LocalPlayer
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        if scripts == nil then
            return nil
        end

        local playerModule = scripts:FindFirstChild("PlayerModule")
        if playerModule == nil then
            return nil
        end

        local controlModule = playerModule:FindFirstChild("ControlModule")
        if controlModule == nil then
            return nil
        end

        ControlModule = require(
            LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"):WaitForChild("ControlModule")
        )
    end

    return ControlModule
end

function module:Setup(_client)
    self.client = _client
end

function module:Step(_client, _deltaTime) end


function module:GenerateCommand(command, serverTime: number, dt: number)
	
	if (command == nil) then
		command = {}
	end
	
    command.x = 0
    command.y = 0
    command.z = 0
    command.deltaTime = dt
    command.serverTime = serverTime

    GetControlModule()
    if ControlModule ~= nil then
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

        local jump = UserInputService:IsKeyDown(Enum.KeyCode.Space)
        local crouch = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        command.y = 0
        if (jump) then
            command.y = 1
        else
            if (crouch) then
                command.y = -1
            end
        end

        --Fire!
        command.f = UserInputService:IsKeyDown(Enum.KeyCode.Q) and 1 or 0

        --Fly?
        if UserInputService:IsKeyDown(Enum.KeyCode.F8) then
            command.flying = 1
        end

        --Cheat #1 - speed cheat!
        if UserInputService:IsKeyDown(Enum.KeyCode.P) then
            command.deltaTime *= 3
        end

        --Cheat #2 - suspend!
        if UserInputService:IsKeyDown(Enum.KeyCode.L) then
            local function test(f)
                return f
            end
            for j = 1, 2000000 do
                local a = j * 12
                test(a)
            end
        end
    end

    if self:GetIsJumping() == true then
        command.y = 1
    end

    if command.f and command.f > 0 then
        --fire angles
        command.fa = self:GetAimPoint()
    end

    --Translate the move vector relative to the camera
    local rawMoveVector = self:CalculateRawMoveVector(Vector3.new(command.x, 0, command.z))
    command.x = rawMoveVector.X
    command.z = rawMoveVector.Z

    return command
end

function module:CalculateRawMoveVector(cameraRelativeMoveVector: Vector3)
    local Camera = workspace.CurrentCamera
    local _, yaw = Camera.CFrame:ToEulerAnglesYXZ()
    return CFrame.fromEulerAnglesYXZ(0, yaw, 0) * Vector3.new(cameraRelativeMoveVector.X, 0, cameraRelativeMoveVector.Z)
end

function module:GetIsJumping()
    if ControlModule == nil then
        return false
    end
    if ControlModule.activeController == nil then
        return false
    end

    return ControlModule.activeController:GetIsJumping()
        or (ControlModule.touchJumpController and ControlModule.touchJumpController:GetIsJumping())
end


function module:GetAimPoint()
    local mouse = game.Players.LocalPlayer:GetMouse()
    local ray = game.Workspace.CurrentCamera:ScreenPointToRay(mouse.X, mouse.Y)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Whitelist

    local whiteList = { game.Workspace.Terrain }
    local collisionRoot = self.client:GetCollisionRoot()
    if (collisionRoot) then
        table.insert(whiteList, collisionRoot)
    end
    raycastParams.FilterDescendantsInstances = whiteList

    local raycastResults = game.Workspace:Raycast(ray.Origin, ray.Direction * 2000, raycastParams)
    if raycastResults then
        return raycastResults.Position
    end
    --We hit the sky perhaps?
    return ray.Origin + (ray.Direction * 2000)
end

return module