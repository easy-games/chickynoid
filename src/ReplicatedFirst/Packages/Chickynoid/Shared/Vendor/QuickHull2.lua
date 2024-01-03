--Port of
--https://github.com/OskarSigvardsson/unity-quickhull/blob/master/Scripts/ConvexHullCalculator.cs
--Which is under the MIT license

local module = {}

local UNASSIGNED = -2
local INSIDE = -1
local EPSILON = 0.0001
local NaN = math.NaN
local counter = 0

--Notes: openSetTail correctly bumped to be 1-based

local function Cross(a, b) 
    return Vector3.new(
        a.y*b.z - a.z*b.y,
        a.z*b.x - a.x*b.z,
        a.x*b.y - a.y*b.x)
end

local function Dot(a, b) 
    return a.x*b.x + a.y*b.y + a.z*b.z
end

 local function PointFaceDistance(point, pointOnFace, face) 
    return Dot(face.Normal, point - pointOnFace)
end
 
local function Normal(v0, v1, v2) 
    return Cross(v1 - v0, v2 - v0).Unit
end
 
local function AreCoincident(a, b) 
    return (a - b).Magnitude <= EPSILON
end

local function AreCollinear(a, b, c) 
    return Cross(c - a, c - b).Magnitude <= EPSILON
end
 
local function AreCoplanar(a, b, c, d) 
    local n1 = Cross(c - a, c - b)
    local n2 = Cross(d - a, d - b)

    local m1 = n1.Magnitude
    local m2 = n2.Magnitude

    return m1 <= EPSILON
        or m2 <= EPSILON
        or AreCollinear(Vector3.zero, (1.0 / m1) * n1, (1.0 / m2) * n2)
end

local function Face(v0, v1, v2, o0, o1, o2, normal)

    return {
        Vertex0 = v0,
        Vertex1 = v1,
        Vertex2 = v2,
        Opposite0 = o0,
        Opposite1 = o1,
        Opposite2 = o2,
        Normal = normal,
    }
end

function FaceEquals(left, other)
    return (left.Vertex0   == other.Vertex0)
        and (left.Vertex1   == other.Vertex1)
        and (left.Vertex2   == other.Vertex2)
        and (left.Opposite0 == other.Opposite0)
        and (left.Opposite1 == other.Opposite1)
        and (left.Opposite2 == other.Opposite2)
        and (left.Normal    == other.Normal)
end

local function PointFace(p, f, d) 
    return {
        Point = p,
		Face = f,
		Distance = d
    }
end

local function HorizonEdge(f, e0, e1)
    return {
		Face = f, 
        Edge0 = e0,
        Edge1 = e1
    }
end

local function Contains(list, item)
    for key,value in pairs(list) do
        
        if (item == value) then
            return true
        end
    end
    return false
end

local function Count(list)
    return #list
end


local faces = {}
local openSet = {}
local litFaces = {}
local horizon = {}

local openSetTail = -1
local faceCount = 0



local function HasEdge(f, e0, e1) 
    return (f.Vertex0 == e0 and f.Vertex1 == e1)
        or (f.Vertex1 == e0 and f.Vertex2 == e1)
        or (f.Vertex2 == e0 and f.Vertex0 == e1)
end

local function VerifyFaces(points)
    for kvpKey, kpvValue in pairs(faces) do
        local fi = kvpKey
        local face = kpvValue

        assert(faces[face.Opposite0] ~= nil)
		assert(faces[face.Opposite1] ~= nil)
		assert(faces[face.Opposite2] ~= nil)

		assert(face.Opposite0 ~= fi)
		assert(face.Opposite1 ~= fi)
		assert(face.Opposite2 ~= fi)

        assert(face.Vertex0 ~= face.Vertex1)
        assert(face.Vertex0 ~= face.Vertex2)
        assert(face.Vertex1 ~= face.Vertex2)

		assert(HasEdge(faces[face.Opposite0], face.Vertex2, face.Vertex1))
		assert(HasEdge(faces[face.Opposite1], face.Vertex0, face.Vertex2))
		assert(HasEdge(faces[face.Opposite2], face.Vertex1, face.Vertex0))

       --[[ assert((face.Normal - Normal(
                    points[face.Vertex0],
                    points[face.Vertex1],
                    points[face.Vertex2])).Magnitude < EPSILON)]]--
    end
