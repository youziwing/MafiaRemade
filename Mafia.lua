local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local drawings = {}
local espObjects = {}
local totalPlayers = 0

local function clearDrawings()
    for _, d in ipairs(drawings) do d:Remove() end
    drawings = {}
end

local function clearESP()
    for _, obj in ipairs(espObjects) do
        for _, line in ipairs(obj.corners) do
            line:Remove()
        end
        obj.label:Remove()
    end
    espObjects = {}
end

local function getDisplayName(player)
    if not player or not player.Character then return player.Name end
    local head = player.Character:FindFirstChild("Head")
    local billboard = head and head:FindFirstChildOfClass("BillboardGui")
    local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
    if label and label.Text ~= "" then return label.Text end
    return player.Name
end

local function countAlivePlayers()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local char = player.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                count = count + 1
            end
        end
    end
    return count
end

local function buildPanel()
    clearDrawings()
    clearESP()

    local channel = TextChatService.TextChannels:FindFirstChild("Mafia")
    
    local playerMap = {}
    for _, player in ipairs(Players:GetPlayers()) do
        playerMap[player.Name] = player
    end

    local mafiaNames = {}
    local mafiaPlayers = {}
    local innocentPlayers = {}

    if channel then
        for _, child in ipairs(channel:GetChildren()) do
            if child.ClassName == "TextSource" then
                local name = child.Name
                local player = playerMap[name]
                local displayName = getDisplayName(player)
                if player and player.Character then
                    local head = player.Character:FindFirstChild("Head")
                    local billboard = head and head:FindFirstChildOfClass("BillboardGui")
                    local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
                    if label and label.Text ~= "" then name = label.Text end
                end
                table.insert(mafiaNames, name)
                if player and player ~= Players.LocalPlayer then
                    table.insert(mafiaPlayers, player)
                end
            end
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local isMafia = false
            for _, mafia in ipairs(mafiaPlayers) do
                if mafia == player then
                    isMafia = true
                    break
                end
            end
            if not isMafia then
                local displayName = getDisplayName(player)
                table.insert(innocentPlayers, {
                    username = player.Name,
                    displayName = displayName,
                    player = player
                })
            end
        end
    end

    for i = #innocentPlayers, 1, -1 do
        for _, mafiaName in ipairs(mafiaNames) do
            if innocentPlayers[i].displayName == mafiaName then
                table.remove(innocentPlayers, i)
                break
            end
        end
    end

    local screenSize = workspace.CurrentCamera.ViewportSize
    local panelWidth = 320
    local lineHeight = 20
    local padding = 10
    local sectionGap = 8
    local mafiaCount = #mafiaNames
    local innocentCount = #innocentPlayers
    local aliveCount = countAlivePlayers()
    
    local mafiaSectionHeight = mafiaCount > 0 and (lineHeight * (mafiaCount + 1)) or lineHeight
    local innocentRows = math.ceil(innocentCount / 2)
    local innocentSectionHeight = lineHeight * (innocentRows + 1)
    local panelHeight = padding * 2 + lineHeight + sectionGap + mafiaSectionHeight + sectionGap + innocentSectionHeight + sectionGap

    local x = screenSize.X - panelWidth - 10
    local y = screenSize.Y / 2 - panelHeight / 2

    local bg = Drawing.new("Square")
    bg.Size = Vector2.new(panelWidth, panelHeight)
    bg.Position = Vector2.new(x, y)
    bg.Color = Color3.fromRGB(15, 15, 15)
    bg.Transparency = 0.4
    bg.Filled = true
    bg.Visible = true
    table.insert(drawings, bg)

    local title = Drawing.new("Text")
    title.Text = "Player List"
    title.Position = Vector2.new(x + padding, y + padding)
    title.Color = Color3.fromRGB(255, 255, 255)
    title.Size = 18
    title.Outline = true
    title.Visible = true
    table.insert(drawings, title)

    local remainingText = Drawing.new("Text")
    remainingText.Text = aliveCount .. "/" .. totalPlayers .. " Remaining"
    remainingText.Position = Vector2.new(x + panelWidth - padding - 110, y + padding + 2)
    remainingText.Color = Color3.fromRGB(255, 200, 50)
    remainingText.Size = 14
    remainingText.Outline = true
    remainingText.Visible = true
    table.insert(drawings, remainingText)

    local currentY = y + padding + lineHeight + sectionGap

    local mafiaTitle = Drawing.new("Text")
    mafiaTitle.Text = "Mafia"
    mafiaTitle.Position = Vector2.new(x + padding, currentY)
    mafiaTitle.Color = Color3.fromRGB(220, 60, 60)
    mafiaTitle.Size = 16
    mafiaTitle.Outline = true
    mafiaTitle.Visible = true
    table.insert(drawings, mafiaTitle)

    currentY = currentY + lineHeight

    if mafiaCount > 0 then
        for i, name in ipairs(mafiaNames) do
            local label = Drawing.new("Text")
            label.Text = "  " .. name
            label.Position = Vector2.new(x + padding, currentY)
            label.Color = Color3.fromRGB(220, 60, 60)
            label.Size = 14
            label.Outline = true
            label.Visible = true
            table.insert(drawings, label)
            currentY = currentY + lineHeight
        end
    else
        local emptyLabel = Drawing.new("Text")
        emptyLabel.Text = "  None detected"
        emptyLabel.Position = Vector2.new(x + padding, currentY)
        emptyLabel.Color = Color3.fromRGB(100, 100, 100)
        emptyLabel.Size = 14
        emptyLabel.Outline = true
        emptyLabel.Visible = true
        table.insert(drawings, emptyLabel)
        currentY = currentY + lineHeight
    end

    currentY = currentY + sectionGap

    local innocentTitle = Drawing.new("Text")
    innocentTitle.Text = "Innocent"
    innocentTitle.Position = Vector2.new(x + padding, currentY)
    innocentTitle.Color = Color3.fromRGB(60, 220, 60)
    innocentTitle.Size = 16
    innocentTitle.Outline = true
    innocentTitle.Visible = true
    table.insert(drawings, innocentTitle)

    currentY = currentY + lineHeight

    local colWidth = (panelWidth - padding * 2) / 2
    for i, p in ipairs(innocentPlayers) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        
        local text = p.displayName

        local label = Drawing.new("Text")
        label.Text = "  " .. text
        label.Position = Vector2.new(x + padding + (col * colWidth), currentY + (row * lineHeight))
        label.Color = Color3.fromRGB(255, 255, 255)
        label.Size = 14
        label.Outline = true
        label.Visible = true
        table.insert(drawings, label)
    end

    for _, player in ipairs(mafiaPlayers) do
        local displayName = getDisplayName(player)
        local corners = {}
        for _ = 1, 8 do
            local line = Drawing.new("Line")
            line.Color = Color3.fromRGB(220, 60, 60)
            line.Thickness = 2
            line.Visible = false
            table.insert(corners, line)
        end

        local label = Drawing.new("Text")
        label.Color = Color3.fromRGB(255, 255, 255)
        label.Size = 13
        label.Outline = true
        label.Center = true
        label.Visible = false

        table.insert(espObjects, {
            player = player,
            displayName = displayName,
            corners = corners,
            label = label
        })
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= Players.LocalPlayer then
        totalPlayers = totalPlayers + 1
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if player ~= Players.LocalPlayer then
        totalPlayers = totalPlayers - 1
    end
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= Players.LocalPlayer then
        totalPlayers = totalPlayers + 1
    end
