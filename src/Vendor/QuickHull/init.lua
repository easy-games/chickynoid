--[[
	This is a module, or rather a set of modules, that will create a convex hull from a point cloud.
	Convex hulls have plenty of application in 3D math as convex shapes tend to be easier and faster to do calculations on.

	This module is a ported version of John Loyd's implementation: http://www.cs.ubc.ca/~lloyd/java/quick_hull3d.html
	It has O(n log(n)) complexity, works with double precision values (although I believe vector3 uses floats), is fairly robust with respect to degenerate situations, and allows the merging of co-planar faces.

	API:

	Constructors:
		quick_hull.new(points)
			> Creates a new quick_hull object from a table filled with Vector3's (the point cloud).
		quick_hull.quick_run(points)
			> Returns a table filled with arrays where each array is filled with 3 vector3 representing a triangle.

	Methods:
		quick_hull:build()
			> Builds the hull on a given quick_hull object.
		quick_hull:collectFaces(skipTriangulation)
			> Returns a table of indices for the quick_hull.vertices table.
			> If skipTriangulation = false then will return a table full of arrays each with 3 indices representing a triangle's indices.

	Properties:
		quick_hull.vertices
			> A table filled with all the vector3's in the point cloud.
			> Use this table as read only, the indices matter!
			
	You are encouraged to try the examples (which are disabled). Make sure to read the code of each test case though. Some need models, etc in the workspace.
	If you already know what you're doing you're free to delete that folder, it has no effect on the module.
		
	You might also notice I've included two other modules, draw and vertices. These are also not needed for the quick_hull module to work and can be deleted.
	However, they are quite useful if you plan on using this module. 

	The draw module is pretty self explanitory and is more or less used for debugging. It's very possible that you may already have functions in your game that will do this kind of debugging so this is less important of the two.

	The vertices module is much more useful in the context of quick_hull. It will take the basic shapes: wedges, ball, cylinder, etc and return their vertices.
	This is really useful for building point clouds b/c if you treat every object as rectangular the bounding points will result in a point cloud that's non-ideal for an accurate convex hull.

	Both these scripts are not very well documented, but I'd imagine most scripters will be able to glance at them to understand what function does what. Then again you can always check the examples :)
			
	Enjoy!
	EgoMoose

	https://www.roblox.com/library/447335959/quick_hull-lua
--]]

local vertexList = require(script:WaitForChild("vertexList", 1))
local vertexModule = require(script:WaitForChild("vertex", 1))
local faceModule = require(script:WaitForChild("face", 1))

local VISIBLE = 0
local NON_CONVEX = 1
local DELETED = 2

local function combine(a, b)
    local t = {}
    local n = #a
    for i = 1, n do
        t[i] = a[i]
    end
    for i = 1, #b do
        t[n + i] = b[i]
    end
    return t
end

local function pointLineDistance(p, a, b)
    local ab = b - a
    local v = (p - a):Cross(ab)
    local area = v.x * v.x + v.y * v.y + v.z * v.z
    local s = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    if s == 0 then
        error("a and b are the same point")
    end
    return math.sqrt(area / s)
end

local function getPlaneNormal(p1, p2, p3)
    local out = p1 - p2
    local tmp = p2 - p3
    out = out:Cross(tmp)
    return out.unit
end

-- class

local EPSILON = 0.0001

local MERGE_NON_CONVEX_WRT_LARGER_FACE = 1
local MERGE_NON_CONVEX = 2

local quick_hull = {}
local quick_hull_mt = { __index = quick_hull }

function quick_hull.new(points)
    if #points < 4 then
        error("cannot build a simplex out of < 4 points")
    end

    local self = {}
    self.tolerance = -1
    self.nFaces = 0
    self.nPoints = #points
    self.faces = {}
    self.newFaces = {}
    self.claimed = vertexList.new()
    self.unclaimed = vertexList.new()

    self.vertices = {}
    for i = 1, #points do
        table.insert(self.vertices, vertexModule.new(points[i], i))
    end
    self.discardedFaces = {}
    self.vertexPointIndices = {}

    return setmetatable(self, quick_hull_mt)
end

