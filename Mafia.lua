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
local ESP_MAX_DISTANCE = 2000

local alertHistory = {}
local displayCache = {}
local knownWeapons = {}
local mafiaCache = {}
local mafiaCacheTime = 0
local joinedNames, joinedCount = {}, 0
local seenAlive = {}
local deadList = {}

local trackerData = { alive = "0 / 0", mafia = "-", dead = "-", inno1 = "-", inno2 = "-", inno3 = "-", inno4 = "-" }

local ESPObjects = {}
local RenderCache = {}
local DrawCache = {}

local function getDisplayName(p)
    if not p then return "Unknown" end
    local n = p.Name
    if displayCache[n] then return displayCache[n] end
    local ok, char = pcall(function() return p.Character end)
    if not ok or not char then return n end
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
    local ok, char = pcall(function() return p.Character end)
    if not ok or not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local ok2, health = pcall(function() return hum.Health end)
    return ok2 and health > 0
end

local function getMafiaChannel()
    local ch
    pcall(function()
        local tc = TextChatService.TextChannels
        if tc then ch = tc:FindFirstChild("Mafia") end
    end)
    if not ch then
        pcall(function() ch = TextChatService:FindFirstChild("Mafia") end)
    end
    return ch
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
    if not p then return nil end
    local ok, char = pcall(function() return p.Character end)
    if not ok or not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local ok2, pos = pcall(function() return hrp.Position end)
        if ok2 and pos then return pos end
    end
    local head = char:FindFirstChild("Head")
    if head then
        local ok2, pos = pcall(function() return head.Position end)
        if ok2 and pos then return pos end
    end
    return nil
end

local function getModelPosition(model)
    if not model then return nil end
    local ok, pos = pcall(function()
        if model:IsA("BasePart") then return model.Position end
        local primary = model:FindFirstChildWhichIsA("BasePart")
        return primary and primary.Position or nil
    end)
    return ok and pos or nil
end

