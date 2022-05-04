local v3 = Vector3.new
local halfEdge = require(script.Parent:WaitForChild("halfEdge", 1))

local function copyVector(v)
    return v3(v.x, v.y, v.z)
end

local function scaleAndAdd(a, b, scale)
    return a + (b * scale)
end

local VISIBLE = 0
local NON_CONVEX = 1
local DELETED = 2

local face = {}
local face_mt = { __index = face }

function face.new()
    local self = {}
    self.normal = v3()
    self.centroid = v3()
    self.offset = 0
    self.outside = nil
    self.mark = VISIBLE
    self.edge = nil
    self.nVertices = 0
    return setmetatable(self, face_mt)
end

function face.createTriangle(v0, v1, v2, minArea)
    local minArea = minArea or 0
    local face = face.new()
    local e0 = halfEdge.new(v0, face)
    local e1 = halfEdge.new(v1, face)
    local e2 = halfEdge.new(v2, face)

    e0.next = e1
    e2.prev = e1
    e1.next = e2
    e0.prev = e2
    e2.next = e0
    e1.prev = e0

    face.edge = e0
    face:computeNormalAndCentroid(minArea)
    return face
end

function face:getEdge(i)
    local it = self.edge
    while i > 0 do
        it = it.next
        i = i - 1
    end
    while i < 0 do
        it = it.prev
        i = i + 1
    end
    return it
end

function face:computeNormal()
    local e0 = self.edge
    local e1 = e0.next
    local e2 = e1.next
    local v2 = e1:head().point - e0:head().point
    local v1

    self.nVertices = 2
    self.normal = v3()
    while e2 ~= e0 do
        v1 = copyVector(v2)
        v2 = e2:head().point - e0:head().point
        self.normal = self.normal + v1:Cross(v2)
        e2 = e2.next
        self.nVertices = self.nVertices + 1
    end

    self.area = self.normal.magnitude
    self.normal = self.normal * (1 / self.area)
end

function face:computeNormalMinArea(minArea)
    self:computeNormal()
    if self.area < minArea then
        local maxEdge
        local maxSquaredLength = 0
        local edge = self.edge

        repeat
            local lengthSquared = edge:lengthSquared()
            if lengthSquared > maxSquaredLength then
                maxEdge = edge
                maxSquaredLength = lengthSquared
            end
            edge = edge.next
        until edge == self.edge

        local p1 = maxEdge:tail().point
        local p2 = maxEdge:head().point
        local maxVector = p2 - p1
        local maxLength = math.sqrt(maxSquaredLength)
        maxVector = maxVector * (1 / maxLength)
        local maxProjection = self.normal:Dot(maxVector)
        self.normal = self.normal + (maxVector * -maxProjection)
        self.normal = self.normal.unit
    end
end

function face:computeCentroid()
    self.centroid = v3()
    local edge = self.edge
    repeat
        self.centroid = self.centroid + edge:head().point
        edge = edge.next
    until edge == self.edge
    self.centroid = self.centroid * (1 / self.nVertices)
end

function face:computeNormalAndCentroid(minArea)
    if minArea then
        self:computeNormalMinArea(minArea)
    else
        self:computeNormal()
    end
    self:computeCentroid()
    self.offset = self.normal:Dot(self.centroid)
end

function face:distanceToPlane(point)
    return self.normal:Dot(point) - self.offset
end

function face:connectHalfEdges(prev, next)
    local discardedFace
    if prev.opposite.face == next.opposite.face then
        local oppositeFace = next.opposite.face
        local oppositeEdge
        if prev == self.edge then
            self.edge = next
        end
        if oppositeFace.nVertices == 3 then
            oppositeEdge = next.opposite.prev.opposite
            oppositeFace.mark = DELETED
            discardedFace = oppositeFace
        else
            oppositeEdge = next.opposite.next
            if oppositeFace.edge == oppositeEdge.prev then
                oppositeFace.edge = oppositeEdge
            end

            oppositeEdge.prev = oppositeEdge.prev.prev
            oppositeEdge.prev.next = oppositeEdge
        end

        next.prev = prev.prev
        next.prev.next = next

        next:setOpposite(oppositeEdge)

        oppositeFace:computeNormalAndCentroid()
    else
        prev.next = next
        next.prev = prev
    end
    return discardedFace
end

function face:mergeAdjacentFaces(adjacentEdge, discardedFaces)
    local oppositeEdge = adjacentEdge.opposite
    local oppositeFace = oppositeEdge.face

    table.insert(discardedFaces, oppositeFace)
    oppositeFace.mark = DELETED

    local adjacentEdgePrev = adjacentEdge.prev
    local adjacentEdgeNext = adjacentEdge.next
    local oppositeEdgePrev = oppositeEdge.prev
    local oppositeEdgeNext = oppositeEdge.next

    while adjacentEdgePrev.opposite.face == oppositeFace do
        adjacentEdgePrev = adjacentEdgePrev.prev
        oppositeEdgeNext = oppositeEdgeNext.next
    end
    while adjacentEdgeNext.opposite.face == oppositeFace do
        adjacentEdgeNext = adjacentEdgeNext.next
        oppositeEdgePrev = oppositeEdgePrev.prev
    end

    local edge = oppositeEdgeNext
    while edge ~= oppositeEdgePrev.next do
        edge.face = self
        edge = edge.next
    end

    self.edge = adjacentEdgeNext

    local discardedFace = self:connectHalfEdges(oppositeEdgePrev, adjacentEdgeNext)
    if discardedFace then
        table.insert(discardedFaces, discardedFace)
    end
    discardedFace = self:connectHalfEdges(adjacentEdgePrev, oppositeEdgeNext)
    if discardedFace then
        table.insert(discardedFaces, discardedFace)
    end

    self:computeNormalAndCentroid()
    return discardedFaces
end

function face:collectIndices()
    local indices = {}
    local edge = self.edge
    repeat
        table.insert(indices, edge:head().index)
        edge = edge.next
    until edge == self.edge
    return indices
end

return face