function quick_hull.quick_run(points)
    local triangles = {}

    local qh = quick_hull.new(points)
    qh:build()

    local faces = qh:collectFaces(false)
    for i = 1, #faces do
        local f = faces[i]
        local a = qh.vertices[f[1]].point
        local b = qh.vertices[f[2]].point
        local c = qh.vertices[f[3]].point
        table.insert(triangles, { a, b, c })
    end

    return triangles
end

function quick_hull:addVertexToFace(vertex, face)
    vertex.face = face
    if not face.outside then
        self.claimed:add(vertex)
    else
        self.claimed:insertBefore(face.outside, vertex)
    end
    face.outside = vertex
end

function quick_hull:removeVertexFromFace(vertex, face)
    if vertex == face.outside then
        if vertex.next and vertex.next.face == face then
            face.outside = vertex.next
        else
            face.outside = nil
        end
    end
    self.claimed:remove(vertex)
end

function quick_hull:removeAllVerticesFromFace(face)
    if face.outside then
        local endy = face.outside
        while endy.next and endy.next.face == face do
            endy = endy.next
        end
        self.claimed:removeChain(face.outside, endy)
        endy.next = nil
        return face.outside
    end
end

function quick_hull:deleteFaceVertices(face, absorbingFace)
    local faceVertices = self:removeAllVerticesFromFace(face)
    if faceVertices then
        if not absorbingFace then
            self.unclaimed:addAll(faceVertices)
        else
            local nextVertex
            local vertex = faceVertices
            while vertex do
                nextVertex = vertex.next
                local distance = absorbingFace:distanceToPlane(vertex.point)

                if distance > self.tolerance then
                    self:addVertexToFace(vertex, absorbingFace)
                else
                    self.unclaimed:add(vertex)
                end

                vertex = nextVertex
            end
        end
    end
end

function quick_hull:resolveUnclaimedPoints(newFaces)
    local vertexNext = self.unclaimed:first()
    local vertex = vertexNext
    while vertex do
        vertexNext = vertex.next
        local maxDistance = self.tolerance
        local maxFace
        for i = 1, #newFaces do
            local face = newFaces[i]
            if face.mark == VISIBLE then
                local dist = face:distanceToPlane(vertex.point)
                if dist > maxDistance then
                    maxDistance = dist
                    maxFace = face
                end
                if maxDistance > 1000 * self.tolerance then
                    break
                end
            end
        end

        if maxFace then
            self:addVertexToFace(vertex, maxFace)
        end

        vertex = vertexNext
    end
end

local XYZ = { "x", "y", "z" }

function quick_hull:computeExtremes()
    local min = {}
    local max = {}

    local minVertices = {}
    local maxVertices = {}

    for i = 1, 3 do
        minVertices[i] = self.vertices[1]
        maxVertices[i] = self.vertices[1]
    end

    for i = 1, 3 do
        min[i] = self.vertices[1].point[XYZ[i]]
        max[i] = self.vertices[1].point[XYZ[i]]
    end

    for i = 2, #self.vertices do
        local vertex = self.vertices[i]
        local point = vertex.point

        for j = 1, 3 do
            if point[XYZ[j]] < min[j] then
                min[j] = point[XYZ[j]]
                minVertices[j] = vertex
            end
        end

        for j = 1, 3 do
            if point[XYZ[j]] > max[j] then
                max[j] = point[XYZ[j]]
                maxVertices[j] = vertex
            end
        end
    end

    self.tolerance = 3
        * EPSILON
        * (
            math.max(math.abs(min[1]), math.abs(max[1]))
            + math.max(math.abs(min[2]), math.abs(max[2]))
            + math.max(math.abs(min[3]), math.abs(max[3]))
        )

    return minVertices, maxVertices
end

