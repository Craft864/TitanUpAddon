-- Titan Up - Loot/LootUI.lua
-- The Loot window: filters + search on top, raid nights / runs on the left,
-- drops on the right (item, boss, winner + roll, trade/equip history).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local LT

local V = {}
ns.LootUI = V

local W, H = 900, 570
local LEFT_W = 250
local ROW_H = 38

local colored = UI.Named

local function rollText(r)
    if r.kind ~= "raid" then return "received" end
    local name = LT.ROLL_NAMES[r.wstate] or "won"
    return r.wroll and (name .. " " .. r.wroll) or name
end

-- "-> Kev -> Selune  equipped" / "unequipped" ...
local function statusText(r)
    local parts = {}
    for _, step in ipairs(r.chain or {}) do parts[#parts + 1] = "> " .. colored(step.to) end
    local s = table.concat(parts, " ")
    if r.equipped then
        s = s .. (s ~= "" and "  " or "") .. "|cff66e08cequipped|r"
    elseif #parts == 0 then
        s = "|cff8a8f9cnot equipped yet|r"
    end
    return s
end

function V:Init() LT = ns.Loot end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpLoot", "loot", "LOOT TRACKER", W, H, { y = 20, mark = { 480, 0.04, -40 },
        cog = { "Loot settings", function() ns.Settings:Open("loot", V.frame) end },
        onShow = function()
            -- pick up anything the loot history has that we haven't seen
            if C_LootHistory and C_LootHistory.GetAllEncounterInfos then
                local ok, list = pcall(C_LootHistory.GetAllEncounterInfos)
                if ok and type(list) == "table" then
                    for _, e in ipairs(list) do LT:SweepEncounter(e.encounterID) end
                end
            end
            V:Refresh()
        end })

    -- filters
    self.filter = "all"
    self.filterBtns = {}
    local x = 12
    for _, def in ipairs({ { "all", "All" }, { "raid", "Raid" }, { "mplus", "Mythic+" } }) do
        local key = def[1]
        local b = UI.Button(f, 74, 24, def[2], nil, function() V.filter = key; V.session = nil; V:Refresh() end)
        b:SetPoint("TOPLEFT", x, -10)
        self.filterBtns[key] = b
        x = x + 78
    end
    local search = UI.EditBox(f, 380, 24, { inset = 8 })
    search:SetPoint("TOPLEFT", x + 10, -10)
    search:SetScript("OnTextChanged", function() V.session = nil; V:Refresh() end)
    self.search = search
    UI.Text(f, "GameFontHighlightSmall", C.muted, "search player, item or boss", "LEFT", search, "RIGHT", 8, 0)

    -- left: sessions
    local left = UI.Panel(f)
    left:SetPoint("TOPLEFT", 12, -42)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(LEFT_W)
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", function(_, d) V.sessOffset = (V.sessOffset or 0) - d * 3; V:Refresh() end)
    self.sessRows = {}
    for i = 1, math.floor((H - 62) / 22) do
        local row = UI.Row(left, 22, 0.05, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.6 })
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
        row:SetPoint("RIGHT", -4, 0)
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -30, 0)
        row.count = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "RIGHT", -6, 0)
        row:SetScript("OnClick", function(s) if s.session ~= nil then V.session = s.session; V.dropOffset = 0; V:Refresh() end end)
        self.sessRows[i] = row
    end

    -- right: drops
    local right = UI.Panel(f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 12)
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, d) V.dropOffset = (V.dropOffset or 0) - d * 2; V:Refresh() end)
    self.title = UI.Text(right, "GameFontNormal", C.accent, nil, "TOPLEFT", 10, -8)
    self.empty = UI.Text(right, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -34)
    self.empty:SetWidth(W - LEFT_W - 60)
    self.empty:SetJustifyH("LEFT")
    self.empty:SetText("No loot recorded yet. Raid drops are recorded automatically when rolls finish; Mythic+ loot when the chest is opened.")
    self.dropRows = {}
    for i = 1, math.floor((H - 90) / ROW_H) do
        local row = CreateFrame("Frame", nil, right)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 6, -28 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -6, 0)
        row:EnableMouse(true)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.04)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", 2, 0)
        row.item = UI.Text(row, "GameFontHighlight", nil, nil, "TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
        row.item:SetWidth(300)
        row.item:SetJustifyH("LEFT")
        row.item:SetWordWrap(false)
        row.sub = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
        row.sub:SetWidth(300)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.status = UI.Text(row, "GameFontHighlightSmall", nil, nil, "RIGHT", -6, 0)
        row.status:SetWidth(250)
        row.status:SetJustifyH("RIGHT")
        row.status:SetWordWrap(false)
        row:SetScript("OnEnter", function(s) V:Tooltip(s) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.dropRows[i] = row
    end
end

function V:Tooltip(row)
    local r = row.drop
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if r.link then GameTooltip:SetHyperlink(r.link) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine((r.boss or r.inst or "") .. (r.diff and ("  (" .. r.diff .. ")") or "") .. "  -  " .. date("%a %b %d %H:%M", r.t or 0), 0.8, 0.82, 0.86)
    if r.kind == "raid" then
        GameTooltip:AddLine("Rolls:", 1, 0.85, 0.3)
        local rolls = {}
        for _, x in ipairs(r.rolls or {}) do rolls[#rolls + 1] = x end
        table.sort(rolls, function(a, b) return (a.r or -1) > (b.r or -1) end)
        for i, x in ipairs(rolls) do
            if i > 12 then break end
            local name = LT.ROLL_NAMES[x.s] or "?"
            GameTooltip:AddDoubleLine(ns.Short(x.n) .. (x.n == r.winner and "  (won)" or ""), name .. (x.r and ("  " .. x.r) or ""), 0.9, 0.9, 0.9, 0.7, 0.7, 0.7)
        end
    else
        GameTooltip:AddLine("Personal loot - " .. ns.Short(r.winner) .. " received it (no roll).", 0.8, 0.82, 0.86, true)
    end
    GameTooltip:AddLine("History:", 1, 0.85, 0.3)
    GameTooltip:AddLine(date("%H:%M", r.t or 0) .. "  " .. ns.Short(r.winner) .. (r.kind == "raid" and " won it" or " received it"), 0.9, 0.9, 0.9)
    for _, s in ipairs(r.chain or {}) do
        GameTooltip:AddLine(date("%H:%M", s.t or 0) .. "  traded " .. ns.Short(s.f) .. " > " .. ns.Short(s.to), 0.9, 0.9, 0.9)
    end
    if r.equipped then
        GameTooltip:AddLine(date("%H:%M", r.equipped.t or 0) .. "  equipped by " .. ns.Short(r.equipped.by), 0.4, 0.9, 0.55)
    else
        GameTooltip:AddLine("Not equipped yet (or the owner doesn't have Titan Up).", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

function V:Refresh()
    if not self.frame then return end
    for key, b in pairs(self.filterBtns) do UI.SetActive(b, key == self.filter) end

    local drops = LT:Drops(self.filter, self.search:GetText())
    local sessions = LT:Sessions(drops)
    -- left list: "All" + sessions grouped under date headers
    local entries = { { all = true, text = "All drops", count = #drops } }
    local lastDate
    for _, s in ipairs(sessions) do
        if s.date ~= lastDate then
            entries[#entries + 1] = { header = true, text = s.label }
            lastDate = s.date
        end
        local tag = (s.kind == "mplus" and "M+ " or s.kind == "dungeon" and "Dungeon: " or "")
        entries[#entries + 1] = { session = s, text = tag .. s.where .. (s.diff and s.kind == "raid" and (" (" .. s.diff .. ")") or ""), count = #s.drops }
    end
    local rows = self.sessRows
    self.sessOffset = math.max(0, math.min(math.max(0, #entries - #rows), self.sessOffset or 0))
    for i, row in ipairs(rows) do
        local e = entries[i + self.sessOffset]
        row:SetShown(e ~= nil)
        if e then
            -- nil = header (not clickable), false = "All drops", otherwise a session key
            if e.header then
                row.session = nil
            elseif e.all then
                row.session = false
            else
                row.session = e.session.key
            end
            local selected = (e.all and not self.session) or (e.session and self.session == e.session.key)
            row.hl:SetShown(selected and true or false)
            if e.header then
                row.text:SetText("|cff4fc3f7" .. e.text:upper() .. "|r")
                row.count:SetText("")
            else
                row.text:SetText((e.all and "" or "  ") .. e.text)
                row.count:SetText(e.count)
            end
        end
    end

    -- right list
    local shown, title = drops, "All drops"
    if self.session then
        for _, s in ipairs(sessions) do
            if s.key == self.session then shown, title = s.drops, s.label .. "  -  " .. s.where end
        end
    end
    self.title:SetText(title .. "  |cff8a8f9c(" .. #shown .. ")|r")
    self.empty:SetShown(#shown == 0)
    local drows = self.dropRows
    self.dropOffset = math.max(0, math.min(math.max(0, #shown - #drows), self.dropOffset or 0))
    for i, row in ipairs(drows) do
        local r = shown[i + self.dropOffset]
        row.drop = r
        row:SetShown(r ~= nil)
        if r then
            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.item)) or (GetItemIcon and GetItemIcon(r.item))
            row.icon:SetTexture(icon or 134400)
            row.item:SetText((r.link or "?") .. (r.ilvl and ("  |cff8a8f9c" .. r.ilvl .. "|r") or ""))
            row.sub:SetText(((r.boss or r.inst or "") .. "  -  " .. colored(r.winner) .. "  |cffffd94d" .. rollText(r) .. "|r"))
            row.status:SetText(statusText(r))
        end
    end
end

ns.RegisterModule({
    key = "loot", name = "Loot", icon = ns.MEDIA .. "Loot", group = "tools", order = 2,
    desc = "Raid drops and rolls, Mythic+ loot, trades until equipped.",
    view = V,
})
