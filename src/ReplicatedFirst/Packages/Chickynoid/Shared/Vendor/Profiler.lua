local module = {}

active = false
module.tags = {}
module.tagStack = {}

function module:BeginSample(name)
	
	local rec = self.tags[name]
	if (rec == nil) then
		rec = {}
		rec.averages = {}
		rec.average = 0
		rec.currentSample = 0
		self.tags[name] = rec
	end
	
	rec.startTime = tick()
	
	table.insert(module.tagStack, name)	
end

function module:EndSample()
	
	if (#module.tagStack == 0) then
		warn("Profile tagstack already empty")
		return
	end
	local rec = module.tags[module.tagStack[#module.tagStack]]
	table.remove(module.tagStack, #module.tagStack)
	rec.currentSample = tick() - rec.startTime
	
	table.insert(rec.averages, rec.currentSample)
	
	if (#rec.averages > 10) then
		table.remove(rec.averages,1)
	end
	
end

function module:Print(name)
	local rec = module.tags[name]
	if (rec == nil) then
		warn("Unknown tag")
		return
	end
	local average = 0
	local counter = 0
	for key,value in rec.averages do
		average += value
		counter += 1
	end
	average /= counter
		
	print(name, string.format("%.3f", rec.currentSample*1000) .. "ms avg:", string.format("%.3f", average*1000) .. "ms")
end

local nextTick = tick() + 1
if (active == true) then
	game["Run Service"].Heartbeat:Connect(function()
		if (tick() > nextTick) then
			nextTick = tick() + 1
			
			for key,value in module.tags do
				module:Print(key)
			end
		end
	end)
end

return module