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

local path = game.ReplicatedFirst.Packages.Chickynoid
local Enums = require(path.Enums)
CharacterModel.template = nil

function CharacterModel:ModuleSetup()
    self.template = game.ReplicatedFirst.Packages.Chickynoid.Assets:FindFirstChild("R15Rig")
    
end


function CharacterModel.new()

    local self = setmetatable({
        model = nil,
        characterData = nil,
        playingTrack = nil,
        playingTrackNum = nil,
        animCounter = -1,
        modelOffset = Vector3.new(0,0.5,0),
        modelReady = false,
        startingAnimation = Enums.Anims.Idle,
        userId = nil,
        mispredict = Vector3.new(0,0,0)
        
    }, CharacterModel)
    
    return self
end 

function CharacterModel:CreateModel(userId)
    
   
    self:DestroyModel()
    
    self.model = self.template:Clone()
    self.userId = userId
    self.animator = self.model:FindFirstChild("Animator",true)
    self.model.Parent = game.Lighting
    self.tracks = {}
    
    
    print("Create character")
    coroutine.wrap(function()
        
        if (self.model) then
            
            if (userId ~= nil and string.sub(self.userId,1,1) ~= "-" ) then
                local description = game.Players:GetHumanoidDescriptionFromUserId(self.userId)
                self.model.Humanoid:ApplyDescription(description)
                
                local hip = (self.model.HumanoidRootPart.Size.y * 0.5) + self.model.Humanoid.hipHeight
                self.modelOffset = Vector3.new(0,hip-2.5,0)
            end

            --Load on the animations
            for key,value in pairs(self.animator:GetChildren())  do

                if (value:IsA("Animation")) then
                    local track = self.animator:LoadAnimation(value)
                    self.tracks[value.Name] = track
                end
            end
            
            self.modelReady = true
            self:PlayAnimation(self.startingAnimation, true)
                        
            self.model.Parent = game.Workspace
            
        end
    end)()
    
end

function CharacterModel:DestroyModel()

    if (self.model) then
        self.model:Destroy()
    end 
    self.model = nil
    self.modelReady = false
end

--you shouldnt ever have to call this directly, change the characterData to trigger this
function CharacterModel:PlayAnimation(enum, force)

    
    local name = "Idle"
    for key,value in pairs(Enums.Anims) do
        if (value == enum) then
            name = key
            break
        end
    end
    
    if (self.modelReady == false) then
        --Model not instantiated yet
        self.startingAnimation = enum
    else
        local track = self.tracks[name]
        if (track) then
            if (self.playingTrack ~= track or force == true) then
        
                for key,value in pairs(self.tracks) do
                    if (value ~= track) then
                        value:Stop(0.1)
                    end
                end
                track:Play(0.1)

                self.playingTrack = track
                self.playingTrackNum = enum
       
            end
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

		self:PlayAnimation(dataRecord.animNum, true)
    end
 
	if (self.playingTrackNum == Enums.Anims.Run or self.playingTrackNum == Enums.Anims.Walk) then
        
        local vel = dataRecord.flatSpeed
        local playbackSpeed = (vel / 16)   --Todo: Persistant player stats
        self.playingTrack:AdjustSpeed(playbackSpeed)
	end
	
	if (self.playingTrackNum == Enums.Anims.Push) then

		local vel = 14
		local playbackSpeed = (vel / 16)   --Todo: Persistant player stats
		self.playingTrack:AdjustSpeed(playbackSpeed)
	end
    
    if (self.model.Humanoid.Health <= 0) then
        --its dead! Really this should never happen
        self.model:Destroy()
        self.modelReady = false
        self.model = nil
        self:CreateModel(self.userId)
        return
    end
    
    
    local newCF = CFrame.new(dataRecord.pos + self.modelOffset + self.mispredict + Vector3.new(0,dataRecord.stepUp,0)) * CFrame.fromEulerAnglesXYZ(0,dataRecord.angle,0)
    self.model:PivotTo(newCF)
end


CharacterModel:ModuleSetup()

return CharacterModel
