local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local MathUtils = require(path.Shared.Simulation.MathUtils)
local Enums = require(path.Shared.Enums)

--Call this on both the client and server!
function module:ModifySimulation(simulation)

   simulation:RegisterMoveState("JumpPad", nil, nil, nil, nil, module.AlwaysThinkLate, 100)
	
end

--this is called inside Simulation...
function module.AlwaysThinkLate(simulation, cmd)
		
	if simulation.lastGround and simulation.lastGround.hullRecord and simulation.lastGround.hullRecord.instance then
		local instance = simulation.lastGround.hullRecord.instance
		 
		--Check jumpPads
		local vec3 = instance:GetAttribute("launch")
		if vec3 then
			local dir = instance.CFrame:VectorToWorldSpace(vec3)
		 
			simulation.state.vel = dir
			simulation.state.jump = 0.2
			simulation.characterData:PlayAnimation("Jump", Enums.AnimChannel.Channel0, true, 0.2)
		end
	end
end

return module