function quick_hull:createInitialSimplex()
    local vertices = self.vertices
    local min, max = self:computeExtremes()
    local v0, v1, v2, v3

    local maxDistance = 0
    local indexMax = 0
    for i = 1, 3 do
        local distance = max[i].point[XYZ[i]] - min[i].point[XYZ[i]]
        if distance > maxDistance then
            maxDistance = distance
            indexMax = i
        end
    end
    v0 = min[indexMax]
    v1 = max[indexMax]

    maxDistance = 0
    for i = 1, #self.vertices do
        local vertex = self.vertices[i]
        if vertex ~= v0 and vertex ~= v1 then
            local distance = pointLineDistance(vertex.point, v0.point, v1.point)
            if distance > maxDistance then
                maxDistance = distance
                v2 = vertex
            end
        end
    end

    if v2 == nil then
        return
    end

    local normal = getPlaneNormal(v0.point, v1.point, v2.point)
    local distPO = v0.point:Dot(normal)
    maxDistance = 0
    for i = 1, #self.vertices do
        local vertex = self.vertices[i]
        if vertex ~= v0 and vertex ~= v1 and vertex ~= v2 then
            local distance = math.abs(normal:Dot(vertex.point) - distPO)
            if distance > maxDistance then
                maxDistance = distance
                v3 = vertex
            end
        end
    end

    if v3 == nil then
        return
    end

    local faces = {}
    if v3.point:Dot(normal) - distPO < 0 then
        faces = combine(faces, {
            faceModule.createTriangle(v0, v1, v2),
            faceModule.createTriangle(v3, v1, v0),
            faceModule.createTriangle(v3, v2, v1),
            faceModule.createTriangle(v3, v0, v2),
        })

        -- I hate Lua and its stupid non-zero index
        for i = 0, 2 do
            local j = (i + 1) % 3
            faces[i + 2]:getEdge(2):setOpposite(faces[1]:getEdge(j))
            faces[i + 2]:getEdge(1):setOpposite(faces[j + 2]:getEdge(0))
        end
    else
        faces = combine(faces, {
            faceModule.createTriangle(v0, v2, v1),
            faceModule.createTriangle(v3, v0, v1),
            faceModule.createTriangle(v3, v1, v2),
            faceModule.createTriangle(v3, v2, v0),
        })

        for i = 0, 2 do
            local j = (i + 1) % 3
            faces[i + 2]:getEdge(2):setOpposite(faces[1]:getEdge((3 - i) % 3))
            faces[i + 2]:getEdge(0):setOpposite(faces[j + 2]:getEdge(1))
        end
    end

    for i = 1, 4 do
        table.insert(self.faces, faces[i])
    end

    for i = 1, #vertices do
        local vertex = vertices[i]
        if vertex ~= v0 and vertex ~= v1 and vertex ~= v2 and vertex ~= v3 then
            maxDistance = self.tolerance
            local maxFace
            for j = 1, 4 do
                local distance = faces[j]:distanceToPlane(vertex.point)
                if distance > maxDistance then
                    maxDistance = distance
                    maxFace = faces[j]
                end
            end

            if maxFace then
                self:addVertexToFace(vertex, maxFace)
            end
        end
    end
end

function quick_hull:reindexFaceAndVertices()
    local activeFaces = {}
    for i = 1, #self.faces do
        local face = self.faces[i]
        if face.mark == VISIBLE then
            table.insert(activeFaces, face)
        end
    end
    self.faces = activeFaces
end

function quick_hull:collectFaces(skipTriangulation)
    local faceIndices = {}
    for i = 1, #self.faces do
        if self.faces[i].mark ~= VISIBLE then
            error("attempt to include a destroyed face in the hull")
        end
        local indices = self.faces[i]:collectIndices()
        if skipTriangulation then
            table.insert(faceIndices, indices)
        else
            for j = 1, #indices - 2 do
                table.insert(faceIndices, { indices[1], indices[j + 1], indices[j + 2] })
            end
        end
    end
    return faceIndices
end

function quick_hull:nextVertexToAdd()
    if not self.claimed:isEmpty() then
        local eyeVertex, vertex
        local maxDistance = 0
        local eyeFace = self.claimed:first().face
        vertex = eyeFace.outside
        while vertex and vertex.face == eyeFace do
            local distance = eyeFace:distanceToPlane(vertex.point)
            if distance > maxDistance then
                maxDistance = distance
                eyeVertex = vertex
            end
            vertex = vertex.next
        end
        return eyeVertex
    end
end

function quick_hull:computeHorizon(eyePoint, crossEdge, face, horizon)
    self:deleteFaceVertices(face)
    face.mark = DELETED

    local edge
    if not crossEdge then
        crossEdge = face:getEdge(0)
        edge = crossEdge
    else
        edge = crossEdge.next
    end

    repeat
        local oppositeEdge = edge.opposite
        local oppositeFace = oppositeEdge.face
        if oppositeFace.mark == VISIBLE then
            if oppositeFace:distanceToPlane(eyePoint) > self.tolerance then
                self:computeHorizon(eyePoint, oppositeEdge, oppositeFace, horizon)
            else
                table.insert(horizon, edge)
            end
        end
        edge = edge.next
    until edge == crossEdge
