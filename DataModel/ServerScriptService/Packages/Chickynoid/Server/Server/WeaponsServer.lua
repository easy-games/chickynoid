local module = {}

module.rocketSerial = 0
module.rockets = {}
module.weaponSerials = 0

local path = game.ReplicatedFirst.Packages.Chickynoid
local TableUtil = require(path.Vendor.TableUtil)

local Enums = require(path.Enums)

local requiredMethods = {
	"ClientThink","ServerThink", "ClientProcessCommand", "ServerProcessCommand", "ClientEventFromServer" , "ServerSetup", "ClientSetup", "ServerEquip", "ServerDequip"
}

function module:OnPlayerConnected(server, playerRecord)

	playerRecord.weapons = {}
	
	playerRecord.currentWeapon = nil
	
	
	function playerRecord:EquipWeapon(serial)
		
		if (self.currentWeapon ~= nil) then
			self.currentWeapon:ServerDequip()
			
			local event = {}
			event.t = Enums.EventType.WeaponDataChanged
			event.s = Enums.WeaponData.Dequip
			event.serial = serial
			self:SendEventToClient(event)
		end		
		
		if (serial ~= nil) then
			local weaponRecord = self.weapons[serial]
			if (weaponRecord == nil) then
				warn("Weapon not found:", serial)
				return
			end
			
			self.currentWeapon = weaponRecord
			weaponRecord:ServerEquip()
		
			local event = {}
			event.t = Enums.EventType.WeaponDataChanged
			event.s = Enums.WeaponData.Equip
			event.serial = serial
			self:SendEventToClient(event)
		end
	end
	
 	function playerRecord:GiveWeapon(name, equip)

		for key,weaponRecord in pairs(self.weapons) do
		
			if (weaponRecord.name == "name") then
				print(self.name , "already has weapon", name)
				return
			end
		end

		local source = path.Custom.Weapons:FindFirstChild(name, true)
		
		if (source == nil) then
			warn("Weapon ", name, " not found!")
			return
		end
		
		local sourceModule = require(source)
		
		--Validate the module
		local hasError = false
		for key,values in pairs(requiredMethods) do
			if (sourceModule[values] == nil) then
				warn("WeaponModule " .. name .. " missing " .. key .. " implementation.")
				hasError = true
			end
		end
		if (hasError == true) then
			return
		end
		
		local weaponRecord = TableUtil.Copy(sourceModule, true)
		weaponRecord.serial = module.weaponSerials
		module.weaponSerials+=1
		
 		weaponRecord.playerRecord = playerRecord
		weaponRecord.server = server
		weaponRecord.weaponModule = module
		weaponRecord.state = {}
		weaponRecord.previousState = {}
		
		weaponRecord:ServerSetup()

		--Add to inventory
		playerRecord.weapons[weaponRecord.serial] = weaponRecord
				
		local event = {}
		event.t = Enums.EventType.WeaponDataChanged
		event.serial = weaponRecord.serial
		event.name = name 
		event.s = Enums.WeaponData.WeaponAdd
		event.serverState = weaponRecord.state
		playerRecord:SendEventToClient(event)
		
		--Equip it		
		if (equip) then
			self:EquipWeapon(weaponRecord.serial)
		end
		
	end
		
	
	function playerRecord:ProcessWeaponCommand(command)
		if (self.currentWeapon~=nil) then

			self.currentWeapon:ServerProcessCommand(command)
		end
	end
	
	--happens after the command for this frame	
	function playerRecord:WeaponThink(deltaTime)
		for key,weaponRecord in pairs(self.weapons) do
			weaponRecord:ServerThink(deltaTime)
		end
		
		--Do networking
		
	end

end


function module:FireBullet(playerRecord,server, origin, dir)
	local rocket = {}

	rocket.p = playerRecord.chickynoid.simulation.state.pos
	rocket.v = Vector3.new(1,0,0)
	rocket.v = dir

	rocket.c = 600
	rocket.o = server.serverSimulationTime
	rocket.s = self.rocketSerial
	self.rocketSerial+=1

	rocket.t = Enums.EventType.RocketSpawn

	server:SendEventToClients(rocket)


	--After its been sent, set a die time
	rocket.aliveTime = 0
	rocket.owner = playerRecord
	rocket.n = -dir
	
	self.rockets[rocket.s] = rocket
