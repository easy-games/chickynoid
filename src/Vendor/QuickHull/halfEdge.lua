local halfEdge = {}
local halfEdge_mt = { __index = halfEdge }

function halfEdge.new(vertex, face)
    local self = {}
    self.vertex = vertex
    self.face = face
    self.next = nil
    self.prev = nil
    self.opposite = nil
    return setmetatable(self, halfEdge_mt)
end

function halfEdge:head()
    return self.vertex
end

function halfEdge:tail()
    return self.prev and self.prev.vertex or nil
end

function halfEdge:length()
    if self:tail() then
        return (self:head().point - self:tail().point).magnitude
    end
    return -1
end

function halfEdge:lengthSquared()
    if self:tail() then
        local v = self:head().point - self:tail().point
        return v.x * v.x + v.y * v.y + v.z * v.z
    end
    return -1
end

function halfEdge:setOpposite(edge)
    self.opposite = edge
    edge.opposite = self
end

return halfEdge
