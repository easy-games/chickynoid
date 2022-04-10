--This script just lets you tag things as "ServerOwned", which forces it to stay network owned by the server
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


