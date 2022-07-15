local RunService = game:GetService("RunService")

local MinkowskiSumInstance = require(script.Parent.MinkowskiSumInstance)

local module = {}
module.grid = {}
module.div = 0
module.counter = 0
module.planeNum = 1000000
module.expansionSize = Vector3.new(1, 1, 1)
module.boxCorners = {}

module.hullCache = {}

local cutoff = 0.20
local terrainQuantization = 8
local showHulls = false
local showCells = false


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

function module:RawFetchCell(key)
    --store in x,z,y order
    
    return self.grid[key]
end

function module:FetchCell(x, y, z)
    return self:FetchCellMarching(x, y, z)
end

local function Sample(occs, x, y, z)
    local avg = occs[x + 0][y + 0][z + 0]
    avg += occs[x + 1][y + 0][z + 0]
    avg += occs[x + 0][y + 0][z + 1]
    avg += occs[x + 1][y + 0][z + 1]
    avg += occs[x + 0][y + 1][z + 0]
    avg += occs[x + 1][y + 1][z + 0]
    avg += occs[x + 0][y + 1][z + 1]
    avg += occs[x + 1][y + 1][z + 1]

	avg /= 8
	
	avg = math.floor(avg * terrainQuantization) / terrainQuantization
    return avg
end


local function EmitSolidPoint(list, pos, val)
    if val >= cutoff then
		--table.insert(list, pos)
		for _, c in pairs(module.boxCorners) do
			table.insert(list, pos + c)
		end
    end
end

local function Frac(min, max, cross)
    local range = max - min
	local frac = (cross - min) / range
	return frac
	--return math.floor(frac*4)/4
end

local function SpanCheck(list, aval, bval, apos, bpos)
    --if its a mismatch
    if aval < cutoff and bval >= cutoff then
		local frac = Frac(aval, bval, cutoff)
		
		if (frac == 0 or frac == 1) then
		--	return
		end
		local pos = apos:Lerp(bpos, frac) --TopD
		
		for _, c in pairs(module.boxCorners) do
			table.insert(list, pos + c)
		end
		
    elseif aval >= cutoff and bval < cutoff then
		local frac = Frac(bval, aval, cutoff)
		
		if (frac == 0 or frac == 1) then
		--	return
		end

		local pos = bpos:Lerp(apos, frac) --TopD
		for _, c in pairs(module.boxCorners) do
			table.insert(list, pos + c)
		end
    end
end



function module:Lookup(a,b,c,d,e,f,g,h)
		
	local key0 = Vector3.new(a,b,c)
	local key1 = Vector3.new(d,e,f)
	local key2 = Vector3.new(g,h,0)

 	local lookup0 = self.hullCache[key0]
	if (lookup0 == nil) then
		return nil
	end 
	
	local lookup1 = lookup0[key1]
	if (lookup1 == nil) then
		return nil
	end
	
	return lookup1[key2]

end

function module:Write(a,b,c,d,e,f,g,h, tris)
	
	local key0 = Vector3.new(a,b,c)
	local key1 = Vector3.new(d,e,f)
	local key2 = Vector3.new(g,h,0)
	
	if (self.hullCache[key0] == nil) then
		self.hullCache[key0] = {}
	end
	if (self.hullCache[key0][key1] == nil) then
		self.hullCache[key0][key1] = {}
	end
	
	self.hullCache[key0][key1][key2] = tris
end


