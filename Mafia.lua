local Players = game.Players or game:GetService("Players") 
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer

local WATCH_NAMES = {"Knife", "Gun", "Pistol", "Revolver", "Weapon", "Blade", "Dagger", "Glock"}
local EXCLUDE_NAMES = {"Handle", "Mesh", "Texture", "Decal"}
local ALERT_COOLDOWN = 3
local KILLER_TIMEOUT = 85

local alertHistory = {}
local mafiaCache = {}
local mafiaCacheTime = 0local veilCache = {}
local veilCacheTime = 0

local deadList = {}
local previousAlive = {}
local totalJoined = 0
local displayCache = {}

local killers = {}
local KILLER_COLOR = Color3.fromRGB(255, 140, 30)
local KILLER_TAG = "[KILLER]"

local veilColor  = Color3.fromRGB(160, 80, 230)
local VEIL_TAG   = "[VEIL]"

local trackerData = { alive = "0 / 0", mafia = "-", veil = "-", dead = "-", inno1 = "-", inno2 = "-", inno3 = "-", inno4 = "-" }

local ESPObjects = {}
local RenderCache = {}
local renderFrame = 0

local mafColor  = Color3.fromRGB(220, 90, 90)
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

local function getVeilChannel()
    local ok, tc = pcall(function() return TextChatService.TextChannels end)
    if ok and tc then
        local ch = tc:FindFirstChild("Veil")
        if ch then return ch end
    end
    local ok2, ch2 = pcall(function() return TextChatService:FindFirstChild("Veil") end)
    return ok2 and ch2 or nil
end

local function getVeilNames()
    local now = tick()
    if now - veilCacheTime < 1 then return veilCache end
    local ch = getVeilChannel()
    if not ch then veilCache = {} veilCacheTime = now return veilCache end
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
    veilCache = names
    veilCacheTime = now
    return names
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

local function isGunName(name)
    if not name then return false end
    local low = name:lower()
    local guns = {"gun", "pistol", "revolver", "glock", "shoot", "fire"}
    for _, g in ipairs(guns) do
        if low:find(g) then return true end
    end
    return false
end

local function isKnifeName(name)
    if not name then return false end
    local low = name:lower()
    local knives = {"knife", "blade", "dagger"}
    for _, k in ipairs(knives) do
        if low:find(k) then return true end
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

local function detectKiller()
    local currentMafia = getMafiaNames()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == lp then continue end
        if not currentMafia[p.Name] then continue end
        local char = p.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then continue end

        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") and isWeaponName(child.Name) then
                if not killers[p.Name] then
                    killers[p.Name] = tick()
                    local weaponType = "attacking"
                    if isGunName(child.Name) then
                        weaponType = "shooting"
                    elseif isKnifeName(child.Name) then
                        weaponType = "knifing"
                    end
                    sendAlert(getDisplayName(p) .. " is " .. weaponType .. "!", p.Name .. "_killer")
                end
            end
        end

        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok and tracks then
                for _, track in ipairs(tracks) do
                    local animName = ""
                    pcall(function() animName = track.Animation and track.Animation.Name or "" end)
                    local lowAnim = animName:lower()
                    if lowAnim:find("shoot") or lowAnim:find("fire") then
                        if not killers[p.Name] then
                            killers[p.Name] = tick()
                            sendAlert(getDisplayName(p) .. " is shooting!", p.Name .. "_killer")
                        end
                    elseif lowAnim:find("knife") or lowAnim:find("stab") or lowAnim:find("slash") then
                        if not killers[p.Name] then
                            killers[p.Name] = tick()
                            sendAlert(getDisplayName(p) .. " is knifing!", p.Name .. "_killer")
                        end
                    end
                end
            end
        end
    end
end

local function resetKillers()
    if next(killers) ~= nil then
        killers = {}
    end
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
        if obj.label   then pcall(function() obj.label:Remove()   end) end
        if obj.tag     then pcall(function() obj.tag:Remove()     end) end
        if obj.veilTag then pcall(function() obj.veilTag:Remove() end) end
        ESPObjects[playerName] = nil
    end
    RenderCache[playerName] = nil
end

