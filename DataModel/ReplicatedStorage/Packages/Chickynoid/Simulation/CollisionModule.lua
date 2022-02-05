local module = {}


module.hullRecords = {}
local SKIN = 0.025 --closest you can get to a wall
module.planeNum = 0
module.gridSize = 5
module.grid = {}

local corners = {
    Vector3.new( 0.5,0.5, 0.5),
    Vector3.new( 0.5,0.5,-0.5),
    Vector3.new(-0.5,0.5, 0.5),
    Vector3.new(-0.5,0.5,-0.5),

    Vector3.new( 0.5,-0.5, 0.5),
    Vector3.new( 0.5,-0.5,-0.5),
    Vector3.new(-0.5,-0.5, 0.5),
    Vector3.new(-0.5,-0.5,-0.5),

}


local boxPlanes ={
    { n = Vector3.new(0,1,0), p = Vector3.new(0,0.5,0) },
    { n = Vector3.new(0,-1,0), p = Vector3.new(0,-0.5,0)},
    { n = Vector3.new(1,0,0), p = Vector3.new(0.5,0,0)},
    { n = Vector3.new(-1,0,0), p = Vector3.new(-0.5,0,0)}, 
    { n = Vector3.new(0,0,1), p = Vector3.new(0,0,0.5)},
    { n = Vector3.new(0,0,-1), p = Vector3.new(0,0,-0.5)},

--[[
    --4 corners. top
    { n = Vector3.new( 1,1, 1), p = Vector3.new(0.5,0.5,0.5) },
    { n = Vector3.new( 1,1,-1), p = Vector3.new(0.5,0.5,-0.5) },
    { n = Vector3.new(-1,1, 1), p = Vector3.new(-0.5,0.5,0.5) },
    { n = Vector3.new(-1,1,-1), p = Vector3.new(-0.5,0.5,-0.5) }, 

    --4 corners. bot
    { n = Vector3.new( 1,-1, 1), p = Vector3.new(0.5,-0.5,0.5) },
    { n = Vector3.new( 1,-1,-1), p = Vector3.new(0.5,-0.5,-0.5) },
    { n = Vector3.new(-1,-1, 1), p = Vector3.new(-0.5,-0.5,0.5) },
    { n = Vector3.new(-1,-1,-1), p = Vector3.new(-0.5,-0.5,-0.5) },
]]--

 
    --4 edges, top
    { n = Vector3.new( 1,1, 0), p = Vector3.new(0.5,0.5,0) },
    { n = Vector3.new( -1,1, 0), p = Vector3.new(-0.5,0.5,0) },
    { n = Vector3.new( 0,1, 1), p = Vector3.new(0,0.5,0.5) },
    { n = Vector3.new( 0,1, -1), p = Vector3.new(0,0.5,-0.5) }, 
    
    --4 edges, bot
    { n = Vector3.new( 1,-1, 0), p = Vector3.new(0.5,-0.5,0) },
    { n = Vector3.new( -1,-1, 0), p = Vector3.new(-0.5,-0.5,0) },
    { n = Vector3.new( 0,-1, 1), p = Vector3.new(0,-0.5,0.5) },
    { n = Vector3.new( 0,-1, -1), p = Vector3.new(0,-0.5,-0.5) },
  
    
    --4 edges, side struts
    { n = Vector3.new( 1,0, 1), p = Vector3.new(0.5,0,0.5) },
    { n = Vector3.new( 1,0, -1), p = Vector3.new(0.5,0,-0.5) },
    { n = Vector3.new( -1,0, 1), p = Vector3.new(-0.5,0,0.5) },
    { n = Vector3.new( -1,0, -1), p = Vector3.new(-0.5,0,-0.5) },    
 

}

for key,value in pairs(boxPlanes )do
    value.n = value.n.Unit
end

function module:FetchCell(x,y,z)

    local x = math.floor(x / self.gridSize)
    local y = math.floor(y / self.gridSize)
    local z = math.floor(z / self.gridSize)
    
    --store in x,z,y order 
    local gx = self.grid[x] 
    if (gx == nil) then
        return nil
    end    
    local gz = gx[z]
    if (gz == nil) then
        return nil
    end
    return gz[y]
end

function module:CreateAndFetchCell(x,y,z)
    local x = math.floor(x / self.gridSize)
    local y = math.floor(y / self.gridSize)
    local z = math.floor(z / self.gridSize)
    
    local gx = self.grid[x] 
    if (gx == nil) then
        gx = {}
        self.grid[x] = gx
    end    
    local gz = gx[z]
    if (gz == nil) then
        gz = {}
        gx[z] = gz
    end
    local gy = gz[y]
    if (gy == nil) then
        gy = {}
        gz[y] = gy
    end
    return gy
