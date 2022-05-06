local CHAR_SET = [[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/]]

-- Tradition is to use chars for the lookup table instead of codepoints.
-- But due to how we're running the encode function, it's faster to use codepoints.
local encode_char_set = {}
local decode_char_set = {}
for i = 1, 64 do
    encode_char_set[i - 1] = string.byte(CHAR_SET, i, i)
    decode_char_set[string.byte(CHAR_SET, i, i)] = i - 1
end

-- stylua: ignore
local HEX_TO_BIN = {
    ["0"] = "0000", ["1"] = "0001", ["2"] = "0010", ["3"] = "0011",
    ["4"] = "0100", ["5"] = "0101", ["6"] = "0110", ["7"] = "0111",
    ["8"] = "1000", ["9"] = "1001", ["a"] = "1010", ["b"] = "1011",
    ["c"] = "1100", ["d"] = "1101", ["e"] = "1110", ["f"] = "1111"
}

-- stylua: ignore
local NORMAL_ID_VECTORS = { -- [Enum.Value] = Vector3.fromNormalId(Enum)
    [0] = Vector3.new(1, 0, 0), -- Enum.NormalId.Right
    [1] = Vector3.new(0, 1, 0), -- Enum.NormalId.Top
    [2] = Vector3.new(0, 0, 1), -- Enum.NormalId.Back
    [3] = Vector3.new(-1, 0, 0), -- Enum.NormalId.Left
    [4] = Vector3.new(0, -1, 0), -- Enum.NormalId.Bottom
    [5] = Vector3.new(0, 0, -1) -- Enum.NormalId.Front
}

local ONES_VECTOR = Vector3.new(1, 1, 1)

local BOOL_TO_BIT = { [true] = 1, [false] = 0 }

local CRC32_POLYNOMIAL = 0xedb88320

local crc32_poly_lookup = {}
for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
        local mask = -bit32.band(crc, 1)
        crc = bit32.bxor(bit32.rshift(crc, 1), bit32.band(CRC32_POLYNOMIAL, mask))
    end
    crc32_poly_lookup[i] = crc
end

local powers_of_2 = {}
for i = 0, 64 do
    powers_of_2[i] = 2 ^ i
end

local byte_to_hex = {}
for i = 0, 255 do
    byte_to_hex[i] = string.format("%02x", i)
end