end

function quick_hull:addAdjoiningFace(eyeVertex, horizonEdge)
    local face = faceModule.createTriangle(eyeVertex, horizonEdge:tail(), horizonEdge:head())
    table.insert(self.faces, face)
    face:getEdge(-1):setOpposite(horizonEdge.opposite)
    return face:getEdge(0)
end

function quick_hull:addNewFaces(eyeVertex, horizon)
    self.newFaces = {}
    local firstSideEdge, previousSideEdge
    for i = 1, #horizon do
        local horizonEdge = horizon[i]
        local sideEdge = self:addAdjoiningFace(eyeVertex, horizonEdge)
        if not firstSideEdge then
            firstSideEdge = sideEdge
        else
            sideEdge.next:setOpposite(previousSideEdge)
        end
        table.insert(self.newFaces, sideEdge.face)
        previousSideEdge = sideEdge
    end
    firstSideEdge.next:setOpposite(previousSideEdge)
end

function quick_hull:getTriangulatedFaces()
    local faces = {}
    for i = 1, #self.faces do
        faces = combine(faces, self.faces[i]:triangulate())
    end
    return faces
end

function quick_hull:oppositeFaceDistance(edge)
    return edge.face:distanceToPlane(edge.opposite.face.centroid)
end

function quick_hull:doAdjacentMerge(face, mergeType)
    local edge = face.edge
    local convex = true
    local it = 0
    repeat
        if it >= face.nVertices then
            error("merge recursion limit exceeded")
        end
        local oppositeFace = edge.opposite.face
        local merge = false

        if mergeType == MERGE_NON_CONVEX then
            if
                self:oppositeFaceDistance(edge) > -self.tolerance
                or self:oppositeFaceDistance(edge.opposite) > self.tolerance
            then
                merge = true
            end
        else
            if face.area > oppositeFace.area then
                if self:oppositeFaceDistance(edge) > -self.tolerance then
                    merge = true
                elseif self:oppositeFaceDistance(edge.opposite) > -self.tolerance then
                    convex = false
                end
            else
                if self:oppositeFaceDistance(edge.opposite) > -self.tolerance then
                    merge = true
                elseif self:oppositeFaceDistance(edge) > -self.tolerance then
                    convex = false
                end
            end

            if merge then
                local discardedFaces = face:mergeAdjacentFaces(edge, {})
                for i = 1, #discardedFaces do
                    self:deleteFaceVertices(discardedFaces[i], face)
                end
                return true
            end
        end
        edge = edge.next
        it = it + 1
    until edge == face.edge

    if not convex then
        face.mark = NON_CONVEX
    end
    return false
end

function quick_hull:addVertexToHull(eyeVertex)
    local horizon = {}
    self.unclaimed:clear()

    self:removeVertexFromFace(eyeVertex, eyeVertex.face)
    self:computeHorizon(eyeVertex.point, nil, eyeVertex.face, horizon)
    self:addNewFaces(eyeVertex, horizon)

    for i = 1, #self.newFaces do
        local face = self.newFaces[i]
        if face.mark == VISIBLE then
            while self:doAdjacentMerge(face, MERGE_NON_CONVEX_WRT_LARGER_FACE) do
            end
        end
    end

    for i = 1, #self.newFaces do
        local face = self.newFaces[i]
        if face.mark == NON_CONVEX then
            face.mark = VISIBLE
            while self:doAdjacentMerge(face, MERGE_NON_CONVEX) do
            end
        end
    end

    self:resolveUnclaimedPoints(self.newFaces)
end

function quick_hull:build()
    local iterations = 0
    self:createInitialSimplex()
    local eyeVertex = self:nextVertexToAdd()
    while eyeVertex do
        iterations = iterations + 1
        self:addVertexToHull(eyeVertex)
        eyeVertex = self:nextVertexToAdd()
    end
    self:reindexFaceAndVertices()
end

return quick_hull
