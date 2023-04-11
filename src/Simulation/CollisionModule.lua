local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local path = script.Parent.Parent

local MinkowskiSumInstance = require(script.Parent.MinkowskiSumInstance)
local TerrainModule = require(script.Parent.TerrainCollision)
local FastSignal = require(path.Vendor.FastSignal)

local module = {}
module.hullRecords = {}
module.dynamicRecords = {}

local SKIN_THICKNESS = 0.05 --closest you can get to a wall
module.planeNum = 0
module.gridSize = 4
module.fatGridSize = 16
module.fatPartSize = 32
module.profile = false

module.grid = {}
module.fatGrid = {}
module.cache = {}
module.cacheCount = 0
module.maxCacheCount = 10000

module.loadProgress = 0
module.OnLoadProgressChanged = FastSignal.new()

module.expansionSize = Vector3.new(2, 5, 2)

local debugParts = false

local corners = {
    Vector3.new(0.5, 0.5, 0.5),
    Vector3.new(0.5, 0.5, -0.5),
    Vector3.new(-0.5, 0.5, 0.5),
    Vector3.new(-0.5, 0.5, -0.5),
    Vector3.new(0.5, -0.5, 0.5),
    Vector3.new(0.5, -0.5, -0.5),
    Vector3.new(-0.5, -0.5, 0.5),
    Vector3.new(-0.5, -0.5, -0.5),
}

function module:FetchCell(x, y, z)
	local key = Vector3.new(x,y,z)
	return self.grid[key]
end

function module:FetchFatCell(x, y, z)
	local key = Vector3.new(x,y,z)
	return self.fatGrid[key]
end

function module:CreateAndFetchCell(x, y, z)
	local key = Vector3.new(x,y,z)
	local res = self.grid[key]
	if (res == nil) then
		res = {}
		self.grid[key] = res
	end
	return res
end

function module:CreateAndFetchFatCell(x, y, z)
	local key = Vector3.new(x,y,z)
	local res = self.fatGrid[key]
	if (res == nil) then
		res = {}
		self.fatGrid[key] = res
	end
	return res
end

function module:FindAABB(part)
    local orientation = part.CFrame
    local size = part.Size

    local minx = math.huge
    local miny = math.huge
    local minz = math.huge
    local maxx = -math.huge
    local maxy = -math.huge
    local maxz = -math.huge

    for _, corner in pairs(corners) do
        local vec = orientation * (size * corner)
        if vec.x < minx then
            minx = vec.x
        end
        if vec.y < miny then
            miny = vec.y
        end
        if vec.z < minz then
            minz = vec.z
        end
        if vec.x > maxx then
            maxx = vec.x
        end
        if vec.y > maxy then
            maxy = vec.y
        end
        if vec.z > maxz then
            maxz = vec.z
        end
    end
    return minx, miny, minz, maxx, maxy, maxz
end

function module:FindPointsAABB(points)
    local minx = math.huge
    local miny = math.huge
    local minz = math.huge
    local maxx = -math.huge
    local maxy = -math.huge
    local maxz = -math.huge

    for _, vec in pairs(points) do
        if vec.x < minx then
            minx = vec.x
        end
        if vec.y < miny then
            miny = vec.y
        end
        if vec.z < minz then
            minz = vec.z
        end
        if vec.x > maxx then
            maxx = vec.x
        end
        if vec.y > maxy then
            maxy = vec.y
        end
        if vec.z > maxz then
            maxz = vec.z
        end
    end
    return minx, miny, minz, maxx, maxy, maxz
