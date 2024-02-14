--!native
local module = {}

local UnreliableRemoteEvent = game.ReplicatedStorage:WaitForChild("ChickynoidUnreliableReplication") :: RemoteEvent

local path = game.ReplicatedFirst.Packages.Chickynoid
local Profiler = require(path.Shared.Vendor.Profiler)
local CharacterData = require(path.Shared.Simulation.CharacterData)

local DeltaTable = require(path.Shared.Vendor.DeltaTable)
local RemotePacketSizeCounter = require(path.Shared.Vendor.RemotePacketSizeCounter)
local Enums = require(path.Shared.Enums)
local EventType = Enums.EventType
local absoluteMaxSizeOfBuffer = 4096
local smallBufferSize = 64
local timeToKeepCache = 30 --in frames
local doCRC = false

local cache = {} 

local function GetCacheItem(otherUserId, serverFrame, comparisonFrame)
	
	local cacheLine = cache[otherUserId]
	if (cacheLine == nil) then
		return nil
	end
	
	local rec = cacheLine[serverFrame]
	if (rec == nil) then
		return nil
	end
	
	if (comparisonFrame == nil) then
		return rec.raw
	end
	
	--we have to find the cache for compariston
	local subRec = rec.comparisons[comparisonFrame]
	return subRec
end

local function StoreCacheItem(otherUserId, serverFrame, comparisonFrame, cacheRec)
	
	local cacheLine = cache[otherUserId]
	if (cacheLine == nil) then
		cacheLine = {}
		cache[otherUserId] = cacheLine
	end
	
	local rec = cacheLine[serverFrame]
	
	if (rec == nil) then
		local newRec = {}
		newRec.raw = cacheRec
		newRec.comparisons = {}
		cacheLine[serverFrame] = newRec
	else
		if (comparisonFrame == nil) then
			rec.raw = cacheRec
		else
			rec.comparisons[comparisonFrame] = cacheRec
		end
	end
	
	--Cleanup old records
	for timeStamp, record in cacheLine do
		if (timeStamp < serverFrame - timeToKeepCache) then
			cacheLine[timeStamp] = nil
		end
	end
end


local function CreateAndQueueSnapshotPacket(currentPacket, playerRecord, fullSnapshot, queue, serverTotalFrames, serverSimulationTime, comparisonFrame)
	local snapshot = {}
	snapshot.t = EventType.Snapshot
	snapshot.full = fullSnapshot
 
	local finalBuffer = buffer.create(currentPacket.offset) 
	buffer.copy(finalBuffer,0,currentPacket.writeBuffer,0,currentPacket.offset)
 
	snapshot.b = finalBuffer
	snapshot.f = serverTotalFrames
	snapshot.cf = comparisonFrame
	snapshot.serverTime = serverSimulationTime
	snapshot.s = #queue + 1
	table.insert(queue,snapshot)
end


