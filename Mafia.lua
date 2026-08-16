local Players = game.Players or game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local WATCH_NAMES    = {"Knife","Gun","Pistol","Revolver","Weapon","Blade","Dagger","Glock"}
local EXCLUDE_NAMES  = {"Handle","Mesh","Texture","Decal"}
local ALERT_COOLDOWN = 3
local KILLER_TIMEOUT = 85
local KILLER_COLOR   = Color3.fromRGB(255, 140, 30)
local KILLER_TAG     = "[KILLER]"
local veilColor      = Color3.fromRGB(160, 80, 230)
local VEIL_TAG       = "[VEIL]"
local POISONER_TAG   = "[POISONER]"
local mafColor       = Color3.fromRGB(220, 90, 90)
local innoColor      = Color3.fromRGB(190, 190, 200)
local VEC_TOP        = Vector3.new(0,  2.8, 0)
local VEC_BOT        = Vector3.new(0, -3.2, 0)
local sessionId         = 0
local activeConnections = {}
local renderConnection  = nil
local alertHistory  = {}
local mafiaCache    = {};  local mafiaCacheTime = 0
local veilCache     = {};  local veilCacheTime  = 0
local deadList      = {}
local previousAlive = {}
local totalJoined   = 0
local displayCache  = {}
local killers       = {}
local poisonerName  = nil
local ESPObjects    = {}
local RenderCache   = {}
local renderFrame   = 0
local trackerData   = {
    alive="0 / 0", mafia="-", veil="-", dead="-",
    inno1="-", inno2="-", inno3="-", inno4="-", poisoner="-"
}
pcall(function()
    UI.AddTab("Players", function(tab)
        local info = tab:Section("Live Info", "Left")
        info:InputText("alive_txt",    "Alive",    trackerData.alive,    function() end)
        info:InputText("mafia_txt",    "Mafia",    trackerData.mafia,    function() end)
        info:InputText("veil_txt",     "Veil",     trackerData.veil,     function() end)
        info:InputText("dead_txt",     "Dead",     trackerData.dead,     function() end)
        info:InputText("poisoner_txt", "Poisoner", trackerData.poisoner, function() end)
        local inno = tab:Section("Innocent", "Right")
        inno:InputText("inno_1", "Row 1", trackerData.inno1, function() end)
        inno:InputText("inno_2", "Row 2", trackerData.inno2, function() end)
        inno:InputText("inno_3", "Row 3", trackerData.inno3, function() end)
        inno:InputText("inno_4", "Row 4", trackerData.inno4, function() end)
    end)
end)
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
    if not ch then mafiaCache = {}; mafiaCacheTime = now; return mafiaCache end
    local lp = Players.LocalPlayer
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
    mafiaCache = names; mafiaCacheTime = now
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
    if not ch then veilCache = {}; veilCacheTime = now; return veilCache end
    local lp = Players.LocalPlayer
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
    veilCache = names; veilCacheTime = now
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
    for _, g in ipairs({"gun","pistol","revolver","glock","shoot","fire"}) do
        if low:find(g) then return true end
    end
    return false
end
local function isKnifeName(name)
    if not name then return false end
    local low = name:lower()
    for _, k in ipairs({"knife","blade","dagger"}) do
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
    pcall(function() notify(msg, "Killer Tracker", 7) end)
end
local function detectKiller()
    local lp = Players.LocalPlayer
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
                    local wt = isGunName(child.Name) and "shooting"
                            or isKnifeName(child.Name) and "knifing"
                            or "attacking"
                    sendAlert(getDisplayName(p) .. " is " .. wt .. "!", p.Name .. "_killer")
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
                    local la = animName:lower()
                    if la:find("shoot") or la:find("fire") then
                        if not killers[p.Name] then
                            killers[p.Name] = tick()
                            sendAlert(getDisplayName(p) .. " is shooting!", p.Name .. "_killer")
                        end
                    elseif la:find("knife") or la:find("stab") or la:find("slash") then
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
local function newText(text, color, size)
    local t = Drawing.new("Text")
    t.Text, t.Size, t.Outline, t.Visible = text or "", size or 14, true, true
    t.Color  = color or Color3.new(1,1,1)
    t.Center = true
    pcall(function() t.Font = Drawing.Fonts.UI end)
    return t
