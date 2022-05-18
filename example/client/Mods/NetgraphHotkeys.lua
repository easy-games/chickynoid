local module = {}
module.heldKeys = {}
module.frameCounter = 0
local UserInputService = game:GetService("UserInputService")

function module:Setup(_client)
    self.client = _client
end

function module:Step(_client, _deltaTime)

    self.frameCounter += 1

    local keys = UserInputService:GetKeysPressed()

    local keysThisFrame = {}
    for _,key in pairs(keys) do
        if (self.heldKeys[key.KeyCode] == nil) then
            self.heldKeys[key.KeyCode] = 0
        end
        self.heldKeys[key.KeyCode] += 1
        
        keysThisFrame[key.KeyCode] = 1
    end
    for key,counter in pairs(self.heldKeys) do
        if (keysThisFrame[key] == nil) then
            self.heldKeys[key] = nil
        end
    end
    
    if (self.heldKeys[Enum.KeyCode.F7] == 1) then --first frame!
        _client.showFpsGraph = not _client.showFpsGraph
        _client.showNetGraph = _client.showFpsGraph
    end
end


return module