end

 
function module:WritePartToHashMap(instance, hullRecord)
    local minx, miny, minz, maxx, maxy, maxz = self:FindAABB(instance)

	if (maxx-minx > self.fatPartSize or maxy-miny > self.fatPartSize or maxz-minz > self.fatPartSize) then
        
        --Part is fat
        for x = math.floor(minx / self.fatGridSize), math.ceil(maxx / self.fatGridSize) - 1 do
            for z = math.floor(minz / self.fatGridSize), math.ceil(maxz / self.fatGridSize) - 1 do
                for y = math.floor(miny / self.fatGridSize), math.ceil(maxy / self.fatGridSize) - 1 do
                    local cell = self:CreateAndFetchFatCell(x, y, z)
                    cell[instance] = hullRecord
                end
            end
        end
		--print("Fat part", instance.Name)
		
		--[[
		if (game["Run Service"]:IsClient() and instance:GetAttribute("showdebug")) then
			for x = math.floor(minx / self.fatGridSize), math.ceil(maxx/self.fatGridSize)-1 do
				for z = math.floor(minz / self.fatGridSize), math.ceil(maxz/self.fatGridSize)-1 do
					for y = math.floor(miny / self.fatGridSize), math.ceil(maxy/self.fatGridSize)-1 do

						self:SpawnDebugFatGridBox(x,y,z, Color3.new(math.random(),1,1))
					end
				end
			end
		end
		]]--
    else
        for x = math.floor(minx / self.gridSize), math.ceil(maxx / self.gridSize) - 1 do
            for z = math.floor(minz / self.gridSize), math.ceil(maxz / self.gridSize) - 1 do
                for y = math.floor(miny / self.gridSize), math.ceil(maxy / self.gridSize) - 1 do
                    local cell = self:CreateAndFetchCell(x, y, z)
                    cell[instance] = hullRecord
                end
            end
        end
        --[[
	if (game["Run Service"]:IsClient() and instance:GetAttribute("showdebug")) then
		for x = math.floor(minx / self.gridSize), math.ceil(maxx/self.gridSize)-1 do
			for z = math.floor(minz / self.gridSize), math.ceil(maxz/self.gridSize)-1 do
				for y = math.floor(miny / self.gridSize), math.ceil(maxy/self.gridSize)-1 do

					self:SpawnDebugGridBox(x,y,z, Color3.new(math.random(),1,1))
				end
			end
		end
	end]]
    --
    end
end

 

function module:RemovePartFromHashMap(instance)
    if instance:GetAttribute("ChickynoidIgnoreRemoval") then
        return
    end

    local minx, miny, minz, maxx, maxy, maxz = self:FindAABB(instance)

	if (maxx-minx > self.fatPartSize or maxy-miny > self.fatPartSize or maxz-minz > self.fatPartSize) then
        
        for x = math.floor(minx / self.fatGridSize), math.ceil(maxx / self.fatGridSize) - 1 do
            for z = math.floor(minz / self.fatGridSize), math.ceil(maxz / self.fatGridSize) - 1 do
                for y = math.floor(miny / self.fatGridSize), math.ceil(maxy / self.fatGridSize) - 1 do
                    local cell = self:FetchFatCell(x, y, z)
                    if cell then
                        cell[instance] = nil
                    end
                end
            end
        end

    else
        for x = math.floor(minx / self.gridSize), math.ceil(maxx / self.gridSize) - 1 do
            for z = math.floor(minz / self.gridSize), math.ceil(maxz / self.gridSize) - 1 do
                for y = math.floor(miny / self.gridSize), math.ceil(maxy / self.gridSize) - 1 do
                    local cell = self:FetchCell(x, y, z)
                    if cell then
                        cell[instance] = nil
                    end
                end
            end
        end
    end
end

function module:FetchHullsForPoint(point)
    local cell = self:FetchCell(
        math.floor(point.x / self.gridSize),
        math.floor(point.y / self.gridSize),
        math.floor(point.z / self.gridSize)
    )
    local hullRecords = {}
    if cell then
        for _, hull in pairs(cell :: table) do
            hullRecords[hull] = hull
        end
    end

    local cell = self:FetchFatCell(
        math.floor(point.x / self.fatGridSize),
        math.floor(point.y / self.fatGridSize),
        math.floor(point.z / self.fatGridSize)
    )
    local hullRecords = {}
    if cell then
        for _, hull in pairs(cell :: table) do
            hullRecords[hull] = hull
        end
    end

    return hullRecords
end

