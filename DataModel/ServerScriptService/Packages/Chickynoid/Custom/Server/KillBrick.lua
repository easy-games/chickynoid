local module = {}

local path = game.ReplicatedFirst.Packages.Chickynoid

function module:Setup(server)
	
end

function module:Step(server, deltaTime)

	local playerRecords = server:GetPlayers()

	for key,playerRecord in pairs(playerRecords) do

		--No character at the moment
		if (playerRecord.chickynoid == nil) then
			continue
		end

		local simulation = playerRecord.chickynoid.simulation
		local state = simulation.state


		local part = simulation:GetStandingPart()

		if (part) then
			if (part:GetAttribute("kill") == true) then
				--kill!
				print("kill")

				local HitPoints = self.server:GetMod("Hitpoints")
				if (HitPoints) then
					HitPoints:SetPlayerHitpoints(playerRecord, 0)
				end


			end
		end
	end	

end


return module
