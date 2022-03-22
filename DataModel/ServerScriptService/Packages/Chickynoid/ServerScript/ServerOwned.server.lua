local CollectionService = game.CollectionService
local list = {}

local owned = CollectionService:GetTagged("ServerOwned")
for key,value in pairs(owned) do
    
    if (value:IsA("BasePart") and value:CanSetNetworkOwnership() == true) then
        value:SetNetworkOwner(nil)
        list[value] = value
    end
end

CollectionService:GetInstanceAddedSignal("ServerOwned"):Connect(function(value)
    
    if (value:IsA("BasePart") and value:CanSetNetworkOwnership() == true) then
        value:SetNetworkOwner(nil)
        list[value] = value
    end
 
end)



CollectionService:GetInstanceRemovedSignal("ServerOwned"):Connect(function(value)
    list[value] = nil
end)



game["Run Service"].Stepped:Connect(function(time,deltaTime)
    
    for key,value in pairs(list) do
        value.Velocity+= Vector3.new(0,0.000001,0)
    end
end)