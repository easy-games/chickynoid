local module = {}
local Enums = require(script.Parent.Parent.Enums)

module.mods = {}

--[=[
	Registers a single ModuleScript as a mod.
	@param mod ModuleScript -- Individual ModuleScript to be loaded as a mod.
]=]
function module:RegisterMod(context: string, mod: ModuleScript)

    if not mod:IsA("ModuleScript") then
        warn("Attempted to load", mod:GetFullName(), "as a mod but it is not a ModuleScript")
        return
    end

    local contents = require(mod)
    if (contents == nil) then
        warn("Attempted to load", mod:GetFullName(), "as a mod, but it's contents is empty.")
        return
    end
    
    if (self.mods[context] == nil) then
        self.mods[context] = {}
    end

    local modPriority = contents.PRIORITY or Enums.Priority.Normal
    if (self.mods[context][modPriority] == nil) then
        self.mods[context][modPriority] = {}
    end

    self.mods[context][modPriority][mod.Name] = contents
    print("[ClientMods]: Registered", mod.Name, "with priority", modPriority)
end

--[=[
	Registers all descendants under this container as a mod.
	@param container Instance -- Container holding mods.
]=]
function module:RegisterMods(context: string, container: Instance)

    for _, mod in ipairs(container:GetDescendants()) do
        if not mod:IsA("ModuleScript") then
            continue
        end

        module:RegisterMod(context, mod)
    end
end

function module:GetMod(context, name)
    print("searching for", name, "in ", self.mods[context])
    for priority, modMap in pairs(self.mods[context]) do
        local content = modMap[name]
        if content then
            return content
        end
    end
end

function module:GetMods(context)
    if (self.mods[context] == nil) then
        self.mods[context] = {}
    end
    
    local returnMap = self.mods[context]
    for priority = 0, 5 do
        if self.mods[context][priority] == nil then
            self.mods[context][priority] = {}
        end
    end

    return self.mods[context]
end

return module