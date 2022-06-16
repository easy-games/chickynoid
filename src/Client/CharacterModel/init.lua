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
		tracks = {},
		animator = nil,
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
		onModelDestroyed = FastSignal.new(),
		
    }, CharacterModel)

    return self
end

function CharacterModel:CreateModel()
    		
	self:DestroyModel()
	
    --print("CreateModel ", self.userId)
    coroutine.wrap(function()
				
		if (self.modelPool[self.userId] == nil) then
			
			local srcModel = self.template:Clone() 
		 	srcModel.Parent = game.Lighting --needs to happen so loadAppearance works
 
			local userId = ""
			local result, err = pcall(function()
				
				userId = self.userId
				
				--Bot id?
				if (string.sub(userId, 1, 1) == "-") then
					userId = string.sub(userId, 2, string.len(userId)) --drop the -
				end
				
                local description = game.Players:GetHumanoidDescriptionFromUserId(userId)
				srcModel.Humanoid:ApplyDescription(description)

				--print("Loaded character appearance ", userId)
				
			end)
			if (result == false) then
				warn("Loading " .. userId .. ":" ..err)
			end
 
			--setup the hip
			local hip = (srcModel.HumanoidRootPart.Size.y
				* 0.5) +srcModel.Humanoid.hipHeight
			
			self.modelData =  { 
				model =	srcModel, 
				modelOffset =  Vector3.new(0, hip - 2.5, 0)
			}
			self.modelPool[self.userId] = self.modelData
		end

		self.modelData = self.modelPool[self.userId]
		self.model = self.modelData.model:Clone()
		self.model.Parent = game.Lighting -- must happen to load animations		

		--Load on the animations			
		self.animator = self.model:FindFirstChild("Animator", true)
		self.tracks = {}

		for _, value in pairs(self.animator:GetChildren()) do
			if value:IsA("Animation") then
				local track = self.animator:LoadAnimation(value)
				self.tracks[value.Name] = track
			end
		end
	
        self.modelReady = true
        self:PlayAnimation(self.startingAnimation, true)
		self.model.Parent = game.Workspace
		self.onModelCreated:Fire(self.model)
 
    end)()
end


function CharacterModel:DestroyModel()

	if (self.model == nil) then
		return
	end
	self.onModelDestroyed:Fire()

	self.playingTrack = nil
	self.modelData = nil
	self.animator = nil
	self.tracks = {}
	self.model:Destroy()
	
	if self.modelData and self.modelData.model then
		self.modelData.model:Destroy()
	end
	
	self.modelData = nil
	self.modelPool[self.userId] = nil
	self.modelReady = false
end

function CharacterModel:PlayerDisconnected(userId)
	
	local modelData = self.modelPool[self.userId]
	if (modelData and modelData.model) then
		modelData.model:Destroy()
	end
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
			
			local tracks = self.tracks
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

function CharacterModel:Think(_deltaTime, dataRecord, bulkMoveToList)
    if self.model == nil then
        return
    end

    --Flag that something has changed
    if self.animCounter ~= dataRecord.animCounter0 then
        self.animCounter = dataRecord.animCounter0

        self:PlayAnimation(dataRecord.animNum0, true)
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

	local humanoid = self.model:FindFirstChild("Humanoid")
	
    if (humanoid and humanoid.Health <= 0) then
        --its dead! Really this should never happen
		self:DestroyModel()
		self:CreateModel(self.userId)
        return
    end

	local newCF = CFrame.new(dataRecord.pos + self.modelData.modelOffset + self.mispredict + Vector3.new(0, dataRecord.stepUp, 0))
        * CFrame.fromEulerAnglesXYZ(0, dataRecord.angle, 0)
    
	if (bulkMoveToList) then
		table.insert(bulkMoveToList.parts, self.model.PrimaryPart)
		table.insert(bulkMoveToList.cframes, newCF)
    else
		self.model:PivotTo(newCF)
	end
end


CharacterModel:ModuleSetup()

return CharacterModel