local function refreshESP()
    local mafiaNames = getMafiaNames()
    local veilNames  = getVeilNames()
    local newCache   = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local alive = isAlive(p)
            if alive then
                local dName  = getDisplayName(p)
                local isMafia = mafiaNames[dName] or mafiaNames[p.Name]
                local isVeil  = veilNames[dName]  or veilNames[p.Name]
                newCache[p.Name] = {
                    player   = p,
                    dName    = dName,
                    status   = isMafia and "Mafia" or "Civ",
                    isKiller = killers[p.Name] ~= nil,
                    isVeil   = isVeil and true or false,
                }
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
    if line.To   ~= t then line.To   = t end
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
            obj = {
                corners  = c,
                label    = newText("", Color3.new(1,1,1), 16),
                tag      = newText("", KILLER_COLOR, 14),
                veilTag  = newText("", veilColor, 14),  -- [VEIL] tag
                hrp      = nil,
                lastFrame = 0
            }
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

                local isKiller = killers[name] ~= nil
                local isVeil   = data.isVeil

                local color = data.status == "Mafia" and mafColor or innoColor
                if isKiller then color = KILLER_COLOR end
                if isVeil   then color = veilColor    end

                local label   = obj.label
                local corners = obj.corners

                for i = 1, 8 do
                    if corners[i].Color ~= color then corners[i].Color = color end
                end

                if data.status == "Mafia" or isVeil then
                    local h     = botPos.Y - topPos.Y
                    local w     = h * 0.45
                    local cs    = math.max(6, math.min(w,h) * 0.15)
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
                    if label.Color ~= color      then label.Color = color     end
                    local labelPos = Vector2.new(topX, topY - 18)
                    if label.Position ~= labelPos then label.Position = labelPos end
                    if not label.Visible then label.Visible = true end

                    if isKiller and not isVeil then
                        local tagPos = Vector2.new(topX + halfW + 35, topY - 18)
                        if obj.tag.Text     ~= KILLER_TAG   then obj.tag.Text     = KILLER_TAG   end
                        if obj.tag.Color    ~= KILLER_COLOR then obj.tag.Color    = KILLER_COLOR end
                        if obj.tag.Position ~= tagPos       then obj.tag.Position = tagPos       end
                        if not obj.tag.Visible then obj.tag.Visible = true end
                    else
                        if obj.tag.Visible then obj.tag.Visible = false end
                    end

                    if isVeil then
                        local vTagPos = Vector2.new(topX + halfW + 35, topY - 18)
                        if obj.veilTag.Text     ~= VEIL_TAG   then obj.veilTag.Text     = VEIL_TAG   end
                        if obj.veilTag.Color    ~= veilColor  then obj.veilTag.Color    = veilColor  end
                        if obj.veilTag.Position ~= vTagPos    then obj.veilTag.Position = vTagPos    end
                        if not obj.veilTag.Visible then obj.veilTag.Visible = true end
                    else
                        if obj.veilTag.Visible then obj.veilTag.Visible = false end
                    end

                else
                    for i = 1, 8 do
                        if corners[i].Visible then corners[i].Visible = false end
                    end

                    if label.Text  ~= data.dName then label.Text  = data.dName  end
                    if label.Color ~= innoColor   then label.Color = innoColor   end
                    local labelPos = Vector2.new(topPos.X, topPos.Y - 18)
                    if label.Position ~= labelPos then label.Position = labelPos end
                    if not label.Visible then label.Visible = true end
                    if obj.tag     and obj.tag.Visible     then obj.tag.Visible     = false end
                    if obj.veilTag and obj.veilTag.Visible then obj.veilTag.Visible = false end
                end
            end
        end
    end

    for name, obj in pairs(ESPObjects) do
        if obj.lastFrame ~= renderFrame then
            for i = 1, 8 do
                if obj.corners[i].Visible then obj.corners[i].Visible = false end
            end
            if obj.label   and obj.label.Visible   then obj.label.Visible   = false end
            if obj.tag     and obj.tag.Visible     then obj.tag.Visible     = false end
            if obj.veilTag and obj.veilTag.Visible then obj.veilTag.Visible = false end
        end
    end
end
─
pcall(function()
    UI.AddTab("Players", function(tab)
        local info = tab:Section("Live Info", "Left")
        info:InputText("alive_txt", "Alive",  trackerData.alive, function() end)
        info:InputText("mafia_txt", "Mafia",  trackerData.mafia, function() end)
        info:InputText("veil_txt",  "Veil",   trackerData.veil,  function() end)
        info:InputText("dead_txt",  "Dead",   trackerData.dead,  function() end)
        local inno = tab:Section("Innocent", "Right")
        inno:InputText("inno_1", "Row 1", trackerData.inno1, function() end)
        inno:InputText("inno_2", "Row 2", trackerData.inno2, function() end)
        inno:InputText("inno_3", "Row 3", trackerData.inno3, function() end)
        inno:InputText("inno_4", "Row 4", trackerData.inno4, function() end)
    end)
end)

local playerAddedConn, playerRemovingConn

if Players.PlayerAdded then
    local ok, conn = pcall(function()
        return Players.PlayerAdded:Connect(function(p)
            if p and p ~= lp then totalJoined = totalJoined + 1 end
        end)
    end)
    if ok and conn then playerAddedConn = conn end
end

if Players.PlayerRemoving then
    local ok, conn = pcall(function()
        return Players.PlayerRemoving:Connect(function(p)
            if not p then return end
            local n = p.Name
            displayCache[n] = nil
            previousAlive[n] = nil
            removePlayerESP(n)
            killers[n] = nil
        end)
    end)
    if ok and conn then playerRemovingConn = conn end
