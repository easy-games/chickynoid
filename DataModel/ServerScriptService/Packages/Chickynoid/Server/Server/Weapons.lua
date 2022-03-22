local module = {}

module.rocketSerial = 0
module.rockets = {}

local path = game.ReplicatedFirst.Packages.Chickynoid
local Enums = require(path.Enums)

function module:SetupWeapon(server, playerRecord)
    
    local weapon = {}
    weapon.name = "rocketlauncher"
    weapon.cooldown = 0
    weapon.cooldownDuration = 0.5
        
    playerRecord.currentWeapon = weapon
end

function module:HandleWeapon(server, playerRecord, deltaTime, command)
    
    
    if (playerRecord.currentWeapon == nil) then
        self:SetupWeapon(server, playerRecord)
    end
        
    --Weapon fire button 
    if (playerRecord.currentWeapon.cooldown <= 0) then
        
        if (command.f  and command.f > 0) then
            --Fire!
            playerRecord.currentWeapon.cooldown =  playerRecord.currentWeapon.cooldownDuration
            
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

function module:Think(server, deltaTime)
    
    
    
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
        else
        
            local result =  self:RayTestPlayers(oldPos, rocket.pos - oldPos, server)
            if (result ~= nil) then
                timePassed = 1000
            end
        end
        
        if (timePassed > 5) then
            local event = {}
            event.t = Enums.EventType.RocketDie
            event.s = rocket.s
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