function module:FetchHullsForBox(min, max)
    local minx = min.x
    local miny = min.y
    local minz = min.z
    local maxx = max.x
    local maxy = max.y
    local maxz = max.z

    if minx > maxx then
        local t = minx
        minx = maxx
        maxx = t
    end
    if miny > maxy then
        local t = miny
        miny = maxy
        maxy = t
    end
    if minz > maxz then
        local t = minz
        minz = maxz
        maxz = t
	end
	
	local key = Vector3.new(math.floor(minx/self.gridSize), math.floor(minz/self.gridSize), math.floor(miny/self.gridSize))
	local otherKey = Vector3.new(math.floor(maxx/self.gridSize), math.floor(maxy/self.gridSize), math.floor(maxz/self.gridSize))

		
	local cached = self.cache[key]
	if (cached) then
		local rec = cached[otherKey]
		if (rec) then
			return rec
		end
	end
			

    local hullRecords = {}

    --Expanded by 1, so objects right on borders will be in the appropriate query
    for x = math.floor(minx / self.gridSize) - 1, math.ceil(maxx / self.gridSize) do
        for z = math.floor(minz / self.gridSize) - 1, math.ceil(maxz / self.gridSize) do
            for y = math.floor(miny / self.gridSize) - 1, math.ceil(maxy / self.gridSize) do
                local cell = self:FetchCell(x, y, z)
                if cell then
                    for _, hull in pairs(cell :: table) do
                        hullRecords[hull] = hull
                    end
                end

                local terrainHull = TerrainModule:FetchCell(x, y, z)
                if terrainHull then
                    for _, hull in pairs(terrainHull) do
                        hullRecords[hull] = hull
                    end
                end
            end
        end
    end

    --Expanded by 1, so objects right on borders will be in the appropriate query
    for x = math.floor(minx / self.fatGridSize) - 1, math.ceil(maxx / self.fatGridSize) do
        for z = math.floor(minz / self.fatGridSize) - 1, math.ceil(maxz / self.fatGridSize) do
            for y = math.floor(miny / self.fatGridSize) - 1, math.ceil(maxy / self.fatGridSize) do
                local cell = self:FetchFatCell(x, y, z)
                if cell then
                    for _, hull in pairs(cell :: table) do
                        hullRecords[hull] = hull
                    end
                end
            end
        end
    end
	
	
	self.cacheCount+=1
	if (self.cacheCount > self.maxCacheCount) then
		self.cacheCount = 0
		self.cache = {}
	end
	
	--Store it
	local cached = self.cache[key]
	if (cached == nil) then
		cached = {}
		self.cache[key] = cached
	end
	cached[otherKey] = hullRecords
	
	
	--Inflate missing hulls
	for key,record in pairs(hullRecords) do
       
    	if (record.hull == nil) then
			record.hull = self:GenerateConvexHullAccurate(record.instance, module.expansionSize, self:GenerateSnappedCFrame(record.instance))
            if (record.hull == nil) then
                hullRecords[key] = nil
            end
		end
	end
	
		
	return hullRecords
end

function module:GenerateConvexHullAccurate(part, expansionSize, cframe)
    local debugRoot = nil
    if debugParts == true and RunService:IsClient() then
        debugRoot = game.Workspace.Terrain
    end

    local hull, counter = MinkowskiSumInstance:GetPlanesForInstance(
        part,
        expansionSize,
        cframe,
        self.planeNum,
        debugRoot
    )
    self.planeNum = counter
    return hull
end

local function Trunc(number)
    return math.floor(number * 20) / 20
end

function module:GenerateSnappedCFrame(instance)
    --Because roblox cannot guarentee perfect replication of part orientation and positions, we'll take what is replicated and truncate it after a certain level of precision
    local snappedPosition = Vector3.new(
        Trunc(instance.Position.x),
        Trunc(instance.Position.y),
        Trunc(instance.Position.z)
    )
    return CFrame.new(snappedPosition)
        * CFrame.fromOrientation(
            math.rad(Trunc(instance.Orientation.x)),
            math.rad(Trunc(instance.Orientation.y)),
            math.rad(Trunc(instance.Orientation.z))
        )
end

function module:ProcessCollisionOnInstance(instance, playerSize)
    if instance:IsA("BasePart") then
        if instance.CanCollide == false then
            return
        end

        if module.hullRecords[instance] ~= nil then
            return
        end
		
		--[[
        if CollectionService:HasTag(instance, "Dynamic") then
            local record = {}
            record.instance = instance
            record.hull = self:GenerateConvexHullAccurate(instance, playerSize, instance.CFrame)
            record.currentCFrame = instance.CFrame

            -- Weird Selene shadowing bug here
            -- selene: allow(shadowing)
            function record:Update()
                if
                    ((record.currentCFrame.Position - instance.CFrame.Position).magnitude < 0.00001)
                    and (record.currentCFrame.LookVector:Dot(instance.CFrame.LookVector) > 0.999)
                then
                    return
                end

                record.hull = module:GenerateConvexHullAccurate(instance, playerSize, instance.CFrame)
                record.currentCFrame = instance.CFrame
            end

            table.insert(module.dynamicRecords, record)

            return
        end]]--

        local record = {}
        record.instance = instance
        --record.hull = self:GenerateConvexHullAccurate(instance, playerSize, self:GenerateSnappedCFrame(instance))
        self:WritePartToHashMap(record.instance, record)

        module.hullRecords[instance] = record
    end
