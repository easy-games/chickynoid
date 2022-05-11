local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local EffectsModule = require(path.Client.Effects)
local Enums = require(path.Enums)

module.rateOfFire = 0.08

--This module is cloned per player on client/server 
function module:ClientThink(deltaTime)
		
	--.state is replicated to here, for things like ammo and weapon cooldowns
	--.client 
	--.weaponModule
	
end

 
function module:ClientProcessCommand(command)
	
	local currentTime = self.client.estimatedServerTime
	local state = self.clientState
	
	
	--Predict firing a bullet
	if (command.f and command.f > 0 and command.fa) then

		if (state.ammo > 0 and currentTime > state.nextFire) then

			--put weapon on cooldown
			--state.ammo -= 1
			state.nextFire = currentTime + state.fireDelay
			--print("predicted pew")
			
			
			local clientChickynoid = self.client:GetClientChickynoid()
			if (clientChickynoid) then
				local origin = clientChickynoid.simulation.state.pos
				local dest = command.fa

				local vec = (dest - origin).Unit
				
				--Do some local effects
				local clone = EffectsModule:SpawnEffect("Tracer", origin + vec*2)
				clone.CFrame = CFrame.lookAt(origin, origin + vec)
				
			end
		end
	end
end

function module:ClientSetup()
	
end

function module:ClientEquip()

end

function module:ClientDequip()

end

--Warning! - this is NOT your local characters or anther characters copy of this weapon
--This is far more akin to a static method
function module:ClientOnBulletImpact(client, event)
	
	print("Pew2")	
end


function module:ServerSetup()
	
	self.state.ammo = 30
	self.state.fireDelay = module.rateOfFire
	self.state.nextFire = 0	
end


function module:ServerThink(deltaTime)
	--update cooldowns
		
	
end


function module:ServerProcessCommand(command)
	
	--actually Fire a bullet
	local currentTime = self.server.serverSimulationTime
	local state = self.state

	if (command.f and command.f > 0 and command.fa) then

		if (state.ammo > 0 and currentTime > state.nextFire) then

			--put weapon on cooldown
			--state.ammo -= 1
			state.nextFire = currentTime + state.fireDelay
			--print("pew")
			

			local serverChickynoid = self.playerRecord.chickynoid
			if (serverChickynoid) then
				local origin = serverChickynoid.simulation.state.pos
				local dest = command.fa
				local vec = (dest - origin).Unit
				local pos, normal, otherPlayer = self.weaponModule:QueryBullet(self.playerRecord, self.server, origin, vec)
		
				--Send an event to render this firing
				--Todo: rewrite this to use packed bytes- this could get very data heavy in a fire fight!
				local event = {}
				event.o = origin
				event.p = pos
				event.n = normal
				event.t = Enums.EventType.BulletImpact
				event.s = self.playerRecord.slot
				event.w = self.weaponId 
				
				event.m = 0
				if (otherPlayer) then
					event.m = 1
				end
				
				self.playerRecord:SendEventToClients(event)
			end
		end
	end
end

function module:ServerEquip()
	
end


function module:ServerDequip()

end




return module
