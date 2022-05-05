local module = {}
module.grid = {}
module.div = 0
module.counter = 0
module.planeNum = 1000000
module.expansionSize = Vector3.new(1, 1, 1)
local MinkowskiSumInstance = require(script.Parent.MinkowskiSumInstance)

local corners = {
    Vector3.new(0.5, 0.5, 0.5),
    Vector3.new(0.5, 0.5, -0.5),
    Vector3.new(-0.5, 0.5, 0.5),
    Vector3.new(-0.5, 0.5, -0.5),
    Vector3.new(0.5, -0.5, 0.5),
    Vector3.new(0.5, -0.5, -0.5),
    Vector3.new(-0.5, -0.5, 0.5),
    Vector3.new(-0.5, -0.5, -0.5),
}

function module:RawFetchCell(x, y, z)
    --store in x,z,y order
    local gx = self.grid[x]
    if gx == nil then
        return nil
    end
    local gz = gx[z]
    if gz == nil then
        return nil
    end
    return gz[y]
end

function module:FetchCell(x, y, z)
    local cell = self:RawFetchCell(x, y, z)

    if cell then
        return cell
    end

    cell = self:CreateAndFetchCell(x, y, z)

    local max = self.div - 1

    local corner = Vector3.new(x, y, z) * self.gridSize
    local region = Region3.new(corner, corner + Vector3.new(self.gridSize + 4, self.gridSize + 4, self.gridSize + 4))

    local _, occs = game.Workspace.Terrain:ReadVoxels(region, 4)

    local step = 4 / self.boxSize

    local list = {}

    for xx = 0, max do
        for yy = 0, max do
            for zz = 0, max do
                local fraction = Vector3.new(x + (xx / self.div), y + (yy / self.div), z + (zz / self.div))
                local fill = self:GetOccupancyBilinear(occs, (xx / step), (yy / step), (zz / step))

                if fill > 0.2 then
                    local center = (fraction * self.gridSize)
                        + (Vector3.new(self.boxSize, self.boxSize, self.boxSize) * 0.5)

                    for _, expandedCorner in pairs(self.expandedCorners) do
                        table.insert(list, center + expandedCorner)
                    end

                    --[[if (game["Run Service"]:IsClient()) then
						self:SpawnDebugGridBox(fraction.x, fraction.y, fraction.z , Color3.fromHSV(math.random(),1,1), self.boxSize)
					end]]
                    --
                end
            end
        end
    end

    if #list > 0 then
        local hull, planeNum = MinkowskiSumInstance:GetPlanesForPoints(list, self.planeNum)
        self.planeNum = planeNum
        if hull and planeNum then
            --CollisionModule.planeNum = planeNum
            table.insert(cell, { hull = hull })
        end
    end

    --self:SpawnDebugGridBox(x, y, z, Color3.fromHSV(math.random(),1,1), self.gridSize)

    return cell
end

local function lerp(a, b, frac)
    return (a * (1 - frac)) + (b * frac)
end

function module:GetOccupancyBilinear(occ, localx, localy, localz)
    localx += 1
    localy += 1
    localz += 1

    local x = math.floor(localx)
    local y = math.floor(localy)
    local z = math.floor(localz)

    --    botface
    --
    --     c -----fx---cd--- d
    --                  |
    --                  |
    --                  |
    --                  |
    --                  fy        ^
    --                  |         |
    --     a -----fx---ab---- b   |
    --                            |
    --     (xaxis)---->           (zaxis)

    local fx = localx - x
    local fy = localy - y
    local fz = localz - z

    --Bot face samples
    local a_bot = occ[x + 0][y + 0][z + 0]
    local b_bot = occ[x + 1][y + 0][z + 0]
    local c_bot = occ[x + 0][y + 0][z + 1]
    local d_bot = occ[x + 1][y + 0][z + 1]

    --Top face samples
    local a_top = occ[x + 0][y + 1][z + 0]
    local b_top = occ[x + 1][y + 1][z + 0]
    local c_top = occ[x + 0][y + 1][z + 1]
    local d_top = occ[x + 1][y + 1][z + 1]

    --Bot face lerped
    local ab_bot = lerp(a_bot, b_bot, fx)
    local cd_bot = lerp(c_bot, d_bot, fx)
    local botFace = lerp(ab_bot, cd_bot, fz)

    --Top face lerped
    local ab_top = lerp(a_top, b_top, fx)
    local cd_top = lerp(c_top, d_top, fx)
    local topFace = lerp(ab_top, cd_top, fz)

    --Between bot and top face
    return lerp(botFace, topFace, fy)
end

function module:SpawnDebugGridBox(x, y, z, color, grid)
    local instance = Instance.new("Part")

    instance.Size = Vector3.new(grid, grid, grid)
    instance.Position = (Vector3.new(x, y, z) * self.gridSize) + (Vector3.new(grid, grid, grid) * 0.5)
    instance.Transparency = 0

    instance.Color = color
    instance.Parent = game.Workspace
    instance.Anchored = true
    instance.TopSurface = Enum.SurfaceType.Smooth
    instance.BottomSurface = Enum.SurfaceType.Smooth
end

function module:CreateAndFetchCell(x, y, z)
    local gx = self.grid[x]
    if gx == nil then
        gx = {}
        self.grid[x] = gx
    end
    local gz = gx[z]
    if gz == nil then
        gz = {}
        gx[z] = gz
    end
    local gy = gz[y]
    if gy == nil then
        gy = {}
        gz[y] = gy
    end
    return gy
end

function module:BuildCollisionData(x, z, collisionModule, playerSize)
    local chunkSize = 4

    local chunkx = math.floor(x / chunkSize)
    local chunkz = math.floor(z / chunkSize)

    local hash = (chunkz * 4096) + chunkx
    if self.mapCache[hash] ~= nil or true then
        return
    end

    self.mapCache[hash] = true

    self:ProcessChunk(chunkx * chunkSize, chunkz * chunkSize, chunkSize, collisionModule, playerSize)
end

function module:Setup(gridSize, expansionSize)
    self.grid = {}
    self.expansionSize = expansionSize

    self.gridSize = gridSize
    self.boxSize = 2
    self.div = self.gridSize / self.boxSize

    self.expandedCorners = {}
    for _, corner in pairs(corners) do
        table.insert(self.expandedCorners, (corner * self.boxSize) + (corner * self.expansionSize))
    end
end

return module