end

function module:SpawnDebugGridBox(x, y, z, color)
    local instance = Instance.new("Part")
    instance.Size = Vector3.new(self.gridSize, self.gridSize, self.gridSize)
    instance.Position = (Vector3.new(x, y, z) * self.gridSize)
        + (Vector3.new(self.gridSize, self.gridSize, self.gridSize) * 0.5)
    instance.Transparency = 0.75
    instance.Color = color
    instance.Parent = game.Workspace
    instance.Anchored = true
    instance.TopSurface = Enum.SurfaceType.Smooth
    instance.BottomSurface = Enum.SurfaceType.Smooth
end

function module:SpawnDebugFatGridBox(x, y, z, color)
	local instance = Instance.new("Part")
	instance.Size = Vector3.new(self.fatGridSize, self.fatGridSize, self.fatGridSize)
	instance.Position = (Vector3.new(x, y, z) * self.fatGridSize)
		+ (Vector3.new(self.fatGridSize, self.fatGridSize, self.fatGridSize) * 0.5)
	instance.Transparency = 0.75
	instance.Color = color
	instance.Parent = game.Workspace
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
end

function module:SimpleRayTest(a, b, hull)
    -- Compute direction vector for the segment
    local d = b - a
    -- Set initial interval to being the whole segment. For a ray, tlast should be
    -- set to +FLT_MAX. For a line, additionally tfirst should be set to –FLT_MAX
    local tfirst = -1
    local tlast = 1

    --Intersect segment against each plane

    for _, p in pairs(hull) do
        local denom = p.n:Dot(d)
        local dist = p.ed - (p.n:Dot(a))

        --Test if segment runs parallel to the plane
        if denom == 0 then
            -- If so, return “no intersection” if segment lies outside plane
            if dist > 0 then
                return nil
            end
        else
            -- Compute parameterized t value for intersection with current plane
            local t = dist / denom
            if denom < 0 then
                -- When entering halfspace, update tfirst if t is larger
                if t > tfirst then
                    tfirst = t
                end
            else
                -- When exiting halfspace, update tlast if t is smaller
                if t < tlast then
                    tlast = t
                end
            end

            -- Exit with “no intersection” if intersection becomes empty
            if tfirst > tlast then
                return nil
            end
        end
    end
    -- A nonzero logical intersection, so the segment intersects the polyhedron
    return tfirst, tlast
end

function module:CheckBrushPoint(data, hullRecord)
    local startsOut = false

    for _, p in pairs(hullRecord.hull) do
        local startDistance = data.startPos:Dot(p.n) - p.ed

        if startDistance > 0 then
            startsOut = true
            break
        end
    end

    if startsOut == false then
        data.startSolid = true
        data.allSolid = true
        return
    end

    data.hullRecord = hullRecord
end

--Checks a brush, but doesn't handle it well if the start point is inside a brush
function module:CheckBrush(data, hullRecord)
    local startFraction = -1.0
    local endFraction = 1.0
    local startsOut = false
    local endsOut = false
    local lastPlane = nil

    for _, p in pairs(hullRecord.hull) do
        local startDistance = data.startPos:Dot(p.n) - p.ed
        local endDistance = data.endPos:Dot(p.n) - p.ed

        if startDistance > 0 then
            startsOut = true
        end
        if endDistance > 0 then
            endsOut = true
        end

        -- make sure the trace isn't completely on one side of the brush
        if startDistance > 0 and (endDistance >= SKIN_THICKNESS or endDistance >= startDistance) then
            return --both are in front of the plane, its outside of this brush
        end
        if startDistance <= 0 and endDistance <= 0 then
            --both are behind this plane, it will get clipped by another one
            continue
        end

        if startDistance > endDistance then
            --  line is entering into the brush
            local fraction = (startDistance - SKIN_THICKNESS) / (startDistance - endDistance)
            if fraction < 0 then
                fraction = 0
            end
            if fraction > startFraction then
                startFraction = fraction
                lastPlane = p
            end
        else
            --line is leaving the brush
            local fraction = (startDistance + SKIN_THICKNESS) / (startDistance - endDistance)
            if fraction > 1 then
                fraction = 1
            end
            if fraction < endFraction then
                endFraction = fraction
            end
        end
    end

    if startsOut == false then
        data.startSolid = true
        if endsOut == false then
            --Allsolid
            data.allSolid = true
            return
        end
    end

    --Update the output fraction
    if startFraction < endFraction then
        if startFraction > -1 and startFraction < data.fraction then
            if startFraction < 0 then
                startFraction = 0
            end
            data.fraction = startFraction
            data.normal = lastPlane.n
            data.planeD = lastPlane.ed
            data.planeNum = lastPlane.planeNum
            data.hullRecord = hullRecord
        end
    end