function module:FetchCellMarching(x, y, z)
	
	local key = Vector3.new(x,y,z)
    local rawCell = self:RawFetchCell(key)
    if rawCell then
        return rawCell
    end

    debug.profilebegin("FetchCellMarching")

    local cell = self:CreateAndFetchCell(key)

    local max = self.div - 1

    local corner = Vector3.new(x, y, z) * self.gridSize

    local region = Region3.new(
        corner + Vector3.new(-4, -4, -4),
        corner + Vector3.new(self.gridSize + 4, self.gridSize + 4, self.gridSize + 4)
    )

    local _materials, occs = game.Workspace.Terrain:ReadVoxels(region, 4)
	
	local topAPos = Vector3.new(0, 4, 0)
	local topBPos = Vector3.new(4, 4, 0)
	local topCPos = Vector3.new(0, 4, 4)
	local topDPos = Vector3.new(4, 4, 4)
	local botAPos = Vector3.new(0, 0, 0)
	local botBPos = Vector3.new(4, 0, 0)
	local botCPos = Vector3.new(0, 0, 4)
	local botDPos = Vector3.new(4, 0, 4)
	
	local new = 0
	local old = 0
	
    for xx = 0, max do
        for yy = 0, max do
            for zz = 0, max do
         
				if showCells and RunService:IsClient() then
					local instance = Instance.new("Part")

					instance.Size = Vector3.new(4, 4, 4)
					local center = corner + Vector3.new(xx * 4, yy * 4, zz * 4)
					instance.Position = center + Vector3.new(2, 2, 2)
					instance.Transparency = 0.9

					instance.Shape = Enum.PartType.Block
					instance.Color = Color3.new(1, 0.3, 0.3)
					instance.Parent = game.Workspace
					instance.Anchored = true
					instance.TopSurface = Enum.SurfaceType.Smooth
					instance.BottomSurface = Enum.SurfaceType.Smooth
				end
				
                local xd = xx + 1
                local yd = yy + 1
                local zd = zz + 1

                local topA = Sample(occs, xd + 0, yd + 1, zd + 0)
                local topB = Sample(occs, xd + 1, yd + 1, zd + 0)
                local topC = Sample(occs, xd + 0, yd + 1, zd + 1)
                local topD = Sample(occs, xd + 1, yd + 1, zd + 1)
                local botA = Sample(occs, xd + 0, yd + 0, zd + 0)
                local botB = Sample(occs, xd + 1, yd + 0, zd + 0)
                local botC = Sample(occs, xd + 0, yd + 0, zd + 1)
                local botD = Sample(occs, xd + 1, yd + 0, zd + 1)
				
				--All empty
				if
					topA < cutoff
					and topB < cutoff
					and topC < cutoff
					and topD < cutoff
					and botA < cutoff
					and botB < cutoff
					and botC < cutoff
					and botD < cutoff
				then
					continue
				end

                local tris = self:Lookup(topA,topB, topC, topD, botA, botB, botC, botD)
				if (tris == nil) then
					local list = {}
	                --All solid ?
	                if
	                    topA >= cutoff
	                    and topB >= cutoff
	                    and topC >= cutoff
	                    and topD >= cutoff
	                    and botA >= cutoff
	                    and botB >= cutoff
	                    and botC >= cutoff
	                    and botD >= cutoff
					then
						continue
	                else
						--Generate a new hull
		                --See if any of the corners are solid
		                EmitSolidPoint(list, topAPos, topA)
		                EmitSolidPoint(list, topBPos, topB)
		                EmitSolidPoint(list, topCPos, topC)
		                EmitSolidPoint(list, topDPos, topD)
		                EmitSolidPoint(list, botAPos, botA)
		                EmitSolidPoint(list, botBPos, botB)
		                EmitSolidPoint(list, botCPos, botC)
		                EmitSolidPoint(list, botDPos, botD)

		                --Vertical spans
		                SpanCheck(list, topA, botA, topAPos, botAPos)
		                SpanCheck(list, topB, botB, topBPos, botBPos)
		                SpanCheck(list, topC, botC, topCPos, botCPos)
		                SpanCheck(list, topD, botD, topDPos, botDPos)

		                --Bottom spans
		                SpanCheck(list, botA, botB, botAPos, botBPos)
		                SpanCheck(list, botC, botD, botCPos, botDPos)
		                SpanCheck(list, botA, botC, botAPos, botCPos)
		                SpanCheck(list, botB, botD, botBPos, botDPos)

		                --Top spans
		                SpanCheck(list, topA, topB, topAPos, topBPos)
		                SpanCheck(list, topC, topD, topCPos, topDPos)
		                SpanCheck(list, topA, topC, topAPos, topCPos)
		                SpanCheck(list, topB, topD, topBPos, topDPos)
					end

	                if #list > 3 then
						tris = MinkowskiSumInstance:GetPlanePointForPoints(list)
						self:Write(topA,topB, topC, topD, botA, botB, botC, botD, tris)				
						new+=1
					end
				end

				--We have tris now
				if (tris ~= nil) then
					local center = corner + Vector3.new(xx * 4, yy * 4, zz * 4)
					local hull = self:BuildHullFromPlanePoint(tris, center)
					table.insert(cell, { hull = hull })

					if showHulls and RunService:IsClient() then
						local points = {}
						for key,tri in pairs(tris) do
							table.insert(points, tri[1]+center)
							table.insert(points, tri[2]+center)
							table.insert(points, tri[3]+center)
						end
						MinkowskiSumInstance:VisualizePlanesForPoints(points)
					end
				end
            end
        end
    end
	if (new > 0) then 
		--print("new ", new)
	end

    debug.profileend()

    return cell
