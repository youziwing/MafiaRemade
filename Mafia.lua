local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

-- Drawing object pools
local drawings = {
    bg = nil, title = nil, remainingText = nil,
    mafiaTitle = nil, innocentTitle = nil,
    mafiaLabels = {}, innocentLabels = {},
    emptyMafiaLabel = nil
}

-- ESP tracking: player.Name -> {corners, label, playerRef, lastSeen, displayName}
local espObjects = {}
local activeMafiaNames = {}
local totalPlayers = 0

-- ESP runs on its own timer, not RenderStepped
local ESP_FPS = 60
local ESP_INTERVAL = 1 / ESP_FPS  -- ~16.6ms
local lastEspUpdate = 0

local function initPanel()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local screenSize = cam.ViewportSize
    if not screenSize then return end
    
    local panelWidth, panelHeight = 320, 400
    local x = screenSize.X - panelWidth - 10
    local y = screenSize.Y / 2 - panelHeight / 2

    drawings.bg = Drawing.new("Square")
    drawings.bg.Color = Color3.fromRGB(15, 15, 15)
    drawings.bg.Transparency = 0.4
    drawings.bg.Filled = true
    drawings.bg.Visible = true
    drawings.bg.Size = Vector2.new(panelWidth, panelHeight)
    drawings.bg.Position = Vector2.new(x, y)

    drawings.title = Drawing.new("Text")
    drawings.title.Text = "Player List"
    drawings.title.Color = Color3.fromRGB(255, 255, 255)
    drawings.title.Size = 18
    drawings.title.Outline = true
    drawings.title.Visible = true
    drawings.title.Position = Vector2.new(x + 10, y + 10)

    drawings.remainingText = Drawing.new("Text")
    drawings.remainingText.Color = Color3.fromRGB(255, 200, 50)
    drawings.remainingText.Size = 14
    drawings.remainingText.Outline = true
    drawings.remainingText.Visible = true

    drawings.mafiaTitle = Drawing.new("Text")
    drawings.mafiaTitle.Text = "Mafia"
    drawings.mafiaTitle.Color = Color3.fromRGB(220, 60, 60)
    drawings.mafiaTitle.Size = 16
    drawings.mafiaTitle.Outline = true
    drawings.mafiaTitle.Visible = true

    drawings.innocentTitle = Drawing.new("Text")
    drawings.innocentTitle.Text = "Innocent"
    drawings.innocentTitle.Color = Color3.fromRGB(60, 220, 60)
    drawings.innocentTitle.Size = 16
    drawings.innocentTitle.Outline = true
    drawings.innocentTitle.Visible = true

    drawings.emptyMafiaLabel = Drawing.new("Text")
    drawings.emptyMafiaLabel.Text = "  None detected"
    drawings.emptyMafiaLabel.Color = Color3.fromRGB(100, 100, 100)
    drawings.emptyMafiaLabel.Size = 14
    drawings.emptyMafiaLabel.Outline = true
    drawings.emptyMafiaLabel.Visible = false
end

local function getDisplayName(player)
    if not player then return "Unknown" end
    if not player.Character then return player.Name or "Unknown" end
    local head = player.Character:FindFirstChild("Head")
    local billboard = head and head:FindFirstChildOfClass("BillboardGui")
    local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
    if label and label.Text and label.Text ~= "" then return label.Text end
    return player.Name or "Unknown"
end

local function countAlivePlayers()
    local count = 0
    local all = Players:GetPlayers()
    if not all then return 0 end
    for _, p in ipairs(all) do
        if p and p ~= Players.LocalPlayer then
            local char = p.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health and hum.Health > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function getMafiaData()
    local channel = TextChatService.TextChannels:FindFirstChild("Mafia")
    local all = Players:GetPlayers()
    if not all then return {}, {} end
    
    local playerMap = {}
    for _, p in ipairs(all) do
        if p and p.Name then playerMap[p.Name] = p end
    end

    local mafiaEntries = {}
    local mafiaPlayers = {}

    if channel then
        local children = channel:GetChildren()
        if children then
            for _, child in ipairs(children) do
                if child and child.ClassName == "TextSource" then
                    local username = child.Name
                    local player = playerMap[username]
                    
                    if player and player ~= Players.LocalPlayer then
                        local displayName = getDisplayName(player)
                        table.insert(mafiaEntries, {
                            username = username,
                            displayName = displayName
                        })
                        table.insert(mafiaPlayers, player)
                    end
                end
            end
        end
    end
    return mafiaEntries, mafiaPlayers
