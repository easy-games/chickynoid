local module = {}

module.rockets = {}
local path = game.ReplicatedFirst.Packages.Chickynoid
local EffectsModule = require(path.Client.Effects)
local Enums = require(path.Enums)

function module:HandleEvent(event)
        
    if (event.t == Enums.EventType.RocketSpawn) then
        --fired a rocket
        local rocket = {}
        self.rockets[event.s] = event
        EffectsModule:SpawnEffect("RocketShoot",event.p) 
        
    end
    
    if (event.t == Enums.EventType.RocketDie) then
        --Kill the rocket
        local rocket = self.rockets[event.s]
        if (rocket.part) then
            EffectsModule:SpawnEffect("Explosion",rocket.part.Position) 
            rocket.part:Destroy()
        end
        self.rockets[event.s] = nil
        
    end    
    
end


function module:Think(predictedServerTime, deltaTime)
    
    
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
            part.Size = Vector3.new(1,1,1)
            part.Shape = Enum.PartType.Ball
            part.Material = Enum.Material.Neon
            part.Color = Color3.new(1,1,0.5)

            rocket.part = part
            
            
       end

        rocket.pos = rocket.p + (rocket.v * rocket.c * timePassed)
        rocket.part.Position = rocket.pos
        
        
    end
end

return module
