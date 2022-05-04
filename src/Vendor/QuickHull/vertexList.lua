local vertexList = {}
local vertexList_mt = { __index = vertexList }

function vertexList.new()
    local self = {}
    self.head = nil
    self.tail = nil
    return setmetatable(self, vertexList_mt)
end

function vertexList:clear()
    self.head = nil
    self.tail = nil
end

function vertexList:insertBefore(target, node)
    node.prev = target.prev
    node.next = target
    if not node.prev then
        self.head = node
    else
        node.prev.next = node
    end
    target.prev = node
end

function vertexList:insertAfter(target, node)
    node.prev = target
    node.next = target.next
    if not node.next then
        self.tail = node
    else
        node.next.prev = node
    end
    target.next = node
end

function vertexList:add(node)
    if not self.head then
        self.head = node
    else
        self.tail.next = node
    end
    node.prev = self.tail
    node.next = nil
    self.tail = node
end

function vertexList:addAll(node)
    if not self.head then
        self.head = node
    else
        self.tail.next = node
    end
    node.prev = self.tail

    while node.next do
        node = node.next
    end
    self.tail = node
end

function vertexList:remove(node)
    if not node.prev then
        self.head = node.next
    else
        node.prev.next = node.next
    end

    if not node.next then
        self.tail = node.prev
    else
        node.next.prev = node.prev
    end
end

function vertexList:removeChain(a, b)
    if not a.prev then
        self.head = b.next
    else
        a.prev.next = b.next
    end

    if not b.next then
        self.tail = a.prev
    else
        b.next.prev = a.prev
    end
end

function vertexList:first()
    return self.head
end

function vertexList:isEmpty()
    return not self.head
end

return vertexList
