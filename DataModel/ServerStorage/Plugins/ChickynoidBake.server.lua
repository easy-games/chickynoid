-- Create a new toolbar section titled "Custom Script Tools"
local toolbar = plugin:CreateToolbar("Chickynoid")


local button = toolbar:CreateButton("Go", "Go", "rbxassetid://4458901886")

button.ClickableWhenViewportHidden = true

local function ProcessMeshes()
	
	
	local database = {}
	local parts = {}
	for key,instance in pairs(game:GetDescendants()) do
		
		if (instance:IsA("MeshPart")) then
			if (instance.CanCollide == true) then
				database[instance.MeshId] = instance.MeshId
				parts[instance] = instance
			end
		end
	end
	
	
	--Download all the meshes
	local count = 0
	for key,value in pairs(database) do
		count += 1
	end
	print("Meshes Found:", count)	
	
	--Download the meshes
	for key,id in pairs(database) do
		print("Fetching: ", id)
		local data = game.HttpService:GetAsync("rbxassetid://9363457191", false)
		print(data)
		"https://assetdelivery.roblox.com/v1/asset?id=9363457191"
	end
end
button.Click:Connect(ProcessMeshes)