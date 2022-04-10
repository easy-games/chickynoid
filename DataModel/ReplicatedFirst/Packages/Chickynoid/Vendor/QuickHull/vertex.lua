local vertex = {}
local vertex_mt = {__index = vertex}

function vertex.new(point, index)
	local self = {}
	self.point = point
	self.index = index
	self.next = nil
	self.prev = nil
	self.face = nil
	return setmetatable(self, vertex_mt)
end 

return vertex