end

spawn(function()
    while true do
        buildPanel()
        wait(3)
    end
end)

RunService.RenderStepped:Connect(function()
    for _, obj in ipairs(espObjects) do
        local char = obj.player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hrp then
            local top = WorldToScreen(Vector3.new(hrp.Position.X, hrp.Position.Y + 2.8, hrp.Position.Z))
            local bot, visible = WorldToScreen(Vector3.new(hrp.Position.X, hrp.Position.Y - 3.2, hrp.Position.Z))

            if visible then
                local h = bot.Y - top.Y
                local w = h * 0.45
                local cornerSize = math.max(6, math.min(w, h) * 0.15)

                local tl = Vector2.new(top.X - w / 2, top.Y)
                local tr = Vector2.new(top.X + w / 2, top.Y)
                local bl = Vector2.new(bot.X - w / 2, bot.Y)
                local br = Vector2.new(bot.X + w / 2, bot.Y)

                local c = obj.corners

                c[1].From = tl; c[1].To = tl + Vector2.new(cornerSize, 0)
                c[2].From = tl; c[2].To = tl + Vector2.new(0, cornerSize)
                c[3].From = tr; c[3].To = tr - Vector2.new(cornerSize, 0)
                c[4].From = tr; c[4].To = tr + Vector2.new(0, cornerSize)
                c[5].From = bl; c[5].To = bl + Vector2.new(cornerSize, 0)
                c[6].From = bl; c[6].To = bl - Vector2.new(0, cornerSize)
                c[7].From = br; c[7].To = br - Vector2.new(cornerSize, 0)
                c[8].From = br; c[8].To = br - Vector2.new(0, cornerSize)

                for _, line in ipairs(c) do
                    line.Visible = true
                end

                obj.label.Text = obj.displayName
                obj.label.Position = Vector2.new(top.X, top.Y - 15)
                obj.label.Visible = true
            else
                for _, line in ipairs(obj.corners) do
                    line.Visible = false
                end
                obj.label.Visible = false
            end
        else
            for _, line in ipairs(obj.corners) do
                line.Visible = false
            end
            obj.label.Visible = false
        end
    end
end)