end
 

--[[
function module:HandleWeapon(server, playerRecord, deltaTime, command)
    
    
    if (playerRecord.currentWeapon == nil) then
        self:SetupWeapon(server, playerRecord)
    end
        
    --Weapon fire button 
    if (playerRecord.currentWeapon.cooldown <= 0) then
        
        if (command.f and command.f > 0) then
            --Fire!
            playerRecord.currentWeapon.cooldown = playerRecord.currentWeapon.cooldownDuration
            
            local rocket = {}
            
            rocket.p = playerRecord.chickynoid.simulation.state.pos
            rocket.v = Vector3.new(1,0,0)
            if (command.fa and typeof(command.fa) == "Vector3") then
                local vec =  command.fa - rocket.p
                if (vec.x == vec.x and vec.y == vec.y and vec.z == vec.z)  then
                    rocket.v = vec.Unit
                end
                
               
            end
            rocket.c = 150
            rocket.o = server.serverSimulationTime
            rocket.s = self.rocketSerial
            self.rocketSerial+=1
            
            rocket.t = Enums.EventType.RocketSpawn
            
            server:SendEventToClients(rocket)
            
            
            --After its been sent, set a die time
            rocket.aliveTime = 0
            rocket.owner = playerRecord
            
            self.rockets[rocket.s] = rocket
            
        end
            
    else
        playerRecord.currentWeapon.cooldown -= deltaTime
    end
end
]]--

function module:Think(server, deltaTime)
    
    
	for key,playerRecord in pairs(server:GetPlayers()) do
		playerRecord:WeaponThink(deltaTime)
	end
	
	
    for serial,rocket in pairs(self.rockets) do
        
        local timePassed = server.serverSimulationTime - rocket.o    
        
        local oldPos = rocket.pos
        
        if (oldPos == nil) then
            oldPos = rocket.p
        end
        rocket.pos = rocket.p + (rocket.v * rocket.c * timePassed)
        
        
        --Trace a line 
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Whitelist
        params.FilterDescendantsInstances = { game.Workspace.GameArea }
        local results  = game.Workspace:Raycast(oldPos, rocket.pos - oldPos, params)
        if (results ~= nil) then
			timePassed = 1000 --Boom
			rocket.n = results.Normal
        else
        
            local result =  self:RayTestPlayers(oldPos, rocket.pos - oldPos, server)
            if (result ~= nil) then
				timePassed = 1000
				rocket.n = Vector3.new(0,1,0)
            end
        end
        
        if (timePassed > 5) then
            local event = {}
            event.t = Enums.EventType.RocketDie
			event.s = rocket.s
			event.n = rocket.n
            server:SendEventToClients(event)
            
            self.rockets[serial] = nil
            self:DoExplosion(server, rocket.pos, 15, 60)
        end        
    end
end

function module:DoExplosion(server, explosionPos, radius, force)
    
    --Get All the players
    for key,playerRecord in pairs(server.playerRecords) do
        
        local sim = playerRecord.chickynoid.simulation
        local pos = sim.state.pos
        
        local vec = pos - explosionPos
        if (vec.magnitude < 10) then
            
            --Always upwards
            local dir = vec.unit
            dir = Vector3.new(dir.x, math.abs(dir.y), dir.z)
            sim.state.vel += dir.unit * force
        end  
    end
end

function module:RayTestPlayers(rayOrigin, vec, server)
    
    --[[
    --Get All the players
    for key,playerRecord in pairs(server.playerRecords) do

        local sim = playerRecord.chickynoid.simulation
        local pos = sim.state.pos

        local vec = pos - explosionPos
        if (vec.magnitude < 10) then

            --Always upwards
            local dir = vec.unit
            dir = Vector3.new(dir.x, 1, dir.z)
            sim.state.vel += dir.unit * force
        end  
    end
    ]]--
    if (server.worldRoot == nil) then
        return nil
    end
    
    local rayCastResult = game.Workspace:Raycast(rayOrigin, vec)
    return rayCastResult
end



return module
