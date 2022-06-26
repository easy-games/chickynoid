local CharacterData = {}
CharacterData.__index = CharacterData

local EPSILION = 0.00001
local mathUtils = require(script.Parent.MathUtils)

local function Lerp(a, b, frac)
    return a:Lerp(b, frac)
end

local function AngleLerp(a, b, frac)
    return mathUtils:LerpAngle(a, b, frac)
end

local function NumberLerp(a, b, frac)
    return (a * (1 - frac)) + (b * frac)
end

local function Raw(_a, b, _frac)
    return b
end

local MAX_FLOAT16 = math.pow(2, 16)
local function ValidateFloat16(float)
    return math.clamp(float, -MAX_FLOAT16, MAX_FLOAT16)
end

local MAX_BYTE = 255
local function ValidateByte(byte)
    return math.clamp(byte, 0, MAX_BYTE)
end

local function ValidateVector3(input)
    return input
end

local function ValidateNumber(input)
    return input
end

local function CompareVector3(a, b)
    if math.abs(a.x - b.x) > EPSILION or math.abs(a.y - b.y) > EPSILION or math.abs(a.z - b.z) > EPSILION then
        return false
    end
    return true
end

local function CompareByte(a, b)
    return a == b
end

local function CompareFloat16(a, b)
    return a == b
end

local function CompareNumber(a, b)
    return a == b
end


function CharacterData:SetIsResimulating(bool)
    self.isResimulating = bool
end

function CharacterData:ModuleSetup()
    CharacterData.methods = {}
    CharacterData.methods["Vector3"] = {
        write = "writeVector3",
        read = "readVector3",
        validate = ValidateVector3,
        compare = CompareVector3,
    }
    CharacterData.methods["Float16"] = {
        write = "writeFloat16",
        read = "readFloat16",
        validate = ValidateFloat16,
        compare = CompareFloat16,
    }
    CharacterData.methods["Number"] = {
        write = "writeFloat32",
        read = "readFloat32",
        validate = ValidateNumber,
        compare = CompareNumber,
    }

    CharacterData.methods["Byte"] = {
        write = "writeByte",
        read = "readByte",
        validate = ValidateByte,
        compare = CompareByte,
    }

    self.packFunctions = {
        pos = "Vector3",
        angle = "Float16",
        stepUp = "Float16",
		flatSpeed = "Float16",
        exclusiveAnimTime = "Number",

		animCounter0 = "Byte",
		animNum0 = "Byte",
		animCounter1 = "Byte",
		animNum1 = "Byte",
		animCounter2 = "Byte",
		animNum2 = "Byte",
		animCounter3 = "Byte",
		animNum3 = "Byte",
    }

    self.lerpFunctions = {
        pos = Lerp,
        angle = AngleLerp,
        stepUp = NumberLerp,
		flatSpeed = NumberLerp,
        exclusiveAnimTime = Raw,
		
		animCounter0 = Raw,
		animNum0 = Raw,
		animCounter1 = Raw,
		animNum1 = Raw,
		animCounter2 = Raw,
		animNum2 = Raw,
		animCounter3 = Raw,
		animNum3 = Raw,
    }
end

function CharacterData.new()
    local self = setmetatable({
        serialized = {
            pos = Vector3.zero,
            angle = 0,
            stepUp = 0,
			flatSpeed = 0,
            exclusiveAnimTime = 0,

			animCounter0 = 0,
			animNum0 = 0,
			animCounter1 = 0,
			animNum1 = 0,
			animCounter2 = 0,
			animNum2 = 0,
			animCounter3 = 0,
			animNum3 = 0,
        },

        --Be extremely careful about having any kind of persistant nonserialized data!
        --If in doubt, stick it in the serialized!
        isResimulating = false,
        targetPosition = Vector3.zero,
        
    }, CharacterData)

    return self
end

--This smoothing is performed on the server only.
--On client, use GetPosition
function CharacterData:SmoothPosition(deltaTime, smoothScale)
    if (smoothScale == 1 or smoothScale == 0)  then
        self.serialized.pos = self.targetPosition
    else
        self.serialized.pos = mathUtils:SmoothLerp(self.serialized.pos, self.targetPosition, smoothScale, deltaTime)
    end
end

function CharacterData:ClearSmoothing()
    self.serialized.pos = self.targetPosition
end

--Sets the target position
function CharacterData:SetTargetPosition(pos, teleport)
    self.targetPosition = pos
    if (teleport) then
        self:ClearSmoothing()
    end
end
 
