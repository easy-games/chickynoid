local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local EffectsModule = require(path.Client.Effects)
local Enums = require(path.Enums)

local FastSignal = require(path.Vendor.FastSignal)
local DeltaTable = require(path.Vendor.DeltaTable)

module.rockets = {}
module.weapons = {}
module.customWeapons = {} 
module.currentWeapon = nil
module.OnBulletImpact = FastSignal.new()

function module:HandleEvent(client, event)
	
	if (event.t == Enums.EventType.BulletImpact) then
		
		local player = client.worldState.players[event.s]
		
		if (player == nil) then
			return
		end
		
		event.player = player
		event.weaponModule = self:GetWeaponModuleByWeaponId(event.w)

		self.OnBulletImpact:Fire(client, event)		
		
		if (event.weaponModule and event.weaponModule.ClientOnBulletImpact) then
			event.weaponModule:ClientOnBulletImpact(client, event)
		end
				
		return
	end
	
	
	--Todo: recode these
    if (event.t == Enums.EventType.RocketSpawn) then
        --fired a rocket
        local rocket = {}
        self.rockets[event.s] = event
        EffectsModule:SpawnEffect("RocketShoot",event.p) 
    	return    
    end
    
    if (event.t == Enums.EventType.RocketDie) then
        --Kill the rocket
        local rocket = self.rockets[event.s]
		if (rocket.part) then
			
			
			local effect = EffectsModule:SpawnEffect("Impact",rocket.part.Position)
			
			local cframe = CFrame.lookAt(rocket.part.Position, rocket.part.Position + event.n)
			effect.CFrame = cframe
			
            rocket.part:Destroy()
        end
        self.rockets[event.s] = nil
		return
	end 
	
	if (event.t == Enums.EventType.WeaponDataChanged) then
		
		if (event.s == Enums.WeaponData.WeaponAdd) then
			
			print("Added weapon:", event.name)
			
			
			local weaponRecord = self.weapons[event.serial]
			if (weaponRecord) then
				error("Weapon already added: " ..  event.name .. " " .. event.serial)
				return
			end
			
			local source = path.Custom.Weapons:FindFirstChild(event.name, true)
			local sourceModule = require(source)
		
			local weaponRecord = DeltaTable:DeepCopy(sourceModule)
			weaponRecord.serial = event.serial
			weaponRecord.name = event.name
			weaponRecord.client = client
			weaponRecord.weaponModule = module
			weaponRecord.clientState = DeltaTable:DeepCopy(event.serverState)
			weaponRecord.serverState = DeltaTable:DeepCopy(event.serverState)
			weaponRecord.preservePredictedStateTimer = 0
			weaponRecord.serverStateDirty = false
			
			function weaponRecord:SetPredictedState()
				--Call this to delay the server from stomping on our state: eg: when firing rapidly
				--when you let off the trigger this will allow the server state to take priority
				weaponRecord.preservePredictedStateTimer = tick() + 0.5 --500ms
				
			end
			
			weaponRecord:ClientSetup()

			--Add to inventory
			self.weapons[weaponRecord.serial] = weaponRecord
		end
	
		--Remove
		if (event.s == Enums.WeaponData.WeaponRemove) then
			if (event.serial ~= nil) then
				local weaponRecord = self.weapons[event.serial]
				if (weaponRecord == nil) then
					warn("Requested remove weapon not found")
					return
				end
				print("Removed ", weaponRecord.name)
				
				--Dequip
				if (self.currentWeapon == weaponRecord) then
					self.currentWeapon:ClientDequip()
					self.currentWeapon = nil
				end
				if (weaponRecord.ClientRemoved) then
					weaponRecord:ClientRemoved()
				end
				self.weapons[weaponRecord.serial] = nil
			end
		end
		
		if (event.s == Enums.WeaponData.WeaponState) then
			local weaponRecord = self.weapons[event.serial]
			if (weaponRecord == nil) then
				warn("Got state for a weapon we dont have.")
				return
			end
			weaponRecord.serverStateDirty = true
			--Apply the delta compressed packet
			weaponRecord.serverState = DeltaTable:ApplyDeltaTable(weaponRecord.serverState, event.deltaTable)
		end
		
		--Dequip
		if (event.s == Enums.WeaponData.Dequip) then
			if (self.currentWeapon ~= nil) then
				self.currentWeapon:ClientDequip()
				self.currentWeapon = nil
			end
		end
		
		--Equip
		if (event.s == Enums.WeaponData.Equip) then
			if (event.serial ~= nil) then
				local weaponRecord = self.weapons[event.serial]
				if (weaponRecord == nil) then
					warn("Requested Equip weapon not found")
					return
				end
				print("Equipped ", weaponRecord.name)
				self.currentWeapon = weaponRecord 
			end
		end

		return
	end
end

function module:ProcessCommand(command)
	
	--Don't get tricked, this can be invoked multiple times in a single frame if the framerate is low
	if (self.currentWeapon ~= nil) then
		self.currentWeapon:ClientProcessCommand(command)
	end
end


function module:Think(predictedServerTime, deltaTime)
	
	
	--Copy the new server states over?	
	for key,weapon in pairs(self.weapons) do
		if (weapon.serverStateDirty == true) then
			if (tick() > weapon.preservePredictedStateTimer) then
				weapon.serverStateDirty = false
			 
				weapon.clientState = DeltaTable:DeepCopy(weapon.serverState)
				if (self.NewServerState) then
					
					self:NewServerState()
				end
			end
		end
	end	
	
	if (self.currentWeapon ~= nil) then
		self.currentWeapon:ClientThink(deltaTime)
	end
	
    for serial, rocket in pairs(self.rockets) do
        
        --just render the rocket from the moment we find out about it as time 0.
        if (rocket.localTime == nil) then
            rocket.localTime = rocket.o
        end 
        rocket.localTime += deltaTime
        
        local timePassed =  rocket.localTime - rocket.o
        
        if (timePassed < 0) then
            --We dont know about this rocket yet, it hasn't technically spawned in the world yet (clients render with a smoothing delay!)
            continue
        end
        
        if (rocket.part == nil) then
            local part = Instance.new("Part")
            part.Parent = game.Workspace
            part.Anchored = true
			part.Size = Vector3.new(0.3,0.3,0.3)
            part.Shape = Enum.PartType.Ball
            part.Material = Enum.Material.Neon
            part.Color = Color3.new(1,1,0.5)

            rocket.part = part
       end

        rocket.pos = rocket.p + (rocket.v * rocket.c * timePassed)
        rocket.part.Position = rocket.pos
    end
end

function module:GetWeaponModuleByWeaponId(weaponId)
	
	return self.customWeapons[weaponId]
end

function module:Setup(client)


	for key,name in pairs(path.Custom.Weapons:GetDescendants()) do

		if (name:IsA("ModuleScript")) then
			local customWeapon = require(name)
			table.insert(self.customWeapons, customWeapon)
			--set the id
			customWeapon.weaponId = #self.customWeapons
		end
	end
end

return module
