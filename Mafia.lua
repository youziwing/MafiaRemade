local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local lp = Players.LocalPlayer

local joinedNames, joinedCount = {}, 0
local displayCache = {}
local seenAlive = {}
local deadList = {}

local uiData = {
    alive = "0 / 0",
    mafia = "-",
    dead = "-",
    inno1 = "-",
    inno2 = "-",
    inno3 = "-",
    inno4 = "-"
}

local mafiaEspSet = {}
local espCache = {}
local lastEspRefresh = 0

local function newSquare()
    local s = Drawing.new("Square")
    s.Thickness = 1.2
    s.Filled = true
    s.Transparency = 0.12
    s.Visible = false
    return s
end

local function newText()
    local t = Drawing.new("Text")
    t.Size = 13
    t.Center = true
    t.Outline = true
    t.Visible = false
    return t
end

local function getDisplayName(p)
    if not p then return "Unknown" end
    local n = p.Name
    local cached = displayCache[n]
    if cached then return cached end
    local char = p.Character
    if not char then return n end
    local head = char:FindFirstChild("Head")
    if not head then return n end
    local bill = head:FindFirstChildOfClass("BillboardGui")
    if not bill then return n end
    local lbl = bill:FindFirstChildOfClass("TextLabel")
    if lbl and lbl.Text ~= "" then
        displayCache[n] = lbl.Text
        return lbl.Text
    end
    return n
end

local function trackJoin(p)
    if not p or p == lp then return end
    local n = p.Name
    if n and not joinedNames[n] then
        joinedNames[n] = true
        joinedCount = joinedCount + 1
    end
end

local function isAlive(p)
    local char = p.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getMafiaChannel()
    local ch
    pcall(function()
        local tc = TextChatService.TextChannels
        if tc then ch = tc:FindFirstChild("Mafia") end
    end)
    if not ch then
        pcall(function()
            ch = TextChatService:FindFirstChild("Mafia")
        end)
    end
    return ch
end

local function getMafia(all, map)
    local ch = getMafiaChannel()
    if not ch then return {}, {} end

    local entries, mafiaPs = {}, {}
    local children = ch:GetChildren()
    if not children then return {}, {} end
    
    for _, c in ipairs(children) do
        if c.ClassName == "TextSource" then
            local p = map[c.Name]
            if p and p ~= lp and isAlive(p) then
                local dName = getDisplayName(p)
                table.insert(entries, dName)
                table.insert(mafiaPs, p)
            end
        end
    end
    return entries, mafiaPs
end

local function getEsp(p)
    local e = espCache[p]
    if e then return e end
    e = {
        box = newSquare(),
        outline = newSquare(),
        name = newText()
    }
    e.outline.Filled = false
    e.outline.Transparency = 1
    espCache[p] = e
    return e
end

local function removeEsp(p)
    local e = espCache[p]
    if not e then return end
    pcall(function() e.box:Remove() end)
    pcall(function() e.outline:Remove() end)
    pcall(function() e.name:Remove() end)
    espCache[p] = nil
end

local function hideEsp(e)
    e.box.Visible = false
    e.outline.Visible = false
    e.name.Visible = false
end

local function toScreen(pos)
    local ok, result, onScreen = pcall(WorldToScreen, pos)
    if ok and onScreen and result then return result end
    return nil
end

local function drawEsp(p, e)
    local char = p.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local head = char:FindFirstChild("Head")
    local topPos = head and (head.Position + Vector3.new(0, 0.6, 0)) or (hrp.Position + Vector3.new(0, 3, 0))
    local botPos = hrp.Position - Vector3.new(0, 3.2, 0)

    local top = toScreen(topPos)
    local bot = toScreen(botPos)
    if not top or not bot then return false end

    local h = bot.Y - top.Y
    if h < 10 then return false end
    local w = h * 0.5
    local x, y = top.X, top.Y

    local fx = math.floor(x - w/2 + 0.5)
    local fy = math.floor(y + 0.5)
    local fw = math.floor(w + 0.5)
    local fh = math.floor(h + 0.5)

    e.box.Position = Vector2.new(fx, fy)
    e.box.Size = Vector2.new(fw, fh)
    e.box.Visible = true

    e.outline.Position = Vector2.new(fx, fy)
    e.outline.Size = Vector2.new(fw, fh)
    e.outline.Visible = true

    e.name.Position = Vector2.new(math.floor(x + 0.5), math.floor(y - 18 + 0.5))
    e.name.Text = getDisplayName(p)
    e.name.Visible = true

    return true
end

local function getMafiaEsp()
    local ch = getMafiaChannel()
    if not ch then return {} end

    local all = Players:GetPlayers()
    local map = {}
    for _, p in ipairs(all) do
        if p and p.Name then map[p.Name] = p end
    end

    local result = {}
    local children = ch:GetChildren()
    if not children then return {} end
    
    for _, c in ipairs(children) do
        if c.ClassName == "TextSource" then
            local p = map[c.Name]
            if p and p ~= lp then
                local char = p.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    result[p] = true
                end
            end
        end
    end
    return result
