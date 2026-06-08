local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local D = {}
local activeMafia = {}
local deadList, deadNames = {}, {}
local aliveCache = {}
local joinedNames, totalJoined = {}, 0

local function newText(text, color, size)
    local t = Drawing.new("Text")
    t.Text, t.Color, t.Size, t.Outline, t.Visible = text or "", color or Color3.new(1,1,1), size or 14, true, true
    return t
end

local function getName(p)
    if not p then return "Unknown" end
    local char = p.Character
    if not char then return p.Name or "Unknown" end
    local head = char:FindFirstChild("Head")
    local bill = head and head:FindFirstChildOfClass("BillboardGui")
    local lbl = bill and bill:FindFirstChildOfClass("TextLabel")
    return (lbl and lbl.Text ~= "" and lbl.Text) or p.Name or "Unknown"
end

local function isAlive(p)
    local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health and hum.Health > 0
end

local function countAlive()
    local c = 0
    for _, p in ipairs(Players:GetPlayers() or {}) do
        if p and p ~= Players.LocalPlayer and isAlive(p) then c = c + 1 end
    end
    return c
end

local function trackJoin(p)
    if not p or p == Players.LocalPlayer then return end
    local n = p.Name
    if n and not joinedNames[n] then joinedNames[n], totalJoined = true, totalJoined + 1 end
end

local function initPanel()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local ss = cam.ViewportSize
    if not ss then return end
    local W, x, y = 288, ss.X - 298, ss.Y/2 - 200

    D.bg = Drawing.new("Square")
    D.bg.Color, D.bg.Transparency, D.bg.Filled, D.bg.Visible = Color3.fromRGB(20,20,25), 0.9, true, true
    D.bg.Size, D.bg.Position = Vector2.new(W,400), Vector2.new(x,y)

    D.title = newText("PLAYERS", Color3.fromRGB(200,200,210), 18)
    D.title.Position = Vector2.new(x+12, y+10)

    D.remain = newText("", Color3.fromRGB(160,160,170), 14)

    D.sep = Drawing.new("Line")
    D.sep.Color, D.sep.Thickness, D.sep.Visible = Color3.fromRGB(50,50,60), 1, true

    D.mafiaT = newText("MAFIA", Color3.fromRGB(220,70,70), 16)
    D.deadT = newText("DEAD", Color3.fromRGB(120,120,130), 16)
    D.innoT = newText("INNOCENT", Color3.fromRGB(80,210,100), 16)

    D.emptyM = newText("None", Color3.fromRGB(80,80,90), 14)
    D.emptyD = newText("None", Color3.fromRGB(80,80,90), 14)

    D.mafiaL, D.innoL, D.deadL = {}, {}, {}
end

local function getMafia()
    local ch = TextChatService.TextChannels:FindFirstChild("Mafia")
    local all = Players:GetPlayers()
    if not all then return {}, {} end
    local map = {}
    for _, p in ipairs(all) do if p and p.Name then map[p.Name] = p end end
    local entries, mafiaPs = {}, {}
    if ch then
        for _, c in ipairs(ch:GetChildren() or {}) do
            if c and c.ClassName == "TextSource" then
                local p = map[c.Name]
                if p and p ~= Players.LocalPlayer and isAlive(p) then
                    table.insert(entries, {username=c.Name, displayName=getName(p)})
                    table.insert(mafiaPs, p)
                end
            end
        end
    end
    return entries, mafiaPs
end

local function updateDead()
    local all = Players:GetPlayers()
    if not all then return false end
    local aliveNow = {}
    for _, p in ipairs(all) do
        if p and p ~= Players.LocalPlayer and p.Name and isAlive(p) then
            aliveNow[p.Name] = true
            aliveCache[p.Name] = {displayName=getName(p), username=p.Name}
        end
    end
    local changed = false
    for name, data in pairs(aliveCache) do
        if not aliveNow[name] and not deadNames[name] then
            local stillHere = false
            for _, p in ipairs(all) do if p.Name == name then stillHere = true break end end
            if stillHere then
                deadNames[name] = true
                table.insert(deadList, {username=data.username, displayName=data.displayName, time=tick()})
                changed = true
            end
        end
    end
    for name, _ in pairs(aliveCache) do
        local here = false
        for _, p in ipairs(all) do if p.Name == name then here = true break end end
        if not here then aliveCache[name] = nil end
    end
    return changed
end

