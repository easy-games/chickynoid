local module = {}
module.ui = nil

function module:AddPoint(y,color, layer)
    
    if (module.ui == nil) then
        return
    end
    local points = module.ui.Frame.Points
    if (points == nil) then
        return
    end
    if (layer == nil) then
        layer = 0
    end
    if (y == nil) then
        y = 0
    end
    y = math.clamp(y,1,100)
    
    local child = Instance.new("Frame")
    child.BorderSizePixel = 0
    child.Size = UDim2.new(0,1,0,1)
    child.Position = UDim2.new(0,99,0,100-math.floor(y))
    child.Parent = points
    child.ZIndex = layer
    child.BackgroundTransparency = 0.5
        
    if (color == nil) then
        child.BackgroundColor3 = Color3.new(0,0,0)    
    else
        child.BackgroundColor3 = color
    end
    
end

function module:AddBar(y,color,layer)

    if (module.ui == nil) then
        return
    end
    local points = module.ui.Frame.Points
    if (points == nil) then
        return
    end
    if (layer == nil) then
        layer = 0
    end
    if (y == nil) then
        y= 0
    end
    y = math.clamp(y,1,100)
    
    local child = Instance.new("Frame")
    child.BorderSizePixel = 0
    child.Size = UDim2.new(0,1,0,math.floor(y))
    child.Position = UDim2.new(0,99,0,100-math.floor(y))
    child.Parent = points
    child.ZIndex = layer
    child.BackgroundTransparency = 0.5
    if (color == nil) then
        child.BackgroundColor3 = Color3.new(0,0,0)    
    else
        child.BackgroundColor3 = color
    end

end

function module:SetWarning(warningText)

    if (module.ui == nil) then
        return
    end
    local warning = module.ui.Frame.Warning
    if (warning ==nil) then
        return
    end
    warning.Text = warningText
end

function module:Scroll()
    
    if (game.Players.LocalPlayer.PlayerGui == nil) then
        return
    end
    
    module.ui = game.Players.LocalPlayer.PlayerGui:FindFirstChild("FpsGraph")
    
    if (module.ui == nil) then
        return
    end
    
    local points = module.ui.Frame.Points
    if (points == nil) then
        return
    end
    
    for _,point in pairs(points:GetChildren()) do
        local pos = point.Position 
        if (pos.X.Offset <= 0) then
            point:Destroy()
        else
            point.Position = UDim2.new(pos.X.Scale,pos.X.Offset-1, pos.Y.Scale, pos.Y.Offset)
        end
    end    
end

return module
