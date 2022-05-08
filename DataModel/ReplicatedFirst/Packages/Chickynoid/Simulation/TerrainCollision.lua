local module = {}
module.grid = {}
module.div = 0
module.counter = 0
module.planeNum = 1000000
module.expansionSize = Vector3.new(1,1,1)
module.boxCorners = {}
local MinkowskiSumInstance = require(script.Parent.MinkowskiSumInstance)
local showHulls = false

local corners = {
	Vector3.new( 0.5,0.5, 0.5),
	Vector3.new( 0.5,0.5,-0.5),
	Vector3.new(-0.5,0.5, 0.5),
	Vector3.new(-0.5,0.5,-0.5),
	Vector3.new( 0.5,-0.5, 0.5),
	Vector3.new( 0.5,-0.5,-0.5),
	Vector3.new(-0.5,-0.5, 0.5),
	Vector3.new(-0.5,-0.5,-0.5),
}


function module:RawFetchCell(x,y,z)

	--store in x,z,y order 
	local gx = self.grid[x] 
	if (gx == nil) then
		return nil
	end    
	local gz = gx[z]
	if (gz == nil) then
		return nil
	end
	return gz[y]
end

function module:FetchCell(x,y,z)
	return self:FetchCellMarching(x,y,z)
end

local function Sample(occs,x,y,z)
	local avg = occs[x+0][y+0][z+0]
	avg += occs[x+1][y+0][z+0]
	avg += occs[x+0][y+0][z+1]
	avg += occs[x+1][y+0][z+1]
	avg += occs[x+0][y+1][z+0]
	avg += occs[x+1][y+1][z+0]
	avg += occs[x+0][y+1][z+1]
	avg += occs[x+1][y+1][z+1]

	avg/=8
	return avg
end

local cutoff = 0.25

local function EmitPointGrey(list, pos,offset)
	--[[
	local instance = Instance.new("Part")

	instance.Size = Vector3.new(1,1,1)
	instance.Position = pos + Vector3.new(0,16,0)
	instance.Transparency = 0.2

	instance.Shape = Enum.PartType.Ball
	instance.Color = Color3.new(0.25,0.25,0.25)
	instance.Parent = game.Workspace
	instance.Transparency = 0.5
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	]]--
end

local function EmitRedDot(list, pos)
	
	--[[
	local instance = Instance.new("Part")

	instance.Size = Vector3.new(0.25,0.25,0.25)
	instance.Position = pos + Vector3.new(0,16,0)
	instance.Transparency = 0

	instance.Shape = Enum.PartType.Ball
	instance.Color = Color3.new(1,0,0.25)
	instance.Parent = game.Workspace
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	]]--

	for a,c in pairs(module.boxCorners) do
		table.insert(list,pos + c)
	end

end

local function EmitPointGreen(list, pos,offset)
	--[[
	local instance = Instance.new("Part")

	instance.Size = Vector3.new(1,1,1)
	instance.Position = pos  + Vector3.new(0,16,0)
	instance.Transparency = 0.5

	instance.Shape = Enum.PartType.Ball
	instance.Color = Color3.new(0.25,1,0.25)
	instance.Parent = game.Workspace
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	]]--
	table.insert(list,pos+offset)
end

local function EmitSolidPoint(list, pos, offset, val)
	if (val < cutoff) then
		EmitPointGrey(list, pos,offset)
	else
		EmitPointGreen(list, pos,offset)
	end
end

local function Frac(min, max, cross)

	local range = max - min
	return  (cross-min) / range
end

local function SpanCheck(list, aval, bval, apos, bpos)

	--if its a mismatch
	if (aval < cutoff and bval >= cutoff) then 
		local frac = Frac(aval,bval, cutoff)
		EmitRedDot(list, apos:Lerp(bpos, frac))--TopD
	elseif (aval >= cutoff and bval < cutoff) then 
		local frac = Frac(bval,aval, cutoff)
		EmitRedDot(list, bpos:Lerp(apos, frac))--TopD
	end
end




