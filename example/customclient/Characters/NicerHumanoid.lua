local module = {}

local StarterPlayer = game:GetService("StarterPlayer")

function module:Setup(simulation)
	-- base speed
	simulation.constants.maxSpeed = 16 --Units per second
	simulation.constants.airSpeed = 16 --Units per second
	simulation.constants.accel = 10 --Units per second per second
	simulation.constants.airAccel = 10 --Uses a different function than ground accel!
	simulation.constants.jumpPunch = 35 --Raw velocity, just barely enough to climb on a 7 unit tall block
	simulation.constants.turnSpeedFrac = 10 --seems about right? Very fast.
	simulation.constants.runFriction = 0.01 --friction applied after max speed
	simulation.constants.brakeFriction = 0.03 --Lower is brake harder, dont use 0
	simulation.constants.maxGroundSlope = 0.55 --about 45o
	simulation.constants.jumpThrustPower = 300 --If you keep holding jump, how much extra vel per second is there?  (turn this off for no variable height jumps)
	simulation.constants.jumpThrustDecay = 0.25 --Smaller is faster

	-- setup base walking state
	local MoveTypeWalking = require(script.Parent.utils.MoveTypeWalking)
	MoveTypeWalking:ModifySimulation(simulation)
end

function module:GetCharacterModel(userId, source)
	local srcModel
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
		
		-- copy template humanoid to player
		local h = srcModel:WaitForChild("Humanoid")
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		h:ClearAllChildren()
		dC.Parent = h
		for _, item in source.template:FindFirstChild("Humanoid"):GetChildren() do
			item:Clone().Parent = h
		end

		srcModel.Parent = game.Lighting
		srcModel.Name = tostring(userId)
		h.DisplayName = player.DisplayName
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


return module