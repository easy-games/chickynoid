local module = {}
module.grid = {}
module.div = 0
module.counter = 0
module.planeNum = 1000000
module.expansionSize = Vector3.new(1,1,1)
local MinkowskiSumInstance = require(script.Parent.MinkowskiSumInstance)

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

	local cell = self:RawFetchCell(x,y,z)
	
	if (cell) then
		return cell
	end
	
	 
	local cell = self:CreateAndFetchCell(x,y,z)
	
	self.testPart.Parent = game.Workspace
	
	local max = self.div-1
	for xx=0,max do
		for yy=0,max do
			for zz=0,max do
				
				
				local center = (Vector3.new(x+(xx / self.div), y+(yy / self.div), z+(zz / self.div))*self.gridSize) + (Vector3.new(self.boxSize,self.boxSize,self.boxSize)*0.5)
				
				self.testPart.Position = center
				
				local parts = self.testPart:GetTouchingParts()
				if (#parts == 0) then
					continue
				end
				
				for key,value in pairs(parts) do
					if value == game.Workspace.Terrain then
					
						--we're good
						local list = {}
						for a,corner in pairs(self.expandedCorners) do
							
							table.insert(list, center + corner)
						end	

						local hull, planeNum = MinkowskiSumInstance:GetPlanesForPoints(list, self.planeNum)
						self.planeNum = planeNum
						if (hull and planeNum) then

							--CollisionModule.planeNum = planeNum 
							table.insert(cell,  { hull = hull } ) 
						end
						
					end
				end
				--[[
				local list = {}
				
				
				
				local hull, planeNum = MinkowskiSumInstance:GetPlanesForPointsExpanded(list, self.expansionSize, self.planeNum)
				self.planeNum = planeNum
				if (hull and planeNum) then
										
					--CollisionModule.planeNum = planeNum 
					cell[hull] = hull
				end
				]]--
				
				--self:SpawnDebugGridBox(x+(xx / self.div), y+(yy / self.div), z+(zz / self.div), Color3.fromHSV(math.random(),1,1), 4)
			end
		end
	end
	self.testPart.Parent = nil
	
	--self:SpawnDebugGridBox(x, y, z, Color3.fromHSV(math.random(),1,1), self.gridSize)
	
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


function module:BuildCollisionData(x, z, collisionModule, playerSize)
 
	local chunkSize = 4	

	local chunkx = math.floor(x / chunkSize)
	local chunkz = math.floor(z / chunkSize)
	
	local hash = (chunkz * 4096) + chunkx
	if (self.mapCache[hash] ~= nil or true) then
		return
	end	
	
	self.mapCache[hash] = true
	
	self:ProcessChunk(chunkx * chunkSize,chunkz * chunkSize, chunkSize, collisionModule, playerSize)
end





function module:Setup(gridSize, expansionSize)
	
	self.grid = {}
	self.expansionSize = expansionSize
	
	self.boxSize = 2 --resolution of the box parts	
	local part = Instance.new("Part")
	part.CanCollide = false
 
	part.Size = Vector3.new(self.boxSize,self.boxSize,self.boxSize)
	part.Anchored = true
	part.Touched:Connect(function()
	end)
	 
	self.testPart = part
	
	self.gridSize = gridSize
	
	self.div = math.floor(gridSize/self.boxSize)
	local a,rem = math.modf(gridSize/self.boxSize)
	if (rem > 0) then
		error("Collision Module gridsize should match the terrain and be divisible by boxSize")
	end
		
	self.expandedCorners = {}
	for key,corner in pairs(corners) do
		table.insert(self.expandedCorners,  (corner * self.boxSize * self.expansionSize))
	end
end

 

return module