end
 


--[[
    Reassign points based on the new faces added by ConstructCone().

    Only points that were previous assigned to a removed face need to
    be updated, so check litFaces while looping through the open set.

    There is a potential optimization here: there's no reason to loop
    through the entire openSet here. If each face had it's own
    openSet, we could just loop through the openSets in the removed
    faces. That would make the loop here shorter.

    However, to do that, we would have to juggle A LOT more List<T>'s,
    and we would need an object pool to manage them all without
    generating a whole bunch of garbage. I don't think it's worth
    doing that to make this loop shorter, a straight for-loop through
    a list is pretty darn fast. Still, it might be worth trying
]]--

local function ReassignPoints(points)
	
	if (false) then
		for key,value in pairs(openSet) do
			print("OpenSet" , value.Face-1, value.Point-1, value.Distance)
		end
		for key,value in pairs(faces) do
			print( "Face" , key-1, value.Vertex0-1 )
		end
	end
    --0123
	--for (int i = 0; i <= openSetTail; i++)
	local i = 0
	--for i = 1, openSetTail do --@@@
	while(i < openSetTail) do --@@@
		i+=1
		
		--print("looking up", i-1)
        local fp = openSet[i]

        if (Contains(litFaces, fp.Face)) then
            local assigned = false
            local point = points[fp.Point]

            for kvpKey,kvpValue in pairs(faces) do
                local fi = kvpKey
                local face = kvpValue

                local dist = PointFaceDistance(
                    point,
                    points[face.Vertex0],
                    face)

                if (dist > EPSILON) then
                    assigned = true

                    fp.Face = fi
                    fp.Distance = dist

					openSet[i] = fp
					
					--print("Assign ", i-1)
                    break
                end
            end

            if (assigned == false) then
                --[[
                // If point hasn't been assigned, then it's inside the
                // convex hull. Swap it with openSetTail, and decrement
                // openSetTail. We also have to decrement i, because
                // there's now a new thing in openSet[i], so we need i
                // to remain the same the next iteration of the loop.
                ]]--
                fp.Face = INSIDE
                fp.Distance = NaN

                openSet[i] = openSet[openSetTail]
				openSet[openSetTail] = fp
				
				--print("Assign B", i-1)

                i-=1
                openSetTail-=1
            end
        end
	end
	
	if (false) then
		print("After")
		for key,value in pairs(openSet) do
			print("OpenSet" , value.Face-1, value.Point-1, value.Distance)
		end
		for key,value in pairs(faces) do
			print( "Face" , key-1, value.Vertex0-1 )
		end
	end
end

local function VerifyOpenSet(points)
    --for (int i = 0; i < openSet.Count; i++) --@@@
    for i=1, Count(openSet) do --@@@
        if (i > openSetTail) then
            assert(openSet[i].Face == INSIDE)
        else 
            assert(openSet[i].Face ~= INSIDE)
            assert(openSet[i].Face ~= UNASSIGNED)

            assert(PointFaceDistance(
                    points[openSet[i].Point],
                    points[faces[openSet[i].Face].Vertex0],
                    faces[openSet[i].Face]) > 0.0)
        end
    end
end

local function VerifyHorizon()
	--for (int i = 0; i < horizon.Count; i++) --@@@
	
    for i = 1, Count(horizon) do --@@@
        --local prev = i == 0 ? horizon.Count - 1 : i - 1
		local prev 
		if (i == 1) then --i == 0 --@@@
            prev = Count(horizon)  --Last index
        else
            prev = i - 1
        end

        assert(horizon[prev].Edge1 == horizon[i].Edge0)
        assert(HasEdge(faces[horizon[i].Face], horizon[i].Edge1, horizon[i].Edge0))
    end
end

