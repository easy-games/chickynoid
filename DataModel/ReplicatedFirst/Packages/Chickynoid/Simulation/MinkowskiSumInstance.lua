local QuickHull = require(game.ReplicatedFirst.Packages.Chickynoid.Vendor.QuickHull)
local TrianglePart = require(game.ReplicatedFirst.Packages.Chickynoid.Vendor.TrianglePart)
local module = {}

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

local function IsUnique(list, normal, d)
	
	local EPS = 0.001
	
	for key,rec in pairs(list) do
		if (math.abs(rec.ed - d) > EPS) then
			continue
		end  
		if (rec.n:Dot(normal) < 1-EPS) then
			continue
		end
		return false --got a match
	end
	return true
end


local function IsUniquePoints(list, p)

	local EPS = 0.001

	for key,point in pairs(list) do
		if ((point - p).magnitude < EPS) then
			return false
		end  
	end
	return true
end

--Generates a very accurate minkowski summed convex hull from an instance and player box size
--Forces you to pass in the part cframe manually, because we need to snap it for client/server precision reasons
--Not a speedy thing to do!
function module:GetPlanesForInstance(instance, playerSize, cframe, basePlaneNum, showDebugParentPart)

	--generate worldspace points
	local points = self:GeneratePointsForInstance(instance, playerSize, cframe)
	
	if (showDebugParentPart ~= nil) then
		self:VisualizePlanesForPoints(points, showDebugParentPart)
	end	
	return self:GetPlanesForPoints(points, basePlaneNum)
	 
end


function module:GetPlanesForPointsExpanded(points, playerSize, basePlaneNum, debugPart)
	
	
	local newPoints = {}
	for _,point in pairs(points) do
		for i, v in pairs(corners) do
			table.insert(newPoints, point + (v * playerSize) )	
		end
	end

	if (debugPart ~= nil) then
		self:VisualizePlanesForPoints(newPoints, debugPart)
	end	
	return self:GetPlanesForPoints(newPoints, basePlaneNum)
		
end

--Same thing but for worldspace point cloud
function module:VisualizePlanesForPoints(points, debugPart)
	
 
	local color = Color3.fromHSV(math.random(), 0.5,1)
	 
	for _,point in pairs(points) do
		local part = Instance.new("Part")
		part.CanCollide = false
		part.Anchored = true
		part.Size = Vector3.new(0.1,0.1,0.1)
		part.Shape = Enum.PartType.Ball
		part.Position = point
		part.Color = Color3.new(0,1,0)
		part.Parent = debugPart
	end

	
	--Run quickhull
	local r = QuickHull.quick_run(points)
	local recs = {}
	
	
	--Add triangles
	for key,tri in pairs(r) do
		
		local normal = (tri[1]-tri[2]):Cross(tri[1]-tri[3]).unit
		local l = math.clamp(normal:Dot(Vector3.new(0.5,0.5,0.5)),0.25, 1)
		local finalColor = Color3.new(color.r * l, color.g *l, color.b * l) 
		
		local a,b = TrianglePart:Triangle(tri[1], tri[2], tri[3])
		a.Parent = game.Workspace.Terrain
		a.Color = color
		b.Parent = game.Workspace.Terrain
		b.Color = color
	end

	
	--Generate unique planes in n+d format 
	for key,tri in pairs(r) do
		
		local normal = (tri[1]-tri[2]):Cross(tri[1]-tri[3]).unit
		local ed = tri[1]:Dot(normal) --expanded distance
	
		
		if (IsUnique(recs, normal,ed)) then
		
			table.insert(recs,
				{
					n = normal,
					ed = tri[1]:Dot(normal), --expanded
					
				}
			)
 
			local pos = (tri[1]+tri[2]+tri[3]) / 3
			
			local part = Instance.new("Part")
			part.CanCollide = false
			part.Anchored = true
			part.Size = Vector3.new(0.1,0.1,2)
			part.CFrame = CFrame.lookAt(pos+normal, pos+(normal*2))
			part.Color = color
			part.Parent = debugPart
 
		end
	end
end


--Same thing but for worldspace point cloud
function module:GetPlanesForPoints(points, basePlaneNum)


	--Run quickhull
	local r = QuickHull.quick_run(points)
	local recs = {}

	--Generate unique planes in n+d format 
	for key,tri in pairs(r) do

		local normal = (tri[1]-tri[2]):Cross(tri[1]-tri[3]).unit
		local ed = tri[1]:Dot(normal) --expanded distance
		basePlaneNum+=1

		if (IsUnique(recs, normal,ed)) then

			table.insert(recs,
				{
					n = normal,
					ed = tri[1]:Dot(normal), --expanded
					planeNum = basePlaneNum,
				}
			)
		end

	end

	return recs, basePlaneNum
end


function module:GeneratePointsForInstance(instance, playerSize, cframe)
	local points = {}
	for i, v in pairs(corners) do
		local part_corner = cframe * CFrame.new(v * instance.Size)

		for i, v in pairs(corners) do
			table.insert(points, (part_corner + v * playerSize).Position)
		end
	end
	return points
end

return module
