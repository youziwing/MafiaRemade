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

        local aliveCount = 0
        local innoList = {}

        for _, p in ipairs(all) do
            if p == lp then continue end
            local n = p.Name
            local dName = getDisplayName(p)

            if isAlive(p) then
                aliveCount = aliveCount + 1
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