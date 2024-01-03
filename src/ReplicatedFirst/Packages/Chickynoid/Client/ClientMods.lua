--!native
local module = {}

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
    
    --Mark the name and priorty
    if (contents.GetPriority ~= nil) then
        contents.priority = contents:GetPriority()
    else
        contents.priority = 0
    end
    contents.name = mod.Name
    
    table.insert(self.mods[context], contents)
    
    table.sort(self.mods[context], function(a,b)
        return a.priority > b.priority
    end)
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

    local list = self.mods[context]

    for key,contents in pairs(list) do
        if (contents.name == name) then
            return contents
        end        
    end
    
    return nil
end

function module:GetMods(context)

    if (self.mods[context] == nil) then
        self.mods[context] = {}
    end
    return self.mods[context]
end

return module