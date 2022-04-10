local QuickHull = require(game.ReplicatedFirst.Packages.Chickynoid.Vendor.QuickHull)
local module = {}

local corners = {
	Vector3.new(0.5, 0.5, 0.5),
	Vector3.new(0.5, 0.5, -0.5),
	Vector3.new(-0.5, 0.5, -0.5),
	Vector3.new(-0.5, 0.5, 0.5),
	Vector3.new(0.5, -0.5, 0.5),
	Vector3.new(0.5, -0.5, -0.5),
	Vector3.new(-0.5, -0.5, -0.5),
	Vector3.new(-0.5, -0.5, 0.5),
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

--Generates a very accurate minkowski summed convex hull from an instance and player box size
--Not a speedy thing to do!
--Forces you to pass in the part cframe manually, because we need to snap it for client/server precision reasons
function module:GetPlanesForInstance(instance, playerSize, cframe, basePlaneNum)
	
	
	--generate worldspace points
	local points = {}
	for i, v in pairs(corners) do
		local part_corner = cframe * CFrame.new(v * instance.Size)

		for i, v in pairs(corners) do
			table.insert(points, (part_corner + v * playerSize).Position)
		end
	end
	
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


return module
