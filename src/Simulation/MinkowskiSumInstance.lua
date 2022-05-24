local Root = script.Parent.Parent
local Vendor = Root.Vendor

local TrianglePart = require(Vendor.TrianglePart)
local QuickHull2 = require(Vendor.QuickHull2)

local module = {}
module.meshCache = {}

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

local function IsUnique(list, normal, d)
    local EPS = 0.01
	local normalTol = 0.95
	
    for _, rec in pairs(list) do
        if (math.abs(rec.ed - d) < EPS and rec.n:Dot(normal) > normalTol) then
        	return false
        end
    end
    return true
end

local function IsUniqueTri(list, normal, d)
	local EPS = 0.001

	for _, rec in pairs(list) do
		if math.abs(rec[5] - d) > EPS then
			continue
		end
		if rec[4]:Dot(normal) < 1 - EPS then
			continue
		end
		return false --got a match
	end
	return true
end

-- local function IsUniquePoints(list, p)
--     local EPS = 0.001

--     for _, point in pairs(list) do
--         if (point - p).magnitude < EPS then
--             return false
--         end
--     end
--     return true
-- end

local function IsValidTri(tri, origin)
	
	local normal = (tri[1] - tri[2]):Cross(tri[1] - tri[3]).unit
	local pos = (tri[1]+tri[2]+tri[3]) / 3
	local vec = (pos-origin).unit

	if (vec:Dot(normal) > 0.75 ) then
		return true
	end
	return false
end


--Generates a very accurate minkowski summed convex hull from an instance and player box size
--Forces you to pass in the part cframe manually, because we need to snap it for client/server precision reasons
--Not a speedy thing to do!
function module:GetPlanesForInstance(instance, playerSize, cframe, basePlaneNum, showDebugParentPart)
	
	if (true and instance:IsA("MeshPart") and instance.Anchored == true and instance.CollisionFidelity == Enum.CollisionFidelity.Hull) then
    	return module:GetPlanesForInstanceMeshPart(instance, playerSize, cframe, basePlaneNum, showDebugParentPart)
	end
	
	--generate worldspace points
	local points = self:GeneratePointsForInstance(instance, playerSize, cframe)
    if showDebugParentPart ~= nil then
        self:VisualizePlanesForPoints(points, showDebugParentPart)
	end

    return self:GetPlanesForPoints(points, basePlaneNum)
end

function module:GetPlanesForPointsExpanded(points, playerSize, basePlaneNum, debugPart)
    local newPoints = {}
    for _, point in pairs(points) do
        for _, v in pairs(corners) do
            table.insert(newPoints, point + (v * playerSize))
        end
    end

    if debugPart ~= nil then
        self:VisualizePlanesForPoints(newPoints, debugPart)
    end
    return self:GetPlanesForPoints(newPoints, basePlaneNum)
end

--Same thing but for worldspace point cloud
function module:VisualizePlanesForPoints(points, debugPart)


	--Run quickhull
	
	local r = QuickHull2:GenerateHull(points)
	local recs = {}
	
	self:VisualizeTriangles(r, Vector3.zero)
end


function module:VisualizeTriangles(tris, offset)
	
	local color = Color3.fromHSV(math.random(), 0.5, 1)
	
    --Add triangles
    for _, tri in pairs(tris) do
		local a, b = TrianglePart:Triangle(tri[1] + offset, tri[2] + offset, tri[3] + offset)
        a.Parent = game.Workspace.Terrain
        a.Color = color
        b.Parent = game.Workspace.Terrain
		b.Color = color
		
		
		--Add a normal 
		local normal = (tri[1] - tri[2]):Cross(tri[1] - tri[3]).unit
		local pos = (tri[1]+tri[2]+tri[3]) / 3
		local instance = Instance.new("Part")
		instance.Size =Vector3.new(0.1,0.1,2)
		instance.CFrame = CFrame.lookAt( pos + (normal), pos + (normal*2))
		instance.Parent = game.Workspace.Terrain
		instance.CanCollide = false
		instance.Anchored = true
		
    end
end

--Same thing but for worldspace point cloud
function module:GetPlanesForPoints(points, basePlaneNum)
    --Run quickhull
    local r = QuickHull2:GenerateHull(points)
    local recs = {}

    --Generate unique planes in n+d format
    for _, tri in pairs(r) do
        local normal = (tri[1] - tri[2]):Cross(tri[1] - tri[3]).unit
        local ed = tri[1]:Dot(normal) --expanded distance
        basePlaneNum += 1

        if IsUnique(recs, normal, ed) then
            table.insert(recs, {
                n = normal,
                ed = ed, --expanded
                planeNum = basePlaneNum,
            })
        end
    end

    return recs, basePlaneNum
end

--Same thing but for worldspace point cloud
function module:GetPlanePointForPoints(points)
	--Run quickhull
	local r = QuickHull2:GenerateHull(points)
	local recs = {}

	--Generate unique planes in n+d format
	for _, tri in pairs(r) do
		local normal = (tri[1] - tri[2]):Cross(tri[1] - tri[3]).unit
		local ed = tri[1]:Dot(normal) --expanded distance
		
		if IsUniqueTri(recs, normal, ed) then
			table.insert(recs, { tri[1],tri[2], tri[3], normal, ed }) 
		end
	end

	return recs
end