end

--Checks a brush, but is smart enough to ignore the brush entirely if the start point is inside but the ray is "exiting" or "exited"
function module:CheckBrushNoStuck(data, hullRecord)
    local startFraction = -1.0
    local endFraction = 1.0
    local startsOut = false
    local endsOut = false
    local lastPlane = nil

    local nearestStart = -math.huge
    local nearestEnd = -math.huge
	
    for _, p in pairs(hullRecord.hull) do
        local startDistance = data.startPos:Dot(p.n) - p.ed
        local endDistance = data.endPos:Dot(p.n) - p.ed

        if startDistance > 0 then
            startsOut = true
        end

        if endDistance > 0 then
            endsOut = true
        end

        -- make sure the trace isn't completely on one side of the brush
        if startDistance > 0 and (endDistance >= SKIN_THICKNESS or endDistance >= startDistance) then
            return --both are in front of the plane, its outside of this brush
        end

        --Record the distance to this plane
        nearestStart = math.max(nearestStart, startDistance)
        nearestEnd = math.max(nearestEnd, endDistance)

        if startDistance <= 0 and endDistance <= 0 then
            --both are behind this plane, it will get clipped by another one
            continue
        end

        if startDistance > endDistance then
            --  line is entering into the brush
            local fraction = (startDistance - SKIN_THICKNESS) / (startDistance - endDistance)
            if fraction < 0 then
                fraction = 0
            end
            if fraction > startFraction then
                startFraction = fraction
                lastPlane = p
            end
        else
            --line is leaving the brush
            local fraction = (startDistance + SKIN_THICKNESS) / (startDistance - endDistance)
            if fraction > 1 then
                fraction = 1
            end
            if fraction < endFraction then
                endFraction = fraction
            end
        end
    end

    --Point started inside this brush
    if startsOut == false then
        data.startSolid = true

        --We might be both start-and-end solid
        --If thats the case, we want to pretend we never saw this brush if we are moving "out"
        --This is either: we exited - or -
        --                the end point is nearer any plane than the start point is
        if endsOut == false and nearestEnd < nearestStart then
            --Allsolid
            data.allSolid = true
            return
        end

        --Not stuck! We should pretend we never touched this brush
        data.startSolid = false
        return --Ignore this brush
    end

    --Update the output fraction
    if startFraction < endFraction then
        if startFraction > -1 and startFraction < data.fraction then
            if startFraction < 0 then
                startFraction = 0
            end
            data.fraction = startFraction
            data.normal = lastPlane.n
            data.planeD = lastPlane.ed
            data.planeNum = lastPlane.planeNum
            data.hullRecord = hullRecord
        end
    end
end

function module:PlaneLineIntersect(normal, distance, V1, V2)
    local diff = V2 - V1
    local denominator = normal:Dot(diff)
    if denominator == 0 then
        return nil
    end
    local u = (normal.x * V1.x + normal.y * V1.y + normal.z * V1.z + distance) / -denominator

    return (V1 + u * (V2 - V1))
end