end

local function updatePanel(mafiaEntries, innocentPlayers)
    if not mafiaEntries or not innocentPlayers then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local screenSize = cam.ViewportSize
    if not screenSize then return end
    
    local panelWidth, lineHeight, padding, sectionGap = 320, 20, 10, 8
    local mafiaCount, innocentCount = #mafiaEntries, #innocentPlayers
    local aliveCount = countAlivePlayers()
    
    local mafiaH = mafiaCount > 0 and (lineHeight * (mafiaCount + 1)) or lineHeight
    local innocentRows = math.ceil(innocentCount / 2)
    local innocentH = lineHeight * (innocentRows + 1)
    local panelHeight = padding * 2 + lineHeight + sectionGap + mafiaH + sectionGap + innocentH + sectionGap

    local x = screenSize.X - panelWidth - 10
    local y = screenSize.Y / 2 - panelHeight / 2

    if drawings.bg then
        drawings.bg.Size = Vector2.new(panelWidth, panelHeight)
        drawings.bg.Position = Vector2.new(x, y)
    end
    if drawings.title then
        drawings.title.Position = Vector2.new(x + padding, y + padding)
    end
    if drawings.remainingText then
        drawings.remainingText.Text = aliveCount .. "/" .. totalPlayers .. " Remaining"
        drawings.remainingText.Position = Vector2.new(x + panelWidth - padding - 110, y + padding + 2)
    end

    local currentY = y + padding + lineHeight + sectionGap
    if drawings.mafiaTitle then
        drawings.mafiaTitle.Position = Vector2.new(x + padding, currentY)
    end
    currentY = currentY + lineHeight

    if drawings.emptyMafiaLabel then
        drawings.emptyMafiaLabel.Visible = (mafiaCount == 0)
        drawings.emptyMafiaLabel.Position = Vector2.new(x + padding, currentY)
    end
    if mafiaCount == 0 then currentY = currentY + lineHeight end

    for i = 1, math.max(mafiaCount, #drawings.mafiaLabels) do
        local label = drawings.mafiaLabels[i]
        if i <= mafiaCount then
            if not label then
                label = Drawing.new("Text")
                label.Color = Color3.fromRGB(220, 60, 60)
                label.Size = 14
                label.Outline = true
                label.Visible = true
                drawings.mafiaLabels[i] = label
            end
            local entry = mafiaEntries[i]
            label.Text = "  " .. tostring(entry and entry.displayName or "Unknown")
            label.Position = Vector2.new(x + padding, currentY)
            label.Visible = true
            currentY = currentY + lineHeight
        elseif label then
            label.Visible = false
        end
    end

    currentY = currentY + sectionGap
    if drawings.innocentTitle then
        drawings.innocentTitle.Position = Vector2.new(x + padding, currentY)
    end
    currentY = currentY + lineHeight

    local colWidth = (panelWidth - padding * 2) / 2
    for i = 1, math.max(innocentCount, #drawings.innocentLabels) do
        local label = drawings.innocentLabels[i]
        if i <= innocentCount then
            if not label then
                label = Drawing.new("Text")
                label.Color = Color3.fromRGB(255, 255, 255)
                label.Size = 14
                label.Outline = true
                label.Visible = true
                drawings.innocentLabels[i] = label
            end
            local entry = innocentPlayers[i]
            if entry then
                local col = (i - 1) % 2
                local row = math.floor((i - 1) / 2)
                label.Text = "  " .. tostring(entry.displayName or entry.username or "Unknown")
                label.Position = Vector2.new(x + padding + (col * colWidth), currentY + (row * lineHeight))
                label.Visible = true
            end
        elseif label then
            label.Visible = false
        end
    end
end

-- ==================== ESP SYSTEM (SEPARATE) ====================

local function ensureESP(player)
    if not player or not player.Name then return nil end
    local name = player.Name
    
    if espObjects[name] then
        espObjects[name].playerRef = player
        espObjects[name].lastSeen = tick()
        espObjects[name].displayName = getDisplayName(player)
        return espObjects[name]
    end
    
    local corners = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Color = Color3.fromRGB(220, 60, 60)
        line.Thickness = 2
        line.Visible = false
        corners[i] = line
    end

    local label = Drawing.new("Text")
    label.Color = Color3.fromRGB(255, 255, 255)
    label.Size = 13
    label.Outline = true
    label.Center = true
    label.Visible = false

    local obj = {
        corners = corners,
        label = label,
        playerRef = player,
        lastSeen = tick(),
        displayName = getDisplayName(player)
    }
    espObjects[name] = obj
    return obj
end

local function hideESP(name)
    local obj = espObjects[name]
    if not obj then return end
    if obj.corners then
        for _, line in ipairs(obj.corners) do
            if line then line.Visible = false end
        end
    end
    if obj.label then obj.label.Visible = false end
end

local function destroyESP(name)
    local obj = espObjects[name]
    if not obj then return end
    if obj.corners then
        for _, line in ipairs(obj.corners) do
            if line then pcall(function() line:Remove() end) end
        end
    end
    if obj.label then pcall(function() obj.label:Remove() end) end
    espObjects[name] = nil
end

-- Purge dead ESP entries
local function purgeDeadESP()
    local now = tick()
    local all = Players:GetPlayers()
    local validNames = {}
    if all then
        for _, p in ipairs(all) do
            if p and p.Name then validNames[p.Name] = true end
        end
    end

    for name, obj in pairs(espObjects) do
        if not validNames[name] or (now - obj.lastSeen > 30) then
            destroyESP(name)
        end
    end
end

-- Update ESP data (who is mafia) - called by panel refresh
local function updateESPTargets(mafiaPlayers)
    if not mafiaPlayers then return end
    activeMafiaNames = {}
    
    for _, player in ipairs(mafiaPlayers) do
        if not player or not player.Name then continue end
        activeMafiaNames[player.Name] = true
        ensureESP(player)  -- create if missing, update if exists
    end
    
    -- Hide ESP for players no longer mafia
    for name, obj in pairs(espObjects) do
        if not activeMafiaNames[name] then
            hideESP(name)
        end
    end
end

-- Render ESP positions - called at fixed FPS
local function renderESP()
    if not espObjects then return end
    
    for name, obj in pairs(espObjects) do
        if not obj then continue end
        if not obj.corners or not obj.label then continue end
        
        -- Only render if this player is currently mafia
        if not activeMafiaNames[name] then
            hideESP(name)
            continue
        end
        
        local player = obj.playerRef
        if not player or not player.Parent then
            local found = Players:FindFirstChild(name)
            if found then
                obj.playerRef = found
                player = found
            else
                hideESP(name)
                continue
            end
        end
        
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        
        if not hrp then
            for _, line in ipairs(obj.corners) do
                if line then line.Visible = false end
            end
            obj.label.Visible = false
            continue
        end

        local topOk, top = pcall(WorldToScreen, Vector3.new(hrp.Position.X, hrp.Position.Y + 2.8, hrp.Position.Z))
        local botOk, bot, visible = pcall(WorldToScreen, Vector3.new(hrp.Position.X, hrp.Position.Y - 3.2, hrp.Position.Z))

        if not topOk or not botOk or not visible or not top or not bot then
            for _, line in ipairs(obj.corners) do
                if line then line.Visible = false end
            end
            obj.label.Visible = false
            continue
        end

        local h = bot.Y - top.Y
        local w = h * 0.45
        local cornerSize = math.max(6, math.min(w, h) * 0.15)

        local tl = Vector2.new(top.X - w / 2, top.Y)
        local tr = Vector2.new(top.X + w / 2, top.Y)
        local bl = Vector2.new(bot.X - w / 2, bot.Y)
        local br = Vector2.new(bot.X + w / 2, bot.Y)

        local c = obj.corners

        if c[1] then c[1].From = tl; c[1].To = tl + Vector2.new(cornerSize, 0) end
        if c[2] then c[2].From = tl; c[2].To = tl + Vector2.new(0, cornerSize) end
        if c[3] then c[3].From = tr; c[3].To = tr - Vector2.new(cornerSize, 0) end
        if c[4] then c[4].From = tr; c[4].To = tr + Vector2.new(0, cornerSize) end
        if c[5] then c[5].From = bl; c[5].To = bl + Vector2.new(cornerSize, 0) end
        if c[6] then c[6].From = bl; c[6].To = bl - Vector2.new(0, cornerSize) end
        if c[7] then c[7].From = br; c[7].To = br - Vector2.new(cornerSize, 0) end
        if c[8] then c[8].From = br; c[8].To = br - Vector2.new(0, cornerSize) end

        for _, line in ipairs(c) do
            if line then line.Visible = true end
        end

        obj.label.Text = tostring(obj.displayName or "Unknown")
        obj.label.Position = Vector2.new(top.X, top.Y - 15)
        obj.label.Visible = true
    end
end

-- ==================== MAIN LOGIC ====================

local function refresh()
    local mafiaEntries, mafiaPlayers = getMafiaData()
    if not mafiaEntries or not mafiaPlayers then return end
    
    local all = Players:GetPlayers()
    if not all then return end

    -- Build set of mafia display names for filtering
    local mafiaDisplayNames = {}
    for _, entry in ipairs(mafiaEntries) do
        if entry and entry.displayName then
            mafiaDisplayNames[entry.displayName] = true
        end
    end

    -- Build innocent list
    local innocentPlayers = {}
    for _, player in ipairs(all) do
        if player and player ~= Players.LocalPlayer then
            local isMafia = false
            for _, mafia in ipairs(mafiaPlayers) do
                if mafia == player then
                    isMafia = true
                    break
                end
            end
            if not isMafia then
                table.insert(innocentPlayers, {
                    username = player.Name,
                    displayName = getDisplayName(player),
                    player = player
                })
            end
        end
    end

    -- Remove mafia by DISPLAY NAME
    for i = #innocentPlayers, 1, -1 do
        local entry = innocentPlayers[i]
        if entry and mafiaDisplayNames[entry.displayName] then
            table.remove(innocentPlayers, i)
        end
    end

    updatePanel(mafiaEntries, innocentPlayers)
    updateESPTargets(mafiaPlayers)  -- only updates WHO to track, not positions
end

-- Events
Players.PlayerAdded:Connect(function(p)
    if p and p ~= Players.LocalPlayer then
        totalPlayers = totalPlayers + 1
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if p and p ~= Players.LocalPlayer then
        totalPlayers = totalPlayers - 1
    end
    if p and p.Name then destroyESP(p.Name) end
end)

local initial = Players:GetPlayers()
if initial then
    for _, p in ipairs(initial) do
        if p and p ~= Players.LocalPlayer then
            totalPlayers = totalPlayers + 1
        end
    end
end

initPanel()

-- Panel refresh: every 3 seconds
task.spawn(function()
    while true do
        local ok, err = pcall(refresh)
        if not ok then warn("Refresh: " .. tostring(err)) end
        task.wait(3)
    end
end)

-- ESP render: fixed 60Hz, completely separate from panel
task.spawn(function()
    while true do
        local now = tick()
        if now - lastEspUpdate >= ESP_INTERVAL then
            lastEspUpdate = now
            local ok, err = pcall(renderESP)
            if not ok then warn("ESP: " .. tostring(err)) end
        end
        task.wait(0.001)  -- tiny sleep to prevent busy-wait
    end
end)

-- Periodic ESP cleanup
task.spawn(function()
    while true do
        task.wait(10)
        pcall(purgeDeadESP)
    end
end)
