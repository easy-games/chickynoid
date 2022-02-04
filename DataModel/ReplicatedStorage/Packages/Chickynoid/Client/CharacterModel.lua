local CharacterModel = {}
CharacterModel.__index = CharacterModel

--[=[
    @class CharacterModel
    @client

    Represents the client side view of a character model
    the local player and all other players get one of these each
    Todo: think about allowing a serverside version of this to exist for perhaps querying rays against?
    
    Consumes a CharacterData 
]=]


CharacterModel.template = nil

function CharacterModel:ModuleSetup()
    self.template = script.Parent.Parent.Assets:FindFirstChild("R15Rig")
    
end


function CharacterModel.new()

    local self = setmetatable({
        model = nil,
        characterData = nil,
        playingTrack = nil,
        animCounter = -1,
        modelOffset = Vector3.new(0,0.5,0),
    }, CharacterModel)
    
    return self
end

function CharacterModel:CreateModel()
    
   
    self:DestroyModel()
    
    self.model = self.template:Clone()
    self.animator = self.model:FindFirstChild("Animator",true)
    self.model.Parent = game.Workspace
    self.tracks = {}
    
    --Load on the animations
    for key,value in pairs(self.animator:GetChildren())  do
        
        if (value:IsA("Animation")) then
            local track = self.animator:LoadAnimation(value)
            self.tracks[value.Name] = track
        end
    end
    
    self:PlayAnimation("Idle", true)
end

function CharacterModel:DestroyModel()

    if (self.model) then
        self.model:Destroy()
    end 
    self.model = nil
end

--you shouldnt ever have to call this directly, change the characterData to trigger this
function CharacterModel:PlayAnimation(name, force)
    if (self.model == nil) then
        return
    end
    
    local track = self.tracks[name]
    if (track) then
        if (self.playingTrack ~= track or force == true) then
            track:Play(0.3)
            if (self.playingTrack) then
                self.playingTrack:Stop()
            end
            self.playingTrack = track
        end
    end
end



function CharacterModel:Think(deltaTime, dataRecord)
    
    if (self.model == nil) then
        return
    end
    
    --Flag that something has changed
    if (self.animCounter ~= dataRecord.animCounter) then
        self.animCounter = dataRecord.animCounter
        self:PlayAnimation(dataRecord.animName, true)
    end
     
    
    self.model:PivotTo(CFrame.new(dataRecord.pos + self.modelOffset + Vector3.new(0,dataRecord.stepUp,0)) * CFrame.fromEulerAnglesXYZ(0,dataRecord.angle,0))
end


CharacterModel:ModuleSetup()

return CharacterModel
