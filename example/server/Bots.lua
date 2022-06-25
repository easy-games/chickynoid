local Enums = require(game.ReplicatedFirst.Packages.Chickynoid.Enums)
local module = {}
module.nextValidBotUserId  = 26000

--debug harness
local debugPlayers = {}
local invalidUserIds = {
	[26003]=1,
	[26020]=1,	
	[26021]=1,
	[26038]=1,
	[26075]=1,
	[26068]=1,
	[26056]=1,
	[26084]=1,
	[26025]=1,
	[26066]=1,
	[26049]=1,
	[26045]=1,
	[26083]=1,
	[26058]=1,
	[26047]=1,
	[26055]=1,
	[26032]=1,
	[26105]=1,
	[26110]=1,
	[26118]=1,
}

function module:MakeBots(Server, numBots)

	--Always the same seed
	math.randomseed(1)
	
	if (numBots > 200) then
		numBots = 200
	end
	
	for counter = 1, numBots do

		local userId = module.nextValidBotUserId
		
		while (invalidUserIds[userId] ~= nil) do
			userId += 1
		end
		--save it
		module.nextValidBotUserId = userId+1
		
		--Set it to negative
		userId = -userId
				
		
		local playerRecord = Server:AddConnection(userId, nil)
		
		if (playerRecord == nil) then
			continue
		end
		
		playerRecord.name = "RandomBot" .. counter
		playerRecord.respawnTime = tick() + counter * 0.1
		
		playerRecord.waitTime = 0 --Bot AI
		playerRecord.leftOrRight = 1 

		if (math.random()>0.5) then
			playerRecord.leftOrRight = -1
		end
		
		--Spawn them in someplace
		playerRecord.OnBeforePlayerSpawn:Connect(function()
			playerRecord.chickynoid:SetPosition(Vector3.new(math.random(-350,350), 100 ,math.random(-350,350) ) + Vector3.new(-250, 0,0))
		end)
		
		 
		table.insert(debugPlayers, playerRecord)

	
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
			if (playerRecord.chickynoid) then
				playerRecord.chickynoid:HandleEvent(Server, event)
			end
		end
	end

end


return module