function module:Sweep(startPos, endPos)
    local data = {}
    data.startPos = startPos
    data.endPos = endPos
    data.fraction = 1
    data.startSolid = false
    data.allSolid = false
    data.planeNum = 0
    data.planeD = 0
    data.normal = Vector3.new(0, 1, 0)
    data.checks = 0
    data.hullRecord = nil

    if (startPos - endPos).magnitude > 1000 then
        return data
    end
    if (self.profile == true) then
        debug.profilebegin("Sweep")
    end
	--calc bounds of sweep
	if (self.profile == true) then
		debug.profilebegin("Fetch")
	end
    local hullRecords = self:FetchHullsForBox(startPos, endPos)
	if (self.profile==true) then
		debug.profileend()
	end
	
	if (self.profile == true) then
		debug.profilebegin("Collide")
	end
    for _, hullRecord in pairs(hullRecords) do
		data.checks += 1
		
		if (hullRecord.hull ~= nil) then
	        self:CheckBrushNoStuck(data, hullRecord)
	        if data.allSolid == true then
	            data.fraction = 0
	            break
	        end
	        if data.fraction < SKIN_THICKNESS then
	            break
			end
		end
	end
	if (self.profile == true) then
		debug.profileend()
	end

    --Collide with dynamic objects
    if data.fraction >= SKIN_THICKNESS or data.allSolid == false then
        for _, hullRecord in pairs(self.dynamicRecords) do
            data.checks += 1

            self:CheckBrushNoStuck(data, hullRecord)
            if data.allSolid == true then
                data.fraction = 0
                break
            end
            if data.fraction < SKIN_THICKNESS then
                break
            end
        end
    end

    if data.fraction < 1 then
        local vec = (endPos - startPos)
        data.endPos = startPos + (vec * data.fraction)
    end

    if (self.profile == true) then
        debug.profileend()
    end
    return data
end

function module:BoxTest(pos)
    local data = {}
    data.startPos = pos
    data.endPos = pos
    data.fraction = 1
    data.startSolid = false
    data.allSolid = false
    data.planeNum = 0
    data.planeD = 0
    data.normal = Vector3.new(0, 1, 0)
    data.checks = 0
    data.hullRecord = nil

    debug.profilebegin("PointTest")
    --calc bounds of sweep
    local hullRecords = self:FetchHullsForPoint(pos)

    for _, hullRecord in pairs(hullRecords) do
        data.checks += 1
        self:CheckBrushPoint(data, hullRecord)
        if data.allSolid == true then
            data.fraction = 0
            break
        end
    end

    debug.profileend()
    return data
end

--Call this before you try and simulate
function module:UpdateDynamicParts()
    for _, record in pairs(self.dynamicRecords) do
        if record.Update then
            record:Update()
        end
    end
end

function module:MakeWorld(folder, playerSize)
	
	debug.setmemorycategory("ChickynoidCollision")
	
    self.expansionSize = playerSize
	self.hulls = {}
	self:ClearCache()
	
	if (self.processing == true) then
		return
	end
	self.processing = true
    TerrainModule:Setup(self.gridSize, playerSize)
	
	local startTime = tick()
	local meshTime = 0

	coroutine.wrap(function()
		local list = folder:GetDescendants()
		local total = #list
		
		local lastTime = tick()
		for counter = 1, total do		
			local instance = list[counter]

			if (instance:IsA("BasePart") and not instance:IsA("Terrain") and instance.CanCollide == true) then		
				local begin = tick()
				self:ProcessCollisionOnInstance(instance, playerSize)
				local timeTaken = tick()- begin
				if (instance:IsA("MeshPart")) then
					meshTime += timeTaken
				end				
			end
		
            local maxTime = 0.2
 
            if (tick() - lastTime > maxTime) then
                lastTime = tick()
      
				wait()	
		
                local progress = counter/total;
                module.loadProgress = progress;
                module.OnLoadProgressChanged:Fire(progress)
				print("Collision processing: " .. math.floor(progress * 100) .. "%")
			end
	    end
        module.loadProgress = 1
        module.OnLoadProgressChanged:Fire(1)
		print("Collision processing: 100%")
		self.processing = false
		
		if (game["Run Service"]:IsServer()) then
			print("Server Time Taken: ", math.floor(tick() - startTime), "seconds")
			
		else
			print("Client Time Taken: ", math.floor(tick() - startTime), "seconds")
		end
		print("Mesh time: ", meshTime, "seconds")
		print("Tracing time:", MinkowskiSumInstance.timeSpentTracing, "seconds")
		self:ClearCache()
 
	end)()
	
	
	 
    folder.DescendantAdded:Connect(function(instance)
        self:ClearCache()
        self:ProcessCollisionOnInstance(instance, playerSize)
    end)
    
    folder.DescendantRemoving:Connect(function(instance)
        local record = module.hullRecords[instance]

		if record then
			self:ClearCache()
            self:RemovePartFromHashMap(instance)
        end
    end)
end

function module:ClearCache()
	self.cache = {}
	self.cacheCount = 0	
end

return module