end

if not playerAddedConn then
    task.spawn(function()
        local knownPlayers = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then knownPlayers[p.Name] = true end
        end
        while true do
            task.wait(2)
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and not knownPlayers[p.Name] then
                    knownPlayers[p.Name] = true
                    totalJoined = totalJoined + 1
                end
            end
        end
    end)
end

if not playerRemovingConn then
    task.spawn(function()
        local knownPlayers = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then knownPlayers[p.Name] = true end
        end
        while true do
            task.wait(2)
            local currentNames = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp then
                    currentNames[p.Name] = true
                    knownPlayers[p.Name] = true
                end
            end
            for name, _ in pairs(knownPlayers) do
                if not currentNames[name] then
                    knownPlayers[name] = nil
                    displayCache[name] = nil
                    previousAlive[name] = nil
                    removePlayerESP(name)
                    killers[name] = nil
                end
            end
        end
    end)
end

local lastWeaponCheck = 0
local lastResetCheck  = 0

task.spawn(function()
    while true do
        local now = tick()

        if now - lastWeaponCheck > 0.1 then
            lastWeaponCheck = now
            detectKiller()
        end

        if now - lastResetCheck > 1 then
            lastResetCheck = now
            for name, time in pairs(killers) do
                if now - time > KILLER_TIMEOUT then
                    killers[name] = nil
                end
            end
        end

        task.wait(0.05)
    end
end)

local lastHrp = nil
task.spawn(function()
    while true do
        task.wait(1)
        local char = lp.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and hrp ~= lastHrp then
            lastHrp = hrp
            resetKillers()
        end
    end
end)

local knownVeil = {}
task.spawn(function()
    while true do
        task.wait(2)
        local currentVeil = getVeilNames()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp then
                local dName = getDisplayName(p)
                if (currentVeil[p.Name] or currentVeil[dName]) and not knownVeil[p.Name] then
                    knownVeil[p.Name] = true
                    sendAlert(dName .. " is in the Veil!", p.Name .. "_veil")
                end
                if not (currentVeil[p.Name] or currentVeil[dName]) then
                    knownVeil[p.Name] = nil                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(5)
        local all     = Players:GetPlayers()
        local nameMap = {}
        for _, p in ipairs(all) do
            if p ~= lp then nameMap[p.Name] = p end
        end

        -- Mafia
        local ch = getMafiaChannel()
        local mafiaEntries = {}
        local mafiaSet     = {}
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

        -- Veil
        local vch = getVeilChannel()
        local veilEntries = {}
        local veilSet     = {}
        if vch then
            local ok, children = pcall(function() return vch:GetChildren() end)
            if ok and children then
                for _, c in ipairs(children) do
                    if c.ClassName == "TextSource" then
                        local p = nameMap[c.Name]
                        if p and isAlive(p) then
                            local dName = getDisplayName(p)
                            table.insert(veilEntries, dName)
                            veilSet[p] = true
                        end
                    end
                end
            end
        end

        local aliveCount  = 0
        local innoList    = {}
        local currentAlive = {}

        for _, p in ipairs(all) do
            if p == lp then continue end
            local dName = getDisplayName(p)
            if isAlive(p) then
                aliveCount = aliveCount + 1
                currentAlive[p.Name] = dName
                if not mafiaSet[p] and not veilSet[p] then
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

        trackerData.alive  = aliveCount .. " / " .. totalJoined
        trackerData.mafia  = #mafiaEntries > 0 and table.concat(mafiaEntries, ", ") or "None"
        trackerData.veil   = #veilEntries  > 0 and table.concat(veilEntries,  ", ") or "None"
        trackerData.dead   = #deadList     > 0 and table.concat(deadList,     ", ") or "None"
        trackerData.inno1  = innoChunks[1] ~= "" and innoChunks[1] or "-"
        trackerData.inno2  = innoChunks[2] ~= "" and innoChunks[2] or "-"
        trackerData.inno3  = innoChunks[3] ~= "" and innoChunks[3] or "-"
        trackerData.inno4  = innoChunks[4] ~= "" and innoChunks[4] or "-"

        pcall(function()
            UI.SetValue("alive_txt", trackerData.alive)
            UI.SetValue("mafia_txt", trackerData.mafia)
            UI.SetValue("veil_txt",  trackerData.veil)
            UI.SetValue("dead_txt",  trackerData.dead)
            UI.SetValue("inno_1",    trackerData.inno1)
            UI.SetValue("inno_2",    trackerData.inno2)
            UI.SetValue("inno_3",    trackerData.inno3)
            UI.SetValue("inno_4",    trackerData.inno4)
        end)
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

notify("Killer Tracker + Veil loaded", "Killer Tracker", 3)