end
local function newLine(color)
    local l = Drawing.new("Line")
    l.Color     = color or Color3.new(1,1,1)
    l.Thickness = 2
    l.Visible   = false
    return l
end
local function removePlayerESP(playerName)
    local obj = ESPObjects[playerName]
    if obj then
        for i = 1, 8 do
            if obj.corners[i] then pcall(function() obj.corners[i]:Remove() end) end
        end
        if obj.label       then pcall(function() obj.label:Remove()       end) end
        if obj.tag         then pcall(function() obj.tag:Remove()         end) end
        if obj.veilTag     then pcall(function() obj.veilTag:Remove()     end) end
        if obj.poisonerTag then pcall(function() obj.poisonerTag:Remove() end) end
        ESPObjects[playerName] = nil
    end
    RenderCache[playerName] = nil
end
local function cleanupAllESP()
    local names = {}
    for name in pairs(ESPObjects) do table.insert(names, name) end
    for _, name in ipairs(names) do removePlayerESP(name) end
    ESPObjects  = {}
    RenderCache = {}
end
local function refreshESP()
    local lp         = Players.LocalPlayer
    local mafiaNames = getMafiaNames()
    local veilNames  = getVeilNames()
    local newCache   = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            if isAlive(p) then
                local dName      = getDisplayName(p)
                local isMafia    = mafiaNames[dName] or mafiaNames[p.Name]
                local isVeil     = veilNames[dName]  or veilNames[p.Name]
                local isPoisoner = poisonerName ~= nil and p.Name == poisonerName
                newCache[p.Name] = {
                    player     = p,
                    dName      = dName,
                    status     = isMafia and "Mafia" or "Civ",
                    isKiller   = killers[p.Name] ~= nil,
                    isVeil     = isVeil and true or false,
                    isPoisoner = isPoisoner,
                }
            else
                removePlayerESP(p.Name)
            end
        end
    end
    for name in pairs(RenderCache) do
        if not newCache[name] then removePlayerESP(name) end
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
                corners     = c,
                label       = newText("", Color3.new(1,1,1), 16),
                tag         = newText("", KILLER_COLOR, 14),
                veilTag     = newText("", veilColor,    14),
                poisonerTag = newText("", veilColor,    14),
                hrp         = nil,
                lastFrame   = 0
            }
            ESPObjects[name] = obj
        end
        if not obj.hrp or obj.hrp.Parent == nil then
            local char = data.player.Character
            obj.hrp = char and char:FindFirstChild("HumanoidRootPart")
        end
        local hrp = obj.hrp
        if hrp then
            local hrpPos         = hrp.Position
            local topPos, topVis = WorldToScreen(hrpPos + VEC_TOP)
            local botPos, botVis = WorldToScreen(hrpPos + VEC_BOT)
            if topVis and botVis and topPos and botPos then
                obj.lastFrame = renderFrame
                local isKiller   = killers[name] ~= nil
                local isVeil     = data.isVeil
                local isPoisoner = data.isPoisoner
                local color = data.status == "Mafia" and mafColor or innoColor
                if isKiller   then color = KILLER_COLOR end
                if isVeil     then color = veilColor    end
                if isPoisoner then color = veilColor    end
                local label   = obj.label
                local corners = obj.corners
                for i = 1, 8 do
                    if corners[i].Color ~= color then corners[i].Color = color end
                end
                if data.status == "Mafia" or isVeil or isPoisoner then
                    local h     = botPos.Y - topPos.Y
                    local w     = h * 0.45
                    local cs    = math.max(6, math.min(w, h) * 0.15)
                    local topX, topY = topPos.X, topPos.Y
                    local botX, botY = botPos.X, botPos.Y
                    local halfW = w / 2
                    local tl = Vector2.new(topX - halfW, topY)
                    local tr = Vector2.new(topX + halfW, topY)
                    local bl = Vector2.new(botX - halfW, botY)
                    local br = Vector2.new(botX + halfW, botY)
                    local vCs = Vector2.new(cs, 0)
                    local vCy = Vector2.new(0,  cs)
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
                    if label.Text  ~= data.dName then label.Text  = data.dName end
                    if label.Color ~= color       then label.Color = color      end
                    local labelPos = Vector2.new(topX, topY - 18)
                    if label.Position ~= labelPos then label.Position = labelPos end
                    if not label.Visible then label.Visible = true end
                    local tagPos = Vector2.new(topX + halfW + 35, topY - 18)
                    if isKiller and not isVeil and not isPoisoner then
                        if obj.tag.Text     ~= KILLER_TAG   then obj.tag.Text     = KILLER_TAG   end
                        if obj.tag.Color    ~= KILLER_COLOR then obj.tag.Color    = KILLER_COLOR end
                        if obj.tag.Position ~= tagPos       then obj.tag.Position = tagPos       end
                        if not obj.tag.Visible then obj.tag.Visible = true end
                    else
                        if obj.tag.Visible then obj.tag.Visible = false end
                    end
                    if isPoisoner then
                        if obj.poisonerTag.Text     ~= POISONER_TAG then obj.poisonerTag.Text     = POISONER_TAG end
                        if obj.poisonerTag.Color    ~= veilColor    then obj.poisonerTag.Color    = veilColor    end
                        if obj.poisonerTag.Position ~= tagPos       then obj.poisonerTag.Position = tagPos       end
                        if not obj.poisonerTag.Visible then obj.poisonerTag.Visible = true end
                        if obj.veilTag.Visible then obj.veilTag.Visible = false end
                    elseif isVeil then
                        if obj.veilTag.Text     ~= VEIL_TAG  then obj.veilTag.Text     = VEIL_TAG  end
                        if obj.veilTag.Color    ~= veilColor then obj.veilTag.Color    = veilColor end
                        if obj.veilTag.Position ~= tagPos    then obj.veilTag.Position = tagPos    end
                        if not obj.veilTag.Visible then obj.veilTag.Visible = true end
                        if obj.poisonerTag.Visible then obj.poisonerTag.Visible = false end
                    else
                        if obj.veilTag.Visible     then obj.veilTag.Visible     = false end
                        if obj.poisonerTag.Visible then obj.poisonerTag.Visible = false end
                    end
                else
                    for i = 1, 8 do
                        if corners[i].Visible then corners[i].Visible = false end
                    end
                    if label.Text  ~= data.dName then label.Text  = data.dName end
                    if label.Color ~= innoColor   then label.Color = innoColor  end
                    local labelPos = Vector2.new(topPos.X, topPos.Y - 18)
                    if label.Position ~= labelPos then label.Position = labelPos end
                    if not label.Visible then label.Visible = true end
                    if obj.tag         and obj.tag.Visible         then obj.tag.Visible         = false end
                    if obj.veilTag     and obj.veilTag.Visible     then obj.veilTag.Visible     = false end
                    if obj.poisonerTag and obj.poisonerTag.Visible then obj.poisonerTag.Visible = false end
                end
            end
        end
    end
    for name, obj in pairs(ESPObjects) do
        if obj.lastFrame ~= renderFrame then
            for i = 1, 8 do
                if obj.corners[i].Visible then obj.corners[i].Visible = false end
            end
            if obj.label       and obj.label.Visible       then obj.label.Visible       = false end
            if obj.tag         and obj.tag.Visible         then obj.tag.Visible         = false end
            if obj.veilTag     and obj.veilTag.Visible     then obj.veilTag.Visible     = false end
            if obj.poisonerTag and obj.poisonerTag.Visible then obj.poisonerTag.Visible = false end
        end
    end