function module:FetchCellMarching(x,y,z)

	local cell = self:RawFetchCell(x,y,z)

	if (cell) then
		return cell
	end


	local cell = self:CreateAndFetchCell(x,y,z)

	local max = self.div-1

	local corner = Vector3.new(x,y,z)*self.gridSize

	local region = Region3.new(corner + Vector3.new(-4,-4,-4), corner + Vector3.new(self.gridSize+4,self.gridSize+4,self.gridSize+4))
 
	local materials,occs = game.Workspace.Terrain:ReadVoxels(region,4)

	local step = 1

	
	for xx=0,max do
		for yy=0,max do
			for zz=0,max do
			
			 	local list = {}
				
				local center = corner + Vector3.new (xx*4, yy*4, zz*4 ) 
				
				local xd = xx+1
				local yd = yy+1
				local zd = zz+1
				 
				local topA = Sample(occs,xd+0,yd+1,zd+0)
				local topB = Sample(occs,xd+1,yd+1,zd+0)
				local topC = Sample(occs,xd+0,yd+1,zd+1)
				local topD = Sample(occs,xd+1,yd+1,zd+1)
				local botA = Sample(occs,xd+0,yd+0,zd+0)
				local botB = Sample(occs,xd+1,yd+0,zd+0)
				local botC = Sample(occs,xd+0,yd+0,zd+1)
				local botD = Sample(occs,xd+1,yd+0,zd+1)
				
				
				--All solid ?
				if (topA >= cutoff and topB >= cutoff and topC >= cutoff and topD >= cutoff and
					botA >= cutoff and botB >= cutoff and botC >= cutoff and botD >= cutoff) then
					
				 
					for a,c in pairs(self.expandedCorners) do
						
						table.insert(list, center + Vector3.new(2,2,2) + c)
					end

					local hull, planeNum = MinkowskiSumInstance:GetPlanesForPoints(list, self.planeNum, nil)
					self.planeNum = planeNum
					if (hull and planeNum) then
						table.insert(cell,  { hull = hull } ) 
					end
					
					continue
				end

				--All empty
				if (topA < cutoff and topB < cutoff and topC < cutoff and topD < cutoff and
					botA < cutoff and botB < cutoff and botC < cutoff and botD < cutoff) then
					continue					
				end
		 
				local topAPos = center + Vector3.new(0,4,0)
				local topBPos = center + Vector3.new(4,4,0) 
				local topCPos = center + Vector3.new(0,4,4) 
				local topDPos = center + Vector3.new(4,4,4) 
				local botAPos = center + Vector3.new(0,0,0) 
				local botBPos = center + Vector3.new(4,0,0) 
				local botCPos = center + Vector3.new(0,0,4) 
				local botDPos = center + Vector3.new(4,0,4) 
				
				EmitSolidPoint(list, topAPos , (self.expansionSize * Vector3.new(-0.5, 0.5,-0.5)), topA)
				EmitSolidPoint(list, topBPos , (self.expansionSize * Vector3.new( 0.5, 0.5,-0.5)), topB)
				EmitSolidPoint(list, topCPos , (self.expansionSize * Vector3.new(-0.5, 0.5, 0.5)), topC)
				EmitSolidPoint(list, topDPos , (self.expansionSize * Vector3.new( 0.5, 0.5, 0.5)), topD)
				EmitSolidPoint(list, botAPos , (self.expansionSize * Vector3.new(-0.5,-0.5,-0.5)), botA)
				EmitSolidPoint(list, botBPos , (self.expansionSize * Vector3.new( 0.5,-0.5,-0.5)), botB)
				EmitSolidPoint(list, botCPos , (self.expansionSize * Vector3.new(-0.5,-0.5, 0.5)), botC)
				EmitSolidPoint(list, botDPos , (self.expansionSize * Vector3.new( 0.5,-0.5, 0.5)), botD)

								
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
				
				if (game["Run Service"]:IsClient() and false) then
					local instance = Instance.new("Part")

					instance.Size = Vector3.new(4,4,4)
					instance.Position = center + Vector3.new(2,2,2)
					instance.Transparency = 0.9
					
					instance.Shape = Enum.PartType.Block
					instance.Color = Color3.new(1,0.3,0.3)
					instance.Parent = game.Workspace
					instance.Anchored = true
					instance.TopSurface = Enum.SurfaceType.Smooth
					instance.BottomSurface = Enum.SurfaceType.Smooth
				end
				
				
				if (#list > 3) then

					local parent = nil
					if (game["Run Service"]:IsClient() and showHulls) then
						parent = game.Workspace.Terrain
					end
					
					local hull, planeNum = MinkowskiSumInstance:GetPlanesForPoints(list, self.planeNum, parent)
					self.planeNum = planeNum
					if (hull and planeNum) then

						--CollisionModule.planeNum = planeNum 
						table.insert(cell,  { hull = hull } ) 
					end
				end
			end
		end
	end



	return cell
end 


function module:SpawnDebugGridBox(x,y,z, color, grid)

	local instance = Instance.new("Part")
 
	instance.Size = Vector3.new(grid,grid,grid)
	instance.Position = (Vector3.new(x,y,z)*self.gridSize) + (Vector3.new(grid,grid,grid)*0.5)
	instance.Transparency = 0
	
	instance.Color = color
	instance.Parent = game.Workspace
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
end



function module:CreateAndFetchCell(x,y,z)

	local gx = self.grid[x] 
	if (gx == nil) then
		gx = {}
		self.grid[x] = gx
	end    
	local gz = gx[z]
	if (gz == nil) then
		gz = {}
		gx[z] = gz
	end
	local gy = gz[y]
	if (gy == nil) then
		gy = {}
		gz[y] = gy
	end
	return gy
end

function module:Setup(gridSize, expansionSize)
	
	self.grid = {}
	self.expansionSize = expansionSize
 
	self.gridSize = gridSize
	self.boxSize = 4
	self.div = self.gridSize / self.boxSize
	

	self.expandedCorners = {}
	for key,corner in pairs(corners) do
		table.insert(self.expandedCorners,  (corner * self.boxSize) + (corner * self.expansionSize ))
	end
	self.boxCorners = {}
	for key,corner in pairs(corners) do
		table.insert(self.boxCorners,  (corner * self.expansionSize ))
	end
	
	local testPart = Instance.new("Part")
	testPart.Size = Vector3.new(self.boxSize,self.boxSize,self.boxSize)
	testPart.CanCollide = false
	self.testPart = testPart	

end

 

return module
