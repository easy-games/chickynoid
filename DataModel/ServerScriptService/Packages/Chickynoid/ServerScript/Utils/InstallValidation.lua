local module = {}

module.validInstall = true
module.errors = {}

function module:Validate()
	
	module.validInstall = true
	module.errors = {}
		
	if (game.Players.CharacterAutoLoads == true) then
		self:Error("game.Players.CharacterAutoLoads needs to be false: Chickynoid will handle character creation")
	end
	
	if (game.ReplicatedFirst:FindFirstChild("Packages") == nil or
		game.ReplicatedFirst.Packages:FindFirstChild("Chickynoid") == nil or
		game.ReplicatedFirst.Packages.Chickynoid.Simulation == nil) then
		self:Error("ReplicatedFirst.Packages.Chickynoid missing or missing files!")
	end

	if (game.ServerScriptService:FindFirstChild("Packages") == nil or
		game.ServerScriptService.Packages:FindFirstChild("Chickynoid") == nil or
		game.ServerScriptService.Packages.Chickynoid:FindFirstChild("Server") == nil) then
		self:Error("game.ServerScriptService.Packages.Chickynoid missing or missing files!")
	end

	if (game.ReplicatedStorage:FindFirstChild("Packages") == nil or
		game.ReplicatedStorage.Packages:FindFirstChild("Chickynoid") == nil or
		game.ReplicatedStorage.Packages.Chickynoid:FindFirstChild("RemoteEvent") == nil) then
		self:Error("game.ReplicatedStorage.Packages.Chickynoid.RemoteEvent missing!")
	end
		
	if (module.validInstall == true) then
		print("Chickynoid Install OK")
	else
		warn("Chickynoid Install Not OK")
		for key, value in pairs(self.errors) do
			warn(value)	
		end
		
	end
	
	return module.validInstall
end

function module:Error(message)

	self.validInstall = false
	table.insert(self.errors, message)
	
end


return module