end
local function stopSession()
    if renderConnection then
        pcall(function() renderConnection:Disconnect() end)
        renderConnection = nil
    end
    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}
    cleanupAllESP()
    sessionId = sessionId + 1
end
local function distanceVec(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end
local function getClosestPlayer(potionPos)
    local closest = nil
    local closestDist = math.huge
    local ok, playerList = pcall(function() return Players:GetPlayers() end)
    if not ok or not playerList then return nil, 0 end
    local lp = Players.LocalPlayer
    for _, player in ipairs(playerList) do
        if player == lp then continue end
        local ok2, dist = pcall(function()
            local char = player.Character
            if not char then return nil end
            local root = char.PrimaryPart
            if not root then return nil end
            return distanceVec(root.Position, potionPos)
        end)
        if ok2 and dist and dist < closestDist then
            closestDist = dist
            closest = player
        end
    end
    return closest, closestDist
end
local function startSession()
    local lp        = Players.LocalPlayer
    local mySession = sessionId
    alertHistory  = {}
    mafiaCache    = {};  mafiaCacheTime = 0
    veilCache     = {};  veilCacheTime  = 0
    deadList      = {}
    previousAlive = {}
    totalJoined   = 0
    displayCache  = {}
    killers       = {}
    poisonerName  = nil
    renderFrame   = 0
    trackerData.poisoner = "-"
    pcall(function() UI.SetValue("poisoner_txt", "-") end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then totalJoined = totalJoined + 1 end
    end
    local ok1, conn1 = pcall(function()
        return Players.PlayerAdded:Connect(function(p)
            if mySession ~= sessionId then return end
            if p and p ~= lp then totalJoined = totalJoined + 1 end
        end)
    end)
    if ok1 and conn1 then table.insert(activeConnections, conn1) end
    local ok2, conn2 = pcall(function()
        return Players.PlayerRemoving:Connect(function(p)
            if mySession ~= sessionId then return end
            if not p then return end
            local n = p.Name
            displayCache[n]  = nil
            previousAlive[n] = nil
            removePlayerESP(n)
            killers[n] = nil
            if poisonerName == n then
                poisonerName = nil
                trackerData.poisoner = "-"
                pcall(function() UI.SetValue("poisoner_txt", "-") end)
            end
        end)
    end)
    if ok2 and conn2 then table.insert(activeConnections, conn2) end
    local ok3, conn3 = pcall(function()
        return RunService.RenderStepped:Connect(function()
            if mySession ~= sessionId then return end
            pcall(renderESP)
        end)
    end)
    if ok3 and conn3 then renderConnection = conn3 end
    task.spawn(function()
        local lastWeaponCheck = 0
        local lastResetCheck  = 0
        while mySession == sessionId do
            local now = tick()
            if now - lastWeaponCheck > 0.1 then
                lastWeaponCheck = now
                pcall(detectKiller)
            end
            if now - lastResetCheck > 1 then
                lastResetCheck = now
                for name, t in pairs(killers) do
                    if now - t > KILLER_TIMEOUT then killers[name] = nil end
                end
            end
            task.wait(0.05)
        end
    end)
    task.spawn(function()
        local lastHrp = nil
        while mySession == sessionId do
            task.wait(1)
            local char = lp and lp.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp ~= lastHrp then
                lastHrp = hrp
                if next(killers) ~= nil then killers = {} end
            end
        end
    end)
    task.spawn(function()
        while mySession == sessionId do
            pcall(refreshESP)
            task.wait(5)
        end
    end)
    task.spawn(function()
        local poisonWasPresent = false
        while mySession == sessionId do
            pcall(function()
                local potion = Workspace:FindFirstChild("poisonPotion")
                local isPresent = potion ~= nil
                if isPresent and not poisonWasPresent then
                    local potionPos = potion.Position
                    local closest, _ = getClosestPlayer(potionPos)
                    if closest then
                        local name = getDisplayName(closest)
                        poisonerName = closest.Name
                        trackerData.poisoner = name
                        pcall(function() UI.SetValue("poisoner_txt", name) end)
                        notify("Veil - Poisoner Found", name)
                    end
                elseif not isPresent and poisonWasPresent then
                    poisonerName = nil
                    trackerData.poisoner = "-"
                    pcall(function() UI.SetValue("poisoner_txt", "-") end)
                end
                poisonWasPresent = isPresent
            end)
            wait(0.05)
        end
    end)
    task.spawn(function()
        while mySession == sessionId do
            task.wait(5)
            if mySession ~= sessionId then break end
            local all     = Players:GetPlayers()
            local nameMap = {}
            for _, p in ipairs(all) do
                if p ~= lp then nameMap[p.Name] = p end
            end
            local ch           = getMafiaChannel()
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
            local vch         = getVeilChannel()
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
            local aliveCount   = 0
            local innoList     = {}
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
                        if dead == dName then alreadyDead = true; break end
                    end
                    if not alreadyDead then table.insert(deadList, dName) end
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
end
task.spawn(function()
    local lastJobId = ""
    pcall(function() lastJobId = tostring(game.JobId) end)
    while true do
        task.wait(2)
        local ok, currentJobId = pcall(function() return tostring(game.JobId) end)
        if ok and currentJobId ~= "" and currentJobId ~= lastJobId then
            lastJobId = currentJobId
            stopSession()
            task.wait(1)
            startSession()
        end
    end
end)
startSession()
notify("Mafia + Veil", "Tracker", 3)
