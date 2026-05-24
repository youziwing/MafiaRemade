local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local drawings = {}
local espObjects = {}

local function clearDrawings()
    for _, d in ipairs(drawings) do d:Remove() end
    drawings = {}
end

local function clearESP()
    for _, obj in ipairs(espObjects) do
        obj.box:Remove()
        obj.label:Remove()
    end
    espObjects = {}
end

local function buildPanel()
    clearDrawings()
    clearESP()

    local channel = TextChatService.TextChannels:FindFirstChild("Mafia")
    if not channel then return end

    local playerMap = {}
    for _, player in ipairs(Players:GetPlayers()) do
        playerMap[player.Name] = player
    end

    local names = {}
    local mafiaPlayers = {}

    for _, child in ipairs(channel:GetChildren()) do
        if child.ClassName == "TextSource" then
            local name = child.Name
            local player = playerMap[name]
            if player and player.Character then
                local head = player.Character:FindFirstChild("Head")
                local billboard = head and head:FindFirstChildOfClass("BillboardGui")
                local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
                if label and label.Text ~= "" then name = label.Text end
            end
            table.insert(names, name)
            if player and player ~= Players.LocalPlayer then
                table.insert(mafiaPlayers, { player = player, displayName = name })
            end
        end
    end

    if #names == 0 then return end

    local screenSize = workspace.CurrentCamera.ViewportSize
    local panelWidth = 160
    local lineHeight = 20
    local padding = 8
    local panelHeight = padding * 2 + lineHeight * (#names + 1)
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
    title.Text = "Mafia"
    title.Position = Vector2.new(x + padding, y + padding)
    title.Color = Color3.fromRGB(220, 60, 60)
    title.Size = 16
    title.Outline = true
    title.Visible = true
    table.insert(drawings, title)

    for i, name in ipairs(names) do
        local label = Drawing.new("Text")
        label.Text = name
        label.Position = Vector2.new(x + padding, y + padding + lineHeight * i)
        label.Color = Color3.fromRGB(255, 255, 255)
        label.Size = 14
        label.Outline = true
        label.Visible = true
        table.insert(drawings, label)
    end

    for _, data in ipairs(mafiaPlayers) do
        local box = Drawing.new("Square")
        box.Color = Color3.fromRGB(220, 60, 60)
        box.Thickness = 2
        box.Filled = false
        box.Visible = false

        local label = Drawing.new("Text")
        label.Color = Color3.fromRGB(255, 255, 255)
        label.Size = 13
        label.Outline = true
        label.Center = true
        label.Visible = false

        table.insert(espObjects, {
            player = data.player,
            displayName = data.displayName,
            box = box,
            label = label
        })
    end
end

-- Rebuild panel on a separate thread every 3 seconds
spawn(function()
    while true do
        buildPanel()
        wait(3)
    end
end)

-- ESP update loop
while true do
    wait()
    for _, obj in ipairs(espObjects) do
        local char = obj.player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hrp then
            local top = WorldToScreen(Vector3.new(hrp.Position.X, hrp.Position.Y + 2.8, hrp.Position.Z))
            local bot, visible = WorldToScreen(Vector3.new(hrp.Position.X, hrp.Position.Y - 3.2, hrp.Position.Z))

            if visible then
                local h = bot.Y - top.Y
                local w = h * 0.45
                obj.box.Position = Vector2.new(top.X - w / 2, top.Y)
                obj.box.Size = Vector2.new(w, h)
                obj.box.Visible = true
                obj.label.Text = obj.displayName
                obj.label.Position = Vector2.new(top.X, top.Y - 15)
                obj.label.Visible = true
            else
                obj.box.Visible = false
                obj.label.Visible = false
            end
        else
            obj.box.Visible = false
            obj.label.Visible = false
        end
    end
end
