local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local WATCH_NAMES = {"Knife", "Gun", "Pistol", "Revolver", "Weapon", "Blade", "Dagger"}
local EXCLUDE_NAMES = {"Handle", "Mesh", "Texture", "Decal"}
local DETECT_RANGE_SQ = 400
local ALERT_COOLDOWN = 3

local alertHistory = {}
local knownWeapons = {}
local mafiaCache = {}
local mafiaCacheTime = 0
local deadList = {}
local previousAlive = {}
local totalJoined = 0
local displayCache = {}

local trackerData = { alive = "0 / 0", mafia = "-", dead = "-", inno1 = "-", inno2 = "-", inno3 = "-", inno4 = "-" }

local ESPObjects = {}
local RenderCache = {}
local renderFrame = 0

local mafColor = Color3.fromRGB(220, 90, 90)
local innoColor = Color3.fromRGB(190, 190, 200)

local VEC_TOP = Vector3.new(0, 2.8, 0)
local VEC_BOT = Vector3.new(0, -3.2, 0)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= lp then totalJoined = totalJoined + 1 end
end

local function getDisplayName(p)
    if not p then return "Unknown" end
    local n = p.Name
    if displayCache[n] then return displayCache[n] end
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

local function isAlive(p)
    local char = p.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getMafiaChannel()
    local ok, tc = pcall(function() return TextChatService.TextChannels end)
    if ok and tc then
        local ch = tc:FindFirstChild("Mafia")
        if ch then return ch end
    end
    local ok2, ch2 = pcall(function() return TextChatService:FindFirstChild("Mafia") end)
    return ok2 and ch2 or nil
end

local function getMafiaNames()
    local now = tick()
    if now - mafiaCacheTime < 1 then return mafiaCache end
    local ch = getMafiaChannel()
    if not ch then mafiaCache = {} mafiaCacheTime = now return mafiaCache end
    local names = {}
    local ok, children = pcall(function() return ch:GetChildren() end)
    if ok and children then
        for _, c in ipairs(children) do
            if c.ClassName == "TextSource" then
                local p = Players:FindFirstChild(c.Name)
                if p and p ~= lp then
                    local dName = getDisplayName(p)
                    names[dName] = true
                    names[p.Name] = true
                end
            end
        end
    end
    mafiaCache = names
    mafiaCacheTime = now
    return names
end

local function getPlayerPosition(p)
    local char = p.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position end
    local head = char:FindFirstChild("Head")
    return head and head.Position or nil
end