function module:DoWork(playerRecords, serverTotalFrames, serverSimulationTime, debugBotBandwidth)
	
	Profiler:BeginSample("BuildSnapshots")
	
	--generate
	local tempQueues = {}
	local statistics = {}
	statistics.generated = 0
	statistics.cached = 0
	
	for userId,playerRecord in playerRecords do
		
		if (playerRecord.dummy == true and debugBotBandwidth == false) then
			continue
		end
		
		--Start building the final data
		local fullSnapshot = false
		fullSnapshot = true

		local currentPacket = nil
		local series = 0
		local queue = {}
		tempQueues[userId] = queue
		
		local comparisonFrame = playerRecord.lastConfirmedSnapshotServerFrame		
		
		--in case there are no other players visible
		currentPacket = {}
		currentPacket.writeBuffer = buffer.create(absoluteMaxSizeOfBuffer)
		currentPacket.offset = 1 --skip a byte to write the recordCound
		currentPacket.recordCount = 0
				
		local visList = playerRecord.visibilityList
		if (visList == nil) then
			visList = playerRecords
		end
		local comparisonVisList = playerRecord.visHistoryList[comparisonFrame]
		if (comparisonVisList == nil) then
			comparisonVisList = {} --Assume we couldn't see anything 
		end
		
		 
		for _,otherPlayerRecord in visList do
			
			local otherUserId = otherPlayerRecord.userId
			if (otherUserId == userId) then
				continue
			end

			if otherPlayerRecord.chickynoid == nil then
				continue
			end
						
			local characterData = otherPlayerRecord.chickynoid.simulation.characterData
			
			--Create a new packet?					
			if (currentPacket == nil) then
				currentPacket = {}
				currentPacket.writeBuffer = buffer.create(absoluteMaxSizeOfBuffer)
				currentPacket.offset = 1 --skip a byte to write the recordCound
				currentPacket.recordCount = 0
			end
			currentPacket.recordCount += 1
			
			local cachedBufferRec = nil
						
			--if we could see them last time, look up our delta to them
			local couldSeeThemLastTime = true
			if (comparisonVisList[otherUserId] == nil) then
				couldSeeThemLastTime = false
			end 
			
			if (couldSeeThemLastTime == true) then 
				cachedBufferRec = GetCacheItem(otherUserId, serverTotalFrames, comparisonFrame)
			end
			
			if (cachedBufferRec == nil) then
				--Generate the cached item
				local prevCharacterData = nil
				if (comparisonFrame ~= nil and couldSeeThemLastTime == true) then
					--Find the previous character data to compare to
					prevCharacterData = otherPlayerRecord.chickynoid.prevCharacterData[comparisonFrame]
				end
				local cacheRec = {}
				cacheRec.writeBuffer = buffer.create(smallBufferSize)
				buffer.writeu8(cacheRec.writeBuffer, 0, otherPlayerRecord.slot)
				cacheRec.offset = 1
				cacheRec.offset = CharacterData.SerializeToBitBuffer(characterData, prevCharacterData, cacheRec.writeBuffer, cacheRec.offset)
				
				if (prevCharacterData == nil) then
					--if its not deltacompressed, store it raw (comparisonFrame = nil)
					StoreCacheItem(otherUserId, serverTotalFrames, nil, cacheRec)
				else
					--store it and flag it as being a delta
					StoreCacheItem(otherUserId, serverTotalFrames, comparisonFrame, cacheRec)
				end
				cachedBufferRec = cacheRec
								
				statistics.generated+=1
			else
				--print("got cached ", comparisonFrame)
				statistics.cached += 1
			end
						
			buffer.copy(currentPacket.writeBuffer, currentPacket.offset, cachedBufferRec.writeBuffer, 0, cachedBufferRec.offset)
			currentPacket.offset+= cachedBufferRec.offset

			if (currentPacket.offset > 700) then
				--Send snapshot
				buffer.writeu8(currentPacket.writeBuffer, 0, currentPacket.recordCount)
				CreateAndQueueSnapshotPacket(currentPacket, playerRecord, fullSnapshot, queue, serverTotalFrames, serverSimulationTime, comparisonFrame)
				currentPacket = nil
			end
		end

		--Wasn't finished, so finish the last one
		if (currentPacket ~= nil) then
			buffer.writeu8(currentPacket.writeBuffer, 0, currentPacket.recordCount)
			CreateAndQueueSnapshotPacket(currentPacket, playerRecord, fullSnapshot, queue, serverTotalFrames, serverSimulationTime, comparisonFrame)
		end
	end
	
	for userId,playerRecord in playerRecords do

		if playerRecord.dummy == false then
			--Transmit!
			local queue = tempQueues[userId]

			for _,snapshot in queue do
				snapshot.m = #queue
				
				local s = RemotePacketSizeCounter.GetDataByteSize(event.playerStateDelta)
				if s > 700 then
					playerRecord:SendEventToClient(snapshot)
				else
					playerRecord:SendUnreliableEventToClient(snapshot)
				end
			end
		end
	end
	
	--print(statistics.generated, " vs ", statistics.cached)
	Profiler:EndSample()
end

return module