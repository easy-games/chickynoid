local CharacterData = {}
CharacterData.__index = CharacterData


function Lerp(a,b,frac)
    return a:Lerp(b,frac)
end

function Raw(a,b,frac)
    return b
end

function CharacterData.new()
    
    local self = setmetatable({
        serialized = {
            
            pos = Vector3.zero,
            animCounter = 0,
            animName = "Idle",
        },
        lerpFunctions = {
            pos = Lerp,
            animCounter = Raw,
            animName = Raw 
        }
        
        
    }, CharacterData)
    
    return self
end

function CharacterData:SetPosition(pos)
    
    self.serialized.pos = pos    
    
end

function CharacterData:PlayAnimation(animName, forceRestart)
    
    if (forceRestart) then
        self.serialized.animCounter += 1
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
    
    local ret = {}
    for key,value in pairs(dataA) do
        local func = self.lerpFunctions[key]
        
        if (func == nil) then
            ret[key] = dataB[key]
        else
            ret[key] = func(dataA[key], dataB[key], fraction)
        end
    end
   
    return ret
end


return CharacterData