end


function module:FindAABB(part)
    local orientation = part.CFrame
    local size = part.Size
    
    local minx = math.huge
    local miny = math.huge
    local minz = math.huge
    local maxx = -math.huge
    local maxy = -math.huge
    local maxz = -math.huge

    for _,corner in pairs(corners) do
        local vec = orientation * (size * corner) 
        if (vec.x <minx) then 
            minx = vec.x
        end
        if (vec.y < miny) then 
            miny = vec.y
        end
        if (vec.z < minz) then 
            minz = vec.z
        end
        if (vec.x > maxx) then 
            maxx = vec.x
        end
        if (vec.y > maxy) then 
            maxy = vec.y
        end
        if (vec.z > maxz) then 
            maxz = vec.z
        end

    end
    return minx, miny, minz, maxx, maxy, maxz
    
end

function module:WritePartToHashMap(instance, hullRecord)
    
    local minx,miny,minz, maxx, maxy, maxz = self:FindAABB(instance)
    
    for x = math.floor(minx / self.gridSize), math.floor(maxx/self.gridSize)+1 do
        for z = math.floor(minz / self.gridSize), math.floor(maxz/self.gridSize)+1 do
            for y = math.floor(miny / self.gridSize), math.floor(maxy/self.gridSize)+1 do
                
                local cell = self:CreateAndFetchCell(x,y,z)
                cell[instance] = hullRecord
            end
        end
    end
    
end

function module:FetchHullsForBox(min, max)
    
    
    
    local minx = min.x
    local miny = min.y
    local minz = min.z
    local maxx = max.x
    local maxy = max.y
    local maxz = max.z
    
    if (minx > maxx) then
        local t = minx
        minx = maxx
        maxx = t
    end
    if (miny > maxy) then
        local t = miny
        miny = maxy
        maxy = t
    end
    if (minz > maxz) then
        local t = minz
        minz = maxz
        maxz = t
    end
    
    local hullRecords = {}
    for x = math.floor(minx / self.gridSize), math.floor(maxx/self.gridSize)+1 do
        for z = math.floor(minz / self.gridSize), math.floor(maxz/self.gridSize)+1 do
            for y = math.floor(miny / self.gridSize), math.floor(maxy/self.gridSize)+1 do

                local cell = self:FetchCell(x,y,z)
                if (cell) then
                    
                    for key,hull in pairs(cell) do
                        hullRecords[hull] = hull
                    end
                end
            end
        end
    end
    return hullRecords
end


function module:GenerateDebugPlane(pos, normal)
    
    local instance = Instance.new("Part")
    instance.Transparency = 0.9
    instance.Size = Vector3.new(3,3,0.0001)
    instance.CFrame = CFrame.new(pos, pos + normal)
    instance.Parent = game.Workspace
    instance.Color= Color3.new(0.3,1,0.3)
    instance.Anchored = true
    instance.CanCollide = false
    instance.CanQuery = false
    instance.CanTouch = false
    
    
end

function module:GenerateConvexHull(part, expansionSize)

    --returns the 6 planes that make up a hull
    local hull = {}
    
    
    for _,rec in pairs(boxPlanes) do

        local normal = part.CFrame:VectorToWorldSpace(rec.n)
        
        local pos =  part.CFrame:PointToWorldSpace(part.Size * rec.p)
     --   local expanded = pos + Vector3.new(axis.x * normal.x, axis.y * normal.y, axis.z * normal.z)
        

        local xx,yy,zz 
        if (normal.x < 0) then
            xx=-0.5
        else
            xx=0.5
        end
        if (normal.y < 0) then
            yy=-0.5
        else
            yy=0.5
        end
        if (normal.z < 0) then
            zz=-0.5
        else
            zz=0.5
        end
        
        local expanded = pos + Vector3.new(expansionSize.x * xx, expansionSize.y*yy, expansionSize.z*zz)

        
        table.insert(hull, { 
            n = normal, 
            d = pos:Dot(normal),
            ed = expanded:Dot(normal),  --preexpanded          
            planeNum = self.planeNum
        })
        self.planeNum+=1
        
        --self:GenerateDebugPlane(expanded, normal)
    end
    
   

    return hull
end

 

function module:MakeWorld(folder, playerSize)
    self.hulls = {}
    for key,value in pairs(folder:GetDescendants()) do
        if (value:IsA("BasePart")) then
            
            local record = {}
            record.instance = value
            record.hull = self:GenerateConvexHull(value, playerSize)
            self:WritePartToHashMap(record.instance, record)
            
            table.insert(module.hullRecords, record)
        end
    end

end


