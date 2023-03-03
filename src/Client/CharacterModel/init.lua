local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CharacterModel = {}

local Janitor = require(ReplicatedStorage.Packages.Janitor)

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
local ClientMods = require(path.Client.ClientMods)

CharacterModel.template = nil
CharacterModel.characterModelCallbacks = {}

function CharacterModel:ModuleSetup()
	self.template = ReplicatedStorage.Assets:FindFirstChild("R15Rig")
	self.modelPool = {}
end

local CAM_OVERRIDE = false
function CharacterModel.new(userId, characterMod)
	if not characterMod then
		warn("No character mod!!")
	end

	local self = setmetatable({
		model = nil,
		tracks = {},
		animator = nil,
		modelData = nil,
		playingTrack = nil,
		playingTrackNum = nil,
		animCounter0 = -1,
		animCounter1 = -1,
		animCounter2 = -1,
		animCounter3 = -1,
		modelOffset = Vector3.new(0, 0.5, 0),
		modelReady = false,
		startingAnimation = Enums.Anims.Stop,
		startingSound = Enums.RootSounds.Stop,
		userId = userId,
		characterMod = characterMod,
		mispredict = Vector3.new(0, 0, 0),
		onModelCreated = FastSignal.new(),
		onModelDestroyed = FastSignal.new(),

		_cameraJanitor = Janitor.new()

	}, CharacterModel)

	if userId == LocalPlayer.UserId and CAM_OVERRIDE then
		local camPart = Instance.new("Part")
		camPart.Size = Vector3.one
		camPart.Transparency = 1
		camPart.Anchored = true
		camPart.CanCollide = false
		camPart.Name = tostring(userId) .. "_camPart"
		camPart.Parent = workspace
		self._camPart = camPart
		self._camConnection = RunService.PostSimulation:Connect(function()
			if self.model ~= nil then
				camPart.CFrame = self.model:GetPivot()
			end
		end)

		task.wait()
		workspace.CurrentCamera.CameraSubject = camPart
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	end
	return self
end

function CharacterModel:ChangeCharacterMod(mod)
	print("changing character mod...")
	self.characterMod = mod
	-- save camera cframe
	local camera = workspace.CurrentCamera
	local cameraCf = camera.CFrame
	-- task.wait()

	if tonumber(self.userId) == game.Players.LocalPlayer.UserId then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	self:CreateModel()
	task.wait()
	if tonumber(self.userId) == game.Players.LocalPlayer.UserId and CAM_OVERRIDE then
		local ZoomDistance = (cameraCf.Position - camera.Focus.Position).Magnitude
		camera.CFrame = cameraCf
		task.wait() -- ignore the task.waits, they're for camera manipulation things...

		-- recovers the zoom (which is lost when you return the camera to "Custom")
		local OldZoomMin = LocalPlayer.CameraMinZoomDistance
		local OldZoomMax = LocalPlayer.CameraMaxZoomDistance
		LocalPlayer.CameraMinZoomDistance = ZoomDistance
		LocalPlayer.CameraMaxZoomDistance = ZoomDistance
		LocalPlayer.CameraMinZoomDistance = OldZoomMin
		LocalPlayer.CameraMaxZoomDistance = OldZoomMax

		-- fall back to camera default

		camera.CameraType = Enum.CameraType.Custom
	end
end