local function bitBuffer(stream)
    if stream ~= nil then
        assert(type(stream) == "string", "argument to BitBuffer constructor must be either nil or a string")
    end

    -- The bit buffer works by keeping an array of bytes, a 'final' byte, and how many bits are currently in that last byte
    -- Bits are not kept track of on their own, and are instead combined to form a byte, which is stored in the last space in the array.
    -- This byte is also stored seperately, so that table operations aren't needed to read or modify its value.
    -- The byte array is called `bytes`. The last byte is stored in `lastByte`. The bit counter is stored in `bits`.

    local bits = 0 -- How many free floating bits there are.
    local bytes = {} --! -- Array of bytes currently in the buffer
    local lastByte = 0 -- The most recent byte in the buffer, made up of free floating bits

    local byteCount = 0 -- This variable keeps track of how many bytes there are total in the bit buffer.
    local bitCount = 0 -- This variable keeps track of how many bits there are total in the bit buffer

    local pointer = 0 -- This variable keeps track of what bit the read functions start at
    local pointerByte = 1 -- This variable keeps track of what byte the pointer is at. It starts at 1 since the byte array starts at 1.

    if stream then
        byteCount = #stream
        bitCount = byteCount * 8

        bytes = table.create(#stream)

        for i = 1, byteCount do
            bytes[i] = string.byte(stream, i, i)
        end
    end

    local function dumpBinary()
        -- This function is for debugging or analysis purposes.
        -- It dumps the contents of the byte array and the remaining bits into a string of binary digits.
        -- Thus, bytes [97, 101] with bits [1, 1, 0] would output "01100001 01100101 110"
        local output = table.create(byteCount) --!
        for i, v in ipairs(bytes) do
            output[i] = string.gsub(byte_to_hex[v], "%x", HEX_TO_BIN)
        end
        if bits ~= 0 then
            -- Because the last byte (where the free floating bits are stored) is in the byte array, it has to be overwritten.
            output[byteCount] = string.sub(output[byteCount], 1, bits)
        end

        return table.concat(output, " ")
    end

    local function dumpString()
        -- This function is for accessing the total contents of the bitbuffer.
        -- This function combines all the bytes, including the last byte, into a string of binary data.
        -- Thus, bytes [97, 101] and bits [1, 1, 0] would become (in hex) "0x61 0x65 0x06"

        -- It's substantially faster to create several smaller strings before using table.concat.
        local output = table.create(math.ceil(byteCount / 4096)) --!
        local c = 1
        for i = 1, byteCount, 4096 do -- groups of 4096 bytes is the point at which there are diminishing returns
            output[c] = string.char(table.unpack(bytes, i, math.min(byteCount, i + 4095)))
            c = c + 1
        end

        return table.concat(output, "")
    end

    local function dumpHex()
        -- This function is for getting the hex of the bitbuffer's contents, should that be desired
        local output = table.create(byteCount) --!
        for i, v in ipairs(bytes) do
            output[i] = byte_to_hex[v]
        end

        return table.concat(output, "")
    end

    local function dumpBase64()
        -- Base64 is a safe and easy way to convert binary data to be entirely printable
        -- It works on the principle that groups of 3 bytes (24 bits) can evenly be divided into 4 groups of 6
        -- And 2^6 is a mere 64, far less than the number of printable characters.
        -- If there are any missing bytes, `=` is added to the end as padding.
        -- Base64 increases the size of its input by 33%.
        local output = table.create(math.ceil(byteCount * 1.333)) --!

        local c = 1
        for i = 1, byteCount, 3 do
            local b1, b2, b3 = bytes[i], bytes[i + 1], bytes[i + 2]
            local packed = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2 or 0, 8), b3 or 0)

            -- This can be done with bit32.extract (and/or bit32.lshift, bit32.band, bit32.rshift)
            -- But bit masking and shifting is more eloquent in my opinion.
            output[c] = encode_char_set[bit32.rshift(bit32.band(packed, 0xfc0000), 0x12)]
            output[c + 1] = encode_char_set[bit32.rshift(bit32.band(packed, 0x3f000), 0xc)]
            output[c + 2] = b2 and encode_char_set[bit32.rshift(bit32.band(packed, 0xfc0), 0x6)] or 0x3d -- 0x3d == "="
            output[c + 3] = b3 and encode_char_set[bit32.band(packed, 0x3f)] or 0x3d

            c = c + 4
        end
        c = c - 1 -- c will always be 1 more than the length of `output`

        local realOutput = table.create(math.ceil(c / 0x1000)) --!
        local k = 1
        for i = 1, c, 0x1000 do
            realOutput[k] = string.char(table.unpack(output, i, math.min(c, i + 0xfff)))
            k = k + 1
        end

        return table.concat(realOutput, "")
    end

    local function exportChunk(chunkLength)
        assert(type(chunkLength) == "number", "argument #1 to BitBuffer.exportChunk should be a number")
        assert(chunkLength > 0, "argument #1 to BitBuffer.exportChunk should be above zero")
        assert(chunkLength % 1 == 0, "argument #1 to BitBuffer.exportChunk should be an integer")

        -- Since `i` is being returned, the most eloquent way to handle this is with a coroutine
        -- This allows returning the existing value of `i` without having to increment it first.
        -- The alternative was starting at `i = -(chunkLength-1)` and incrementing at the start of the iterator function.
        return coroutine.wrap(function()
            local realChunkLength = chunkLength - 1
            -- Since this function only has one 'state', it's perfectly fine to use a for-loop.
            for i = 1, byteCount, chunkLength do
                local chunk = string.char(table.unpack(bytes, i, math.min(byteCount, i + realChunkLength)))
                coroutine.yield(i, chunk)
            end
        end)
    end

    local function exportBase64Chunk(chunkLength)
        chunkLength = chunkLength or 76
        assert(type(chunkLength) == "number", "argument #1 to BitBuffer.exportBase64Chunk should be a number")
        assert(chunkLength > 0, "argument #1 to BitBuffer.exportBase64Chunk should be above zero")
        assert(chunkLength % 1 == 0, "argument #1 to BitBuffer.exportBase64Chunk should be an integer")

        local output = table.create(math.ceil(byteCount * 0.333)) --!

        local c = 1
        for i = 1, byteCount, 3 do
            local b1, b2, b3 = bytes[i], bytes[i + 1], bytes[i + 2]
            local packed = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2 or 0, 8), b3 or 0)

            output[c] = encode_char_set[bit32.rshift(bit32.band(packed, 0xfc0000), 0x12)]
            output[c + 1] = encode_char_set[bit32.rshift(bit32.band(packed, 0x3f000), 0xc)]
            output[c + 2] = b2 and encode_char_set[bit32.rshift(bit32.band(packed, 0xfc0), 0x6)] or 0x3d
            output[c + 3] = b3 and encode_char_set[bit32.band(packed, 0x3f)] or 0x3d

            c = c + 4
        end
        c = c - 1

        return coroutine.wrap(function()
            local realChunkLength = chunkLength - 1
            for i = 1, c, chunkLength do
                local chunk = string.char(table.unpack(output, i, math.min(c, i + realChunkLength)))
                coroutine.yield(chunk)
            end
        end)
    end

    local function exportHexChunk(chunkLength)
        assert(type(chunkLength) == "number", "argument #1 to BitBuffer.exportHexChunk should be a number")
        assert(chunkLength > 0, "argument #1 to BitBuffer.exportHexChunk should be above zero")
        assert(chunkLength % 1 == 0, "argument #1 to BitBuffer.exportHexChunk should be an integer")

        local halfLength = math.floor(chunkLength / 2)

        if chunkLength % 2 == 0 then
            return coroutine.wrap(function()
                local output = {} --!
                for i = 1, byteCount, halfLength do
                    for c = 0, halfLength - 1 do
                        output[c] = byte_to_hex[bytes[i + c]]
                    end
                    coroutine.yield(table.concat(output, "", 0))
                end
            end)
        else
            return coroutine.wrap(function()
                local output = { [0] = "" } --!
                local remainder = ""

                local i = 1
                while i <= byteCount do
                    if remainder == "" then
                        output[0] = ""
                        for c = 0, halfLength - 1 do
                            output[c + 1] = byte_to_hex[bytes[i + c]]
                        end
                        local endByte = byte_to_hex[bytes[i + halfLength]]
                        if endByte then
                            output[halfLength + 1] = string.sub(endByte, 1, 1)
                            remainder = string.sub(endByte, 2, 2)
                        end
                        i = i + 1
                    else
                        output[0] = remainder
                        for c = 0, halfLength - 1 do
                            output[c + 1] = byte_to_hex[bytes[i + c]]
                        end
                        output[halfLength + 1] = ""
                        remainder = ""
                    end

                    coroutine.yield(table.concat(output, "", 0))
                    i = i + halfLength
                end
            end)
        end
    end

    local function crc32()
        local crc = 0xffffffff -- 2^32

        for _, v in ipairs(bytes) do
            local poly = crc32_poly_lookup[bit32.band(bit32.bxor(crc, v), 255)]
            crc = bit32.bxor(bit32.rshift(crc, 8), poly)
        end

        return bit32.bnot(crc) % 0xffffffff -- 2^32
    end

    local function getLength()
        return bitCount
    end

    local function getByteLength()
        return byteCount
    end

    local function getPointer()
        -- This function gets the value of the pointer. This is self-explanatory.
        return pointer
    end

    local function setPointer(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.setPointer should be a number")
        assert(n >= 0, "argument #1 to BitBuffer.setPointer should be zero or higher")
        assert(n % 1 == 0, "argument #1 to BitBuffer.setPointer should be an integer")
        assert(n <= bitCount, "argument #1 to BitBuffer.setPointerByte should within range of the buffer")
        -- This function sets the value of pointer. This is self-explanatory.
        pointer = n
        pointerByte = math.floor(n / 8) + 1
    end

    local function setPointerFromEnd(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.setPointerFromEnd should be a number")
        assert(n >= 0, "argument #1 to BitBuffer.setPointerFromEnd should be zero or higher")
        assert(n % 1 == 0, "argument #1 to BitBuffer.setPointerFromEnd should be an integer")
        assert(n <= bitCount, "argument #1 to BitBuffer.setPointerFromEnd should within range of the buffer")

        pointer = bitCount - n
        pointerByte = math.floor(pointer / 8 + 1)
    end

    local function getPointerByte()
        return pointerByte
    end

    local function setPointerByte(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.setPointerByte should be a number")
        assert(n > 0, "argument #1 to BitBuffer.setPointerByte should be positive")
        assert(n % 1 == 0, "argument #1 to BitBuffer.setPointerByte should be an integer")
        assert(n <= byteCount, "argument #1 to BitBuffer.setPointerByte should be within range of the buffer")
        -- Sets the value of the pointer in bytes instead of bits
        pointer = n * 8
        pointerByte = n
    end

    local function setPointerByteFromEnd(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.setPointerByteFromEnd should be a number")
        assert(n >= 0, "argument #1 to BitBuffer.setPointerByteFromEnd should be zero or higher")
        assert(n % 1 == 0, "argument #1 to BitBuffer.setPointerByteFromEnd should be an integer")
        assert(n <= byteCount, "argument #1 to BitBuffer.setPointerByteFromEnd should be within range of the buffer")

        pointerByte = byteCount - n
        pointer = pointerByte * 8
    end

    local function isFinished()
        return pointer == bitCount
    end

    local function writeBits(...)
        -- The first of two main functions for the actual 'writing' of the bitbuffer.
        -- This function takes a vararg of 1s and 0s and writes them to the buffer.
        local bitN = select("#", ...)
        if bitN == 0 then
            return
        end -- Throwing here seems unnecessary
        bitCount = bitCount + bitN
        local packed = table.pack(...)
        for _, v in ipairs(packed) do
            assert(v == 1 or v == 0, "arguments to BitBuffer.writeBits should be either 1 or 0")
            if bits == 0 then -- If the bit count is 0, increment the byteCount
                -- This is the case at the beginning of the buffer as well as when the the buffer reaches 7 bits,
                -- so it's done at the beginning of the loop.
                byteCount = byteCount + 1
            end
            lastByte = lastByte + (v == 1 and powers_of_2[7 - bits] or 0) -- Add the current bit to lastByte, from right to left
            bits = bits + 1
            if bits == 8 then -- If the bit count is 8, set it to 0, write lastByte to the byte list, and set lastByte to 0
                bits = 0
                bytes[byteCount] = lastByte
                lastByte = 0
            end
        end
        if bits ~= 0 then -- If there are some bits in lastByte, it has to be put into lastByte
            -- If this is done regardless of the bit count, there might be a trailing zero byte
            bytes[byteCount] = lastByte
        end
    end

    local function writeByte(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeByte should be a number")
        assert(n >= 0 and n <= 255, "argument #1 to BitBuffer.writeByte should be in the range [0, 255]")
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeByte should be an integer")
        -- The second of two main functions for the actual 'writing' of the bitbuffer.
        -- This function takes a byte (an 8-bit integer) and writes it to the buffer.
        if bits == 0 then
            -- If there aren't any free-floating bits, this is easy.
            byteCount = byteCount + 1
            bytes[byteCount] = n
        else
            local nibble = bit32.rshift(n, bits) -- Shift `bits` number of bits out of `n` (they go into the aether)
            bytes[byteCount] = lastByte + nibble -- Manually set the most recent byte to the lastByte + the front part of `n`
            byteCount = byteCount + 1
            lastByte = bit32.band(bit32.lshift(n, 8 - bits), 255) -- Shift `n` forward `8-bits` and get what remains in the first 8 bits
            bytes[byteCount] = lastByte
        end
        bitCount = bitCount + 8 -- Increment the bit counter
    end

    local function writeUnsigned(width, n)
        assert(type(width) == "number", "argument #1 to BitBuffer.writeUnsigned should be a number")
        assert(width >= 1 and width <= 64, "argument #1 to BitBuffer.writeUnsigned should be in the range [1, 64]")
        assert(width % 1 == 0, "argument #1 to BitBuffer.writeUnsigned should be an integer")

        assert(type(n) == "number", "argument #2 to BitBuffer.writeUnsigned should be a number")
        assert(n >= 0 and n <= powers_of_2[width] - 1, "argument #2 to BitBuffer.writeUnsigned is out of range")
        assert(n % 1 == 0, "argument #2 to BitBuffer.writeUnsigned should be an integer")
        -- Writes unsigned integers of arbitrary length to the buffer.
        -- This is the first function that uses other functions in the buffer to function.
        -- This is done because the space taken up would be rather large for very little performance gain.

        -- Get the number of bytes and number of floating bits in the specified width
        local bytesInN, bitsInN = math.floor(width / 8), width % 8
        local extractedBits = table.create(bitsInN) --!

        -- If the width is less than or equal to 32-bits, bit32 can be used without any problem.
        if width <= 32 then
            -- Counting down from the left side, the bytes are written to the buffer
            local c = width
            for _ = 1, bytesInN do
                c = c - 8
                writeByte(bit32.extract(n, c, 8))
            end
            -- Any remaining bits are stored in an array
            for i = bitsInN - 1, 0, -1 do
                extractedBits[bitsInN - i] = BOOL_TO_BIT[bit32.btest(n, powers_of_2[i])]
            end
            -- Said array is then used to write them to the buffer
            writeBits(table.unpack(extractedBits))
        else
            -- If the width is greater than 32, the number has to be divided up into a few 32-bit or less numbers
            local leastSignificantChunk = n % 0x100000000 -- Get bits 0-31 (counting from the right side). 0x100000000 is 2^32.
            local mostSignificantChunk = math.floor(n / 0x100000000) -- Get any remaining bits by manually right shifting by 32 bits

            local c = width - 32 -- The number of bits in mostSignificantChunk is variable, but a counter is still needed
            for _ = 1, bytesInN - 4 do -- 32 bits is 4 bytes
                c = c - 8
                writeByte(bit32.extract(mostSignificantChunk, c, 8))
            end
            -- `bitsInN` is always going to be the number of spare bits in `mostSignificantChunk`
            -- which comes before `leastSignificantChunk`
            for i = bitsInN - 1, 0, -1 do
                extractedBits[bitsInN - i] = BOOL_TO_BIT[bit32.btest(mostSignificantChunk, powers_of_2[i])]
            end
            writeBits(table.unpack(extractedBits))

            for i = 3, 0, -1 do -- Then of course, write all 4 bytes of leastSignificantChunk
                writeByte(bit32.extract(leastSignificantChunk, i * 8, 8))
            end
        end
    end

    local function writeSigned(width, n)
        assert(type(width) == "number", "argument #1 to BitBuffer.writeSigned should be a number")
        assert(width >= 2 and width <= 64, "argument #1 to BitBuffer.writeSigned should be in the range [2, 64]")
        assert(width % 1 == 0, "argument #1 to BitBuffer.writeSigned should be an integer")

        assert(type(n) == "number", "argument #2 to BitBuffer.writeSigned should be a number")
        assert(
            n >= -powers_of_2[width - 1] and n <= powers_of_2[width - 1] - 1,
            "argument #2 to BitBuffer.writeSigned is out of range"
        )
        assert(n % 1 == 0, "argument #2 to BitBuffer.writeSigned should be an integer")
        -- Writes signed integers of arbitrary length to the buffer.
        -- These integers are stored using two's complement.
        -- Essentially, this means the first bit in the number is used to store whether it's positive or negative
        -- If the number is positive, it's stored normally.
        -- If it's negative, the number that's stored is equivalent to the max value of the width + the number
        if n >= 0 then
            writeBits(0)
            writeUnsigned(width - 1, n) -- One bit is used for the sign, so the stored number's width is actually width-1
        else
            writeBits(1)
            writeUnsigned(width - 1, powers_of_2[width - 1] + n)
        end
    end

    local function writeFloat(exponentWidth, mantissaWidth, n)
        assert(type(exponentWidth) == "number", "argument #1 to BitBuffer.writeFloat should be a number")
        assert(
            exponentWidth >= 1 and exponentWidth <= 64,
            "argument #1 to BitBuffer.writeFloat should be in the range [1, 64]"
        )
        assert(exponentWidth % 1 == 0, "argument #1 to BitBuffer.writeFloat should be an integer")

        assert(type(mantissaWidth) == "number", "argument #2 to BitBuffer.writeFloat should be a number")
        assert(
            mantissaWidth >= 1 and mantissaWidth <= 64,
            "argument #2 to BitBuffer.writeFloat should be in the range [1, 64]"
        )
        assert(mantissaWidth % 1 == 0, "argument #2 to BitBuffer.writeFloat should be an integer")

        assert(type(n) == "number", "argument #3 to BitBuffer.writeFloat should be a number")

        -- Given that floating point numbers are particularly hard to grasp, this function is annotated heavily.
        -- This stackoverflow answer is a great help if you just want an overview:
        -- https://stackoverflow.com/a/7645264
        -- Essentially, floating point numbers are scientific notation in binary.
        -- Instead of expressing numbers like 10^e*m, floating points instead use 2^e*m.
        -- For the sake of this function, `e` is referred to as `exponent` and `m` is referred to as `mantissa`.

        -- Floating point numbers are stored in memory as a sequence of bitfields.
        -- Every float has a set number of bits assigned for exponent values and mantissa values, along with one bit for the sign.
        -- The order of the bits in the memory is: sign, exponent, mantissa.

        -- Given that floating points have to represent numbers less than zero as well as those above them,
        -- some parts of the exponent are set aside to be negative exponents. In the case of floats,
        -- this is about half of the values. To calculate the 'real' value of an exponent a number that's half of the max exponent
        -- is added to the exponent. More info can be found here: https://stackoverflow.com/q/2835278
        -- This number is called the 'bias'.
        local bias = powers_of_2[exponentWidth - 1] - 1

        local sign = n < 0 -- The sign of a number is important.
        -- In this case, since we're using a lookup table for the sign bit, we want `sign` to indicate if the number is negative or not.
        n = math.abs(n) -- But it's annoying to work with negative numbers and the sign isn't important for decomposition.

        -- Lua has a function specifically for decomposing (or taking apart) a floating point number into its pieces.
        -- These pieces, as listed above, are the mantissa and exponent.
        local mantissa, exponent = math.frexp(n)

        -- Before we go further, there are some concepts that get special treatment in the floating point format.
        -- These have to be accounted for before normal floats are written to the buffer.

        if n == math.huge then
            -- Positive and negative infinities are specifically indicated with an exponent that's all 1s
            -- and a mantissa that's all 0s.
            writeBits(BOOL_TO_BIT[sign]) -- As previously said, there's a bit for the sign
            writeUnsigned(exponentWidth, powers_of_2[exponentWidth] - 1) -- Then comes the exponent
            writeUnsigned(mantissaWidth, 0) -- And finally the mantissa
            return
        elseif n ~= n then
            -- NaN is indicated with an exponent that's all 1s and a mantissa that isn't 0.
            -- In theory, the individual bits of NaN should be maintained but Lua doesn't allow that,
            -- so the mantissa is just being set to 10 for no particular reason.
            writeBits(BOOL_TO_BIT[sign])
            writeUnsigned(exponentWidth, powers_of_2[exponentWidth] - 1)
            writeUnsigned(mantissaWidth, 10)
            return
        elseif n == 0 then
            -- Zero is represented with an exponent that's zero and a mantissa that's also zero.
            -- Lua doesn't have a signed zero, so that translates to the entire number being all 0s.
            writeUnsigned(exponentWidth + mantissaWidth + 1, 0)
            return
        elseif exponent + bias <= 1 then
            -- Subnormal numbers are a number that's exponent (when biased) is zero.
            -- Because of a quirk with the way Lua and C decompose numbers, subnormal numbers actually have an exponent of one when biased.

            -- The process behind this is explained below, so for the sake of brevity it isn't explained here.
            -- The only difference between processing subnormal and normal numbers is with the mantissa.
            -- As subnormal numbers always start with a 0 (in binary), it doesn't need to be removed or shifted out
            -- so it's a simple shift and round.
            mantissa = math.floor(mantissa * powers_of_2[mantissaWidth] + 0.5)

            writeBits(BOOL_TO_BIT[sign])
            writeUnsigned(exponentWidth, 0) -- Subnormal numbers always have zero for an exponent
            writeUnsigned(mantissaWidth, mantissa)
            return
        end

        -- In every normal case, the mantissa of a number will have a 1 directly after the decimal point (in binary).
        -- As an example, 0.15625 has a mantissa of 0.625, which is 0.101 in binary. The 1 after the decimal point is always there.
        -- That means that for the sake of space efficiency that can be left out.
        -- The bit has to be removed. This uses subtraction and multiplication to do it since bit32 is for integers only.
        -- The mantissa is then shifted up by the width of the mantissa field and rounded.
        mantissa = math.floor((mantissa - 0.5) * 2 * powers_of_2[mantissaWidth] + 0.5)
        -- (The first fraction bit is equivalent to 0.5 in decimal)

        -- After that, it's just a matter of writing to the stream:
        writeBits(BOOL_TO_BIT[sign])
        writeUnsigned(exponentWidth, exponent + bias - 1) -- The bias is added to the exponent to properly offset it
        -- The extra -1 is added because Lua, for whatever reason, doesn't normalize its results
        -- This is the cause of the 'quirk' mentioned when handling subnormal number
        -- As an example, math.frexp(0.15625) = 0.625, -2
        -- This means that 0.15625 = 0.625*2^-2
        -- Or, in binary: 0.00101 = 0.101 >> 2
        -- This is a correct statement but the actual result is meant to be:
        -- 0.00101 = 1.01 >> 3, or 0.15625 = 1.25*2^-3
        -- A small but important distinction that has made writing this module frustrating because no documentation notates this.
        writeUnsigned(mantissaWidth, mantissa)
    end

    local function writeBase64(input)
        assert(type(input) == "string", "argument #1 to BitBuffer.writeBase64 should be a string")
        assert(
            not string.find(input, "[^%w%+/=]"),
            "argument #1 to BitBuffer.writeBase64 should only contain valid base64 characters"
        )

        for i = 1, #input, 4 do
            local b1, b2, b3, b4 = string.byte(input, i, i + 3)

            b1 = decode_char_set[b1]
            b2 = decode_char_set[b2]
            b3 = decode_char_set[b3]
            b4 = decode_char_set[b4]

            local packed = bit32.bor(bit32.lshift(b1, 18), bit32.lshift(b2, 12), bit32.lshift(b3 or 0, 6), b4 or 0)

            writeByte(bit32.rshift(packed, 16))
            if not b3 then
                break
            end
            writeByte(bit32.band(bit32.rshift(packed, 8), 0xff))
            if not b4 then
                break
            end
            writeByte(bit32.band(packed, 0xff))
        end
    end

    local function writeString(str)
        assert(type(str) == "string", "argument #1 to BitBuffer.writeString  should be a string")
        -- The default mode of writing strings is length-prefixed.
        -- This means that the length of the string is written before the contents of the string.
        -- For the sake of speed it has to be an even byte.
        -- One and two bytes is too few characters (255 bytes and 65535 bytes respectively), so it has to be higher.
        -- Three bytes is roughly 16.77mb, and four is roughly 4.295gb. Given this is Lua and is thus unlikely to be processing strings
        -- that large, this function uses three bytes, or 24 bits for the length

        writeUnsigned(24, #str)

        for i = 1, #str do
            writeByte(string.byte(str, i, i))
        end
    end

    local function writeTerminatedString(str)
        assert(type(str) == "string", "argument #1 to BitBuffer.writeTerminatedString should be a string")
        -- This function writes strings that are null-terminated.
        -- Null-terminated strings are strings of bytes that end in a 0 byte (\0)
        -- This isn't the default because it doesn't allow for binary data to be written cleanly.

        for i = 1, #str do
            writeByte(string.byte(str, i, i))
        end
        writeByte(0)
    end

    local function writeSetLengthString(str)
        assert(type(str) == "string", "argument #1 to BitBuffer.writeSetLengthString should be a string")
        -- This function writes strings as a pure string of bytes
        -- It doesn't store any data about the length of the string,
        -- so reading it requires knowledge of how many characters were stored

        for i = 1, #str do
            writeByte(string.byte(str, i, i))
        end
    end

    local function writeField(...)
        -- This is equivalent to having a writeBitfield function.
        -- It combines all of the passed 'bits' into an unsigned number, then writes it.
        local field = 0
        local bools = table.pack(...)
        for i = 1, bools.n do
            field = field * 2 -- Shift `field`. Equivalent to field<<1. At the beginning of the loop to avoid an extra shift.

            local v = bools[i]
            if v then
                field = field + 1 -- If the bit is truthy, turn it on (it defaults to off so it's fine to not have a branch)
            end
        end

        writeUnsigned(bools.n, field)
    end

    -- All write functions below here are shorthands. For the sake of performance, these functions are implemented manually.
    -- As an example, while it would certainly be easier to make `writeInt16(n)` just call `writeUnsigned(16, n),
    -- it's more performant to just manually call writeByte twice for it.

    local function writeUInt8(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeUInt8 should be a number")
        assert(n >= 0 and n <= 255, "argument #1 to BitBuffer.writeUInt8 should be in the range [0, 255]")
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeUInt8 should be an integer")

        writeByte(n)
    end

    local function writeUInt16(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeUInt16 should be a number")
        assert(n >= 0 and n <= 65535, "argument #1 to BitBuffer.writeInt16 should be in the range [0, 65535]")
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeUInt16 should be an integer")

        writeByte(bit32.rshift(n, 8))
        writeByte(bit32.band(n, 255))
    end

    local function writeUInt32(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeUInt32 should be a number")
        assert(
            n >= 0 and n <= 4294967295,
            "argument #1 to BitBuffer.writeUInt32 should be in the range [0, 4294967295]"
        )
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeUInt32 should be an integer")

        writeByte(bit32.rshift(n, 24))
        writeByte(bit32.band(bit32.rshift(n, 16), 255))
        writeByte(bit32.band(bit32.rshift(n, 8), 255))
        writeByte(bit32.band(n, 255))
    end

    local function writeInt8(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeInt8 should be a number")
        assert(n >= -128 and n <= 127, "argument #1 to BitBuffer.writeInt8 should be in the range [-128, 127]")
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeInt8 should be an integer")

        if n < 0 then
            n = (128 + n) + 128
        end

        writeByte(n)
    end

    local function writeInt16(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeInt16 should be a number")
        assert(n >= -32768 and n <= 32767, "argument #1 to BitBuffer.writeInt16 should be in the range [-32768, 32767]")
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeInt16 should be an integer")

        if n < 0 then
            n = (32768 + n) + 32768
        end

        writeByte(bit32.rshift(n, 8))
        writeByte(bit32.band(n, 255))
    end

    local function writeInt32(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeInt32 should be a number")
        assert(
            n >= -2147483648 and n <= 2147483647,
            "argument #1 to BitBuffer.writeInt32 should be in the range [-2147483648, 2147483647]"
        )
        assert(n % 1 == 0, "argument #1 to BitBuffer.writeInt32 should be an integer")

        if n < 0 then
            n = (2147483648 + n) + 2147483648
        end

        writeByte(bit32.rshift(n, 24))
        writeByte(bit32.band(bit32.rshift(n, 16), 255))
        writeByte(bit32.band(bit32.rshift(n, 8), 255))
        writeByte(bit32.band(n, 255))
    end

    local function writeFloat16(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeFloat16 should be a number")

        local sign = n < 0
        n = math.abs(n)

        local mantissa, exponent = math.frexp(n)

        if n == math.huge then
            if sign then
                writeByte(252) -- 11111100
            else
                writeByte(124) -- 01111100
            end
            writeByte(0) -- 00000000
            return
        elseif n ~= n then
            -- 01111111 11111111
            writeByte(127)
            writeByte(255)
            return
        elseif n == 0 then
            writeByte(0)
            writeByte(0)
            return
        elseif exponent + 15 <= 1 then -- Bias for halfs is 15
            mantissa = math.floor(mantissa * 1024 + 0.5)
            if sign then
                writeByte(128 + bit32.rshift(mantissa, 8)) -- Sign bit, 5 empty bits, 2 from mantissa
            else
                writeByte(bit32.rshift(mantissa, 8))
            end
            writeByte(bit32.band(mantissa, 255)) -- Get last 8 bits from mantissa
            return
        end

        mantissa = math.floor((mantissa - 0.5) * 2048 + 0.5)

        -- The bias for halfs is 15, 15-1 is 14
        if sign then
            writeByte(128 + bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8))
        else
            writeByte(bit32.lshift(exponent + 14, 2) + bit32.rshift(mantissa, 8))
        end
        writeByte(bit32.band(mantissa, 255))
    end

    local function writeFloat32(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeFloat32 should be a number")

        local sign = n < 0
        n = math.abs(n)

        local mantissa, exponent = math.frexp(n)

        if n == math.huge then
            if sign then
                writeByte(255) -- 11111111
            else
                writeByte(127) -- 01111111
            end
            writeByte(128) -- 10000000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            return
        elseif n ~= n then
            -- 01111111 11111111 11111111 11111111
            writeByte(127)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            return
        elseif n == 0 then
            writeByte(0)
            writeByte(0)
            writeByte(0)
            writeByte(0)
            return
        elseif exponent + 127 <= 1 then -- bias for singles is 127
            mantissa = math.floor(mantissa * 8388608 + 0.5)
            if sign then
                writeByte(128) -- Sign bit, 7 empty bits for exponent
            else
                writeByte(0)
            end
            writeByte(bit32.rshift(mantissa, 16))
            writeByte(bit32.band(bit32.rshift(mantissa, 8), 255))
            writeByte(bit32.band(mantissa, 255))
            return
        end

        mantissa = math.floor((mantissa - 0.5) * 16777216 + 0.5)

        -- 127-1 = 126
        if sign then -- sign + 7 exponent
            writeByte(128 + bit32.rshift(exponent + 126, 1))
        else
            writeByte(bit32.rshift(exponent + 126, 1))
        end
        writeByte(bit32.band(bit32.lshift(exponent + 126, 7), 255) + bit32.rshift(mantissa, 16)) -- 1 exponent + 7 mantissa
        writeByte(bit32.band(bit32.rshift(mantissa, 8), 255)) -- 8 mantissa
        writeByte(bit32.band(mantissa, 255)) -- 8 mantissa
    end

    local function writeFloat64(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.writeFloat64 should be a number")

        local sign = n < 0
        n = math.abs(n)

        local mantissa, exponent = math.frexp(n)

        if n == math.huge then
            if sign then
                writeByte(255) -- 11111111
            else
                writeByte(127) -- 01111111
            end
            writeByte(240) -- 11110000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            writeByte(0) -- 00000000
            return
        elseif n ~= n then
            -- 01111111 11111111 11111111 11111111 11111111 11111111 11111111 11111111
            writeByte(127)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            writeByte(255)
            return
        elseif n == 0 then
            writeByte(0)
            return
        elseif exponent + 1023 <= 1 then -- bias for doubles is 1023
            mantissa = math.floor(mantissa * 4503599627370496 + 0.5)
            if sign then
                writeByte(128) -- Sign bit, 7 empty bits for exponent
            else
                writeByte(0)
            end

            -- This is labeled better below
            local leastSignificantChunk = mantissa % 0x100000000 -- 32 bits
            local mostSignificantChunk = math.floor(mantissa / 0x100000000) -- 20 bits

            writeByte(bit32.rshift(mostSignificantChunk, 16))
            writeByte(bit32.band(bit32.rshift(mostSignificantChunk, 8), 255))
            writeByte(bit32.band(mostSignificantChunk, 255))
            writeByte(bit32.rshift(leastSignificantChunk, 24))
            writeByte(bit32.band(bit32.rshift(leastSignificantChunk, 16), 255))
            writeByte(bit32.band(bit32.rshift(leastSignificantChunk, 8), 255))
            writeByte(bit32.band(leastSignificantChunk, 255))
            return
        end

        mantissa = math.floor((mantissa - 0.5) * 9007199254740992 + 0.5)

        --1023-1 = 1022
        if sign then
            writeByte(128 + bit32.rshift(exponent + 1022, 4)) -- shift out 4 of the bits in exponent
        else
            writeByte(bit32.rshift(exponent + 1022, 4)) -- 01000001 0110
        end
        -- Things start to get a bit wack here because the mantissa is 52 bits, so bit32 *can't* be used.
        -- As the Offspring once said... You gotta keep 'em seperated.
        local leastSignificantChunk = mantissa % 0x100000000 -- 32 bits
        local mostSignificantChunk = math.floor(mantissa / 0x100000000) -- 20 bits

        -- First, the last 4 bits of the exponent and the first 4 bits of the mostSignificantChunk:
        writeByte(bit32.band(bit32.lshift(exponent + 1022, 4), 255) + bit32.rshift(mostSignificantChunk, 16))
        -- Then, the next 16 bits:
        writeByte(bit32.band(bit32.rshift(mostSignificantChunk, 8), 255))
        writeByte(bit32.band(mostSignificantChunk, 255))
        -- Then... 4 bytes of the leastSignificantChunk
        writeByte(bit32.rshift(leastSignificantChunk, 24))
        writeByte(bit32.band(bit32.rshift(leastSignificantChunk, 16), 255))
        writeByte(bit32.band(bit32.rshift(leastSignificantChunk, 8), 255))
        writeByte(bit32.band(leastSignificantChunk, 255))
    end

    -- All write functions below here are Roblox specific datatypes.

    local function writeBrickColor(n)
        assert(typeof(n) == "BrickColor", "argument #1 to BitBuffer.writeBrickColor should be a BrickColor")

        writeUInt16(n.Number)
    end

    local function writeColor3(c3)
        assert(typeof(c3) == "Color3", "argument #1 to BitBuffer.writeColor3 should be a Color3")

        writeByte(math.floor(c3.R * 0xff + 0.5))
        writeByte(math.floor(c3.G * 0xff + 0.5))
        writeByte(math.floor(c3.B * 0xff + 0.5))
    end

    local function writeCFrame(cf)
        assert(typeof(cf) == "CFrame", "argument #1 to BitBuffer.writeCFrame should be a CFrame")
        -- CFrames can be rather lengthy (if stored naively, they would each be 48 bytes long) so some optimization is done here.
        -- Specifically, if a CFrame is axis-aligned (it's only rotated in 90 degree increments), the rotation matrix isn't stored.
        -- Instead, an 'id' for its orientation is generated and that's stored instead of the rotation.
        -- This means that for the most common rotations, only 13 bytes are used.
        -- The downside is that non-axis-aligned CFrames use 49 bytes instead of 48, but that's a small price to pay.

        local upVector = cf.UpVector
        local rightVector = cf.RightVector

        -- This is an easy trick to check if a CFrame is axis-aligned:
        -- Essentially, in order for a vector to be axis-aligned, two of the components have to be 0
        -- This means that the dot product between the vector and a vector of all 1s will be 1 (0*x = 0)
        -- Since these are all unit vectors, there is no other combination that results in 1.
        local rightAligned = math.abs(rightVector:Dot(ONES_VECTOR))
        local upAligned = math.abs(upVector:Dot(ONES_VECTOR))
        -- At least one of these two vectors is guaranteed to not result in 0.

        local axisAligned = (math.abs(1 - rightAligned) < 0.00001 or rightAligned == 0)
            and (math.abs(1 - upAligned) < 0.00001 or upAligned == 0)
        -- There are limitations to `math.abs(a-b) < epsilon` but they're not relevant:
        -- The range of numbers is [0, 1] and this just needs to know if the number is approximately 1

        --todo special code for quaternions (0x01 in Roblox's format, would clash with 0x00 here)
        if axisAligned then
            local position = cf.Position
            -- The ID of an orientation is generated through what can best be described as 'hand waving';
            -- This is how Roblox does it and it works, so it was chosen to do it this way too.
            local rightNormal, upNormal
            for i = 0, 5 do
                local v = NORMAL_ID_VECTORS[i]
                if 1 - v:Dot(rightVector) < 0.00001 then
                    rightNormal = i
                end
                if 1 - v:Dot(upVector) < 0.00001 then
                    upNormal = i
                end
            end
            -- The ID generated here is technically off by 1 from what Roblox would store, but that's not important
            -- It just means that 0x02 is actually 0x01 for the purposes of this module's implementation.
            writeByte(rightNormal * 6 + upNormal)
            writeFloat32(position.X)
            writeFloat32(position.Y)
            writeFloat32(position.Z)
        else
            -- If the CFrame isn't axis-aligned, the entire rotation matrix has to be written...
            writeByte(0) -- Along with a byte to indicate the matrix was written.
            local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
            writeFloat32(x)
            writeFloat32(y)
            writeFloat32(z)
            writeFloat32(r00)
            writeFloat32(r01)
            writeFloat32(r02)
            writeFloat32(r10)
            writeFloat32(r11)
            writeFloat32(r12)
            writeFloat32(r20)
            writeFloat32(r21)
            writeFloat32(r22)
        end
    end

    local function writeVector3(v3)
        assert(typeof(v3) == "Vector3", "argument #1 to BitBuffer.writeVector3 should be a Vector3")

        writeFloat32(v3.X)
        writeFloat32(v3.Y)
        writeFloat32(v3.Z)
    end

    local function writeVector2(v2)
        assert(typeof(v2) == "Vector2", "argument #1 to BitBuffer.writeVector2 should be a Vector2")

        writeFloat32(v2.X)
        writeFloat32(v2.Y)
    end

    local function writeUDim2(u2)
        assert(typeof(u2) == "UDim2", "argument #1 to BitBuffer.writeUDim2 should be a UDim2")

        writeFloat32(u2.X.Scale)
        writeInt32(u2.X.Offset)
        writeFloat32(u2.Y.Scale)
        writeInt32(u2.Y.Offset)
    end

    local function writeUDim(u)
        assert(typeof(u) == "UDim", "argument #1 to BitBuffer.writeUDim should be a UDim")

        writeFloat32(u.Scale)
        writeInt32(u.Offset)
    end

    local function writeRay(ray)
        assert(typeof(ray) == "Ray", "argument #1 to BitBuffer.writeRay should be a Ray")

        writeFloat32(ray.Origin.X)
        writeFloat32(ray.Origin.Y)
        writeFloat32(ray.Origin.Z)

        writeFloat32(ray.Direction.X)
        writeFloat32(ray.Direction.Y)
        writeFloat32(ray.Direction.Z)
    end

    local function writeRect(rect)
        assert(typeof(rect) == "Rect", "argument #1 to BitBuffer.writeRect should be a Rect")

        writeFloat32(rect.Min.X)
        writeFloat32(rect.Min.Y)

        writeFloat32(rect.Max.X)
        writeFloat32(rect.Max.Y)
    end

    local function writeRegion3(region)
        assert(typeof(region) == "Region3", "argument #1 to BitBuffer.writeRegion3 should be a Region3")

        local min = region.CFrame.Position - (region.Size / 2)
        local max = region.CFrame.Position + (region.Size / 2)

        writeFloat32(min.X)
        writeFloat32(min.Y)
        writeFloat32(min.Z)

        writeFloat32(max.X)
        writeFloat32(max.Y)
        writeFloat32(max.Z)
    end

    local function writeEnum(enum)
        assert(typeof(enum) == "EnumItem", "argument #1 to BitBuffer.writeEnum should be an EnumItem")

        -- Relying upon tostring is generally not good, but there's not any other options for this.
        writeTerminatedString(tostring(enum.EnumType))
        writeUInt16(enum.Value) -- Optimistically assuming no Roblox Enum value will ever pass 65,535
    end

    local function writeNumberRange(range)
        assert(typeof(range) == "NumberRange", "argument #1 to BitBuffer.writeNumberRange should be a NumberRange")

        writeFloat32(range.Min)
        writeFloat32(range.Max)
    end

    local function writeNumberSequence(sequence)
        assert(
            typeof(sequence) == "NumberSequence",
            "argument #1 to BitBuffer.writeNumberSequence should be a NumberSequence"
        )

        writeUInt32(#sequence.Keypoints)
        for _, keypoint in ipairs(sequence.Keypoints) do
            writeFloat32(keypoint.Time)
            writeFloat32(keypoint.Value)
            writeFloat32(keypoint.Envelope)
        end
    end

    local function writeColorSequence(sequence)
        assert(
            typeof(sequence) == "ColorSequence",
            "argument #1 to BitBuffer.writeColorSequence should be a ColorSequence"
        )

        writeUInt32(#sequence.Keypoints)
        for _, keypoint in ipairs(sequence.Keypoints) do
            local c3 = keypoint.Value
            writeFloat32(keypoint.Time)
            writeByte(math.floor(c3.R * 0xff + 0.5))
            writeByte(math.floor(c3.G * 0xff + 0.5))
            writeByte(math.floor(c3.B * 0xff + 0.5))
        end
    end

    -- These are the read functions for the 'abstract' data types. At the bottom, there are shorthand read functions.

    local function readBits(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.readBits should be a number")
        assert(n > 0, "argument #1 to BitBuffer.readBits should be greater than zero")
        assert(n % 1 == 0, "argument #1 to BitBuffer.readBits should be an integer")

        assert(pointer + n <= bitCount, "BitBuffer.readBits cannot read past the end of the stream")

        -- The first of two main functions for the actual 'reading' of the bitbuffer.
        -- Reads `n` bits and returns an array of their values.
        local output = table.create(n) --!
        local byte = bytes[pointerByte] -- For the sake of efficiency, the current byte that the bits are coming from is stored
        local c = pointer % 8 -- A counter is set with the current position of the pointer in the byte
        for i = 1, n do
            -- Then, it's as easy as moving through the bits of the byte
            -- And getting the individiual bit values
            local pow = powers_of_2[7 - c]
            output[i] = BOOL_TO_BIT[bit32.btest(byte, pow)] -- Test if a bit is on by &ing it by 2^[bit position]
            c = c + 1
            if c == 8 then -- If the byte boundary is reached, increment pointerByte and store the new byte in `byte`
                pointerByte = pointerByte + 1
                byte = bytes[pointerByte]
                c = 0
            end
        end
        pointer = pointer + n -- Move the pointer forward
        return output
    end

    local function readByte()
        assert(pointer + 8 <= bitCount, "BitBuffer.readByte cannot read past the end of the stream")
        -- The second of two main functions for the actual 'reading' of the bitbuffer.
        -- Reads a byte and returns it
        local c = pointer % 8 -- How far into the pointerByte the pointer is
        local byte1 = bytes[pointerByte] -- The pointerByte
        pointer = pointer + 8
        if c == 0 then -- Trivial if the pointer is at the beginning of the pointerByte
            pointerByte = pointerByte + 1
            return byte1
        else
            pointerByte = pointerByte + 1
            -- Get the remainder of the first pointerByte and add it to the part of the new pointerByte that's required
            -- Both these methods are explained in writeByte
            return bit32.band(bit32.lshift(byte1, c), 255) + bit32.rshift(bytes[pointerByte], 8 - c)
        end
    end

    local function readUnsigned(width)
        assert(type(width) == "number", "argument #1 to BitBuffer.readUnsigned should be a number")
        assert(width >= 1 and width <= 64, "argument #1 to BitBuffer.readUnsigned should be in the range [1, 64]")
        assert(width % 1 == 0, "argument #1 to BitBuffer.readUnsigned should be an integer")

        assert(pointer + width <= bitCount, "BitBuffer.readUnsigned cannot read past the end of the stream")
        -- Implementing this on its own was considered because of a worry that it would be inefficient to call
        -- readByte and readBit several times, but it was decided the simplicity is worth a minor performance hit.
        local bytesInN, bitsInN = math.floor(width / 8), width % 8

        -- No check is required for if the width is greater than 32 because bit32 isn't used.
        local n = 0
        -- Shift and add a read byte however many times is necessary
        -- Adding after shifting is importnat - it prevents there from being 8 empty bits of space
        for _ = 1, bytesInN do
            n = n * 0x100 -- 2^8; equivalent to n << 8
            n = n + readByte()
        end
        -- The bits are then read and added to the number
        if bitsInN ~= 0 then
            for _, v in ipairs(readBits(width % 8)) do --todo benchmark against concat+tonumber; might be worth the code smell
                n = n * 2
                n = n + v
            end
        end
        return n
    end

    local function readSigned(width)
        assert(type(width) == "number", "argument #1 to BitBuffer.readSigned should be a number")
        assert(width >= 2 and width <= 64, "argument #1 to BitBuffer.readSigned should be in the range [2, 64]")
        assert(width % 1 == 0, "argument #1 to BitBuffer.readSigned should be an integer")

        assert(pointer + 8 <= bitCount, "BitBuffer.readSigned cannot read past the end of the stream")
        local sign = readBits(1)[1]
        local n = readUnsigned(width - 1) -- Again, width-1 is because one bit is used for the sign

        -- As said in writeSigned, the written number is unmodified if the number is positive (the sign bit is 0)
        if sign == 0 then
            return n
        else
            -- And the number is equal to max value of the width + the number if the number is negative (the sign bit is 1)
            -- To reverse that, the max value is subtracted from the stored number.
            return n - powers_of_2[width - 1]
        end
    end

    local function readFloat(exponentWidth, mantissaWidth)
        assert(type(exponentWidth) == "number", "argument #1 to BitBuffer.readFloat should be a number")
        assert(
            exponentWidth >= 1 and exponentWidth <= 64,
            "argument #1 to BitBuffer.readFloat should be in the range [1, 64]"
        )
        assert(exponentWidth % 1 == 0, "argument #1 to BitBuffer.readFloat should be an integer")

        assert(type(mantissaWidth) == "number", "argument #2 to BitBuffer.readFloat should be a number")
        assert(
            mantissaWidth >= 1 and mantissaWidth <= 64,
            "argument #2 to BitBuffer.readFloat should be in the range [1, 64]"
        )
        assert(mantissaWidth % 1 == 0, "argument #2 to BitBuffer.readFloat should be an integer")

        assert(
            pointer + exponentWidth + mantissaWidth + 1 <= bitCount,
            "BitBuffer.readFloat cannot read past the end of the stream"
        )
        -- Recomposing floats is rather straightfoward.
        -- The bias is subtracted from the exponent, the mantissa is shifted back by mantissaWidth, one is added to the mantissa
        -- and the whole thing is recomposed with math.ldexp (this is identical to mantissa*(2^exponent)).

        local bias = powers_of_2[exponentWidth - 1] - 1

        local sign = readBits(1)[1]
        local exponent = readUnsigned(exponentWidth)
        local mantissa = readUnsigned(mantissaWidth)

        -- Before normal numbers are handled though, special cases and subnormal numbers are once again handled seperately
        if exponent == powers_of_2[exponentWidth] - 1 then
            if mantissa ~= 0 then -- If the exponent is all 1s and the mantissa isn't zero, the number is NaN
                return 0 / 0
            else -- Otherwise, it's positive or negative infinity
                return sign == 0 and math.huge or -math.huge
            end
        elseif exponent == 0 then
            if mantissa == 0 then -- If the exponent and mantissa are both zero, the number is zero.
                return 0
            else -- If the exponent is zero and the mantissa is not zero, the number is subnormal
                -- Subnormal numbers are straightforward: shifting the mantissa so that it's a fraction is all that's required
                mantissa = mantissa / powers_of_2[mantissaWidth]

                -- Since the exponent is 0, it's actual value is just -bias (it would be exponent-bias)
                -- As previously touched on in writeFloat, the exponent value is off by 1 in Lua though.
                return sign == 1 and -math.ldexp(mantissa, -bias + 1) or math.ldexp(mantissa, -bias + 1)
            end
        end

        -- First, the mantissa is shifted back by the mantissaWidth
        -- Then, 1 is added to it to 'normalize' it.
        mantissa = (mantissa / powers_of_2[mantissaWidth]) + 1

        -- Because the mantissa is normalized above (the leading 1 is in the ones place), it's accurate to say exponent-bias
        return sign == 1 and -math.ldexp(mantissa, exponent - bias) or math.ldexp(mantissa, exponent - bias)
    end

    local function readString()
        assert(pointer + 24 <= bitCount, "BitBuffer.readString cannot read past the end of the stream")
        -- Reading a length-prefixed string is rather straight forward.
        -- The length is read, then that many bytes are read and put in a string.

        local stringLength = readUnsigned(24)
        assert(pointer + (stringLength * 8) <= bitCount, "BitBuffer.readString cannot read past the end of the stream")

        local outputCharacters = table.create(stringLength) --!

        for i = 1, stringLength do
            outputCharacters[i] = readByte()
        end

        local output = table.create(math.ceil(stringLength / 4096))
        local k = 1
        for i = 1, stringLength, 4096 do
            output[k] = string.char(table.unpack(outputCharacters, i, math.min(stringLength, i + 4095)))
            k = k + 1
        end

        return table.concat(output)
    end

    local function readTerminatedString()
        local outputCharacters = {}

        -- Bytes are read continuously until either a nul-character is reached or until the stream runs out.
        local length = 0
        while true do
            local byte = readByte()
            if not byte then -- Stream has ended
                error("BitBuffer.readTerminatedString cannot read past the end of the stream", 2)
            elseif byte == 0 then -- String has ended
                break
            else -- Add byte to string
                length = length + 1
                outputCharacters[length] = byte
            end
        end

        local output = table.create(math.ceil(length / 4096))
        local k = 1
        for l = 1, length, 4096 do
            output[k] = string.char(table.unpack(outputCharacters, l, math.min(length, l + 4095)))
            k = k + 1
        end

        return table.concat(output)
    end

    local function readSetLengthString(length)
        assert(type(length) == "number", "argument #1 to BitBuffer.readSetLengthString should be a number")
        assert(length >= 0, "argument #1 to BitBuffer.readSetLengthString should be zero or higher.")
        assert(length % 1 == 0, "argument #1 to BitBuffer.readSetLengthString should be an integer")

        assert(
            pointer + (length * 8) <= bitCount,
            "BitBuffer.readSetLengthString cannot read past the end of the stream"
        )
        -- `length` number of bytes are read and put into a string

        local outputCharacters = table.create(length) --!

        for i = 1, length do
            outputCharacters[i] = readByte()
        end

        local output = table.create(math.ceil(length / 4096))
        local k = 1
        for i = 1, length, 4096 do
            output[k] = string.char(table.unpack(outputCharacters, i, math.min(length, i + 4095)))
            k = k + 1
        end

        return table.concat(output)
    end

    local function readField(n)
        assert(type(n) == "number", "argument #1 to BitBuffer.readField should be a number")
        assert(n > 0, "argument #1 to BitBuffer.readField should be above 0")
        assert(n % 1 == 0, "argument #1 to BitBuffer.readField should be an integer")

        assert(pointer + n <= bitCount, "BitBuffer.readField cannot read past the end of the stream")
        -- Reading a bit field is again rather simple. You read the actual field, then take the bits out.
        local readInt = readUnsigned(n)
        local output = table.create(n) --!

        for i = n, 1, -1 do -- In reverse order since we're pulling bits out from lsb to msb
            output[i] = readInt % 2 == 1 -- Equivalent to an extraction of the lsb
            readInt = math.floor(readInt / 2) -- Equivalent to readInt>>1
        end

        return output
    end

    -- All read functions below here are shorthands.
    -- As with their write variants, these functions are implemented manually using readByte for performance reasons.

    local function readUInt8()
        assert(pointer + 8 <= bitCount, "BitBuffer.readUInt8 cannot read past the end of the stream")

        return readByte()
    end

    local function readUInt16()
        assert(pointer + 16 <= bitCount, "BitBuffer.readUInt16 cannot read past the end of the stream")

        return bit32.lshift(readByte(), 8) + readByte()
    end

    local function readUInt32()
        assert(pointer + 32 <= bitCount, "BitBuffer.readUInt32 cannot read past the end of the stream")

        return bit32.lshift(readByte(), 24) + bit32.lshift(readByte(), 16) + bit32.lshift(readByte(), 8) + readByte()
    end

    local function readInt8()
        assert(pointer + 8 <= bitCount, "BitBuffer.readInt8 cannot read past the end of the stream")

        local n = readByte()
        local sign = bit32.btest(n, 128)
        n = bit32.band(n, 127)

        if sign then
            return n - 128
        else
            return n
        end
    end

    local function readInt16()
        assert(pointer + 16 <= bitCount, "BitBuffer.readInt16 cannot read past the end of the stream")

        local n = bit32.lshift(readByte(), 8) + readByte()
        local sign = bit32.btest(n, 32768)
        n = bit32.band(n, 32767)

        if sign then
            return n - 32768
        else
            return n
        end
    end

    local function readInt32()
        assert(pointer + 32 <= bitCount, "BitBuffer.readInt32 cannot read past the end of the stream")

        local n = bit32.lshift(readByte(), 24) + bit32.lshift(readByte(), 16) + bit32.lshift(readByte(), 8) + readByte()
        local sign = bit32.btest(n, 2147483648)
        n = bit32.band(n, 2147483647)

        if sign then
            return n - 2147483648
        else
            return n
        end
    end

    local function readFloat16()
        assert(pointer + 16 <= bitCount, "BitBuffer.readFloat16 cannot read past the end of the stream")

        local b0 = readByte()
        local sign = bit32.btest(b0, 128)
        local exponent = bit32.rshift(bit32.band(b0, 127), 2)
        local mantissa = bit32.lshift(bit32.band(b0, 3), 8) + readByte()

        if exponent == 31 then --2^5-1
            if mantissa ~= 0 then
                return 0 / 0
            else
                return sign and -math.huge or math.huge
            end
        elseif exponent == 0 then
            if mantissa == 0 then
                return 0
            else
                return sign and -math.ldexp(mantissa / 1024, -14) or math.ldexp(mantissa / 1024, -14)
            end
        end

        mantissa = (mantissa / 1024) + 1

        return sign and -math.ldexp(mantissa, exponent - 15) or math.ldexp(mantissa, exponent - 15)
    end

    local function readFloat32()
        assert(pointer + 32 <= bitCount, "BitBuffer.readFloat32 cannot read past the end of the stream")

        local b0 = readByte()
        local b1 = readByte()
        local sign = bit32.btest(b0, 128)
        local exponent = bit32.band(bit32.lshift(b0, 1), 255) + bit32.rshift(b1, 7)
        local mantissa = bit32.lshift(bit32.band(b1, 127), 23 - 7)
            + bit32.lshift(readByte(), 23 - 7 - 8)
            + bit32.lshift(readByte(), 23 - 7 - 8 - 8)

        if exponent == 255 then -- 2^8-1
            if mantissa ~= 0 then
                return 0 / 0
            else
                return sign and -math.huge or math.huge
            end
        elseif exponent == 0 then
            if mantissa == 0 then
                return 0
            else
                -- -126 is the 0-bias+1
                return sign and -math.ldexp(mantissa / 8388608, -126) or math.ldexp(mantissa / 8388608, -126)
            end
        end

        mantissa = (mantissa / 8388608) + 1

        return sign and -math.ldexp(mantissa, exponent - 127) or math.ldexp(mantissa, exponent - 127)
    end

    local function readFloat64()
        assert(pointer + 64 <= bitCount, "BitBuffer.readFloat64 cannot read past the end of the stream")

        local b0 = readByte()
        local b1 = readByte()

        local sign = bit32.btest(b0, 128)
        local exponent = bit32.lshift(bit32.band(b0, 127), 4) + bit32.rshift(b1, 4)
        local mostSignificantChunk = bit32.lshift(bit32.band(b1, 15), 16) + bit32.lshift(readByte(), 8) + readByte()
        local leastSignificantChunk = bit32.lshift(readByte(), 24)
            + bit32.lshift(readByte(), 16)
            + bit32.lshift(readByte(), 8)
            + readByte()

        -- local mantissa = (bit32.lshift(bit32.band(b1, 15), 16)+bit32.lshift(readByte(), 8)+readByte())*0x100000000+
        --     bit32.lshift(readByte(), 24)+bit32.lshift(readByte(), 16)+bit32.lshift(readByte(), 8)+readByte()

        local mantissa = mostSignificantChunk * 0x100000000 + leastSignificantChunk

        if exponent == 2047 then -- 2^11-1
            if mantissa ~= 0 then
                return 0 / 0
            else
                return sign and -math.huge or math.huge
            end
        elseif exponent == 0 then
            if mantissa == 0 then
                return 0
            else
                return sign and -math.ldexp(mantissa / 4503599627370496, -1022)
                    or math.ldexp(mantissa / 4503599627370496, -1022)
            end
        end

        mantissa = (mantissa / 4503599627370496) + 1

        return sign and -math.ldexp(mantissa, exponent - 1023) or math.ldexp(mantissa, exponent - 1023)
    end

    -- All read functions below here are Roblox specific datatypes.

    local function readBrickColor()
        assert(pointer + 16 <= bitCount, "BitBuffer.readBrickColor cannot read past the end of the stream")

        return BrickColor.new(readUInt16())
    end

    local function readColor3()
        assert(pointer + 24 <= bitCount, "BitBuffer.readColor3 cannot read past the end of the stream")

        return Color3.fromRGB(readByte(), readByte(), readByte())
    end

    local function readCFrame()
        assert(pointer + 8 <= bitCount, "BitBuffer.readCFrame cannot read past the end of the stream")

        local id = readByte()

        if id == 0 then
            assert(pointer + 384 <= bitCount, "BitBuffer.readCFrame cannot read past the end of the stream") -- 4*12 bytes = 383 bits

            -- stylua: ignore
            return CFrame.new(
                readFloat32(), readFloat32(), readFloat32(),
                readFloat32(), readFloat32(), readFloat32(),
                readFloat32(), readFloat32(), readFloat32(),
                readFloat32(), readFloat32(), readFloat32()
            )
        else
            assert(pointer + 96 <= bitCount, "BitBuffer.readCFrame cannot read past the end of the stream") -- 4*3 bytes = 96 bits

            local rightVector = NORMAL_ID_VECTORS[math.floor(id / 6)]
            local upVector = NORMAL_ID_VECTORS[id % 6]
            local lookVector = rightVector:Cross(upVector)

            -- CFrame's full-matrix constructor takes right/up/look vectors as columns...
            -- stylua: ignore
            return CFrame.new(
                readFloat32(), readFloat32(), readFloat32(),
                rightVector.X, upVector.X, lookVector.X,
                rightVector.Y, upVector.Y, lookVector.Y,
                rightVector.Z, upVector.Z, lookVector.Z
            )
        end
    end

    local function readVector3()
        assert(pointer + 96 <= bitCount, "BitBuffer.readVector3 cannot read past the end of the stream")

        return Vector3.new(readFloat32(), readFloat32(), readFloat32())
    end

    local function readVector2()
        assert(pointer + 64 <= bitCount, "BitBuffer.readVector2 cannot read past the end of the stream")

        return Vector2.new(readFloat32(), readFloat32())
    end

    local function readUDim2()
        assert(pointer + 128 <= bitCount, "BitBuffer.readUDim2 cannot read past the end of the stream")

        return UDim2.new(readFloat32(), readInt32(), readFloat32(), readInt32())
    end

    local function readUDim()
        assert(pointer + 64 <= bitCount, "BitBuffer.readUDim cannot read past the end of the stream")

        return UDim.new(readFloat32(), readInt32())
    end

    local function readRay()
        assert(pointer + 192 <= bitCount, "BitBuffer.readRay cannot read past the end of the stream")

        return Ray.new(
            Vector3.new(readFloat32(), readFloat32(), readFloat32()),
            Vector3.new(readFloat32(), readFloat32(), readFloat32())
        )
    end

    local function readRect()
        assert(pointer + 128 <= bitCount, "BitBuffer.readRect cannot read past the end of the stream")

        return Rect.new(readFloat32(), readFloat32(), readFloat32(), readFloat32())
    end

    local function readRegion3()
        assert(pointer + 192 <= bitCount, "BitBuffer.readRegion3 cannot read past the end of the stream")

        return Region3.new(
            Vector3.new(readFloat32(), readFloat32(), readFloat32()),
            Vector3.new(readFloat32(), readFloat32(), readFloat32())
        )
    end

    local function readEnum()
        assert(pointer + 8 <= bitCount, "BitBuffer.readEnum cannot read past the end of the stream")

        local name = readTerminatedString() -- This might expose an error from readString to the end-user but it's not worth the hassle to fix.

        assert(pointer + 16 <= bitCount, "BitBuffer.readEnum cannot read past the end of the stream")

        local value = readUInt16() -- Again, optimistically assuming no Roblox Enum value will ever pass 65,535

        -- Catching a potential error only to throw it with different formatting seems... Superfluous.
        -- Open an issue on github if you feel otherwise.
        for _, v in ipairs(Enum[name]:GetEnumItems()) do
            if v.Value == value then
                return v
            end
        end

        error(
            "BitBuffer.readEnum could not get value: `"
                .. tostring(value)
                .. "` is not a valid member of `"
                .. name
                .. "`",
            2
        )
    end

    local function readNumberRange()
        assert(pointer + 64 <= bitCount, "BitBuffer.readNumberRange cannot read past the end of the stream")

        return NumberRange.new(readFloat32(), readFloat32())
    end

    local function readNumberSequence()
        assert(pointer + 32 <= bitCount, "BitBuffer.readNumberSequence cannot read past the end of the stream")

        local keypointCount = readUInt32()

        assert(pointer + keypointCount * 96, "BitBuffer.readColorSequence cannot read past the end of the stream")

        local keypoints = table.create(keypointCount)

        -- As it turns out, creating a NumberSequence with a negative value as its first argument (in the first and second constructor)
        -- creates NumberSequenceKeypoints with negative envelopes. The envelope is read and saved properly, as you would expect,
        -- but you can't create a NumberSequence with a negative envelope if you're using a table of keypoints (which is happening here).
        -- If you're confused, run this snippet: NumberSequence.new(NumberSequence.new(-1).Keypoints)
        -- As a result, there has to be some branching logic in this function.
        -- ColorSequences don't have envelopes so it's not necessary for them.

        for i = 1, keypointCount do
            local time, value, envelope = readFloat32(), readFloat32(), readFloat32()
            if value < 0 then
                envelope = nil
            end
            keypoints[i] = NumberSequenceKeypoint.new(time, value, envelope)
        end

        return NumberSequence.new(keypoints)
    end

    local function readColorSequence()
        assert(pointer + 32 <= bitCount, "BitBuffer.readColorSequence cannot read past the end of the stream")

        local keypointCount = readUInt32()

        assert(pointer + keypointCount * 56, "BitBuffer.readColorSequence cannot read past the end of the stream")

        local keypoints = table.create(keypointCount)

        for i = 1, keypointCount do
            keypoints[i] = ColorSequenceKeypoint.new(readFloat32(), Color3.fromRGB(readByte(), readByte(), readByte()))
        end

        return ColorSequence.new(keypoints)
    end

    return {
        dumpBinary = dumpBinary,
        dumpString = dumpString,
        dumpHex = dumpHex,
        dumpBase64 = dumpBase64,
        exportChunk = exportChunk,
        exportBase64Chunk = exportBase64Chunk,
        exportHexChunk = exportHexChunk,

        crc32 = crc32,
        getLength = getLength,
        getByteLength = getByteLength,
        getPointer = getPointer,
        setPointer = setPointer,
        setPointerFromEnd = setPointerFromEnd,
        getPointerByte = getPointerByte,
        setPointerByte = setPointerByte,
        setPointerByteFromEnd = setPointerByteFromEnd,
        isFinished = isFinished,

        writeBits = writeBits,
        writeByte = writeByte,
        writeUnsigned = writeUnsigned,
        writeSigned = writeSigned,
        writeFloat = writeFloat,
        writeBase64 = writeBase64,
        writeString = writeString,
        writeTerminatedString = writeTerminatedString,
        writeSetLengthString = writeSetLengthString,
        writeField = writeField,

        writeUInt8 = writeUInt8,
        writeUInt16 = writeUInt16,
        writeUInt32 = writeUInt32,
        writeInt8 = writeInt8,
        writeInt16 = writeInt16,
        writeInt32 = writeInt32,

        writeFloat16 = writeFloat16,
        writeFloat32 = writeFloat32,
        writeFloat64 = writeFloat64,

        writeBrickColor = writeBrickColor,
        writeColor3 = writeColor3,
        writeCFrame = writeCFrame,
        writeVector3 = writeVector3,
        writeVector2 = writeVector2,
        writeUDim2 = writeUDim2,
        writeUDim = writeUDim,
        writeRay = writeRay,
        writeRect = writeRect,
        writeRegion3 = writeRegion3,
        writeEnum = writeEnum,
        writeNumberRange = writeNumberRange,
        writeNumberSequence = writeNumberSequence,
        writeColorSequence = writeColorSequence,

        readBits = readBits,
        readByte = readByte,
        readUnsigned = readUnsigned,
        readSigned = readSigned,
        readFloat = readFloat,
        readString = readString,
        readTerminatedString = readTerminatedString,
        readSetLengthString = readSetLengthString,
        readField = readField,

        readUInt8 = readUInt8,
        readUInt16 = readUInt16,
        readUInt32 = readUInt32,
        readInt8 = readInt8,
        readInt16 = readInt16,
        readInt32 = readInt32,

        readFloat16 = readFloat16,
        readFloat32 = readFloat32,
        readFloat64 = readFloat64,

        readBrickColor = readBrickColor,
        readColor3 = readColor3,
        readCFrame = readCFrame,
        readVector3 = readVector3,
        readVector2 = readVector2,
        readUDim2 = readUDim2,
        readUDim = readUDim,
        readRay = readRay,
        readRect = readRect,
        readRegion3 = readRegion3,
        readEnum = readEnum,
        readNumberRange = readNumberRange,
        readNumberSequence = readNumberSequence,
        readColorSequence = readColorSequence,
    }
end

return bitBuffer
