local CharacterData = {}
CharacterData.__index = CharacterData

local BitBuffer = require(script.Parent.Parent.Vendor.BitBuffer)
local EPSILION = 0.00001
local mathUtils = require(script.Parent.MathUtils)

local function Lerp(a,b,frac)
    return a:Lerp(b,frac)
end

local function AngleLerp(a,b,frac)
    return mathUtils:LerpAngle(a,b,frac)
end

local function NumberLerp(a,b,frac)
        
    return (a * (1-frac)) + (b * frac)
end

local function Raw(a,b,frac)
    return b
end

local MAX_FLOAT16 = math.pow(2,16)
local function ValidateFloat16(float)
    return math.clamp(float,-MAX_FLOAT16, MAX_FLOAT16)
end

local MAX_BYTE = 255
local function ValidateByte(byte)
    return math.clamp(byte,0, MAX_BYTE)
end

local function ValidateVector3(input)
    return input
end

local function CompareVector3(a,b)
    if (math.abs(a.x-b.x)>EPSILION or math.abs(a.y-b.y)>EPSILION or math.abs(a.z-b.z)>EPSILION) then
        return false
    end
    return true
end

local function CompareByte(a,b)
    return a==b
end

local function CompareFloat16(a,b)
    return a==b
end

function CharacterData:SetIsResimulating(bool)
	self.isResimulating = bool
end

function CharacterData:ModuleSetup()
    
    CharacterData.methods = {}
    CharacterData.methods["Vector3"] =  { write = "writeVector3", read = "readVector3" , validate = ValidateVector3, compare = CompareVector3 }
    CharacterData.methods["Float16"] = { write = "writeFloat16", read = "readFloat16", validate = ValidateFloat16,compare = CompareFloat16  }
    CharacterData.methods["Byte"] = { write = "writeByte", read = "readByte", validate = ValidateByte, compare = CompareByte  }
    
    self.packFunctions = {
        pos = "Vector3",
        angle = "Float16",
        animCounter = "Byte",
        animNum = "Byte",
        stepUp = "Float16",
        flatSpeed = "Float16",
    }

    self.lerpFunctions = {
        pos = Lerp,
        angle = AngleLerp,
        animCounter = Raw,
        animNum = Raw,
        stepUp = NumberLerp,
        flatSpeed = NumberLerp,
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
            flatSpeed = 0,
        },
        
        --Be extremely careful about having any kind of persistant nonserialized data!
        --If in doubt, stick it in the serialized!
		animationExclusiveTime = 0,
		isResimulating = false,
        
    }, CharacterData)
    
    return self
end



function CharacterData:SetPosition(pos)
    self.serialized.pos = pos  
   
end

function CharacterData:SetFlatSpeed(num)
    self.serialized.flatSpeed = num
end

function CharacterData:SetAngle(angle)
    self.serialized.angle = angle  
end

function CharacterData:SetStepUp(amount)
    self.serialized.stepUp = amount
end


function CharacterData:PlayAnimation(animNum, forceRestart, exclusiveTime )
	
	--Dont change animations during resim
	if (self.isResimulating == true) then
		return
	end
	
	--If we're in an exclusive window of having an animation play, ignore this request
    if (tick() < self.animationExclusiveTime and forceRestart == false) then
        return
    end
	
	--Restart this anim, or its a different anim than we're currently playing	
    if (forceRestart == true or animNum ~= self.serialized.animNum) then
        self.serialized.animCounter += 1
        if (self.serialized.animCounter > 255) then
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


function CharacterData:SerializeToBitBuffer(previousData, bitBuffer)
    
    if (previousData == nil) then
        
        --calculate bits
        for key,value in pairs(self.serialized) do
            local func = CharacterData.methods[self.packFunctions[key]]
            if (func) then
                bitBuffer.writeBits(1)
                value = func.validate(value)
                bitBuffer[func.write](value)    
            else
                warn("Missing serializer for ", key)
            end
        end    
    else
        --calculate bits
        for key,value in pairs(self.serialized) do
            
            local func = CharacterData.methods[self.packFunctions[key]]
            if (func) then
                
                local valueA = func.validate(previousData.serialized[key])
                local valueB = func.validate(value)
                
                if (func.compare(valueA, valueB) == true) then
                    bitBuffer.writeBits(0)
                else
                    bitBuffer.writeBits(1)
                    bitBuffer[func.write](value)
                end
            else
                warn("Missing serializer for ", key)
            end
        end    
        
    end
    
end

function CharacterData:DeserializeFromBitBuffer(bitBuffer)
    
    for key,value in pairs(self.serialized) do
        local set = bitBuffer.readBits(1)
        if (set[1] == 1) then
            local func = CharacterData.methods[self.packFunctions[key]]
            self.serialized[key] = bitBuffer[func.read]()    
             
        end
    end
end
function CharacterData:CopySerialized(otherSerialized)

    for key,value in pairs(otherSerialized) do
        self.serialized[key] = value
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