function CharacterModel:CreateModel()

	self:DestroyModel()

	--print("CreateModel ", self.userId)
	coroutine.wrap(function()
		local player = Players:GetPlayerByUserId(self.userId)

		if (self.modelPool[self.userId] == nil) then

			local srcModel = nil
			-- Download custom character
			for _, characterModelCallback in ipairs(self.characterModelCallbacks) do
				local result = characterModelCallback(self.userId);
				if (result) then
					srcModel = result:Clone()
				end
			end

			--Check the character mod
			if (srcModel == nil) then
				if (self.characterMod) then
					local loadedModule = ClientMods:GetMod("characters", self.characterMod)
					if (loadedModule and loadedModule.GetCharacterModel) then
						local template = loadedModule:GetCharacterModel(self.userId, self)
						if (template) then
							self.modelData = template
							self.modelPool[self.userId] = template
							print("got new template")
						else
							warn("Could not get character model for " .. self.characterMod)
						end
					end
				end
			end

			-- fallback default character
			if (srcModel == nil) then
				local userId = self.userId
				local result, err = pcall(function()
					--Bot id?
					if (string.sub(userId, 1, 1) == "-") then
						userId = string.sub(userId, 2, string.len(userId)) --drop the -
					end
			
					userId = tonumber(userId)
			
					local player = game.Players:GetPlayerByUserId(userId)
					local description
					if StarterPlayer.LoadCharacterAppearance then
						description = game.Players:GetHumanoidDescriptionFromUserId(player.CharacterAppearanceId)
					else
						description = game.ReplicatedStorage:WaitForChild("DefaultDescription")
					end
					local dC = description:Clone()
					srcModel = game:GetService("Players"):CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
					local humanoid = srcModel:WaitForChild("Humanoid")
					dC.Parent = humanoid
			
					srcModel.Parent = game.Lighting
					srcModel.Name = tostring(userId)
					humanoid.DisplayName = player.DisplayName
				end)
			
				if (result == false) then
					warn("Loading " .. userId .. ":" ..err)
				elseif srcModel then
			
					local hip = (srcModel.HumanoidRootPart.Size.y
							* 0.5) +srcModel.Humanoid.hipHeight
			
					local data = { 
						model =	srcModel, 
						modelOffset = Vector3.yAxis * (hip - 2.55)
					}
			
					return data
				end
			end

		else
			print("something bad happened...")
		end

		self.model = self.modelData.model:Clone()
		self.primaryPart = self.model.PrimaryPart
		self.model.Parent = game.Lighting -- must happen to load animations		

		--Load on the animations			
		self.animator = self.model:FindFirstChild("Animator", true)
		if (not self.animator) then
			local humanoid = self.model:FindFirstChild("Humanoid")
			if (humanoid) then
				self.animator = self.template:FindFirstChild("Animator", true):Clone()
				self.animator.Parent = humanoid
			end
		end
		self.tracks = {}

		for _, value in pairs(self.animator:GetChildren()) do
			if value:IsA("Animation") then
				local track = self.animator:LoadAnimation(value)
				self.tracks[value.Name] = track
			end
		end

		-- load RootPart sfx
		self.rootSfx = {}
		local sfxFolder = ReplicatedStorage.Assets.SFX.RootPart
		for _, sfx : Sound in sfxFolder:GetChildren() do
			local newSfx = sfx:Clone()
			newSfx.Parent = self.model.PrimaryPart
			self.rootSfx[newSfx.Name] = newSfx

			local startTime = newSfx:GetAttribute("StartTime")
			local endTime = newSfx:GetAttribute("EndTime")

			-- custom time marker things
			if startTime or endTime then
				if newSfx.PlaybackRegionsEnabled then -- hopefully this goes live sometime soon
					newSfx.PlaybackRegion.Min = startTime or 0
					newSfx.PlaybackRegion.Max = endTime or 6000

					if newSfx.Looped then
						newSfx.LoopRegion.Min = startTime or 0
						newSfx.LoopRegion.Max = endTime or 6000
					end
				else
					-- legacy listeners
					newSfx.TimePosition = startTime or 0
					newSfx.Stopped:Connect(function()
						newSfx.TimePosition = startTime or 0
					end)

					if newSfx.Looped and endTime then
						newSfx:GetAttributeChangedSignal("TimePosition"):Connect(function()
							if newSfx.TimePosition >= endTime then
								newSfx.TimePosition = startTime or 0
							end
						end)
					end
				end
			end
		end

		-- load particles to body parts
		local srcParticles = ReplicatedStorage.Assets.Particles.Init
		self.bodyParticles = {}
		for _, bodyPart : BasePart in srcParticles:GetChildren() do
			for _, particle : ParticleEmitter in bodyPart:GetChildren() do
				if not self.bodyParticles[particle.Name] then
					self.bodyParticles[particle.Name] = {}
				end
				local newParticle = particle:Clone()
				newParticle.Parent = self.model:FindFirstChild(bodyPart.Name)

				self.bodyParticles[particle.Name][bodyPart.Name] = newParticle
			end
		end

		self.modelReady = true
		self:PlayAnimation(self.startingAnimation, true, 0)
		self:PlayRootSound(self.startingSound, true, 0)

		self.model.Parent = game.Workspace
		self.onModelCreated:Fire(self.model)
		
		if player == LocalPlayer then
			local con
			con = player.PlayerScripts.ChildAdded:Connect(function(c)
				if c.Name == "RbxCharacterSounds" then
					c:Destroy()
					con:Disconnect()
				end
			end)
			local sounds = player.PlayerScripts:FindFirstChild("RbxCharacterSounds")
			if sounds then
				sounds:Destroy()
			end
		end

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
function CharacterModel:PlayAnimation(enum, force, slot)
	local name = "Stop"
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
			if enum == 0 then
				if self["playingTrack" .. slot] then
					self["playingTrack" .. slot]:Stop(0.1)
					self["playingTrack" .. slot] = track
				end
				return
			end
			
			if track then
				if self["playingTrack" .. slot] ~= track or force == true then
					if self["playingTrack" .. slot] ~= track and self["playingTrack" .. slot] ~= nil then
						self["playingTrack" .. slot]:Stop(0.1)
					end
					
					track:Play(0.1)

					self["playingTrack" .. slot] = track
					-- self.playingTrackNum = enum
				end
			end
		end
	end
end

function CharacterModel:PlayRootSound(enum, force, slot)
	local name = "Stop"
	for key, value in pairs(Enums.RootSounds) do
		if value == enum then
			name = key
			break
		end
	end

	if self.modelReady == false then
		self.startingSound = enum
	else
		if (self.modelData) then
			local sounds = self.rootSfx
			local sound : Sound = sounds[name]
			if enum == 0 then
				if self["playingSound" .. slot] then
					self["playingSound" .. slot]:Stop()
					self["playingSound" .. slot] = sound
				end
				return
			end

			if sound then
				if self["playingSound" .. slot] ~= sound or force == true then
					if self["playingSound" .. slot] ~= sound and self["playingSound" .. slot] ~= nil then
						self["playingSound" .. slot]:Stop(0.1)
					end

					sound.TimePosition = sound:GetAttribute("StartTime") or 0
					sound:Play()

					self["playingSound" .. slot] = sound
				end
			else
				warn("Could not find sound to play")
			end
		end
	end
end

function CharacterModel:ToggleParticles(enum, slot, state)
	local name = "Stop"
	for key, value in pairs(Enums.Particles) do
		if value == enum then
			name = key
			break
		end
	end

	local particles = self.bodyParticles[name]
	if enum == 0 then
		if self["particles" .. slot] then
			for _, p in self["particles" .. slot] do
				p.Enabled = false
			end
		end
		return
	end

	if self.modelReady then
		if self.modelData then
			if particles then
				for _, p in particles do
					p.Enabled = state or not p.Enabled
				end

				self["particles" .. slot] = particles
			end
		end
	end
end

function CharacterModel:Think(_deltaTime, dataRecord, bulkMoveToList)
	if self.model == nil then
		return
	end

	if self.modelData == nil then
		return
	end

	--Flag that something has changed
	for i = 0, 3 do
		local counterString = "animCounter" .. i
		local numString = "animNum" .. i
		if self[counterString] ~= dataRecord[counterString] then
			self[counterString] = dataRecord[counterString]
	
			self:PlayAnimation(dataRecord[numString], true, i)
		end
	end

	for i = 0, 3 do
		local counterString = "soundCounter" .. i
		local numString = "soundNum" .. i
		if self[counterString] ~= dataRecord[counterString] then
			self[counterString] = dataRecord[counterString]
	
			self:PlayRootSound(dataRecord[numString], true, i)
		end
	end

	for i = 0, 1 do
		local counterString = "particlesCounter" .. i
		local numString = "particlesNum" .. i
		if self[counterString] ~= dataRecord[counterString] then
			self[counterString] = dataRecord[counterString]

			self:ToggleParticles(dataRecord[numString], i)
		end
	end

	-- if self.playingTrackNum == Enums.Anims.Run or self.playingTrackNum == Enums.Anims.Walk then
	-- 	local vel = dataRecord.flatSpeed
	-- 	local playbackSpeed = (vel / 16) --Todo: Persistant player stats
	-- 	self.playingTrack:AdjustSpeed(playbackSpeed)
	-- end

	-- if self.playingTrackNum == Enums.Anims.Push then
	-- 	local vel = 14
	-- 	local playbackSpeed = (vel / 16) --Todo: Persistant player stats
	-- 	self.playingTrack:AdjustSpeed(playbackSpeed)
	-- end


	--[[
	if (self.humanoid == nil) then
		self.humanoid = self.model:FindFirstChild("Humanoid")
	end]]--

	--[[
    if (self.humanoid and self.humanoid.Health <= 0) then
        --its dead! Really this should never happen
		self:DestroyModel()
		self:CreateModel(self.userId)
        return
    end]]--

	local newCF = CFrame.new(dataRecord.pos + self.modelData.modelOffset + self.mispredict)
		* CFrame.fromOrientation(dataRecord.angleX, dataRecord.angle, dataRecord.angleZ)

	if (bulkMoveToList) then
		table.insert(bulkMoveToList.parts, self.primaryPart)
		table.insert(bulkMoveToList.cframes, newCF)
	else
		self.model:PivotTo(newCF)
	end
end

function CharacterModel:SetCharacterModel(callback)
	table.insert(self.characterModelCallbacks, callback)
end


CharacterModel:ModuleSetup()

return CharacterModel
