local module = {}

module.bullets = {}
module.bulletId = 0

function module:Setup(_server) end

 
function module:FireBullet(origin, vec, speed, maxDistance, drop, serverTime)

    
    --add the projectile
    local bulletRecord = {}
 
    bulletRecord.position = origin
    bulletRecord.vec = vec
    bulletRecord.serverTime = serverTime    
    bulletRecord.speed = speed
    bulletRecord.maxDist = maxDistance
    bulletRecord.drop = drop
    bulletRecord.travel = 0
    bulletRecord.bulletId = self.bulletId
    
    module.bullets[self.bulletId] = bulletRecord
    self.bulletId+=1
    if (self.bulletId > 16000) then
        self.bulletId = 0
    end
    return bulletRecord
end

function module:Step(_client, deltaTime) 

    for key, bulletRecord in pairs(self.bullets) do
        
        bulletRecord.serverTime += deltaTime
        
        local lastPos = bulletRecord.position
        
        bulletRecord.vec += Vector3.new(0, bulletRecord.drop * deltaTime, 0)
        local add = bulletRecord.vec * bulletRecord.speed * deltaTime
        bulletRecord.position += add
        bulletRecord.travel += add.Magnitude
        
        if (bulletRecord.DoCollisionCheck) then
            bulletRecord.res = bulletRecord.DoCollisionCheck(bulletRecord, lastPos, bulletRecord.position)
            if (bulletRecord.res ~= nil) then
                bulletRecord.die = true
            end
        end

        if (bulletRecord.travel > bulletRecord.maxDist) then
            --kill locally
            bulletRecord.die = true
        end

        if (bulletRecord.die == true) then
            
            --Send the event that this terminated
            if (bulletRecord.OnBulletDie) then
                bulletRecord.OnBulletDie(bulletRecord)
            end

            self.bullets[key] = nil
        end
    end
end

return module