--   Recursively search to find the horizon or lit set.
local function SearchHorizon(points, point, prevFaceIndex, faceCount, face)
    --assert(prevFaceIndex >= 0)
   -- assert(litFaces.Contains(prevFaceIndex))
    --assert(litFaces.Contains(faceCount) == false)
   -- assert(FaceEquals(faces[faceCount],face))

    
    --litFaces.Add(faceCount)
    table.insert(litFaces,faceCount)

    --[[
    Use prevFaceIndex to determine what the next face to search will
    be, and what edges we need to cross to get there. It's important
    that the search proceeds in counter-clockwise order from the
    previous face.
    ]]--
    local nextFaceIndex0 = 0
    local nextFaceIndex1 = 0
    local edge0 = 0
    local edge1 = 0
    local edge2 = 0

    if (prevFaceIndex == face.Opposite0) then
        nextFaceIndex0 = face.Opposite1
        nextFaceIndex1 = face.Opposite2

        edge0 = face.Vertex2
        edge1 = face.Vertex0
        edge2 = face.Vertex1
    elseif (prevFaceIndex == face.Opposite1) then
        nextFaceIndex0 = face.Opposite2;
        nextFaceIndex1 = face.Opposite0;

        edge0 = face.Vertex0;
        edge1 = face.Vertex1;
        edge2 = face.Vertex2;
    else
        --assert(prevFaceIndex == face.Opposite2)

        nextFaceIndex0 = face.Opposite0
        nextFaceIndex1 = face.Opposite1

        edge0 = face.Vertex1
        edge1 = face.Vertex2
        edge2 = face.Vertex0
    end

    if (Contains(litFaces, nextFaceIndex0) == false) then
        local oppositeFace = faces[nextFaceIndex0]

        local dist = PointFaceDistance(
            point,
            points[oppositeFace.Vertex0],
            oppositeFace)

        if (dist <= 0.0) then
            table.insert(horizon,HorizonEdge(nextFaceIndex0, edge0, edge1))
        else
            SearchHorizon(points, point, faceCount, nextFaceIndex0, oppositeFace)
        end
    end

    if (Contains(litFaces, nextFaceIndex1) == false) then
        local oppositeFace = faces[nextFaceIndex1]

        local dist = PointFaceDistance(
            point,
            points[oppositeFace.Vertex0],
            oppositeFace)

        if (dist <= 0.0) then
			table.insert(horizon,HorizonEdge(nextFaceIndex1, edge1, edge2))
                
        else 
            SearchHorizon(points, point, faceCount, nextFaceIndex1, oppositeFace)
        end
    end
end

--[[
	Start the search for the horizon.
	
    The search is a DFS search that searches neighboring triangles in
    a counter-clockwise fashion. When it find a neighbor which is not
    lit, that edge will be a line on the horizon. If the search always
    proceeds counter-clockwise, the edges of the horizon will be found
    in counter-clockwise order.
    
    The heart of the search can be found in the recursive
    SearchHorizon() method, but the the first iteration of the search
    is special, because it has to visit three neighbors (all the
    neighbors of the initial triangle), while the rest of the search
    only has to visit two (because one of them has already been
    visited, the one you came from).
]]--

local function FindHorizon(points, point, fi, face)

	-- TODO should I use epsilon in the PointFaceDistance comparisons?

    litFaces = {}
    horizon = {}

    table.insert(litFaces, fi)
    
    --assert(PointFaceDistance(point, points[face.Vertex0], face) > 0.0)

    -- For the rest of the recursive search calls, we first check if the
    -- triangle has already been visited and is part of litFaces.
    -- However, in this first call we can skip that because we know it
    -- can't possibly have been visited yet, since the only thing in
    -- litFaces is the current triangle.
  
    local oppositeFace = faces[face.Opposite0]

    local dist = PointFaceDistance(
        point,
        points[oppositeFace.Vertex0],
        oppositeFace)

    if (dist <= 0.0) then
        --horizon.Add(HorizonEdge(face.Opposite0,face.Vertex1,face.Vertex2))
        table.insert(horizon,HorizonEdge(face.Opposite0,face.Vertex1,face.Vertex2))
    else
        SearchHorizon(points, point, fi, face.Opposite0, oppositeFace)
    end
 

    if (Contains(litFaces, face.Opposite1) == false) then
        local oppositeFace = faces[face.Opposite1]

        local dist = PointFaceDistance(
            point,
            points[oppositeFace.Vertex0],
            oppositeFace);

        if (dist <= 0.0) then
            table.insert(horizon, HorizonEdge(face.Opposite1,face.Vertex2, face.Vertex0))
        else
            SearchHorizon(points, point, fi, face.Opposite1, oppositeFace)
        end
    end

    if (Contains(litFaces, face.Opposite2) == false) then
        local oppositeFace = faces[face.Opposite2]

        local dist = PointFaceDistance(point, points[oppositeFace.Vertex0], oppositeFace)

        if (dist <= 0.0) then
            table.insert(horizon, HorizonEdge(face.Opposite2, face.Vertex0, face.Vertex1))
        else
            SearchHorizon(points, point, fi, face.Opposite2, oppositeFace)
        end
    end
