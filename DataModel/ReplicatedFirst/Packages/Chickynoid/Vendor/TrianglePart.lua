local Triangle = {}


local ref = Instance.new('WedgePart') 
ref.Color         = Color3.fromRGB(200, 255, 200)
ref.Material      = Enum.Material.SmoothPlastic
ref.Reflectance   = 0
ref.Transparency  = 0
ref.Name          = "Tri"
ref.Anchored      = true
ref.CanCollide    = false
ref.CanTouch      = false
ref.CanQuery      = false
ref.CFrame        = CFrame.new()
ref.Size          = Vector3.new(0.25, 0.25, 0.25)
ref.BottomSurface = Enum.SurfaceType.Smooth
ref.TopSurface    = Enum.SurfaceType.Smooth


local function fromAxes(p, x, y, z)
	return CFrame.new(
		p.x, p.y, p.z,
		x.x, y.x, z.x,
		x.y, y.y, z.y,
		x.z, y.z, z.z
	)
end
	
function Triangle:Triangle(a, b, c)
	local ab, ac, bc = b - a, c - a, c - b
	local abl, acl, bcl = ab.magnitude, ac.magnitude, bc.magnitude
	if abl > bcl and abl > acl then
		c, a = a, c
	elseif acl > bcl and acl > abl then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local out = ac:Cross(ab).unit
	local wb = ref:Clone()
	local wc = ref:Clone()
	local biDir = bc:Cross(out).unit
	local biLen = math.abs(ab:Dot(biDir))
	local norm = bc.magnitude
	wb.Size = Vector3.new(0, math.abs(ab:Dot(bc))/norm, biLen)
	wc.Size = Vector3.new(0, biLen, math.abs(ac:Dot(bc))/norm)
	bc = -bc.unit
	wb.CFrame = fromAxes((a + b)/2, -out, bc, -biDir)
	wc.CFrame = fromAxes((a + c)/2, -out, biDir, bc)
	
	return wb, wc
end

return Triangle