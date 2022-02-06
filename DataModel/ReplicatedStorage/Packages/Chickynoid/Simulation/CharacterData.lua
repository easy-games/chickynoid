local CharacterData = {}
CharacterData.__index = CharacterData

local BitBuffer = require(script.Parent.Parent.Vendor.BitBuffer)

function Lerp(a,b,frac)
    return a:Lerp(b,frac)
end


function AngleLerp(a,b,frac)
    --Todo
    return a
end

function NumberLerp(a,b,frac)
        
    return (a * (1-frac)) + (b * frac)
end

function Raw(a,b,frac)
    return b
end

function CharacterData:ModuleSetup()
    
    self.packFunctions = {
        pos = { "writeVector3", "readVector3" },
        angle = { "writeFloat16", "readFloat16"  },
        animCounter = { "writeByte", "readByte"  },
        animNum = { "writeByte", "readByte" },
        stepUp = { "writeFloat16", "readFloat16" },
    }

    self.lerpFunctions = {
        pos = Lerp,
        angle = AngleLerp,
        animCounter = Raw,
        animNum = Raw,
        stepUp = NumberLerp,
    }
end

 
function CharacterData.new()
    
    local self = setmetatable({
        serialized = {
            
            pos = Vector3.zero,
            angle = 0,
            animCounter = 0,
            animNum = 0,
            stepUp = 0,
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

function CharacterData:SetStepUp(amount)
    self.serialized.stepUp = amount
end


function CharacterData:PlayAnimation(animNum, forceRestart, exclusiveTime )
    
    if (tick() < self.animationExclusiveTime) then
        return
    end
        
    
    if (forceRestart or animNum ~= self.serialized.animNum) then
        self.serialized.animCounter += 1
        if (self.serialized.animCounter > 128) then
            self.serialized.animCounter = 0
        end
    end    
    
    if (exclusiveTime ~= nil and exclusiveTime > 0) then
        self.animationExclusiveTime = tick() + exclusiveTime
    end
    
    self.serialized.animNum = animNum
    
    
end


function CharacterData:Serialize()
    
    local ret = {}
    --Todo: Add bitpacking
    for key,value in pairs(self.serialized) do
        ret[key] = self.serialized[key]    
    end
    
    return ret   
end


function CharacterData:SerializeToBitBuffer(bitBuffer)
    
    
    for key,value in pairs(self.serialized) do
        local func = self.packFunctions[key]
        if (func) then
            bitBuffer[func[1]](value)    
        end
    end
end

function CharacterData:DeserializeFromBitBuffer(bitBuffer)

    for key,value in pairs(self.serialized) do
        local func = self.packFunctions[key]
        if (func) then
            self.serialized[key] = bitBuffer[func[2]]()    
        end
    end
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

CharacterData:ModuleSetup()
return CharacterData