local function getModelPosition(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model.Position end
    local primary = model:FindFirstChildWhichIsA("BasePart")
    return primary and primary.Position or nil
end

local function distanceSquared(a, b)
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    return dx*dx + dy*dy + dz*dz
end

local function findClosestPlayer(pos)
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local pPos = getPlayerPosition(p)
            if pPos then
                local distSq = distanceSquared(pos, pPos)
                if distSq < closestDist then
                    closestDist = distSq
                    closest = p
                end
            end
        end
    end
    return closest, closestDist
end

local function isWeaponName(name)
    if not name then return false end
    local low = name:lower()
    for _, w in ipairs(WATCH_NAMES) do
        if low:find(w:lower()) then
            for _, ex in ipairs(EXCLUDE_NAMES) do
                if low == ex:lower() then return false end
            end
            return true
        end
    end
    return false
end

local function sendAlert(msg, key)
    local now = tick()
    if key then
        local last = alertHistory[key]
        if last and (now - last) < ALERT_COOLDOWN then return end
        alertHistory[key] = now
    end
    pcall(function()
        notify(msg, "Killer Tracker", 7)
    end)
end

local function checkWeapon(model, weaponName)
    local pos = getModelPosition(model)
    if not pos then return end
    local closest, distSq = findClosestPlayer(pos)
    if not closest or distSq > DETECT_RANGE_SQ then return end
    local mafiaNames = getMafiaNames()
    local dName = getDisplayName(closest)
    if not (mafiaNames[dName] or mafiaNames[closest.Name]) then return end
    sendAlert(string.format("MAFIA %s has %s", dName, weaponName), closest.Name .. "_" .. weaponName)
end

local function newText(text, color, size)
    local t = Drawing.new("Text")
    t.Text, t.Size, t.Outline, t.Visible = text or "", size or 14, true, true
    t.Color = color or Color3.new(1,1,1)
    t.Center = true
    pcall(function() t.Font = Drawing.Fonts.UI end)
    return t
end

local function newLine(color)
    local l = Drawing.new("Line")
    l.Color = color or Color3.new(1,1,1)
    l.Thickness = 2
    l.Visible = false
    return l
end

local function removePlayerESP(playerName)
    local obj = ESPObjects[playerName]
    if obj then
        for i = 1, 8 do
            if obj.corners[i] then pcall(function() obj.corners[i]:Remove() end) end
        end
        if obj.label then pcall(function() obj.label:Remove() end) end
        ESPObjects[playerName] = nil
    end
    RenderCache[playerName] = nil
end

local function refreshESP()
    local mafiaNames = getMafiaNames()
    local newCache = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local alive = isAlive(p)
            if alive then
                local dName = getDisplayName(p)
                local isMafia = mafiaNames[dName] or mafiaNames[p.Name]
                newCache[p.Name] = { player = p, dName = dName, status = isMafia and "Mafia" or "Civ" }
            else
                removePlayerESP(p.Name)
            end
        end
    end
    for name in pairs(RenderCache) do
        if not newCache[name] then
            removePlayerESP(name)
        end
    end
    RenderCache = newCache
end

local function setLineFast(line, f, t)
    if line.From ~= f then line.From = f end
    if line.To ~= t then line.To = t end
end

local function renderESP()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    renderFrame = renderFrame + 1

    for name, data in pairs(RenderCache) do
        local obj = ESPObjects[name]
        if not obj then
            local c = {}
            for i = 1, 8 do c[i] = newLine(Color3.fromRGB(220, 60, 60)) end
            obj = { corners = c, label = newText("", Color3.new(1,1,1), 16), hrp = nil, lastFrame = 0 }
            ESPObjects[name] = obj
        end

        if not obj.hrp or obj.hrp.Parent == nil then
            local char = data.player.Character
            obj.hrp = char and char:FindFirstChild("HumanoidRootPart")
        end

        local hrp = obj.hrp
        if hrp then
            local hrpPos = hrp.Position
            
            local topPos, topVis = WorldToScreen(hrpPos + VEC_TOP)
            local botPos, botVis = WorldToScreen(hrpPos + VEC_BOT)

            if topVis and botVis and topPos and botPos then
                obj.lastFrame = renderFrame 
                
                local isMafia = data.status == "Mafia"
                local label = obj.label
                local corners = obj.corners

                if isMafia then
                    local h = botPos.Y - topPos.Y
                    local w = h * 0.45
                    local cs = math.max(6, math.min(w,h) * 0.15)
                    local topX, topY = topPos.X, topPos.Y
                    local botX, botY = botPos.X, botPos.Y
                    local halfW = w / 2

                    local tl = Vector2.new(topX - halfW, topY)
                    local tr = Vector2.new(topX + halfW, topY)
                    local bl = Vector2.new(botX - halfW, botY)
                    local br = Vector2.new(botX + halfW, botY)

                    local vCs = Vector2.new(cs, 0)
                    local vCy = Vector2.new(0, cs)

                    setLineFast(corners[1], tl, tl + vCs)
                    setLineFast(corners[2], tl, tl + vCy)
                    setLineFast(corners[3], tr, tr - vCs)
                    setLineFast(corners[4], tr, tr + vCy)
                    setLineFast(corners[5], bl, bl + vCs)
                    setLineFast(corners[6], bl, bl - vCy)
                    setLineFast(corners[7], br, br - vCs)
                    setLineFast(corners[8], br, br - vCy)

                    for i = 1, 8 do 
                        if not corners[i].Visible then corners[i].Visible = true end 
                    end

                    if label.Text ~= data.dName then label.Text = data.dName end
                    if label.Color ~= mafColor then label.Color = mafColor end
                    if label.Position ~= Vector2.new(topX, topY - 18) then label.Position = Vector2.new(topX, topY - 18) end
                    if not label.Visible then label.Visible = true end
                else
                    for i = 1, 8 do 
                        if corners[i].Visible then corners[i].Visible = false end 
                    end

                    if label.Text ~= data.dName then label.Text = data.dName end
                    if label.Color ~= innoColor then label.Color = innoColor end
                    if label.Position ~= Vector2.new(topPos.X, topPos.Y - 18) then label.Position = Vector2.new(topPos.X, topPos.Y - 18) end
                    if not label.Visible then label.Visible = true end
                end
            end
        end
    end

    for name, obj in pairs(ESPObjects) do
        if obj.lastFrame ~= renderFrame then
            for i = 1, 8 do 
                if obj.corners[i].Visible then obj.corners[i].Visible = false end 
            end
            if obj.label.Visible then obj.label.Visible = false end
        end
    end
end

pcall(function()
    UI.AddTab("Players", function(tab)
        local info = tab:Section("Live Info", "Left")
        info:InputText("alive_txt", "Alive", trackerData.alive, function() end)
        info:InputText("mafia_txt", "Mafia", trackerData.mafia, function() end)
        info:InputText("dead_txt", "Dead", trackerData.dead, function() end)
        local inno = tab:Section("Innocent", "Right")
        inno:InputText("inno_1", "Row 1", trackerData.inno1, function() end)
        inno:InputText("inno_2", "Row 2", trackerData.inno2, function() end)
        inno:InputText("inno_3", "Row 3", trackerData.inno3, function() end)
        inno:InputText("inno_4", "Row 4", trackerData.inno4, function() end)
    end)
end)

Players.PlayerAdded:Connect(function(p)
    if p and p ~= lp then totalJoined = totalJoined + 1 end
end)

Players.PlayerRemoving:Connect(function(p)
    if not p then return end
    local n = p.Name
    displayCache[n] = nil
    previousAlive[n] = nil
    removePlayerESP(n)
    for model, _ in pairs(knownWeapons) do
        if typeof(model) == "Instance" and (not model.Parent or not p.Character or not p.Character:IsDescendantOf(game)) then
            knownWeapons[model] = nil
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(5)
        local all = Players:GetPlayers()
        local nameMap = {}
        for _, p in ipairs(all) do
            if p ~= lp then nameMap[p.Name] = p end
        end

        local ch = getMafiaChannel()
        local mafiaEntries = {}
        local mafiaSet = {}
        if ch then
            local ok, children = pcall(function() return ch:GetChildren() end)
            if ok and children then
                for _, c in ipairs(children) do
                    if c.ClassName == "TextSource" then
                        local p = nameMap[c.Name]
                        if p and isAlive(p) then
                            local dName = getDisplayName(p)
                            table.insert(mafiaEntries, dName)
                            mafiaSet[p] = true
                        end
                    end
                end
            end
        end

        local aliveCount = 0
        local innoList = {}
        local currentAlive = {}

        for _, p in ipairs(all) do
            if p == lp then continue end
            local dName = getDisplayName(p)
            if isAlive(p) then
                aliveCount = aliveCount + 1
                currentAlive[p.Name] = dName
                if not mafiaSet[p] then
                    table.insert(innoList, dName)
                end
            end
        end

        for name, dName in pairs(previousAlive) do
            if not currentAlive[name] then
                local alreadyDead = false
                for _, dead in ipairs(deadList) do
                    if dead == dName then alreadyDead = true break end
                end
                if not alreadyDead then
                    table.insert(deadList, dName)
                end
            end
        end
        previousAlive = currentAlive

        local innoChunks = {"", "", "", ""}
        for i, name in ipairs(innoList) do
            local line = math.ceil(i / 5)
            if line <= 4 then
                local chunk = innoChunks[line]
                innoChunks[line] = chunk .. (chunk ~= "" and ", " or "") .. name
            end
        end

        trackerData.alive = aliveCount .. " / " .. totalJoined
        trackerData.mafia = #mafiaEntries > 0 and table.concat(mafiaEntries, ", ") or "None"
        trackerData.dead = #deadList > 0 and table.concat(deadList, ", ") or "None"
        trackerData.inno1 = innoChunks[1] ~= "" and innoChunks[1] or "-"
        trackerData.inno2 = innoChunks[2] ~= "" and innoChunks[2] or "-"
        trackerData.inno3 = innoChunks[3] ~= "" and innoChunks[3] or "-"
        trackerData.inno4 = innoChunks[4] ~= "" and innoChunks[4] or "-"

        pcall(function()
            UI.SetValue("alive_txt", trackerData.alive)
            UI.SetValue("mafia_txt", trackerData.mafia)
            UI.SetValue("dead_txt", trackerData.dead)
            UI.SetValue("inno_1", trackerData.inno1)
            UI.SetValue("inno_2", trackerData.inno2)
            UI.SetValue("inno_3", trackerData.inno3)
            UI.SetValue("inno_4", trackerData.inno4)
        end)
    end
end)

task.spawn(function()
    local wasPresent = false
    while true do
        task.wait(0.2)
        local a = ReplicatedStorage:FindFirstChild("assets")
        local m = a and a:FindFirstChild("models")
        local model = m and m:FindFirstChild("Knife")
        local isPresent = model ~= nil
        if isPresent and not wasPresent then
            checkWeapon(model, "Knife")
        end
        wasPresent = isPresent
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local mafiaNames = getMafiaNames()
        for _, p in ipairs(Players:GetPlayers()) do
            if p == lp then continue end
            if not mafiaNames[p.Name] then continue end
            local char = p.Character
            if not char then continue end
            for _, child in ipairs(char:GetChildren()) do
                local n = child.Name
                if isWeaponName(n) and not knownWeapons[child] then
                    knownWeapons[child] = true
                    local dName = getDisplayName(p)
                    sendAlert(string.format("MAFIA %s has %s", dName, n), p.Name .. "_" .. n)
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        local ok, err = pcall(refreshESP)
        if not ok then warn("[ESP Refresh] " .. tostring(err)) end
        task.wait(5)
    end
end)

RunService.RenderStepped:Connect(renderESP)

notify("Killer Tracker + ESP loaded", "Killer Tracker", 3)
