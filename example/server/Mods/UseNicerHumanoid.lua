local module = {}

function module:Setup(server)

    server.OnPlayerConnected:Connect(function(serv, playerRecord)
        playerRecord:SetHumanoidType("NicerHumanoid")
    end)
end

return module