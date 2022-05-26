local module = {}

--Compares two tables, and produces a new table containing the differences
function module:MakeDeltaTable(oldTable, newTable)
    
    if (oldTable == nil) then
        return self:DeepCopy(newTable)
    end
    
    local deltaTable = {}
    local changes = 0
    for var, data in pairs(newTable) do
        if oldTable[var] == nil then
            deltaTable[var] = data
        else
            if type(newTable[var]) == "table" then
                --its a table, recurse
                local newtable, num = module:MakeDeltaTable(oldTable[var], newTable[var])
                if num > 0 then
                    changes = changes + 1
                    deltaTable[var] = newtable
                end
            else
                local a = newTable[var]
                local b = oldTable[var]
                if a ~= b then
                    changes = changes + 1
                    deltaTable[var] = a
                end
            end
        end
    end
    --Check for deletions
    for var, _ in pairs(oldTable) do
        if newTable[var] == nil then
            if deltaTable.__deletions == nil then
                deltaTable.__deletions = {}
            end
            table.insert(deltaTable.__deletions, var)
        end
    end

    return deltaTable, changes
end

--Produces a new table that is the combination of a target, and a deltaTable produced by MakeDeltaTable
function module:ApplyDeltaTable(target, deltaTable)
	
	if (target == nil) then
		target = {}
	end
    local newTable = self:DeepCopy(target)
    if newTable == nil then
        newTable = {}
    end

    for var, _ in pairs(deltaTable) do
        if type(deltaTable[var]) == "table" then
			newTable[var] = self:ApplyDeltaTable(target[var], deltaTable[var])
        else
            newTable[var] = deltaTable[var]
        end
    end

    if newTable.__deletions ~= nil then
        for _, var in pairs(newTable.__deletions) do
            newTable[var] = nil
            print("deleted ", var)
        end
    end

    return newTable
end

function module:DeepCopy(sourceTable)
    local function Deep(tbl)
        local tCopy = table.create(#tbl)
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                tCopy[k] = Deep(v)
            else
                tCopy[k] = v
            end
        end
        return tCopy
    end
    return Deep(sourceTable)
end

return module