function module:SimpleRayTest(a, b, hull)

    -- Compute direction vector for the segment
    local d = b - a
    -- Set initial interval to being the whole segment. For a ray, tlast should be
    -- set to +FLT_MAX. For a line, additionally tfirst should be set to –FLT_MAX
    local tfirst = -1
    local tlast = 1

    --Intersect segment against each plane

    for _,p in pairs(hull) do

        local denom = p.n:Dot(d)
        local dist = p.d - (p.n:Dot(a))

        --Test if segment runs parallel to the plane
        if (denom == 0) then 

            -- If so, return “no intersection” if segment lies outside plane
            if (dist > 0) then
                return nil
            end
        else
            -- Compute parameterized t value for intersection with current plane
            local t = dist / denom
            if (denom < 0) then

                -- When entering halfspace, update tfirst if t is larger
                if (t > tfirst) then
                    tfirst = t
                end
            else
                -- When exiting halfspace, update tlast if t is smaller
                if (t < tlast) then
                    tlast = t
                end
            end

            -- Exit with “no intersection” if intersection becomes empty
            if (tfirst > tlast) then 
                return nil
            end

        end            

    end
    -- A nonzero logical intersection, so the segment intersects the polyhedron
    return tfirst,tlast

end

local EPS = 0.00001
function module:CheckBrush(data, hullRecord )

    local startFraction = -1.0
    local endFraction = 1.0
    local startsOut = false
    local endsOut = false
    local lastPlane = nil

    for _,p in pairs(hullRecord.hull) do

        local startDistance = data.startPos:Dot(p.n ) - p.ed
        local endDistance = data.endPos:Dot(p.n ) - p.ed

        if (startDistance > 0) then
            startsOut = true
        end
        if (endDistance > 0) then
            endsOut = true
        end

        -- make sure the trace isn't completely on one side of the brush
        if (startDistance > 0 and (endDistance >= EPS or endDistance >= startDistance)) then
            return   --both are in front of the plane, its outside of this brush
        end
        if (startDistance <= 0 and endDistance <= 0) then
            --both are behind this plane, it will get clipped by another one
            continue
        end

        if (startDistance > endDistance) then
            --  line is entering into the brush
            local fraction = (startDistance - EPS) / (startDistance - endDistance)
            if (fraction < 0) then
                fraction = 0
            end
            if (fraction > startFraction) then
                startFraction = fraction
                lastPlane = p
                
            end
        else
            --line is leaving the brush
            local fraction = (startDistance + EPS) / (startDistance - endDistance)
            if (fraction > 1) then
                fraction = 1
             
            end
            if (fraction < endFraction) then
                endFraction = fraction
                
            end
        end
    end

    if (startsOut == false) then
        data.startSolid = true
        if (endsOut == false) then
            --Allsolid
            data.allSolid = true
            return
        end
      
    end

    --Update the output fraction
    if (startFraction < endFraction) then

        if (startFraction > -1 and startFraction < data.fraction) then

            if (startFraction < 0) then
                startFraction = 0
            end
            data.fraction = startFraction
            data.normal = lastPlane.n
            data.planeD = lastPlane.d
            data.planeNum = lastPlane.planeNum
            data.hullRecord = hullRecord
        end
    end

end

function module:PlaneLineInteresct(normal, distance, V1, V2)

    local diff = V2 - V1
    local denominator = normal:Dot(diff)
    if (denominator == 0) then

        return nil
    end
    local u = (normal.x * V1.x + normal.y * V1.y + normal.z * V1.z + distance) / -denominator

    return (V1 + u * (V2 - V1))
end
 

function module:Sweep(startPos, endPos)
 
    
    local data = {}
    data.startPos = startPos
    data.endPos = endPos
    data.fraction = 1
    data.startSolid = false
    data.allSolid = false
    data.planeNum = 0
    data.planeD = 0 
    data.normal = Vector3.new(0,1,0)
    data.checks = 0
    data.hullRecord = nil
    
    
    if (startPos-endPos).magnitude > 1000 then
        return data
    end
    

    debug.profilebegin("Sweep")
    --calc bounds of sweep
    local hullRecords = self:FetchHullsForBox(startPos, endPos)
    
 
    for _,hullRecord in pairs(hullRecords) do
        
        data.checks+=1
        self:CheckBrush(data, hullRecord)
        if (data.allSolid == true) then
            data.fraction = 0
            break
        end
        if (data.fraction < EPS) then
            break
        end
    end
 
    if (data.fraction < 1) then
        --Todo: calculate the skin better? - endpos should be nearest point on the plane + skin?
        local vec = (endPos-startPos)
        data.endPos = startPos + (vec * data.fraction ) - (vec.unit * SKIN)
    end
    
    debug.profileend()
    return data
end
 




return module
