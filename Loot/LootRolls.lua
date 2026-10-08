-- Titan Up - Loot/LootRolls.lua
-- The roll window (Loot settings, off by default): one window for every
-- group-loot roll instead of Blizzard's separate Need / Greed pop-ups.
--   * Each item: Need / Greed / Transmog / Pass (sent to the game exactly as
--     Blizzard's buttons do), tags (BIS, Sidegrade, 2pc, 4pc - any mix) and
--     a short note.
--   * Tags, notes and roll choices are shared with the raid's Titan Up users;
--     click an item to see everyone's, plus the game's live rolls and the
--     winner - so a Sidegrade win over someone's BIS shows while the item
--     can still be traded.
--   * Blizzard's pop-ups are hidden only while this window is showing; close
--     it (or turn the setting off) and any roll you haven't made goes back to
--     a Blizzard pop-up, so a roll can't be missed.
--
-- Messages ("TitanUpLR", guildmates in your group):
--   P item rollID tags roll note    tags: any of "BS24"; roll: 1 Need, 2 Greed,
--                                   4 Transmog, 0 Pass, "" not rolled yet
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local LR = {}
ns.LootRolls = LR

local PREFIX = "TitanUpLR"
local KEEP = 2 * 3600            -- rolls stay viewable for the 2-hour trade window
local NOTE_MAX = 40

LR.TAGS = {
    { "B", "BIS", "Best in slot for me" },
    { "S", "Sidegrade", "An upgrade, but not my best in slot" },
    { "2", "2pc", "Completes my 2-piece set bonus" },
    { "4", "4pc", "Completes my 4-piece set bonus" },
}

LR.NEED = LOOT_ROLL_TYPE_NEED or 1
LR.GREED = LOOT_ROLL_TYPE_GREED or 2
LR.TRANSMOG = LOOT_ROLL_TYPE_TRANSMOG or 4
LR.PASS = LOOT_ROLL_TYPE_PASS or 0
LR.ROLL_LABEL = { [LR.NEED] = "Need", [LR.GREED] = "Greed", [LR.TRANSMOG] = "Transmog", [LR.PASS] = "Pass", [3] = "Disenchant" }

LR.items = {}                    -- this session's rolls, in the order they started
local pending = {}               -- picks that arrived before their roll started here

local function bad(v) return v == nil or ns.IsSecret(v) end
local function db() return ns.udb.loot end
function LR:Enabled() return db().rollWindow and true or false end

local function clean(note) return (tostring(note or ""):gsub("[%^|\r\n]", ""):sub(1, NOTE_MAX)) end
local function cleanTags(s)
    local out = ""
    for _, t in ipairs(LR.TAGS) do if tostring(s or ""):find(t[1], 1, true) then out = out .. t[1] end end
    return out
end
function LR.TagText(tags)
    local parts = {}
    for _, t in ipairs(LR.TAGS) do if (tags or ""):find(t[1], 1, true) then parts[#parts + 1] = t[2] end end
    return table.concat(parts, ", ")
end

local function refresh() if LR.V.frame and LR.V.frame:IsShown() then LR.V:Refresh() end end

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
function LR:Init()
    ns.On("START_LOOT_ROLL", function(rollID, rollTime) LR:OnStart(rollID, rollTime) end)
    ns.On("CANCEL_LOOT_ROLL", function(rollID) LR:OnEnd(rollID) end)
    ns.On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, lootListID) LR:OnHistory(encounterID, lootListID) end)
    ns.Listen(PREFIX, "group", function(text, sender) LR:OnMessage(text, sender) end)
    -- Blizzard opens a pop-up per roll: hide the ones this window is showing
    if hooksecurefunc and GroupLootFrame_OpenNewFrame then
        hooksecurefunc("GroupLootFrame_OpenNewFrame", function() LR:HideBlizzard() end)
    end
end

function LR:Find(rollID)
    for _, e in ipairs(self.items) do if e.rollID == rollID then return e end end
end

-- a new loot session (a new boss) starts with a clean list; older rolls stay
-- for the trade window while the list is still in use
function LR:Prune()
    local now, newest, open = time(), 0, false
    for i = #self.items, 1, -1 do
        local e = self.items[i]
        if e.sim or now - e.t > KEEP then table.remove(self.items, i)      -- (preview items go too)
        else
            newest = math.max(newest, e.t)
            if not e.closed then open = true end
        end
    end
    if not open and now - newest > 300 then wipe(self.items) end
