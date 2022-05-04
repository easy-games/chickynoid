local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local module = {}

function module:PositionWorld(serverTime, deltaTime)
    if true then
        return
    end
    local movers = CollectionService:GetTagged("Dynamic")

    for _, value: BasePart in pairs(movers) do
        local basePos = value:GetAttribute("BasePos")

        value.Position = basePos + Vector3.new(0, math.sin(serverTime) * 3, 0)
        local PrevPosition = basePos + Vector3.new(0, math.sin(serverTime - deltaTime) * 3, 0)

        value.Velocity = (value.Position - PrevPosition) / deltaTime
    end
end

function module:ServerInit()
    if true then
        return
    end
    local movers = CollectionService:GetTagged("Dynamic")
    for _, value: BasePart in pairs(movers) do
        value:SetAttribute("BasePos", value.Position)
    end
end

-- TODO: This shouldn't be done here
if RunService:IsServer() then
    module:ServerInit()
end

return module
