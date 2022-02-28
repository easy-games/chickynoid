local module = {}

local CollectionService = game:GetService("CollectionService")



function module:PositionWorld(serverTime,deltaTime)
    
    local movers = CollectionService:GetTagged("Dynamic")
    
    for key,value in pairs(movers) do
        local basePos = value:GetAttribute("BasePos")
        
        value.Position = basePos + Vector3.new(0,math.sin(serverTime)*3,0) 
        local PrevPosition =  basePos + Vector3.new(0,math.sin(serverTime - deltaTime)*3,0)
        
        value.Velocity = (value.Position - PrevPosition) / deltaTime
    end
    
    
end


function module:ServerInit()
    
    local movers = CollectionService:GetTagged("Dynamic")
    for key,value in pairs(movers) do
        value:SetAttribute("BasePos", value.Position)        
    end
end

if (game["Run Service"]:IsServer()) then
    module:ServerInit()
end

return module
