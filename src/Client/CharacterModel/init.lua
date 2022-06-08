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

local path = script.Parent.Parent
local Enums = require(path.Enums)
local FastSignal = require(path.Vendor.FastSignal)
CharacterModel.template = nil
 

function CharacterModel:ModuleSetup()
	self.template = path.Assets:FindFirstChild("R15Rig")
	self.modelPool = {}
 
end


function CharacterModel.new(userId)
    local self = setmetatable({
		model = nil,
        modelData = nil,
        playingTrack = nil,
        playingTrackNum = nil,
        animCounter = -1,
        modelOffset = Vector3.new(0, 0.5, 0),
        modelReady = false,
        startingAnimation = Enums.Anims.Idle,
		userId = userId,
		
        mispredict = Vector3.new(0, 0, 0),
		onModelCreated = FastSignal.new(),
		onModelAdded = FastSignal.new(),
		onModelRemoved = FastSignal.new(),
		onModelDestroyed = FastSignal.new(),
    }, CharacterModel)

    return self
end

function CharacterModel:AddModel()
    		
	local created = false

    print("AddModel ", self.userId)
    coroutine.wrap(function()
				
		if (self.modelPool[self.userId] == nil) then
			self.model = self.template:Clone()
			self.model.Parent = game.Lighting -- must happen to load animations		
		 			
			created = true
			local userId = ""
			local result, err = pcall(function()
				
				userId = self.userId
				
				--Bot id?
				if (string.sub(userId, 1, 1) == "-") then
					userId = string.sub(userId, 2, string.len(userId)) --drop the -
				end
				
                local description = game.Players:GetHumanoidDescriptionFromUserId(userId)
				self.model.Humanoid:ApplyDescription(description)

				print("Loaded character appearance ", userId)
				
			end)
			if (result == false) then
				warn("Loading " .. userId .. ":" ..err)
			end
 
			--setup the hip
			local hip = (self.model.HumanoidRootPart.Size.y
				* 0.5) + self.model.Humanoid.hipHeight
			self.modelOffset = Vector3.new(0, hip - 2.5, 0)

			--Load on the animations			
			local animator = self.model:FindFirstChild("Animator", true)
			local trackData = {}
			
			for _, value in pairs(animator:GetChildren()) do
				if value:IsA("Animation") then
					local track = animator:LoadAnimation(value)
					trackData[value.Name] = track
				end
			end
			
			self.modelData =  { 
				model =	self.model, 
				tracks = trackData, 
				animator = self.animator 
			} 
			self.modelPool[self.userId] = self.modelData
			
		else
			self.modelData = self.modelPool[self.userId]
			self.model = self.modelData.model
		end

        self.modelReady = true
        self:PlayAnimation(self.startingAnimation, true)
		self.model.Parent = game.Workspace
		
		if (created == true) then
			self.onModelCreated:Fire(self.model)
		end
		self.onModelAdded:Fire(self.model)
 
    end)()
end

function CharacterModel:RemoveModel()
		
	self.onModelRemoved:Fire(self.model)
	if (self.modelData) then
		self.modelData.model.Parent = game.Lighting
		
		local animator = self.modelData.animator
		if (animator) then
			
			local tracks = animator:GetPlayingAnimationTracks()
			for key,value in pairs(tracks) do
				value:Stop()
			end
		end
	end
	self.model = nil
	self.modelData = nil
	self.playingTrack = nil
	
    self.modelReady = false
end

function CharacterModel:DestroyModel()
	
	self:RemoveModel()
	self.onModelDestroyed:Fire()
	
	if self.modelData and self.modelData.model then
		self.modelData.model:Destroy()
	end
	
	self.modelData = nil
	self.modelPool[self.userId] = nil
	self.modelReady = false
end


--you shouldnt ever have to call this directly, change the characterData to trigger this
function CharacterModel:PlayAnimation(enum, force)
    local name = "Idle"
    for key, value in pairs(Enums.Anims) do
        if value == enum then
            name = key
            break
        end
    end

    if self.modelReady == false then
        --Model not instantiated yet
        self.startingAnimation = enum
	else
		if (self.modelData) then
			
			local tracks = self.modelData.tracks
			local track = tracks[name]
	        if track then
	            if self.playingTrack ~= track or force == true then
	                for _, value in pairs(tracks) do
	                    if value ~= track then
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
end

function CharacterModel:Think(_deltaTime, dataRecord)
    if self.model == nil then
        return
    end

    --Flag that something has changed
    if self.animCounter ~= dataRecord.animCounter then
        self.animCounter = dataRecord.animCounter

        self:PlayAnimation(dataRecord.animNum, true)
    end

    if self.playingTrackNum == Enums.Anims.Run or self.playingTrackNum == Enums.Anims.Walk then
        local vel = dataRecord.flatSpeed
        local playbackSpeed = (vel / 16) --Todo: Persistant player stats
        self.playingTrack:AdjustSpeed(playbackSpeed)
    end

    if self.playingTrackNum == Enums.Anims.Push then
        local vel = 14
        local playbackSpeed = (vel / 16) --Todo: Persistant player stats
        self.playingTrack:AdjustSpeed(playbackSpeed)
    end

    if self.model.Humanoid.Health <= 0 then
        --its dead! Really this should never happen
		self:DestroyModel()
		self:AddModel(self.userId)
        return
    end

    local newCF = CFrame.new(dataRecord.pos + self.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0))
        * CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0)
    self.model:PivotTo(newCF)
end


CharacterModel:ModuleSetup()

return CharacterModel
