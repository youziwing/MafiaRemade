local RunService = game:GetService("RunService")

local POOL_SIZE = 64
local BOX_COLOR = Color3.fromRGB(0, 255, 0)
local CROSS_COLOR = Color3.fromRGB(255, 0, 0)
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)
local REFRESH_INTERVAL = 5

local pool = {}
for i = 1, POOL_SIZE do
    local box = Drawing.new("Square")
    box.Thickness = 2
    box.Filled = false
    box.Color = BOX_COLOR
    box.Visible = false
    pool[i] = box
end

local crossH = {}
for i = 1, POOL_SIZE do
    local line = Drawing.new("Line")
    line.Thickness = 1
    line.Color = CROSS_COLOR
    line.Visible = false
    crossH[i] = line
end

local crossV = {}
for i = 1, POOL_SIZE do
    local line = Drawing.new("Line")
    line.Thickness = 1
    line.Color = CROSS_COLOR
    line.Visible = false
    crossV[i] = line
end

local labelPool = {}
for i = 1, POOL_SIZE do
    local label = Drawing.new("Text")
    label.Text = "MEDKIT"
    label.Color = LABEL_COLOR
    label.Outline = true
    label.Center = true
    label.Font = Drawing.Fonts.SystemBold
    label.Size = 13
    label.Visible = false
    labelPool[i] = label
end

local medkitCache = {}

local function rebuildCache()
    local newCache = {}
    local ok, children = pcall(function()
        return game.Workspace.Map.Medkits:GetChildren()
    end)
    if not ok or not children then return end
    for _, model in ipairs(children) do
        if model.Name == "Medkit" and model:IsA("Model") then
            for _, desc in ipairs(model:GetDescendants()) do
                if desc.Name == "MedkitTop" and desc.ClassName == "Part" then
                    newCache[#newCache + 1] = desc
                    break
                end
            end
        end
    end
    medkitCache = newCache
end

rebuildCache()
local lastRefresh = tick()
local renderTargets = {}

RunService.RenderStepped:Connect(function()
    local now = tick()

    if now - lastRefresh >= REFRESH_INTERVAL then
        lastRefresh = now
        rebuildCache()
    end

    local count = 0
    for _, part in ipairs(medkitCache) do
        local pos = part.Position
        local headScreen, headVis = WorldToScreen(pos + Vector3.new(0, 1.5, 0))
        local footScreen, footVis = WorldToScreen(pos - Vector3.new(0, 0.5, 0))
        if headVis and footVis then
            count = count + 1
            local h = math.abs(footScreen.Y - headScreen.Y)
            local cx = headScreen.X
            local cy = (headScreen.Y + footScreen.Y) / 2
            renderTargets[count] = {
                cx = cx, cy = cy, side = h,
                topY = headScreen.Y
            }
        end
    end

    for i = 1, POOL_SIZE do
        local t = renderTargets[i]
        if i <= count and t then
            local half = t.side / 2
            local x = t.cx - half
            local y = t.cy - half

            local box = pool[i]
            box.Position = Vector2.new(x, y)
            box.Size = Vector2.new(t.side, t.side)
            box.Visible = true

            local h = crossH[i]
            h.From = Vector2.new(x, t.cy)
            h.To = Vector2.new(x + t.side, t.cy)
            h.Visible = true

            local v = crossV[i]
            v.From = Vector2.new(t.cx, y)
            v.To = Vector2.new(t.cx, y + t.side)
            v.Visible = true

            local lbl = labelPool[i]
            lbl.Position = Vector2.new(t.cx, y - 14)
            lbl.Visible = true
        else
            pool[i].Visible = false
            crossH[i].Visible = false
            crossV[i].Visible = false
            labelPool[i].Visible = false
        end
    end

    for i = count + 1, #renderTargets do
        renderTargets[i] = nil
    end
end)