function CharacterData:GetPosition()
    return self.serialized.pos
end

function CharacterData:SetFlatSpeed(num)
    self.serialized.flatSpeed = num
end

function CharacterData:SetAngle(angle)
    self.serialized.angle = angle
end

function CharacterData:GetAngle()
    return self.serialized.angle
end

function CharacterData:SetStepUp(amount)
    self.serialized.stepUp = amount
end

function CharacterData:PlayAnimation(animNum, animChannel, forceRestart, exclusiveTime)
    --Dont change animations during resim
    if self.isResimulating == true then
        return
    end

    if (animChannel < 0 or animChannel > 3) then
        return
    end

    --If we're in an exclusive window of having an animation play, ignore this request
    if tick() < self.serialized.exclusiveAnimTime and forceRestart == false then
        return
    end
    if exclusiveTime ~= nil and exclusiveTime > 0 then
        self.serialized.exclusiveAnimTime = tick() + exclusiveTime
    end

    local counterString = "animCounter"..animChannel
    local slotString = "animNum"..animChannel

    --Restart this anim, or its a different anim than we're currently playing
    if forceRestart == true or self.serialized[slotString] ~= animNum then
        self.serialized[counterString] += 1
        if self.serialized[counterString] > 255 then
            self.serialized[counterString] = 0
        end
    end
    self.serialized[slotString] = animNum
end

function CharacterData:InternalSetAnim(animChannel, animNum)
    local counterString = "animCounter"..animChannel
    local slotString = "animNum"..animChannel

    self.serialized[counterString] += 1
    if self.serialized[counterString] > 255 then
        self.serialized[counterString] = 0
    end
    self.serialized[slotString] = 0
end
function CharacterData:StopAnimation(animChannel)
    self:InternalSetAnim(animChannel, 0)
end

function CharacterData:StopAllAnimation()
    self.serialized.exclusiveAnimTime = 0
    self:InternalSetAnim(0, 0)
    self:InternalSetAnim(1, 0)
    self:InternalSetAnim(2, 0)
    self:InternalSetAnim(3, 0)
end


function CharacterData:Serialize()
    local ret = {}
    --Todo: Add bitpacking
    for key, _ in pairs(self.serialized) do
        ret[key] = self.serialized[key]
    end

    return ret
end

function CharacterData:SerializeToBitBuffer(previousData, bitBuffer)
    if previousData == nil then
        --calculate bits
        for key, value in pairs(self.serialized) do
            local func = CharacterData.methods[self.packFunctions[key]]
            if func then
                bitBuffer.writeBits(1)
                bitBuffer[func.write](value)
            else
                warn("Missing serializer for ", key)
            end
        end
    else
        --calculate bits
        for key, value in pairs(self.serialized) do
            local func = CharacterData.methods[self.packFunctions[key]]
            if func then
                local valueA = previousData.serialized[key]
                local valueB = value

                if func.compare(valueA, valueB) == true then
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

function CharacterData:SerializeToBitBufferValidate(previousData, bitBuffer)
	if previousData == nil then
		--calculate bits
		for key, value in pairs(self.serialized) do
			local func = CharacterData.methods[self.packFunctions[key]]
			if func then
				bitBuffer.writeBits(1)
				value = func.validate(value)
				bitBuffer[func.write](value)
			else
				warn("Missing serializer for ", key)
			end
		end
	else
		--calculate bits
		for key, value in pairs(self.serialized) do
			local func = CharacterData.methods[self.packFunctions[key]]
			if func then
				local valueA = func.validate(previousData.serialized[key])
				local valueB = func.validate(value)

				if func.compare(valueA, valueB) == true then
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
    for key, _ in pairs(self.serialized) do
        local set = bitBuffer.readBits(1)
        if set[1] == 1 then
            local func = CharacterData.methods[self.packFunctions[key]]
            self.serialized[key] = bitBuffer[func.read]()
        end
	end
	
	--Skip any stray bits
	bitBuffer.skipStrayBits()
	

end
function CharacterData:CopySerialized(otherSerialized)
    for key, value in pairs(otherSerialized) do
        self.serialized[key] = value
    end
end

function CharacterData:Interpolate(dataA, dataB, fraction)
    local dataRecord = {}
    for key, _ in pairs(dataA) do
        local func = self.lerpFunctions[key]

        if func == nil then
            dataRecord[key] = dataB[key]
        else
            dataRecord[key] = func(dataA[key], dataB[key], fraction)
        end
    end

    return dataRecord
end
 

CharacterData:ModuleSetup()
return CharacterData