end

function LR:OnStart(rollID, rollTime)
    if not self:Enabled() or bad(rollID) or self:Find(rollID) then return end
    local ok, icon, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, _, _, canTransmog =
        pcall(GetLootRollItemInfo, rollID)
    if not ok or bad(name) then return end
    local link = GetLootRollItemLink and ns.Safe.Call(GetLootRollItemLink, rollID)
    if bad(link) then link = nil end
    self:Prune()
    local e = {
        rollID = rollID, t = time(), link = link, name = name, icon = ns.Safe.Num(icon) or ns.Safe.Text(icon),
        item = ns.Loot.ItemID(link), quality = ns.Safe.Num(quality), count = ns.Safe.Num(count),
        ilvl = link and ns.Loot.ItemLevel(link), bop = bop and not bad(bop),
        canNeed = canNeed and not bad(canNeed), canGreed = canGreed and not bad(canGreed),
        canTransmog = canTransmog and not bad(canTransmog), canDE = canDE and not bad(canDE),
        reasonNeed = ns.Safe.Num(reasonNeed), reasonGreed = ns.Safe.Num(reasonGreed),
        expires = GetTime() + (ns.Safe.Num(rollTime) or 60000) / 1000,
        total = math.max(1, (ns.Safe.Num(rollTime) or 60000) / 1000),      -- the roll's full length (the time bar)
        tags = "", note = "", picks = {}, rolls = {},
    }
    self.items[#self.items + 1] = e
    -- picks raiders sent before this client saw the roll
    for i = #pending, 1, -1 do
        local p = pending[i]
        if GetTime() - p.at > 120 then table.remove(pending, i)
        elseif p.item == e.item then e.picks[p.sender] = p.pick; table.remove(pending, i) end
    end
    self.V:Open()
    self:HideBlizzard()
    if C_Timer then C_Timer.After(0, function() LR:HideBlizzard() end) end
end

function LR:OnEnd(rollID)
    local e = not bad(rollID) and self:Find(rollID)
    if not e then return end
    e.closed = true
    refresh()
end

-- ---------------------------------------------------------------------
-- Blizzard's pop-ups: hidden while this window shows the roll
-- ---------------------------------------------------------------------
function LR:HideBlizzard()
    if not (self.V.frame and self.V.frame:IsShown()) then return end
    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local f = _G["GroupLootFrame" .. i]
        local e = f and f:IsShown() and f.rollID and self:Find(f.rollID)
        if e and (not e.handedBack or e.rolled) then f:Hide() end
    end
end

-- give the rolls you haven't made back to Blizzard's pop-ups
function LR:HandBack()
    for _, e in ipairs(self.items) do
        if not e.sim and not e.rolled and not e.closed and not e.handedBack and GroupLootFrame_OpenNewFrame then
            local left = ns.Safe.Call(GetLootRollTimeLeft, e.rollID)
            if left and left > 0 then
                e.handedBack = true
                pcall(GroupLootFrame_OpenNewFrame, e.rollID, left)
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Your choices
-- ---------------------------------------------------------------------
function LR:Roll(e, kind)
    if e.rolled or e.closed then return end
    if not e.sim then
        local ok = pcall(RollOnLoot, e.rollID, kind)
        if not ok then return ns.Print("That roll didn't go through - use Blizzard's roll pop-up for this item.") end
    end
    e.rolled = kind
    self:HideBlizzard()
    self:Share(e)
    refresh()
end

function LR:ToggleTag(e, code)
    if e.tags:find(code, 1, true) then e.tags = e.tags:gsub(code, "") else e.tags = cleanTags(e.tags .. code) end
    self:Share(e)
    refresh()
end

function LR:SetNote(e, text)
    text = clean(text)
    if text == e.note then return end
    e.note = text
    self:Share(e)
end

-- Picks go out a moment after the last change (typing a note sends once).
function LR:Share(e)
    if e.sim then return end
    e.dirty = true
    if self.sending then return end
    self.sending = true
    C_Timer.After(1, function() LR:Flush() end)
end

function LR:Flush()
    self.sending = nil
    if ns.InLockdown() then self.sending = true; return C_Timer.After(2, function() LR:Flush() end) end
    for _, e in ipairs(self.items) do
        if e.dirty then
            e.dirty = nil
            ns.SendFields(PREFIX, "P", e.item or 0, e.rollID, e.tags, e.rolled or "", e.note)
        end
    end
end

-- ---------------------------------------------------------------------
-- Everyone else's
-- ---------------------------------------------------------------------
function LR:OnMessage(text, sender)
    if not self:Enabled() then return end
    local f = ns.Split(text, "^")
    if f[1] ~= "P" then return end
    local item, rollID = tonumber(f[2]), tonumber(f[3])
    if not item or item == 0 then return end
    local pick = { tags = cleanTags(f[4]), roll = tonumber(f[5]), note = clean(f[6]) }
    -- the same roll here (roll ids normally match), else the newest roll of that item
    local found
    for _, e in ipairs(self.items) do
        if e.item == item and (not found or e.rollID == rollID) then found = e end
        if found and found.rollID == rollID then break end
    end
    if found then
        found.picks[sender] = pick
        refresh()
    else
        pending[#pending + 1] = { item = item, sender = sender, pick = pick, at = GetTime() }
        while #pending > 200 do table.remove(pending, 1) end
    end
end

-- The game's loot history: everyone's live roll choices, then the winner.
function LR:OnHistory(encounterID, lootListID)
    if not self:Enabled() or #self.items == 0 then return end
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) or bad(encounterID) or bad(lootListID) then return end
    local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
    if not ok or type(drop) ~= "table" or bad(drop.itemHyperlink) then return end
    local item, key = ns.Loot.ItemID(drop.itemHyperlink), encounterID .. "-" .. lootListID
    local e
    for _, x in ipairs(self.items) do if x.listKey == key then e = x break end end
    if not e then
        for _, x in ipairs(self.items) do
            if not x.listKey and x.item == item then e = x break end
        end
        if not e then return end
        e.listKey = key
    end
    for _, r in ipairs(drop.rollInfos or {}) do
        if not bad(r.playerName) then
            e.rolls[ns.NormalizeSender(r.playerName)] = { s = ns.Safe.Num(r.state), r = ns.Safe.Num(r.roll), c = ns.Safe.Text(r.playerClass) }
        end
    end
    local w = drop.winner
    if w and not bad(w.playerName) then
        e.winner, e.wstate, e.wroll = ns.NormalizeSender(w.playerName), ns.Safe.Num(w.state), ns.Safe.Num(w.roll)
        e.closed = true
    end
    if drop.allPassed and not bad(drop.allPassed) then e.allPassed, e.closed = true, true end
    refresh()
end

-- ---------------------------------------------------------------------
-- What the window shows for one item
-- ---------------------------------------------------------------------
local NO_ROLL = 4                 -- loot history: hasn't chosen yet

-- one line per raider: you, Titan Up picks, and the game's rolls
function LR:Raiders(e)
    local by, list = {}, {}
    local function get(name)
        if not by[name] then by[name] = { name = name }; list[#list + 1] = by[name] end
        return by[name]
    end
    local me = get(ns.me)
    me.tags, me.note, me.roll, me.titan = e.tags, e.note, e.rolled, true
    for name, p in pairs(e.picks) do
        local x = get(name)
        x.tags, x.note, x.roll, x.titan = p.tags, p.note, p.roll, true
    end
    for name, r in pairs(e.rolls) do
        local x = get(name)
        x.class = r.c
        if r.s and r.s ~= NO_ROLL then x.state, x.num = r.s, r.r end
    end
    for _, x in ipairs(list) do
        x.won = e.winner == x.name
        local text
        if x.state then
            text = (ns.Loot.ROLL_NAMES[x.state] or "?") .. (x.num and ("  " .. x.num) or "")
        elseif x.roll then
            text = LR.ROLL_LABEL[x.roll] or "?"
        else
            text = e.closed and "-" or "deciding..."
        end
        x.rollText = text
    end
    table.sort(list, function(a, b)
        if a.won ~= b.won then return a.won end
        if (a.num or -1) ~= (b.num or -1) then return (a.num or -1) > (b.num or -1) end
        if ((a.tags or "") ~= "") ~= ((b.tags or "") ~= "") then return (a.tags or "") ~= "" end
        return a.name < b.name
    end)
    return list
end

-- "Kev tagged it BIS, but Mossy won it as a Sidegrade - a trade could help."
function LR:TradeHint(e)
    if not e.winner then return nil end
    local list = self:Raiders(e)
    local winner
    for _, x in ipairs(list) do if x.won then winner = x end end
    local wTags = winner and winner.tags or ""
    if wTags:find("B", 1, true) then return nil end
    local want = {}
    for _, x in ipairs(list) do
        if not x.won and (x.tags or ""):find("B", 1, true) then want[#want + 1] = UI.Named(x.name) end
    end
    if #want == 0 then return nil end
    local how = (wTags ~= "" and (" as " .. LR.TagText(wTags))) or (winner and winner.titan and " (no tags)") or ""
    return ("%s tagged it BIS, but %s won it%s - a trade could help (2 hours to trade)."):format(table.concat(want, ", "), UI.Named(e.winner), how)
end

-- ---------------------------------------------------------------------
-- Preview (Loot settings): sample items and raiders, nothing is sent or rolled
-- ---------------------------------------------------------------------
local SAMPLE = {
    { "Crown of the Fallen Titan", "Interface\\Icons\\INV_Helmet_03", 681, true },
    { "Signet of Endless Night", "Interface\\Icons\\INV_Jewelry_Ring_03", 678 },
    { "Cloak of Shattered Stars", "Interface\\Icons\\INV_Misc_Cape_18", 678 },
    { "Void-Touched Curio", "Interface\\Icons\\INV_Misc_Gem_Variety_01", 684 },
}
local SAMPLE_PICKS = {
    { { "Kev-Medivh", "B4", 1, "4pc for me" }, { "Mossy-Medivh", "S", 1, "" }, { "Brakk-Medivh", "", 2, "" } },
    { { "Brakk-Medivh", "B", 1, "huge for tanking" }, { "Selune-Medivh", "S", 1, "" } },
    { { "Kev-Medivh", "", 4, "" }, { "Selune-Medivh", "S", 2, "" } },
    { { "Mossy-Medivh", "2", 1, "my 2pc" }, { "Selune-Medivh", "B4", 1, "" } },
}
local PREVIEW_SECONDS = 45
local SAMPLE_WINS = { { "Mossy-Medivh", 0, 91 }, { "Brakk-Medivh", 0, 77 }, { "Selune-Medivh", 3, 64 }, { "Selune-Medivh", 0, 88 } }

function LR:Preview()
    wipe(self.items)
    self.previewId = (self.previewId or 0) + 1
    local id = self.previewId
    for i, s in ipairs(SAMPLE) do
        local e = { rollID = -i, sim = true, t = time(), name = s[1], link = "|cffa335ee[" .. s[1] .. "]|r", icon = s[2], ilvl = s[3],
                    bop = s[4], item = -i, canNeed = true, canGreed = true, canTransmog = i ~= 4,
                    expires = GetTime() + PREVIEW_SECONDS, total = PREVIEW_SECONDS, tags = "", note = "", picks = {}, rolls = {} }
        for _, p in ipairs(SAMPLE_PICKS[i]) do e.picks[p[1]] = { tags = p[2], roll = p[3], note = p[4] } end
        self.items[#self.items + 1] = e
    end
    self.V:Open()
    ns.Print("Roll window preview: sample items and raiders - nothing is rolled or sent. The rolls finish in " .. PREVIEW_SECONDS .. " seconds.")
    C_Timer.After(PREVIEW_SECONDS, function()
        if self.previewId ~= id then return end
        for i, e in ipairs(self.items) do
            if e.sim then
                for name, p in pairs(e.picks) do e.rolls[name] = { s = p.roll == 1 and 0 or p.roll == 2 and 3 or 2, r = 20 + (#name * 7 + i * 13) % 60 } end
                if e.rolled and e.rolled ~= LR.PASS then e.rolls[ns.me] = { s = e.rolled == 1 and 0 or e.rolled == 2 and 3 or 2, r = 50 } end
                local w = SAMPLE_WINS[i]
                e.winner, e.wstate, e.wroll = w[1], w[2], w[3]
                e.rolls[w[1]] = { s = w[2], r = w[3] }
                e.closed = true
            end
        end
        refresh()
    end)
end

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------
local V = {}
LR.V = V

local W, ROWS, ROW_H = 880, 6, 58
local LIST_W = 576
local LIST_H = ROWS * ROW_H + 8
local H = 48 + LIST_H + 12
local RAIDER_H, RAIDER_ROWS = 30, 8

function V:Open()
    self:Create()
    for _, e in ipairs(LR.items) do if not e.rolled then e.handedBack = nil end end
    if not self.frame:IsShown() then self.frame:Show() end
    if not self.sel or not tContains(LR.items, self.sel) then self.sel = LR.items[#LR.items] end
    self:Refresh()
    LR:HideBlizzard()
end

function V:Hide() if self.frame then self.frame:Hide() end end

local function rollButton(row, label, kind, x, y)
    local b = UI.Button(row, 64, 20, label, nil, function(s) if s.entry and not s.disabled then LR:Roll(s.entry, kind) end end)
    b:SetPoint("TOPRIGHT", x, y)
    return b
end

function V:Create()
    if self.frame then return end
    local f = UI.Window("TitanUpLootRolls", W, H, { border = C.accent })
    self.frame = f
    UI.Draggable(f, db, { "CENTER", "CENTER", 0, 120 })
    f:Place()
    UI.Text(f, "GameFontNormal", C.accent, "LOOT ROLLS", "TOPLEFT", 14, -14)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Tag each item for the raid, then roll.  Click an item to see what everyone chose.", "LEFT", f, "TOPLEFT", 110, -21)
    local x = UI.Button(f, 22, 20, "X", "Close (rolls you haven't made go back to Blizzard's pop-ups)", function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -8, -8)
    f:SetScript("OnShow", function()
        if V.ticker then V.ticker:Cancel() end
        V.ticker = C_Timer.NewTicker(0.5, function() V:Refresh() end)
        if ns.BonusRollGuard then ns.BonusRollGuard:Dock() end      -- a bonus roll showing moves in
    end)
    f:SetScript("OnHide", function()
        if V.ticker then V.ticker:Cancel(); V.ticker = nil end
        LR:HandBack()
        if ns.BonusRollGuard then ns.BonusRollGuard:Undock() end
    end)

    -- left: the items
    local list = UI.Panel(f)
    list:SetPoint("TOPLEFT", 12, -40)
    list:SetSize(LIST_W, LIST_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) V.offset = (V.offset or 0) - d; V:Refresh() end)
    self.empty = UI.Text(list, "GameFontHighlightSmall", C.muted, "No loot rolls right now.", "CENTER")
    self.rows = {}
    for i = 1, ROWS do
        local row = UI.Row(list, ROW_H - 2, 0.04, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.45 }, "GameFontHighlight", true)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(s) if s.entry then V.sel = s.entry; V:Refresh() end end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(40, 40)
        row.icon:SetPoint("TOPLEFT", 4, -7)
        local hot = CreateFrame("Frame", nil, row)      -- the item's tooltip
        hot:SetAllPoints(row.icon)
        hot:EnableMouse(true)
        hot:SetScript("OnEnter", function() V:ItemTip(hot, row.entry) end)
        hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hot:SetScript("OnMouseUp", function() if row.entry then V.sel = row.entry; V:Refresh() end end)
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
        row.text:SetWidth(300)
        row.info = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", row.icon, "TOPRIGHT", 8, -15)
        row.info:SetWidth(330)
        row.info:SetJustifyH("LEFT")
        row.info:SetWordWrap(false)
        -- tags + note
        row.tags = {}
        local tx = 52
        for _, t in ipairs(LR.TAGS) do
            local w = t[1] == "S" and 70 or 40
            local b = UI.Button(row, w, 18, t[2], t[3], function() if row.entry then LR:ToggleTag(row.entry, t[1]) end end)
            b:SetPoint("BOTTOMLEFT", tx, 5)
            row.tags[t[1]] = b
            tx = tx + w + 4
        end
        local note = UI.EditBox(row, 156, 18, { inset = 5, max = NOTE_MAX })
        note:SetPoint("BOTTOMLEFT", tx + 2, 5)
        note:SetFontObject("GameFontHighlightSmall")
        note.hint = UI.Text(note, "GameFontHighlightSmall", C.muted, "add a note...", "LEFT", 6, 0)
        note:SetScript("OnTextChanged", function(s, user)
            s.hint:SetShown(s:GetText() == "" and not s:HasFocus())
            if user and row.entry then LR:SetNote(row.entry, s:GetText()) end
        end)
        note:SetScript("OnEditFocusGained", function(s) s.hint:Hide() end)
        note:SetScript("OnEditFocusLost", function(s) s.hint:SetShown(s:GetText() == "") end)
        row.note = note
        -- rolls
        row.need = rollButton(row, "Need", LR.NEED, -72, -6)
        row.greed = rollButton(row, "Greed", LR.GREED, -4, -6)
        row.tmog = rollButton(row, "Transmog", LR.TRANSMOG, -72, -30)
        row.pass = rollButton(row, "Pass", LR.PASS, -4, -30)
        row.result = UI.Text(row, "GameFontHighlightSmall", C.text, nil, "TOPRIGHT", -8, -10)
        row.result:SetWidth(128)
        row.result:SetJustifyH("RIGHT")
        -- time left
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        row.bar:SetPoint("BOTTOMLEFT", 0, 0)
        row.bar:SetHeight(2)
        self.rows[i] = row
    end

    -- right: one item in detail
    local d = UI.Panel(f)
    d:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    d:SetPoint("BOTTOMRIGHT", -12, 12)
    d:EnableMouseWheel(true)
    d:SetScript("OnMouseWheel", function(_, dd) V.dOffset = (V.dOffset or 0) - dd; V:Refresh() end)
    self.detail = d
    local dw = W - LIST_W - 44
    local title = CreateFrame("Frame", nil, d)
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetSize(dw - 16, 16)
    title:EnableMouse(true)
    title:SetScript("OnEnter", function() V:ItemTip(title, V.sel) end)
    title:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.dTitle = UI.Text(title, "GameFontNormal", C.text, nil, "LEFT")
    self.dTitle:SetWidth(dw - 16)
    self.dTitle:SetJustifyH("LEFT")
    self.dTitle:SetWordWrap(false)
    self.dWinner = UI.Text(d, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 8, -28)
    self.dWinner:SetWidth(dw - 16)
    self.dWinner:SetJustifyH("LEFT")
    self.dHint = UI.Text(d, "GameFontHighlightSmall", C.warn, nil, "TOPLEFT", self.dWinner, "BOTTOMLEFT", 0, -4)
    self.dHint:SetWidth(dw - 16)
    self.dHint:SetJustifyH("LEFT")
    self.dRows = {}
    for i = 1, RAIDER_ROWS do
        local r = CreateFrame("Frame", nil, d)
        r:SetSize(dw - 12, RAIDER_H)
        r.name = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 4, -2)
        r.roll = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "TOPRIGHT", -4, -2)
        r.sub = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 14, -15)
        r.sub:SetWidth(dw - 34)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)
        self.dRows[i] = r
    end
    self.dEmpty = UI.Text(d, "GameFontHighlightSmall", C.muted, nil, "TOP", 0, -80)
end

function V:ItemTip(owner, e)
    if not e then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if not e.sim and GameTooltip.SetLootRollItem and not e.closed then shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, e.rollID) end
    if not shown and e.link and not e.sim then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, e.link) end
    if not shown then
        GameTooltip:SetText(e.name or "?", 1, 1, 1)
        if e.sim then GameTooltip:AddLine("Preview item", 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local REASON = { [1] = "Your class can't use it", [2] = "You already have the most you can carry", [3] = "Needs a higher level" }

local function status(e)
    if e.winner then
        local how = ns.Loot.ROLL_NAMES[e.wstate] or "won"
        return "|cff66e08cWon by|r " .. UI.Named(e.winner) .. "  |cffffd94d" .. how .. (e.wroll and (" " .. e.wroll) or "") .. "|r"
    end
    if e.allPassed then return "Everyone passed" end
    if e.rolled then return "You: |cffffd94d" .. (LR.ROLL_LABEL[e.rolled] or "?") .. "|r" .. (e.closed and "" or "  - waiting for the raid") end
    if e.closed then return "|cff8a8f9cRolls finished|r" end
    return nil
end

function V:Refresh()
    if not self.frame then return end
    local items, rows = LR.items, self.rows
    self.offset = math.max(0, math.min(math.max(0, #items - ROWS), self.offset or 0))
    self.empty:SetShown(#items == 0)
    local now = GetTime()
    for i, row in ipairs(rows) do
        local e = items[i + self.offset]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            row.icon:SetTexture(e.icon or 134400)
            row.text:SetText((e.link or e.name or "?") .. (e.count and e.count > 1 and (" x" .. e.count) or ""))
            local others = 0
            for _, p in pairs(e.picks) do if p.tags ~= "" or p.note ~= "" then others = others + 1 end end
            local bits = {}
            if e.ilvl then bits[#bits + 1] = "item level " .. e.ilvl end
            if e.bop then bits[#bits + 1] = "binds on pickup" end
            if others > 0 then bits[#bits + 1] = "|cff4fc3f7" .. others .. (others == 1 and " raider tagged it|r" or " raiders tagged it|r") end
            row.info:SetText(table.concat(bits, "  -  "))
            row.hl:SetShown(self.sel == e)
            for code, b in pairs(row.tags) do UI.SetActive(b, e.tags:find(code, 1, true) ~= nil) end
            if not row.note:HasFocus() and row.note:GetText() ~= e.note then row.note:SetText(e.note) end
            row.note.hint:SetShown(e.note == "" and not row.note:HasFocus())
            local done = status(e)
            local open = not e.rolled and not e.closed
            for _, def in ipairs({ { row.need, e.canNeed, REASON[e.reasonNeed] or "You can't Need this" },
                                   { row.greed, e.canGreed, REASON[e.reasonGreed] or "You can't Greed this" },
                                   { row.tmog, e.canTransmog, "Not a transmog appearance you can collect" },
                                   { row.pass, true } }) do
                local b = def[1]
                b.entry = e
                b:SetShown(open)
                UI.SetDisabled(b, not def[2])
                b.tip = not def[2] and def[3] or nil
            end
            local left = e.expires - now
            if open then
                row.result:SetText("")
                row.bar:SetShown(left > 0)
                row.bar:SetWidth(math.max(1, (LIST_W - 8) * math.min(1, left / (e.total or 60))))
                if left > 0 then row.info:SetText(row.info:GetText() .. (row.info:GetText() ~= "" and "  -  " or "") .. UI.Clock(left) .. " left") end
            else
                row.result:SetText(done or "")
                row.bar:Hide()
            end
        end
    end
    self:RefreshDetail()
end

function V:RefreshDetail()
    local e = self.sel
    if e and not tContains(LR.items, e) then e = nil; self.sel = nil end
    for _, r in ipairs(self.dRows) do r:Hide() end
    if not e then
        self.dTitle:SetText("")
        self.dWinner:SetText("")
        self.dHint:SetText("")
        self.dEmpty:SetText("Click an item to see what the raid chose.")
        return
    end
    self.dEmpty:SetText("")
    self.dTitle:SetText(e.link or e.name or "?")
    self.dWinner:SetText(status(e) or ("|cff8a8f9cRolling - " .. UI.Clock(math.max(0, e.expires - GetTime())) .. " left|r"))
    self.dHint:SetText(LR:TradeHint(e) or "")
    local list = LR:Raiders(e)
    self.dOffset = math.max(0, math.min(math.max(0, #list - RAIDER_ROWS), self.dOffset or 0))
    local top = -46 - ((self.dHint:GetText() or "") ~= "" and 40 or 0)
    for i, r in ipairs(self.dRows) do
        local x = list[i + self.dOffset]
        if x then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 6, top - (i - 1) * RAIDER_H)
            if top - i * RAIDER_H < -(LIST_H - 4) then break end
            r:Show()
            r.name:SetText((x.won and "|cff66e08c>|r " or "") .. UI.ClassName(x.name, x.class or ns.ClassOf(x.name)) .. (x.name == ns.me and " |cff8a8f9c(you)|r" or ""))
            r.roll:SetText((x.won and "|cff66e08c" or "|cffffd94d") .. x.rollText .. "|r")
            local sub = LR.TagText(x.tags)
            if (x.note or "") ~= "" then sub = sub .. (sub ~= "" and "  -  " or "") .. "\"" .. x.note .. "\"" end
            if sub == "" then sub = x.titan and "no tags" or "|cff5a5f6ano Titan Up tags|r" end
            r.sub:SetText(sub)
        end
    end
end