local function updatePanel(mafiaE, innoP)
    if not mafiaE or not innoP then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local ss = cam.ViewportSize
    if not ss then return end
    local W, LH, P, G = 288, 19, 12, 5
    local mC, iC, dC = #mafiaE, #innoP, #deadList
    local halfW = (W - P*3)/2
    local mH = mC > 0 and LH*(mC+1) or LH
    local dH = dC > 0 and LH*(dC+1) or LH
    local topH = math.max(mH, dH)
    local iRows = math.ceil(iC/2)
    local iH = LH*(iRows+1)
    local pH = 34 + G + topH + G + iH + P
    local x, y = ss.X - W - 10, ss.Y/2 - pH/2

    D.bg.Size, D.bg.Position = Vector2.new(W,pH), Vector2.new(x,y)
    D.title.Position = Vector2.new(x+12, y+8)
    D.remain.Position = Vector2.new(x+W-96, y+9)

    D.sep.From = Vector2.new(x+12, y+31)
    D.sep.To = Vector2.new(x+W-12, y+31)

    local my = y + 34 + G
    D.mafiaT.Position = Vector2.new(x+P, my)
    local mcy = my + LH
    D.emptyM.Visible = mC == 0
    D.emptyM.Position = Vector2.new(x+P+2, mcy)
    if mC == 0 then mcy = mcy + LH end

    for i = 1, math.max(mC, #D.mafiaL) do
        local l = D.mafiaL[i]
        if i <= mC then
            if not l then l = newText("", Color3.fromRGB(220,90,90), 14); D.mafiaL[i] = l end
            l.Text = mafiaE[i] and mafiaE[i].displayName or "Unknown"
            l.Position, l.Visible = Vector2.new(x+P+2, mcy), true
            mcy = mcy + LH
        elseif l then l.Visible = false end
    end

    local dx = x + P*2 + halfW
    D.deadT.Position = Vector2.new(dx, my)
    local dcy = my + LH
    D.emptyD.Visible = dC == 0
    D.emptyD.Position = Vector2.new(dx+2, dcy)
    if dC == 0 then dcy = dcy + LH end

    for i = 1, math.max(dC, #D.deadL) do
        local l = D.deadL[i]
        if i <= dC then
            if not l then l = newText("", Color3.fromRGB(120,120,130), 14); D.deadL[i] = l end
            l.Text = deadList[i] and deadList[i].displayName or "Unknown"
            l.Position, l.Visible = Vector2.new(dx+2, dcy), true
            dcy = dcy + LH
        elseif l then l.Visible = false end
    end

    local iy = my + topH + G
    D.innoT.Position = Vector2.new(x+P, iy)
    iy = iy + LH
    local colW = (W - P*2)/2

    for i = 1, math.max(iC, #D.innoL) do
        local l = D.innoL[i]
        if i <= iC then
            if not l then l = newText("", Color3.fromRGB(190,190,200), 14); D.innoL[i] = l end
            local e = innoP[i]
            l.Text = e and (e.displayName or e.username or "Unknown") or "Unknown"
            l.Position = Vector2.new(x+P+2 + ((i-1)%2)*colW, iy + math.floor((i-1)/2)*LH)
            l.Visible = true
        elseif l then l.Visible = false end
    end
end

local function updateRemainCounter()
    if not D.remain then return end
    local aliveC = countAlive()
    D.remain.Text = aliveC.." / "..totalJoined
end

local function refresh()
    local mafiaE, mafiaP = getMafia()
    if not mafiaE then return end
    local mafiaNames = {}
    for _, e in ipairs(mafiaE) do if e and e.displayName then mafiaNames[e.displayName] = true end end
    local innoP = {}
    for _, p in ipairs(Players:GetPlayers() or {}) do
        if p and p ~= Players.LocalPlayer and isAlive(p) then
            local isM = false
            for _, m in ipairs(mafiaP) do if m == p then isM = true break end end
            if not isM then table.insert(innoP, {username=p.Name, displayName=getName(p), player=p}) end
        end
    end
    for i = #innoP, 1, -1 do
        if mafiaNames[innoP[i].displayName] then table.remove(innoP, i) end
    end
    updatePanel(mafiaE, innoP)
end

Players.PlayerAdded:Connect(trackJoin)
Players.PlayerRemoving:Connect(function(p)
    if p and p.Name then aliveCache[p.Name] = nil end
end)
for _, p in ipairs(Players:GetPlayers() or {}) do trackJoin(p) end
initPanel()

task.spawn(function()
    while true do
        local deadChanged = false
        local ok1, changed = pcall(updateDead)
        if ok1 and changed then deadChanged = true end
        pcall(updateRemainCounter)
        if deadChanged then
            pcall(refresh)
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    while true do
        task.wait(3)
        local ok, err = pcall(refresh)
        if not ok then warn("R: "..tostring(err)) end
    end
end)
