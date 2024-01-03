local module = {}

local module = {}
module.__index = module

function module.new(buf : buffer)
	local self = setmetatable({
		offset = 0,
		buf = buf,
	},module)
	return self
end

function module:ResetReadPos()
	self.offset = 0
end

function module:ReadU8()

	local data = buffer.readu8(self.buf, self.offset)
	self.offset+=1
	return data
end


function module:ReadI16()
	local data = buffer.readu16(self.buf, self.offset)
	self.offset+=2
	return data
end

function module:ReadVector3()
	
	local x,y,z
	x = buffer.readf32(self.buf, self.offset)
	self.offset+=4
	y = buffer.readf32(self.buf, self.offset)
	self.offset+=4
	z = buffer.readf32(self.buf, self.offset)
	self.offset+=4
	return Vector3.new(x,y,z)
end


function module:ReadFloat16() 

	local b0 = buffer.readu8(self.buf, self.offset)
	self.offset+=1
	local b1 = buffer.readu8(self.buf, self.offset)
	self.offset+=1

	local sign = bit32.btest(b0, 128)
	local exponent = bit32.rshift(bit32.band(b0, 127), 2)
	local mantissa = bit32.lshift(bit32.band(b0, 3), 8) + b1

	if exponent == 31 then --2^5-1
		if mantissa ~= 0 then
			return (0 / 0)
		else
			return (sign and -math.huge or math.huge)
		end
	elseif exponent == 0 then
		if mantissa == 0 then
			return 0
		else
			return (sign and -math.ldexp(mantissa / 1024, -14) or math.ldexp(mantissa / 1024, -14))
		end
	end

	mantissa = (mantissa / 1024) + 1

	return (sign and -math.ldexp(mantissa, exponent - 15) or math.ldexp(mantissa, exponent - 15))
end

 
return module