function module:PointInsideHull(hullRecord,point)

	for _, p in pairs(hullRecord) do
		local dist = point:Dot(p.n) - p.ed
		
		if (dist > 0) then
			return true
		end
	end
	return false
end

function module:GeneratePointsForInstance(instance, playerSize, cframe)
      
    local points = {}
    for _, v in pairs(corners) do
        local part_corner = cframe * CFrame.new(v * instance.Size)

        for _, c in pairs(corners) do
            table.insert(points, (part_corner + c * playerSize).Position)
        end
    end

    
    return points
end

--As they say - if it's stupid and it works... 
--So the idea here is we scale a mesh down to 1,1,1
--Fire a grid of rays at it
--And return this array of points to build a convex hull out of
function module:GetRaytraceInstancePoints(instance, cframe)
	
	local points = self.meshCache[instance.MeshId]
	
	if (points == nil) then
		print("Raytracing ", instance.Name, instance.MeshId)
		points = {}
		local step = 0.2
		
	    local function AddUnique(list, point)
	        for key,value in pairs(list) do
	            if ((value-point).magnitude < 0.1) then
	                return
	            end
	        end
	        table.insert(list, point)
		end
					
		local meshCopy = instance:Clone()
		meshCopy.CFrame = CFrame.new(Vector3.new(0,0,0))
		meshCopy.Size = Vector3.one
		meshCopy.Parent = game.Workspace
		meshCopy.CanQuery = true
		
		
		local raycastParam = RaycastParams.new()
		raycastParam.FilterType = Enum.RaycastFilterType.Whitelist
		raycastParam.FilterDescendantsInstances = { meshCopy }
			
		for x=-0.5, 0.5, step do
			for y=-0.5, 0.5, step do
				local pos = Vector3.new(x,-2,y)
				local dir = Vector3.new(0,4,0)
				local result = game.Workspace:Raycast(pos, dir, raycastParam)
				if (result) then 
					AddUnique(points, result.Position)
				
					--we hit something, trace from the other side too
					local pos = Vector3.new(x,2,y)
					local dir = Vector3.new(0,-4,0)
					local result = game.Workspace:Raycast(pos, dir, raycastParam)
					if (result) then 
						AddUnique(points, result.Position)
					end
				end
			end
		end
		
		for x=-0.5, 0.5, step do
			for y=-0.5, 0.5, step do
				local pos = Vector3.new(-2,x,y)
				local dir = Vector3.new(4,0,0)
				local result = game.Workspace:Raycast(pos, dir, raycastParam)
				if (result) then 
					AddUnique(points, result.Position)
					
                    --we hit something, trace from the other side too
					local pos = Vector3.new(2,x,y)
					local dir = Vector3.new(-4,0,0)
					local result = game.Workspace:Raycast(pos, dir, raycastParam)
					if (result) then 
						AddUnique(points, result.Position)
					end
				end
			end
		end
		
		for x=-0.5, 0.5, step do
			for y=-0.5, 0.5, step do
				local pos = Vector3.new(x,y,-2)
				local dir = Vector3.new(0,0,4)
				local result = game.Workspace:Raycast(pos, dir, raycastParam)
				if (result) then 
					AddUnique(points, result.Position)

					--we hit something, trace from the other side too
					local pos = Vector3.new(x,y,2)
					local dir = Vector3.new(0,0,-4)
					local result = game.Workspace:Raycast(pos, dir, raycastParam)
					if (result) then 
						AddUnique(points, result.Position)
					end
				end
			end
		end
		
		meshCopy:Destroy()
		
		self.meshCache[instance.MeshId] = points
	end
	
	
	local finals = {}
	local size = instance.Size
	
	for key,point in pairs(points) do
		local p = cframe:PointToWorldSpace(point * size)
		table.insert(finals, p)	
	end

	
 
	if (false and game["Run Service"]:IsClient()) then
		for key,point in pairs(finals) do

			local debugInstance = Instance.new("Part")
			debugInstance.Parent = game.Workspace
			debugInstance.Anchored = true
			debugInstance.Size = Vector3.new(1,1,1)
			debugInstance.Position = point
			debugInstance.Shape = Enum.PartType.Ball
			debugInstance.Color = Color3.new(0,1,0)
		end
		
		self:VisualizePlanesForPoints(finals, game.Workspace)
	end
 

    return finals
end

function module:GetPlanesForInstanceMeshPart(instance, playerSize, cframe, basePlaneNum, showDebugParentPart)
	
	local sourcePoints = self:GetRaytraceInstancePoints(instance, cframe)
	local points = {}

	for _, point in pairs(sourcePoints) do
		for _, c in pairs(corners) do
			table.insert(points, point + (c * playerSize))
		end
	end

	local r = QuickHull2:GenerateHull(points)
 
	local recs = {}

	--Generate unique planes in n+d format
	if (r == nil) then 
		return nil, basePlaneNum
		
	end
	for _, tri in pairs(r) do
		local normal = (tri[1] - tri[2]):Cross(tri[1] - tri[3]).unit
		local ed = tri[1]:Dot(normal) --expanded distance
		basePlaneNum += 1

		if IsUnique(recs, normal, ed) then
			table.insert(recs, {
				n = normal,
				ed = ed, --expanded
				planeNum = basePlaneNum,
			})
		end
	end

	if showDebugParentPart ~= nil and game["Run Service"]:IsClient()  then
		--self:VisualizeTriangles(r, Vector3.zero)
	end

	return recs, basePlaneNum
end
	
return module