local function distanceSquared(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
    return dx*dx + dy*dy + dz*dz
end

local function findClosestPlayer(pos)
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == lp then continue end
        local pPos = getPlayerPosition(p)
        if not pPos then continue end
        local distSq = distanceSquared(pos, pPos)
        if distSq < closestDist then closestDist = distSq closest = p end
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

local function printAlert(msg, key)
    local now = tick()
    if key then
        local last = alertHistory[key]
        if last and (now - last) < ALERT_COOLDOWN then return end
        alertHistory[key] = now
    end
    print(msg)
end

local function checkWeapon(model, weaponName)
    local pos = getModelPosition(model)
    if not pos then return end
    local closest, distSq = findClosestPlayer(pos)
    if not closest or distSq > DETECT_RANGE_SQ then return end
    local mafiaNames = getMafiaNames()
    local dName = getDisplayName(closest)
    if not (mafiaNames[dName] or mafiaNames[closest.Name]) then return end
    local key = closest.Name .. "_" .. weaponName
    printAlert(string.format("MAFIA %s has %s", dName, weaponName), key)
end

local function newText(text, color, size)
    local t = Drawing.new("Text")
    t.Text, t.Size, t.Outline, t.Visible = text or "", size or 14, true, true
    t.Color = color or Color3.new(1,1,1)
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

local function setVis(obj, id, vis)
    local c = DrawCache[id]
    if not c then c = {}; DrawCache[id] = c end
    if c.vis ~= vis then
        c.vis = vis
        obj.Visible = vis
    end
end

local function setText(obj, id, txt)
    local c = DrawCache[id]
    if not c then c = {}; DrawCache[id] = c end
    if c.text ~= txt then
        c.text = txt
        obj.Text = txt
    end
end

local function setColor(obj, id, col)
    local c = DrawCache[id]
    if not c then c = {}; DrawCache[id] = c end
    if c.color ~= col then
        c.color = col
        obj.Color = col
    end
end

local function setPos(obj, id, pos)
    local c = DrawCache[id]
    if not c then c = {}; DrawCache[id] = c end
    if c.pos ~= pos then
        c.pos = pos
        obj.Position = pos
    end
end

local function setLine(obj, id, from, to)
    local c = DrawCache[id]
    if not c then c = {}; DrawCache[id] = c end
    if c.from ~= from then
        c.from = from
        obj.From = from
    end
    if c.to ~= to then
        c.to = to
        obj.To = to
    end
end

local function getHRPPosition(hrp)
    if not hrp then return nil end
    local ok, pos = pcall(function() return hrp.Position end)
    if ok and pos and typeof(pos) == "Vector3" then
        return pos
    end
    local ok2, cf = pcall(function() return hrp.CFrame end)
    if ok2 and cf and typeof(cf) == "CFrame" then
        return cf.Position
    end
    return nil
end

local function safeWorldToScreen(pos)
    if not pos then return nil, false end
    local ok, screenPos, onScreen = pcall(WorldToScreen, pos)
    if ok and screenPos and typeof(screenPos) == "Vector2" then
        return screenPos, onScreen
    end
    return nil, false
end

local function removePlayerESP(playerName)
    local obj = ESPObjects[playerName]
    if obj then
        for i = 1, 8 do
            if obj.corners[i] then obj.corners[i]:Remove() end
        end
        if obj.label then obj.label:Remove() end
        ESPObjects[playerName] = nil
    end
    RenderCache[playerName] = nil
    for k in pairs(DrawCache) do
        if k:sub(1, #playerName) == playerName then
            DrawCache[k] = nil
        end
    end
end

local function refreshESP()
    local mafiaNames = getMafiaNames()
    local newCache = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local ok, char = pcall(function() return p.Character end)
            if ok and char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local alive = hum and hum.Health > 0
                if alive then
                    local dName = getDisplayName(p)
                    local isMafia = mafiaNames[dName] or mafiaNames[p.Name]
                    newCache[p.Name] = { player = p, dName = dName, status = isMafia and "Mafia" or "Civ" }
                else
                    removePlayerESP(p.Name)
                end
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

local function renderESP()
    local camPos = Workspace.CurrentCamera.Position
    local usedThisFrame = {}
    for name, data in pairs(RenderCache) do
        local obj = ESPObjects[name]
        if not obj then
            local c = {}
            for i = 1, 8 do c[i] = newLine(Color3.fromRGB(220, 60, 60)) end
            local lbl = newText("", Color3.new(1,1,1), 16)
            obj = { corners = c, label = lbl, hrp = nil }
            ESPObjects[name] = obj
        end
        if not obj.hrp or obj.hrp.Parent == nil then
            local ok, char = pcall(function() return data.player.Character end)
            obj.hrp = ok and char and char:FindFirstChild("HumanoidRootPart")
        end
        local hrp = obj.hrp
        if hrp then
            local hrpPos = getHRPPosition(hrp)
            if hrpPos and (hrpPos - camPos).Magnitude <= ESP_MAX_DISTANCE then
                local topPos, topVis = safeWorldToScreen(hrpPos + Vector3.new(0, 2.8, 0))
                local botPos, botVis = safeWorldToScreen(hrpPos + Vector3.new(0, -3.2, 0))
                if topVis and botVis and topPos and botPos then
                    usedThisFrame[name] = true
                    local label = obj.label
                    local isMafia = data.status == "Mafia"
                    local baseId = name .. "_"
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
                        local c = obj.corners
                        local vCs = Vector2.new(cs, 0)
                        local vCy = Vector2.new(0, cs)
                        setLine(c[1], baseId.."c1", tl, tl + vCs)
                        setLine(c[2], baseId.."c2", tl, tl + vCy)
                        setLine(c[3], baseId.."c3", tr, tr - vCs)
                        setLine(c[4], baseId.."c4", tr, tr + vCy)
                        setLine(c[5], baseId.."c5", bl, bl + vCs)
                        setLine(c[6], baseId.."c6", bl, bl - vCy)
                        setLine(c[7], baseId.."c7", br, br - vCs)
                        setLine(c[8], baseId.."c8", br, br - vCy)
                        for i = 1, 8 do setVis(c[i], baseId.."c"..i, true) end
                        setText(label, baseId.."lbl", data.dName)
                        setColor(label, baseId.."lbl", Color3.fromRGB(220, 90, 90))
                        setPos(label, baseId.."lbl", Vector2.new(topX, topY - 18))
                        setVis(label, baseId.."lbl", true)
                    else
                        for i = 1, 8 do setVis(obj.corners[i], baseId.."c"..i, false) end
                        setText(label, baseId.."lbl", data.dName)
                        setColor(label, baseId.."lbl", Color3.fromRGB(190, 190, 200))
                        setPos(label, baseId.."lbl", Vector2.new(topPos.X, topPos.Y - 18))
                        setVis(label, baseId.."lbl", true)
                    end
                end
            end
        end
    end
    for name, obj in pairs(ESPObjects) do
        if not usedThisFrame[name] then
            local baseId = name .. "_"
            for i = 1, 8 do setVis(obj.corners[i], baseId.."c"..i, false) end
            setVis(obj.label, baseId.."lbl", false)
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

for _, p in ipairs(Players:GetPlayers() or {}) do
    if p and p ~= lp then
        joinedNames[p.Name] = true
        joinedCount = joinedCount + 1
    end
end

Players.PlayerAdded:Connect(function(p)
    if p and p ~= lp and not joinedNames[p.Name] then
        joinedNames[p.Name] = true
        joinedCount = joinedCount + 1
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if not p then return end
    local n = p.Name
    local dName = displayCache[n] or n
    displayCache[n] = nil
    seenAlive[n] = nil
    removePlayerESP(n)
end)

task.spawn(function()
    while true do
        task.wait(5)
        local all = Players:GetPlayers()
        if not all then continue end
        
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
        local currentAliveNames = {}
        
        for _, p in ipairs(all) do
            if p == lp then continue end
            local n = p.Name
            local dName = getDisplayName(p)
            local alive = isAlive(p)
            
            if alive then
                aliveCount = aliveCount + 1
                seenAlive[n] = dName
                currentAliveNames[n] = true
                if not mafiaSet[p] then
                    table.insert(innoList, dName)
                end
            else
                if seenAlive[n] and not currentAliveNames[n] then
                    local alreadyDead = false
                    for _, dead in ipairs(deadList) do
                        if dead == dName then alreadyDead = true break end
                    end
                    if not alreadyDead then
                        table.insert(deadList, dName)
                    end
                end
                if not seenAlive[n] and not currentAliveNames[n] then
                    local alreadyDead = false
                    for _, dead in ipairs(deadList) do
                        if dead == dName then alreadyDead = true break end
                    end
                    if not alreadyDead then
                        table.insert(deadList, dName)
                    end
                end
                seenAlive[n] = nil
            end
        end
        
        for n in pairs(seenAlive) do
            if not nameMap[n] then seenAlive[n] = nil end
        end
        
        local innoChunks = {"", "", "", ""}
        for i, name in ipairs(innoList) do
            local line = math.ceil(i / 5)
            if line <= 4 then
                local chunk = innoChunks[line]
                innoChunks[line] = chunk .. (chunk ~= "" and ", " or "") .. name
            end
        end
        
        trackerData.alive = aliveCount .. " / " .. joinedCount
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

local function watchPath(name, getModel)
    task.spawn(function()
        local wasPresent = false
        while true do
            task.wait(0.2)
            local model = getModel()
            local isPresent = model ~= nil
            if isPresent and not wasPresent then
                checkWeapon(model, name)
            end
            wasPresent = isPresent
        end
    end)
end

watchPath("Knife", function()
    local a = ReplicatedStorage:FindFirstChild("assets")
    local m = a and a:FindFirstChild("models")
    return m and m:FindFirstChild("Knife")
end)

watchPath("Gun", function()
    local e = Workspace:FindFirstChild("End")
    local three = e and e:FindFirstChild("3")
    local p = three and three:FindFirstChild("Poses")
    local v = p and p:FindFirstChild("vigilantePlaceholder1")
    return v and v:FindFirstChild("Gun")
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local mafiaNames = getMafiaNames()
        for _, p in ipairs(Players:GetPlayers()) do
            if p == lp then continue end
            local ok, char = pcall(function() return p.Character end)
            if not ok or not char then continue end
            local ok2, children = pcall(function() return char:GetChildren() end)
            if ok2 and children then
                for _, child in ipairs(children) do
                    local n = child.Name
                    if isWeaponName(n) and not knownWeapons[child] then
                        knownWeapons[child] = true
                        local pos = getModelPosition(child)
                        if pos then
                            local closest, distSq = findClosestPlayer(pos)
                            if closest and distSq <= DETECT_RANGE_SQ then
                                local dName = getDisplayName(closest)
                                if mafiaNames[dName] or mafiaNames[closest.Name] then
                                    local key = closest.Name .. "_" .. n
                                    printAlert(string.format("MAFIA %s has %s", dName, n), key)
                                end
                            end
                        end
                    end
                end
            end
            local backpack = p:FindFirstChild("Backpack")
            if backpack then
                local ok3, bpChildren = pcall(function() return backpack:GetChildren() end)
                if ok3 and bpChildren then
                    for _, child in ipairs(bpChildren) do
                        local n = child.Name
                        if isWeaponName(n) and not knownWeapons[child] then
                            knownWeapons[child] = true
                            local dName = getDisplayName(p)
                            if mafiaNames[dName] or mafiaNames[p.Name] then
                                local key = p.Name .. "_BP_" .. n
                                printAlert(string.format("MAFIA %s has %s (in backpack)", dName, n), key)
                            end
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        local ok, err = pcall(refreshESP)
        if not ok then warn("[ESP Refresh] " .. tostring(err)) end
        task.wait(1.5)
    end
end)

RunService.RenderStepped:Connect(renderESP)

print("Killer Tracker")