end


--[[
	Find four points in the point cloud that are not coplanar for the
	seed hull
]]--	

local function FindInitialHullIndices(points)
    local count = Count(points)

    --for (int i0 = 0; i0 < count - 3; i0++) ---@@@@
    for i0 = 1, count - 2 do

        --for (int i1 = i0 + 1; i1 < count - 2; i1++)  --@@@@
		for i1 = i0 + 1, count - 1 do
		    local p0 = points[i0]
		    local p1 = points[i1]

			if (AreCoincident(p0, p1)) then
                continue
            end

            --for (int i2 = i1 + 1; i2 < count - 1; i2++)  --@@@@
			for i2 = i1 + 1, count do
                local p2 = points[i2]

                if (AreCollinear(p0, p1, p2)) then
                    continue
                end

                --for (int i3 = i2 + 1; i3 < count - 0; i3++) --@@@@
                for i3 = i2 + 1, count + 1 do
                    local p3 = points[i3]

                    if(AreCoplanar(p0, p1, p2, p3)) then 
                        continue
                    end
                    return i0, i1, i2, i3
				end
            end
		end
    end
    error("Can't generate hull, points are coplanar")
end

local function GenerateInitialHull(points) 
    --[[
        Find points suitable for use as the seed hull. Some varieties of
        this algorithm pick extreme points here, but I'm not convinced
        you gain all that much from that. Currently what it does is just
        find the first four points that are not coplanar.
    ]]--

    local b0, b1, b2, b3 = FindInitialHullIndices(points)

    local v0 = points[b0]
    local v1 = points[b1]
    local v2 = points[b2]
    local v3 = points[b3]

    local above = Dot(v3 - v1, Cross(v1 - v0, v2 - v0)) > 0.0

    --[[
        Create the faces of the seed hull. You need to draw a diagram
        here, otherwise it's impossible to know what's going on :)

        Basically: there are two different possible start-tetrahedrons,
        depending on whether the fourth point is above or below the base
        triangle. If you draw a tetrahedron with these coordinates (in a
        right-handed coordinate-system):

        b0 = (0,0,0)
        b1 = (1,0,0)
        b2 = (0,1,0)
        b3 = (0,0,1)

        you can see the first case (set b3 = (0,0,-1) for the second
        case). The faces are added with the proper references to the
        faces opposite each vertex
    ]]--
	
	
	--Bump the indices (3,1,2 etc by 1, because lua 1 array)
    faceCount = 0 -- stays on 0, its the number of faces in the array: correct elsewhere!
    if (above) then
		faces[faceCount+1] = Face(b0, b2, b1, 3+1, 1+1, 2+1, Normal(points[b0], points[b2], points[b1]))
        faceCount+=1
		faces[faceCount+1] = Face(b0, b1, b3, 3+1, 2+1, 0+1, Normal(points[b0], points[b1], points[b3]))
        faceCount+=1
		faces[faceCount+1] = Face(b0, b3, b2, 3+1, 0+1, 1+1, Normal(points[b0], points[b3], points[b2]))
        faceCount+=1
		faces[faceCount+1] = Face(b1, b2, b3, 2+1, 1+1, 0+1, Normal(points[b1], points[b2], points[b3]))
        faceCount+=1
    else
		faces[faceCount+1] = Face(b0, b1, b2, 3+1, 2+1, 1+1, Normal(points[b0], points[b1], points[b2]))
        faceCount+=1
		faces[faceCount+1] = Face(b0, b3, b1, 3+1, 0+1, 2+1, Normal(points[b0], points[b3], points[b1]))
        faceCount+=1
		faces[faceCount+1] = Face(b0, b2, b3, 3+1, 1+1, 0+1, Normal(points[b0], points[b2], points[b3]))
        faceCount+=1
		faces[faceCount+1] = Face(b1, b3, b2, 2+1, 0+1, 1+1, Normal(points[b1], points[b3], points[b2]))
        faceCount+=1
    end

    --VerifyFaces(points)

    --[[
        Create the openSet. Add all points except the points of the seed
        hull.
    ]]--

    --for (int i = 0; i < points.Count; i++)  --@@@
    for i = 1, Count(points) do
        if (i == b0 or i == b1 or i == b2 or i == b3) then
            continue
        end

        --openSet.Add(PointFace(i, UNASSIGNED, 0.0))
        table.insert(openSet, PointFace(i, UNASSIGNED, 0.0))
    end

    --[[
        Add the seed hull verts to the tail of the list.
    ]]--
    
    table.insert(openSet,PointFace(b0, INSIDE, NaN))
    table.insert(openSet,PointFace(b1, INSIDE, NaN))
    table.insert(openSet,PointFace(b2, INSIDE, NaN))
    table.insert(openSet,PointFace(b3, INSIDE, NaN))
    --openSet.Add(PointFace(b0, INSIDE, NaN))
    --openSet.Add(PointFace(b1, INSIDE, NaN))
    --openSet.Add(PointFace(b2, INSIDE, NaN))
    --openSet.Add(PointFace(b3, INSIDE, NaN))

    --[[
        Set the openSetTail value. Last item in the array is
        openSet.Count - 1, but four of the points (the verts of the seed
        hull) are part of the closed set, so move openSetTail to just
        before those.
        
        (last is now #openSet !)
    ]]--
    --openSetTail = openSet.Count - 5 --@@@@
    openSetTail = Count(openSet) - 4

	--assert(Count(openSet) == Count(points))

    --[[
        Assign all points of the open set. This does basically the same
        thing as ReassignPoints()
    ]]--

	--for (int i = 0; i <= openSetTail; i++)  ----@@@@
	local i = 0
	while (i < openSetTail) do
		i += 1
	
    --for i = 1, openSetTail do
        --assert(openSet[i].Face == UNASSIGNED)
        --assert(openSet[openSetTail].Face == UNASSIGNED)
        --assert(openSet[openSetTail + 1].Face == INSIDE)

        local assigned = false
        local fp = openSet[i]

        --assert(Count(faces) == 4)
        --assert(Count(faces) == faceCount)
        --for (int j = 0; j < 4; j++)  ---@@@@
        for j = 1, 4 do
           -- assert(faces[j] ~= nil)

            local face = faces[j]

            local dist = PointFaceDistance(points[fp.Point], points[face.Vertex0], face);

            if (dist > 0) then
                fp.Face = j
                fp.Distance = dist
                openSet[i] = fp

                assigned = true
                break
            end
        end

        if (assigned == false) then
            -- Point is inside
            fp.Face = INSIDE
            fp.Distance = NaN

            --[[
                Point is inside seed hull: swap point with tail, and move
                openSetTail back. We also have to decrement i, because
                there's a new item at openSet[i], and we need to process
                it next iteration
            ]]--
            openSet[i] = openSet[openSetTail]
            openSet[openSetTail] = fp

            openSetTail -= 1
            i -= 1
        end
    end
    --VerifyOpenSet(points)
end

--[[
   Remove all lit faces and construct new faces from the horizon in a
   "cone-like" fashion.

   This is a relatively straight-forward procedure, given that the
   horizon is handed to it in already sorted counter-clockwise. The
   neighbors of the new faces are easy to find: they're the previous
   and next faces to be constructed in the cone, as well as the face
   on the other side of the horizon. We also have to update the face
   on the other side of the horizon to reflect it's new neighbor from
   the cone.
]]--
 
local function ConstructCone(points, farthestPoint)
    
    --foreach (var fi in litFaces)  ---@@
    for _,fi in pairs(litFaces) do
       -- assert(faces[fi] ~= nil) -- ??
        --faces.Remove(fi)
        faces[fi] = nil
    end

	local firstNewFace = faceCount --Facecount is # of faces, make sure to +1 before using it to write/read
	
    --for (int i = 0; i < horizon.Count; i++)  --@@@
    for i = 1, Count(horizon) do
        -- Vertices of the new face, the farthest point as well as the
        -- edge on the horizon. Horizon edge is CCW, so the triangle
        -- should be as well.
        local v0 = farthestPoint
        local v1 = horizon[i].Edge0
        local v2 = horizon[i].Edge1

        -- Opposite faces of the triangle. First, the edge on the other
        -- side of the horizon, then the next/prev faces on the new cone
		local o0 = horizon[i].Face
		
        --local o1 = (i == horizon.Count - 1) ? firstNewFace : firstNewFace + i + 1
        local o1 
		if (i == Count(horizon)) then --Last index --@@@@  horizon.Count-1
            o1 = firstNewFace + 1
        else
            o1 = firstNewFace + i + 1
        end
        
        --local o2 = (i == 0) ? (firstNewFace + horizon.Count - 1) : firstNewFace + i - 1
        local o2
        if (i == 1) then
            o2 = firstNewFace + Count(horizon)  
        else
            o2 = firstNewFace + i - 1
        end
		
		--print(i-1, "o0", o0-1, "o1", o1-1, "o2", o2-1 )
		
        local fi = faceCount + 1
        faceCount+=1
		
		--faces[fi] = Face( ----@@@@@@  incremented faceCount by 1, because 1 based
        faces[fi] = Face(
            v0, v1, v2,
            o0, o1, o2,
            Normal(points[v0], points[v1], points[v2]))

        local horizonFace = faces[horizon[i].Face]

        if (horizonFace.Vertex0 == v1) then
            --assert(v2 == horizonFace.Vertex2)
            horizonFace.Opposite1 = fi
        elseif (horizonFace.Vertex1 == v1) then
            --assert(v2 == horizonFace.Vertex0)
            horizonFace.Opposite2 = fi
        else 
           -- assert(v1 == horizonFace.Vertex2)
           -- assert(v2 == horizonFace.Vertex1)
            horizonFace.Opposite0 = fi
        end
		
		--@@@@@ faces[horizon[i].Face] = horizonFace
        faces[horizon[i].Face] = horizonFace
    end
end



--[[
        Grow the hull. This method takes the current hull, and expands it
        to encompass the point in openSet with the point furthest away
        from its face.
]]--

local function GrowHull(points)
	
	--print("GROW HULL", counter)
	counter+=1
   -- assert(openSetTail >= 0)
	--assert(openSet[1].Face ~= INSIDE) -- assert(openSet[0].Face ~= INSIDE) --@@@@

    -- Find farthest point and first lit face.
	local farthestPoint = 1
	
	local dist = openSet[1].Distance -----local dist = openSet[0].Distance -- @@@

    --for (int i = 1; i <= openSetTail; i++)  ---@@@@
    for i = 2, openSetTail do
        if (openSet[i].Distance > dist) then
            farthestPoint = i
            dist = openSet[i].Distance
        end
	end

    -- Use lit face to find horizon and the rest of the lit
    -- faces.
	FindHorizon(
				points,
				points[openSet[farthestPoint].Point],
				openSet[farthestPoint].Face,
				faces[openSet[farthestPoint].Face])

	--VerifyHorizon()

	--Construct new cone from horizon
	ConstructCone(points, openSet[farthestPoint].Point)

	--VerifyFaces(points)

    --Reassign points
	ReassignPoints(points)
end


function module:GenerateHull(points)
    if (#points < 4)  then
        return nil
    end
    
    faceCount = 0
    openSetTail = -1
	faces = {}
	
	openSet = {}
	litFaces = {}
	horizon = {}

    GenerateInitialHull(points)

    while (openSetTail >= 1) do
        GrowHull(points)
	end
	
	--unroll
	local tris = {}
	for key,value in pairs(faces) do
		local tri = {}
		table.insert(tri, points[value.Vertex0])
		table.insert(tri, points[value.Vertex1])
		table.insert(tri, points[value.Vertex2])
		table.insert(tris, tri)
	end
	return tris
end

return module