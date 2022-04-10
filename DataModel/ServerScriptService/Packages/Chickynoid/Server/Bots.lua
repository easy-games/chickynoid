local Enums = require(game.ReplicatedFirst.Packages.Chickynoid.Enums)
local module = {}


--debug harness
local debugPlayers = {}
function module:MakeBots(Server, numBots)

	--Always the same seed
	math.randomseed(1)
	
	if (numBots > 200) then
		numBots = 200
	end
	
	for counter = 1, numBots do

		local userId = -10000-counter
		local playerRecord = Server:AddConnection(userId, nil)

		playerRecord.name = "RandomBot" .. counter

		playerRecord.waitTime = 0 --Bot AI
		playerRecord.leftOrRight = 1 

		if (math.random()>0.5) then
			playerRecord.leftOrRight = -1
		end

		playerRecord.chickynoid = Server:CreateChickynoidAsync(playerRecord)
		table.insert(debugPlayers, playerRecord)

		playerRecord.chickynoid:SetPosition(Vector3.new(math.random(-150,150), 4000 ,math.random(-150,150) ) + Vector3.new(-150, 0,0)) 

		playerRecord.BotThink = function(deltaTime)


			if (playerRecord.waitTime > 0) then
				playerRecord.waitTime -= deltaTime
			end

			local event = {}
			event.t = Enums.EventType.Command
			event.command = {}
			event.command.l = playerRecord.frame
			event.command.x = 0
			event.command.y = 0
			event.command.z = 0
			event.command.serverTime = tick()
			event.command.deltaTime = deltaTime

			if (playerRecord.waitTime <=0) then
				event.command.x = math.sin(playerRecord.frame*0.03 * playerRecord.leftOrRight)
				event.command.y = 0
				event.command.z =  math.cos(playerRecord.frame*0.03 * playerRecord.leftOrRight)

				if (math.random() < 0.05) then
					event.command.y = 1
				end
			end

			if (math.random() < 0.01) then
				playerRecord.waitTime = math.random() * 5                
			end

			playerRecord.frame += 1
			playerRecord.chickynoid:HandleEvent(Server, event)
		end
	end

end


return module
