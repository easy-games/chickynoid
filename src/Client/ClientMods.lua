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
    
    if (self.mods[context] == nil) then
        self.mods[context] = {}
    end

    self.mods[context][mod.Name] = contents
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
    return self.mods[context][name]
end

function module:GetMods(context)

    if (self.mods[context] == nil) then
        self.mods[context] = {}
    end
    return self.mods[context]
end

return module