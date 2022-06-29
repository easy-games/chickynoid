local ReplicatedFirst = game:GetService("ReplicatedFirst")
local module = {}
module.bullets = {}
module.bulletId = -1

-- FIXME: These should be surfaced to top-level APIs
local WeaponsClient = require(ReplicatedFirst.Packages.Chickynoid.Client.WeaponsClient)
local EffectsModule = require(ReplicatedFirst.Packages.Chickynoid.Client.Effects)

function module:Setup(_client) end

function module:FireBullet(origin, vec, speed, maxDistance, drop, bulletId)

    if (bulletId == -1) then
        bulletId = self.bulletId 
        self.bulletId -= 1
    end
    --add the projectile
    local bulletRecord = {}
 
    bulletRecord.position = origin
    bulletRecord.vec = vec
    
    bulletRecord.speed = speed
    bulletRecord.maxDist = maxDistance
    bulletRecord.drop = drop
    bulletRecord.travel = 0
    

    module.bullets[bulletId] = bulletRecord
    
    return bulletRecord
end


function module:Step(_client, deltaTime) 

    for key, bulletRecord in pairs(self.bullets) do
        --visual!
        if (bulletRecord.part == nil) then
            
            bulletRecord.part = Instance.new("Part")
            bulletRecord.part.Anchored = true
            bulletRecord.part.CanCollide = false
            bulletRecord.part.CanTouch = false
            bulletRecord.part.CanQuery = false
            bulletRecord.part.Size = Vector3.new(0.2,0.2,0.2)
            bulletRecord.part.Shape = Enum.PartType.Ball
            bulletRecord.part.Material = Enum.Material.Neon
            bulletRecord.part.Color = Color3.new(1,1,1)
            bulletRecord.part.Parent = game.Workspace
        end
        
        local lastPos = bulletRecord.position

        bulletRecord.vec += Vector3.new(0, bulletRecord.drop * deltaTime, 0)
        local add = bulletRecord.vec * bulletRecord.speed * deltaTime
        bulletRecord.position += add
        bulletRecord.travel += add.Magnitude
        

        if (bulletRecord.DoCollisionCheck) then
            local res = bulletRecord.DoCollisionCheck(bulletRecord, lastPos, bulletRecord.position)
            if (res ~= nil) then
                bulletRecord.die = true
            end
        end

        bulletRecord.part.Position = bulletRecord.position

        if (bulletRecord.travel > bulletRecord.maxDist) then
            --kill locally
            bulletRecord.die = true
        end

        if (bulletRecord.die == true) then
            bulletRecord.part:Destroy()
            self.bullets[key] = nil
        end
    end
end

return module
