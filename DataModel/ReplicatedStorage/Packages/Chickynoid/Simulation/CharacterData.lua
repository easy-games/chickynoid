local CharacterData = {}
CharacterData.__index = CharacterData


function Lerp(a,b,frac)
    return a:Lerp(b,frac)
end


function AngleLerp(a,b,frac)
    --Todo
    return a
end


function Raw(a,b,frac)
    return b
end

function CharacterData.new()
    
    local self = setmetatable({
        serialized = {
            
            pos = Vector3.zero,
            angle = 0,
            animCounter = 0,
            animName = "Idle",
        },
        
        
        lerpFunctions = {
            pos = Lerp,
            angle = AngleLerp,
            animCounter = Raw,
            animName = Raw 
        },
        
        animationExclusiveTime = 0,
        
    }, CharacterData)
    
    return self
end



function CharacterData:SetPosition(pos)
    self.serialized.pos = pos    
end

function CharacterData:SetAngle(angle)
    self.serialized.angle = angle    
end


function CharacterData:PlayAnimation(animName, forceRestart, exclusiveTime )
    
    if (tick() < self.animationExclusiveTime) then
        return
    end
    
    if (forceRestart or animName ~= self.serialized.animName) then
        self.serialized.animCounter += 1
    end    
    
    if (exclusiveTime ~= nil and exclusiveTime > 0) then
        self.animationExclusiveTime = tick() + exclusiveTime
    end
    
    self.serialized.animName = animName
    
    
end

function CharacterData:Serialize()
    
    local ret = {}
    --Todo: Add bitpacking
    for key,value in pairs(self.serialized) do
        ret[key] = self.serialized[key]    
    end
    
    return ret   
end



function CharacterData:Interpolate(dataA, dataB, fraction)
    
    local dataRecord = {}
    for key,value in pairs(dataA) do
        local func = self.lerpFunctions[key]
        
        if (func == nil) then
            dataRecord[key] = dataB[key]
        else
            dataRecord[key] = func(dataA[key], dataB[key], fraction)
        end
    end
   
    return dataRecord
end


return CharacterData
