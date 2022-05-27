local module = {}

function module:Setup(server)

    server.OnPlayerConnected:Connect(function(serv, playerRecord)
        playerRecord:SetCharacterMod("NicerHumanoid")
    end)
end

return module