end

function module:BuildHullFromPlanePoint(tris, offset)

	local records = {}

	--Generate unique planes in n+d format
	for _, tri in pairs(tris) do
		local normal = tri[4]
		local ed = (tri[1]+offset):Dot(normal) --expanded distance
		
		table.insert(records, {
			n = normal,
			ed = ed,  
			planeNum = self.planeNum,
		})
		self.planeNum+=1
	end

	return records
end

function module:SpawnDebugGridBox(x, y, z, color, grid)
    local instance = Instance.new("Part")

    instance.Size = Vector3.new(grid, grid, grid)
    instance.Position = (Vector3.new(x, y, z) * self.gridSize) + (Vector3.new(grid, grid, grid) * 0.5)
    instance.Transparency = 0

    instance.Color = color
    instance.Parent = game.Workspace
    instance.Anchored = true
    instance.TopSurface = Enum.SurfaceType.Smooth
    instance.BottomSurface = Enum.SurfaceType.Smooth
end

function module:CreateAndFetchCell(key)
	
	local cell = self.grid[key]
	if (cell == nil) then
		cell = {}
		self.grid[key] = cell
	end
    return cell
end

function module:Setup(gridSize, expansionSize)
    self.grid = {}
    self.expansionSize = expansionSize

    self.gridSize = gridSize
    self.boxSize = 4
    self.div = self.gridSize / self.boxSize

    self.expandedCorners = {}
    for _, corner in pairs(corners) do
        table.insert(self.expandedCorners, (corner * self.boxSize) + (corner * self.expansionSize))
    end
    self.boxCorners = {}
    for _, corner in pairs(corners) do
        table.insert(self.boxCorners, (corner * self.expansionSize))
    end

    local testPart = Instance.new("Part")
    testPart.Size = Vector3.new(self.boxSize, self.boxSize, self.boxSize)
    testPart.CanCollide = false
    self.testPart = testPart

    if (game:GetService("RunService"):IsServer() == true) then
--        self:PreprocessTerrain()
    end
end

function module:PreprocessTerrain()

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { game.Workspace.Terrain}
    rayParams.FilterType = Enum.RaycastFilterType.Whitelist

    local counter = 0
    coroutine.wrap(function()
        print("Starting preprocess")    
        local height = -200
        for x=-2048,2048, self.gridSize do
            for z=-2048, 2048, self.gridSize do
                local hit = game.Workspace:Raycast(Vector3.new(x + self.gridSize*0.5,height,z+ self.gridSize*0.5), Vector3.new(0,-1000,0))
                if (hit) then
                    local xx = math.floor(x / self.gridSize)
                    local yy = math.floor(hit.Position.Y / self.gridSize)
                    local zz = math.floor(z / self.gridSize)
                    self:FetchCell(xx,yy,zz)
                end
                counter+=1
                if (counter >1000) then
                    counter = 0
                    print(x,z)
                    wait()
                end
            end
        end
    end)()
end

return module