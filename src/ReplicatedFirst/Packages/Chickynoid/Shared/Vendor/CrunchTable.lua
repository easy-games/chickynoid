--CrunchTable lets you define compression schemes for simple tables to be sent by roblox
--If a field in a table is not defined in the layout, it will be ignored and stay in the table
--If a field in a table is not present, but is defined in the layout, it'll default to 0 (or equiv)

local module = {}

module.Enum = {
	FLOAT = 1,
	VECTOR3 = 2,
	INT32 = 3,
	UBYTE = 4,
}
table.freeze(module.Enum)

module.Sizes = {
		4,
		12,
		4,
		1
}
table.freeze(module.Sizes)

function module:CreateLayout()
	local layout = {}
	layout.pairTable = {}
	
	layout.totalBytes = 0
	
	function layout:Add(field :string, enum : number)
		table.insert(self.pairTable, {field = field, enum = enum})
		module:CalcSize(self)
	end
	return layout
end

function module:CalcSize(layout)
	local totalBytes = 0
	for index,rec in layout.pairTable do
		
		rec.size = module.Sizes[rec.enum]
		totalBytes += rec.size
		
	end	
	local numBytesForIndex = 2
	layout.totalBytes = totalBytes + numBytesForIndex
end

function module:DeepCopy(sourceTable)
	local function Deep(tbl)
		local tCopy = table.create(#tbl)
		for k, v in pairs(tbl) do
			if type(v) == "table" then
				tCopy[k] = Deep(v)
			else
				tCopy[k] = v
			end
		end
		return tCopy
	end
	return Deep(sourceTable)
end


function module:BinaryEncodeTable(srcData, layout)

	local newPacket = self:DeepCopy(srcData)
	
	local buf = buffer.create(layout.totalBytes)
	local numBytesForIndex = 2
	local offset = numBytesForIndex 
	local contentBits = 0
	local bitIndex = 0
	
	for index,rec in layout.pairTable do
		
		local key = rec.field
		local encodeChar = rec.enum
		
		local srcValue = newPacket[key]
				
		if (encodeChar == module.Enum.INT32) then
			if (srcValue ~= nil and srcValue ~= 0) then
				buffer.writei32(buf,offset, srcValue)
				offset+=rec.size
				contentBits = bit32.bor(contentBits, bit32.lshift(1, bitIndex))
			end
		elseif (encodeChar == module.Enum.FLOAT) then
			if (srcValue ~= nil and srcValue ~= 0) then
				buffer.writef32(buf,offset,srcValue)
				offset+=rec.size
				contentBits = bit32.bor(contentBits, bit32.lshift(1, bitIndex))
			end
		elseif (encodeChar == module.Enum.UBYTE) then
			if (srcValue ~= nil and srcValue ~= 0) then
				buffer.writeu8(buf,offset,srcValue)
				offset+=rec.size
				contentBits = bit32.bor(contentBits, bit32.lshift(1, bitIndex))
			end
		elseif (encodeChar == module.Enum.VECTOR3) then
			if (srcValue ~= nil and srcValue.magnitude > 0) then
				buffer.writef32(buf,offset,srcValue.X)
				offset+=4
				buffer.writef32(buf,offset,srcValue.Y)
				offset+=4
				buffer.writef32(buf,offset,srcValue.Z)
				offset+=4
				contentBits = bit32.bor(contentBits, bit32.lshift(1, bitIndex))
			end
		end
		
		newPacket[key] = nil

		bitIndex += 1
	end

	--Write the contents
	buffer.writeu16(buf,0, contentBits)

	--Copy it to a new buffer
	local finalBuffer = buffer.create(offset)
	buffer.copy(finalBuffer, 0, buf, 0, offset)

	newPacket._b = finalBuffer
 
	--leave the other fields untouched
	return newPacket	
end
	

function module:BinaryDecodeTable(srcData, layout)

	local command = self:DeepCopy(srcData)
	if (command._b == nil) then
		error("missing _b field")
		return
	end
	local buf = command._b
	command._b = nil

	local offset = 0

	local contentBits = buffer.readu16(buf, 0)
	offset+=2

	local bitIndex = 0
	
	for index,rec in layout.pairTable do
		local key = rec.field
		local encodeChar = rec.enum
		
		local hasBit = bit32.band(contentBits, bit32.lshift(1, bitIndex)) > 0
		
		if (hasBit == false) then
			if (encodeChar == module.Enum.INT32) then
				command[key] = 0
			elseif (encodeChar == module.Enum.FLOAT) then
				command[key] = 0
			elseif (encodeChar == module.Enum.UBYTE) then
				command[key] = 0
			elseif (encodeChar == module.Enum.VECTOR3) then
				command[key] = Vector3.zero
			end
		else
			if (encodeChar == module.Enum.INT32) then
				command[key] = buffer.readi32(buf,offset)
				offset+=rec.size
			elseif (encodeChar == module.Enum.FLOAT) then
				command[key] = buffer.readf32(buf,offset)
				offset+=rec.size
			elseif (encodeChar == module.Enum.UBYTE) then
				command[key] = buffer.readu8(buf,offset)
				offset+=rec.size
			elseif (encodeChar == module.Enum.VECTOR3) then
				local x = buffer.readf32(buf,offset)
				offset+=4
				local y = buffer.readf32(buf,offset)
				offset+=4
				local z = buffer.readf32(buf,offset)
				offset+=4
				command[key] = Vector3.new(x,y,z)
			end
		end
		bitIndex+=1
	end
	return command
end

return module