end

UI.AddTab("Player Tracker", function(tab)
    local info = tab:Section("Live Info", "Left")
    info:InputText("alive_txt", "Alive", uiData.alive, function() return uiData.alive end)
    info:InputText("mafia_txt", "Mafia", uiData.mafia, function() return uiData.mafia end)
    info:InputText("dead_txt", "Dead", uiData.dead, function() return uiData.dead end)

    local inno = tab:Section("Innocent", "Right")
    inno:InputText("inno_1", "Row 1", uiData.inno1, function() return uiData.inno1 end)
    inno:InputText("inno_2", "Row 2", uiData.inno2, function() return uiData.inno2 end)
    inno:InputText("inno_3", "Row 3", uiData.inno3, function() return uiData.inno3 end)
    inno:InputText("inno_4", "Row 4", uiData.inno4, function() return uiData.inno4 end)
end)

for _, p in ipairs(Players:GetPlayers() or {}) do trackJoin(p) end
Players.PlayerAdded:Connect(trackJoin)
Players.PlayerRemoving:Connect(function(p)
    if not p then return end
    local n = p.Name
    local dName = displayCache[n] or n

    displayCache[n] = nil
    seenAlive[n] = nil

    for i = #deadList, 1, -1 do
        if deadList[i] == dName then
            table.remove(deadList, i)
            break
        end
    end

    removeEsp(p)
    mafiaEspSet[p] = nil
end)

task.spawn(function()
    while true do
        task.wait(1.5)

        local all = Players:GetPlayers()
        if not all then continue end

        local nameMap = {}
        for _, p in ipairs(all) do
            trackJoin(p)
            if p ~= lp then
                nameMap[p.Name] = p
            end
        end

        local mafiaNames, mafiaP = getMafia(all, nameMap)

        local mafiaSetTracker = {}
        for _, m in ipairs(mafiaP) do
            mafiaSetTracker[m] = true
        end

        local aliveNow = {}
        local aliveCount = 0
        local innoList = {}

        for _, p in ipairs(all) do
            if p == lp then continue end
            local n = p.Name
            local dName = getDisplayName(p)

            if isAlive(p) then
                aliveCount = aliveCount + 1
                aliveNow[n] = dName
                seenAlive[n] = dName
                if not mafiaSetTracker[p] then
                    table.insert(innoList, dName)
                end
            else
                if seenAlive[n] then
                    local alreadyDead = false
                    for _, dead in ipairs(deadList) do
                        if dead == dName then
                            alreadyDead = true
                            break
                        end
                    end
                    if not alreadyDead then
                        table.insert(deadList, dName)
                    end
                    seenAlive[n] = nil
                end
            end
        end

        for n in pairs(seenAlive) do
            if not nameMap[n] then
                seenAlive[n] = nil
            end
        end

        local innoChunks = {"", "", "", ""}
        for i, name in ipairs(innoList) do
            local line = math.ceil(i / 5)
            if line <= 4 then
                local chunk = innoChunks[line]
                innoChunks[line] = chunk .. (chunk ~= "" and ", " or "") .. name
            end
        end

        uiData.alive = aliveCount .. " / " .. joinedCount
        uiData.mafia = #mafiaNames > 0 and table.concat(mafiaNames, ", ") or "None"
        uiData.dead = #deadList > 0 and table.concat(deadList, ", ") or "None"
        uiData.inno1 = innoChunks[1] ~= "" and innoChunks[1] or "-"
        uiData.inno2 = innoChunks[2] ~= "" and innoChunks[2] or "-"
        uiData.inno3 = innoChunks[3] ~= "" and innoChunks[3] or "-"
        uiData.inno4 = innoChunks[4] ~= "" and innoChunks[4] or "-"

        pcall(function()
            UI.SetValue("alive_txt", uiData.alive)
            UI.SetValue("mafia_txt", uiData.mafia)
            UI.SetValue("dead_txt", uiData.dead)
            UI.SetValue("inno_1", uiData.inno1)
            UI.SetValue("inno_2", uiData.inno2)
            UI.SetValue("inno_3", uiData.inno3)
            UI.SetValue("inno_4", uiData.inno4)
        end)
    end
end)

task.spawn(function()
    while true do
        task.wait(0.1)

        local now = tick()
        if now - lastEspRefresh > 0.5 then
            mafiaEspSet = getMafiaEsp()
            lastEspRefresh = now
        end

        for p, e in pairs(espCache) do
            if not mafiaEspSet[p] then
                hideEsp(e)
            end
        end

        for p in pairs(mafiaEspSet) do
            if not p or not p.Parent then
                mafiaEspSet[p] = nil
                removeEsp(p)
                continue
            end
            local e = getEsp(p)
            local ok = pcall(drawEsp, p, e)
            if not ok then
                hideEsp(e)
            end
        end

        local toRemove = {}
        for p in pairs(espCache) do
            if not p or not p.Parent then
                table.insert(toRemove, p)
            end
        end
        for _, p in ipairs(toRemove) do
            removeEsp(p)
        end
    end
end)
