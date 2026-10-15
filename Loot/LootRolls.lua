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
--   * Need / Greed on a bind-on-pickup item: the game asks first ("will
--     bind"); the roll only counts once that's accepted, so until then the
--     item says so and stays open (the raid sees the roll only once it's made).
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

local NO_ROLL = 4                 -- loot history: hasn't chosen yet
local PASSED = 5                  -- loot history: passed

LR.items = {}                    -- this session's rolls, in the order they started
local pending = {}               -- picks that arrived before their roll started here

local Num, Text, Bool = ns.Safe.Num, ns.Safe.Text, ns.Safe.Bool
local function db() return ns.udb.loot end
function LR:Enabled() return db().rollWindow and true or false end

local function clean(note) return ns.CleanField(note, NOTE_MAX) end
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
    -- a roll that needs the "will bind" confirmation, and that confirmation
    ns.On("CONFIRM_LOOT_ROLL", function(rollID, rollType) LR:OnConfirmAsked(rollID, rollType) end)
    if hooksecurefunc and ConfirmLootRoll then
        hooksecurefunc("ConfirmLootRoll", function(rollID, rollType) LR:OnConfirmed(rollID, rollType) end)
    end
    ns.On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, lootListID) LR:OnHistory(encounterID, lootListID) end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        LR:FreeSlots()
        if LR.handBackLater then
            LR.handBackLater = nil
            if not (LR.V.frame and LR.V.frame:IsShown()) then LR:HandBack() end
        end
    end)
    ns.Listen(PREFIX, "group", function(text, sender) LR:OnMessage(text, sender) end)
    -- Blizzard opens a pop-up per roll: hide the ones this window is showing
    -- (GroupLootContainer_OpenNewFrame since 10.1.5; the old name as fallback)
    if hooksecurefunc then
        for _, fn in ipairs({ "GroupLootContainer_OpenNewFrame", "GroupLootFrame_OpenNewFrame" }) do
            if _G[fn] then hooksecurefunc(fn, function() LR:HideBlizzard() end) break end
        end
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
    if not self:Enabled() or not Num(rollID) or self:Find(rollID) then return end
    local ok, icon, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, _, _, canTransmog =
        pcall(GetLootRollItemInfo, rollID)
    if not ok or not Text(name) then return end
    local link = GetLootRollItemLink and Text(ns.Safe.Call(GetLootRollItemLink, rollID))
    self:Prune()
    local e = {
        rollID = rollID, t = time(), link = link, name = name, icon = Num(icon) or Text(icon),
        item = ns.Loot.ItemID(link), quality = Num(quality), count = Num(count),
        ilvl = link and ns.Loot.ItemLevel(link), bop = Bool(bop) or (Num(bop) or 0) > 0,
        canNeed = Bool(canNeed) or false, canGreed = Bool(canGreed) or false,
        canTransmog = Bool(canTransmog) or false, canDE = Bool(canDE) or false,
        reasonNeed = Num(reasonNeed), reasonGreed = Num(reasonGreed),
        expires = GetTime() + (Num(rollTime) or 60000) / 1000,
        total = math.max(1, (Num(rollTime) or 60000) / 1000),      -- the roll's full length (the time bar)
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
    local e = Num(rollID) and self:Find(rollID)
    if not e then return end
    e.closed, e.pending = true, nil
    refresh()
end

-- ---------------------------------------------------------------------
-- Blizzard's pop-ups: hidden while this window shows the roll
-- ---------------------------------------------------------------------
-- Blizzard's container keeps a slot per pop-up: take it out through the
-- container (a bare Hide leaves the slot taken, and the column keeps
-- growing). Taking one out can open a waiting roll in its place, which this
-- hides too. Not in combat: the container lays out frames the game protects
-- then - a bare Hide, and the slots are freed once combat ends.
local function canUseContainer()
    return GroupLootContainer_RemoveFrame and GroupLootContainer and not (InCombatLockdown and InCombatLockdown())
end

local function takeOut(f)
    if canUseContainer() and pcall(GroupLootContainer_RemoveFrame, GroupLootContainer, f) then return end
    f:Hide()
    LR.leftovers = true
end

-- after combat: free the slots of pop-ups hidden during it
function LR:FreeSlots()
    if not self.leftovers or not canUseContainer() or type(GroupLootContainer.rollFrames) ~= "table" then return end
    self.leftovers = nil
    local stale = {}
    for _, f in pairs(GroupLootContainer.rollFrames) do
        if type(f) == "table" and f.IsShown and not f:IsShown() and tostring(f.GetName and f:GetName() or ""):find("^GroupLootFrame") then stale[#stale + 1] = f end
    end
    for _, f in ipairs(stale) do pcall(GroupLootContainer_RemoveFrame, GroupLootContainer, f) end
    self:HideBlizzard()                     -- (a waiting roll may have opened in a freed slot)
end

function LR:HideBlizzard()
    if self.hiding or not (self.V.frame and self.V.frame:IsShown()) then return end
    self.hiding = true
    for _ = 1, 8 do
        local hid = false
        for i = 1, 4 do
            local f = _G["GroupLootFrame" .. i]
            local e = f and f:IsShown() and f.rollID and self:Find(f.rollID)
            -- (never while its "will bind" question is up: hiding the pop-up closes that too)
            if e and not e.pending and (not e.handedBack or e.rolled) then takeOut(f); hid = true end
        end
        if not hid then break end
    end
    self.hiding = nil
end

-- Open Blizzard's pop-up for a roll: GroupLootContainer_AddRoll (10.1.5+,
-- with the roll's full length like Blizzard's own call), else the old
-- GroupLootFrame_OpenNewFrame. True if one was there to call.
local function blizzardOpen(rollID, left)
    if GroupLootContainer_AddRoll then
        local full = C_Loot and C_Loot.GetLootRollDuration and ns.Safe.Num(ns.Safe.Call(C_Loot.GetLootRollDuration, rollID))
        return pcall(GroupLootContainer_AddRoll, rollID, full or left)
    elseif GroupLootFrame_OpenNewFrame then
        return pcall(GroupLootFrame_OpenNewFrame, rollID, left)
    end
    return false
end

-- give the rolls you haven't made back to Blizzard's pop-ups
function LR:HandBack()
    local n = 0
    for _, e in ipairs(self.items) do
        if not e.sim and not e.rolled and not e.closed and not e.handedBack then
            local left = ns.Safe.Num(ns.Safe.Call(GetLootRollTimeLeft, e.rollID))
            if left and left > 0 then
                e.handedBack = true
                if blizzardOpen(e.rollID, left) then n = n + 1 end
            end
        end
    end
    if n > 0 then
        ns.Print(("Blizzard's roll pop-ups are back for %d item%s - /tu rolls opens this window again."):format(n, n == 1 and "" or "s"))
    end
    return n
end

-- ---------------------------------------------------------------------
-- Your choices
-- ---------------------------------------------------------------------
-- A roll counts as made once the game has it. Need / Greed on a
-- bind-on-pickup item first asks "will bind" (CONFIRM_LOOT_ROLL, right
-- after the roll); until that's accepted (ConfirmLootRoll - or your choice
-- shows in the loot history) the item stays open and says so. No question
-- within a moment: the roll went straight through.
LR.CONFIRM_WAIT = 0.3

function LR:Roll(e, kind)
    if e.rolled or e.closed then return end
    if e.sim then return self:Rolled(e, kind) end
    e.trying, e.asked = kind, nil                 -- (set first: the game may ask while the roll is sent)
    local ok = pcall(RollOnLoot, e.rollID, kind)
    if not ok then
        e.trying = nil
        return ns.Print("That roll didn't go through - use Blizzard's roll pop-up for this item.")
    end
    C_Timer.After(LR.CONFIRM_WAIT, function()
        if e.trying == kind and not e.asked then LR:Rolled(e, kind) end
    end)
end

function LR:OnConfirmAsked(rollID, rollType)
    local e = Num(rollID) and self:Find(rollID)
    if not e or e.rolled or e.closed then return end
    e.asked = true
    e.pending = Num(rollType) or e.trying
    refresh()
end

function LR:OnConfirmed(rollID, rollType)
    local e = Num(rollID) and self:Find(rollID)
    if e and not e.rolled and not e.closed then self:Rolled(e, Num(rollType) or e.pending or e.trying) end
end

function LR:Rolled(e, kind)
    if e.rolled or kind == nil then return end
    e.rolled, e.pending, e.trying = kind, nil, nil
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
    for i = #self.items, 1, -1 do
        local e = self.items[i]
        if e.item == item then
            if e.rollID == rollID then found = e break end
            found = found or e
        end
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
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) or not Num(encounterID) or not Num(lootListID) then return end
    local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
    if not ok or type(drop) ~= "table" or not Text(drop.itemHyperlink) then return end
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
        if Text(r.playerName) then
            e.rolls[ns.NormalizeSender(r.playerName)] = { s = Num(r.state), r = Num(r.roll), c = Text(r.playerClass) }
        end
    end
    -- your roll in the history: it went through (a "will bind" question was accepted)
    local mine = e.rolls[ns.me]
    if mine and mine.s and mine.s ~= NO_ROLL and (e.pending or e.trying) then self:Rolled(e, e.pending or e.trying) end
    local w = drop.winner
    if w and Text(w.playerName) then
        if not e.winner then e.flashAt = GetTime() end                -- the row flashes green once
        e.winner, e.wstate, e.wroll = ns.NormalizeSender(w.playerName), Num(w.state), Num(w.roll)
        e.closed, e.pending = true, nil
    end
    if Bool(drop.allPassed) then e.allPassed, e.closed, e.pending = true, true, nil end
    refresh()
end

-- ---------------------------------------------------------------------
-- What the window shows for one item
-- ---------------------------------------------------------------------

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
        x.class, x.hist = r.c, true
        if r.s and r.s ~= NO_ROLL then x.state, x.num = r.s, r.r end
    end
    -- loot wishlists (0.37.0): raiders who wanted it, even if they haven't picked anything
    if ns.Wishlist and e.item and e.item > 0 then
        for _, w in ipairs(ns.Wishlist:Wanters(e.item)) do
            if w.group or by[w.name] then get(w.name).wish = w.tag end
        end
    end
    local hist = next(e.rolls) ~= nil
    for _, x in ipairs(list) do
        x.won = e.winner == x.name
        -- passed (in the game, or their Titan Up pick), or never rolled before it ended
        x.passed = x.state == PASSED or (not x.state and x.roll == LR.PASS) or (e.closed and x.hist and not x.state and not x.roll) or nil
        -- still to roll: the game lists who can roll; without its list yet, Titan Up users
        x.wait = not e.closed and not x.state and not x.roll and (hist and x.hist or (not hist and x.titan)) or nil
        local text
        if x.passed and not x.state and not x.roll then
            text = "no roll"
        elseif x.state then
            text = (ns.Loot.ROLL_NAMES[x.state] or "?") .. (x.num and ("  " .. x.num) or "")
        elseif x.roll then
            text = LR.ROLL_LABEL[x.roll] or "?"
        else
            text = (e.closed or not x.wait) and "-" or "deciding..."
        end
        x.rollText = text
    end
    table.sort(list, function(a, b)
        if a.won ~= b.won then return a.won end
        if (a.num or -1) ~= (b.num or -1) then return (a.num or -1) > (b.num or -1) end
        if ((a.tags or "") ~= "") ~= ((b.tags or "") ~= "") then return (a.tags or "") ~= "" end
        if (a.wish == "B") ~= (b.wish == "B") then return a.wish == "B" end
        return a.name < b.name
    end)
    return list
end

-- Who the item is still waiting on, and how many have rolled:
-- waiting (list), done, total, fromGame (false: Titan Up users only)
function LR:Waiting(e, list)
    list = list or self:Raiders(e)
    local waiting, total = {}, 0
    local hist = next(e.rolls) ~= nil
    for _, x in ipairs(list) do
        if hist and x.hist or (not hist and x.titan) then total = total + 1 end
        if x.wait then waiting[#waiting + 1] = x end
    end
    return waiting, total - #waiting, total, hist
end

-- "Kev tagged it BIS, but Mossy won it as a Sidegrade - a trade could help."
-- (list: LR:Raiders(e), if already built)
function LR:TradeHint(e, list)
    if not e.winner then return nil end
    list = list or self:Raiders(e)
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
local SMALL_H = 26                 -- an item you passed on: one thin line
local SLOTS = 14                   -- row frames (thin rows let more fit)
local LIST_W = 576
local LIST_H = ROWS * ROW_H + 8
local H = 48 + LIST_H + 12
local RAIDER_H, RAIDER_ROWS = 30, 8

local YELLOW, PURPLE = { 1, 0.85, 0.30 }, { 0.78, 0.61, 1 }
local WAIT_HEX = "|cffffa340"

local function passedOn(e) return e.rolled == LR.PASS end
local function rowHeight(e) return passedOn(e) and SMALL_H or ROW_H end
-- you've rolled, and the item is still open: waiting on the raid
local function waitingOnRaid(e) return e.rolled and not passedOn(e) and not e.closed end

function V:Open()
    self:Create()
    for _, e in ipairs(LR.items) do if not e.rolled then e.handedBack = nil end end
    if not self.frame:IsShown() then self.frame:Show() end
    if not self.sel or not tContains(LR.items, self.sel) then self.sel = LR.items[#LR.items] end
    self:Refresh()
    self:Tick()
    LR:HideBlizzard()
end

-- The countdowns tick twice a second while a roll is still open (yours or
-- the raid's); once every roll is over, the window only redraws when
-- something changes.
local function anyOpen()
    local now = GetTime()
    for _, e in ipairs(LR.items) do if not e.closed and now < e.expires + 10 then return true end end
    return false
end

function V:Tick()
    if self.ticker or not (self.frame and self.frame:IsShown()) or not anyOpen() then return end
    self.ticker = C_Timer.NewTicker(0.5, function()
        V:Refresh()
        if not anyOpen() and V.ticker then V.ticker:Cancel(); V.ticker = nil end
    end)
end

function V:Hide() if self.frame then self.frame:Hide() end end

-- Need / Greed / Transmog / Pass: one row on the right, each in its own
-- fixed slot (Greed and Transmog share one - Blizzard shows one or the other)
local function rollButton(row, label, kind, x, w, color)
    local b = UI.Button(row, w, 26, label, nil, function(s) if s.entry and not s.disabled then LR:Roll(s.entry, kind) end end)
    b:SetPoint("TOPRIGHT", x, -15)
    b.label:SetFontObject("GameFontHighlight")
    b.textColor = color
    b.edge = { color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 1 }
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end   -- a greyed button still shows why
    UI.Paint(b)
    return b
end

-- a pulsing border while the raid is still rolling, and a green flash when
-- the winner comes in
local function effects(row)
    local p = CreateFrame("Frame", nil, row, "BackdropTemplate")
    p:SetAllPoints()
    p:EnableMouse(false)
    UI.Skin(p, { C.accent[1], C.accent[2], C.accent[3], 0.06 }, C.accent)
    local ag = p:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15); a:SetToAlpha(1); a:SetDuration(0.8)
    p.anim = ag
    p:Hide()
    row.pulse = p

    local fl = CreateFrame("Frame", nil, row)
    fl:SetAllPoints()
    fl:EnableMouse(false)
    local t = fl:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(C.good[1], C.good[2], C.good[3], 0.45)
    local fg = fl:CreateAnimationGroup()
    local fa = fg:CreateAnimation("Alpha")
    fa:SetFromAlpha(1); fa:SetToAlpha(0); fa:SetDuration(1.2)
    fg:SetScript("OnFinished", function() fl:Hide() end)
    fl.anim = fg
    fl:Hide()
    row.flash = fl
end

-- a row's two shapes: the full item, or one thin line for an item you passed on
local function setCollapsed(row, on)
    if row.collapsed == on then return end
    row.collapsed = on
    row:SetHeight(on and (SMALL_H - 2) or (ROW_H - 2))
    row.icon:SetSize(on and 18 or 40, on and 18 or 40)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("TOPLEFT", 4, on and -3 or -7)
    row.text:ClearAllPoints()
    if on then row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0) else row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0) end
    row.result:ClearAllPoints()
    if on then row.result:SetPoint("RIGHT", -10, 0) else row.result:SetPoint("TOPRIGHT", -8, -9) end
    for _, part in ipairs({ row.info, row.note, row.count, row.cbar }) do part:SetShown(not on) end
    for _, b in pairs(row.tags) do b:SetShown(not on) end
end

function V:Create()
    if self.frame then return end
    local f = UI.Window("TitanUpLootRolls", W, H, { border = C.accent })
    self.frame = f
    UI.Draggable(f, db, { "CENTER", "CENTER", 0, 120 })
    f:Place()
    UI.Text(f, "GameFontNormal", C.accent, "LOOT ROLLS", "TOPLEFT", 14, -14)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Tag each item for the raid, then roll.  Click an item to see what everyone chose.", "LEFT", f, "TOPLEFT", 110, -21)
    local x = UI.Button(f, 22, 20, "X", "Close - rolls you haven't made go back to Blizzard's pop-ups. /tu rolls opens this window again.", function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -8, -8)
    f:SetScript("OnShow", function()
        V:Tick()
        if ns.BonusRollGuard then ns.BonusRollGuard:Dock() end      -- a bonus roll showing moves in
    end)
    f:SetScript("OnHide", function()
        if V.ticker then V.ticker:Cancel(); V.ticker = nil end
        -- the bonus roll goes back first, so Blizzard's re-layout for the
        -- handed-back rolls places it too
        if ns.BonusRollGuard then ns.BonusRollGuard:Undock() end
        -- Blizzard's container can't be driven from here in combat (see
        -- takeOut): the pop-ups come back as soon as combat ends
        if InCombatLockdown() then
            LR.handBackLater = true
            ns.Print("Rolls you haven't made come back as Blizzard's pop-ups when combat ends - /tu rolls opens this window again.")
        else
            LR:HandBack()
        end
    end)

    -- left: the items
    local list = UI.Panel(f)
    list:SetPoint("TOPLEFT", 12, -40)
    list:SetSize(LIST_W, LIST_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) V.offset = (V.offset or 0) - d; V:Refresh() end)
    self.empty = UI.Text(list, "GameFontHighlightSmall", C.muted, "No loot rolls right now.", "CENTER")
    self.rows = {}
    for i = 1, SLOTS do
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
        row.info:SetWidth(318)
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
        local note = UI.EditBox(row, 100, 18, { inset = 5, max = NOTE_MAX })
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
        -- rolls: Need, then Greed or Transmog, then Pass
        row.need = rollButton(row, "Need", LR.NEED, -138, 58, C.good)
        row.greed = rollButton(row, "Greed", LR.GREED, -59, 74, YELLOW)
        row.tmog = rollButton(row, "Transmog", LR.TRANSMOG, -59, 74, PURPLE)
        row.pass = rollButton(row, "Pass", LR.PASS, -6, 48, C.bad)
        row.result = UI.Text(row, "GameFontHighlightSmall", C.text, nil, "TOPRIGHT", -8, -9)
        row.result:SetWidth(170)
        row.result:SetJustifyH("RIGHT")
        -- how many have rolled (while you wait on the raid)
        row.count = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", -8, -24)
        row.count:SetJustifyH("RIGHT")
        row.cbar = CreateFrame("Frame", nil, row, "BackdropTemplate")
        UI.Skin(row.cbar, C.canvas, C.line)
        row.cbar:SetSize(120, 5)
        row.cbar:SetPoint("TOPRIGHT", -8, -40)
        row.cbar.fill = row.cbar:CreateTexture(nil, "ARTWORK")
        row.cbar.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
        row.cbar.fill:SetPoint("TOPLEFT", 1, -1)
        row.cbar.fill:SetPoint("BOTTOMLEFT", 1, 1)
        -- time left
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        row.bar:SetPoint("BOTTOMLEFT", 0, 0)
        row.bar:SetHeight(2)
        effects(row)
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
    -- who it's still waiting on
    self.dWaitHead = UI.Text(d, "GameFontNormalSmall", C.warn, nil, "TOPLEFT", 8, -46)
    self.dWaitCount = UI.Text(d, "GameFontNormalSmall", C.warn, nil, "TOPRIGHT", -8, -46)
    self.dWaitNames = UI.Text(d, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 8, -60)
    self.dWaitNames:SetWidth(dw - 16)
    self.dWaitNames:SetJustifyH("LEFT")
    self.dRolledHead = UI.Text(d, "GameFontNormalSmall", C.muted, nil, "TOPLEFT", 8, -46)
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
    -- who passed: one line that opens to their names
    self.dPassBtn = UI.Button(d, dw - 16, 20, "", "Show or hide who passed", function()
        if V.sel then V.sel.showPassed = not V.sel.showPassed; V:RefreshDetail() end
    end)
    self.dPassBtn.textColor = C.bad
    self.dPassNames = UI.Text(d, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", self.dPassBtn, "BOTTOMLEFT", 4, -4)
    self.dPassNames:SetWidth(dw - 24)
    self.dPassNames:SetJustifyH("LEFT")
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

-- Why a button is greyed: the game's own reason (what Blizzard's pop-up
-- shows), else ours
local function reason(code, fallback)
    local n = Num(code)
    local text = n and n > 0 and Text(_G["LOOT_ROLL_INELIGIBLE_REASON" .. n])
    return text or fallback
end

local function status(e)
    if e.winner then
        local how = ns.Loot.ROLL_NAMES[e.wstate] or "won"
        return "|cff66e08cWon by|r " .. UI.Named(e.winner) .. "  |cffffd94d" .. how .. (e.wroll and (" " .. e.wroll) or "") .. "|r"
    end
    if e.allPassed then return "Everyone passed" end
    if e.pending and not e.closed then return "|cffffd94dConfirm Blizzard's \"will bind\" pop-up|r to " .. (LR.ROLL_LABEL[e.pending] or "roll") end
    if e.rolled then return "You: |cffffd94d" .. (LR.ROLL_LABEL[e.rolled] or "?") .. "|r" end
    if e.closed then return "|cff8a8f9cRolls finished|r" end
    return nil
end

local function nameList(people, max)
    local out = {}
    for i, x in ipairs(people) do
        if max and i > max then
            out[#out] = out[#out] .. "  |cff8a8f9c+" .. (#people - max) .. "|r"
            break
        end
        out[#out + 1] = x.name == ns.me and "You" or UI.ClassName(x.name, x.class or ns.ClassOf(x.name))
    end
    return table.concat(out, max and ", " or "   ")
end

-- the item shown in a row (the full shape or the thin "passed" line)
function V:DrawRow(row, e, now)
    local collapsed = passedOn(e)
    setCollapsed(row, collapsed)
    row.icon:SetTexture(e.icon or 134400)
    row.text:SetText((e.link or e.name or "?") .. (e.count and e.count > 1 and (" x" .. e.count) or ""))
    row.hl:SetShown(self.sel == e)
    local open = not e.rolled and not e.closed
    local left = e.expires - now
    -- the roll buttons Blizzard's pop-up would show: Transmog instead of
    -- Greed when the look is one you can collect
    for _, def in ipairs({ { row.need, true, e.canNeed, reason(e.reasonNeed, "You can't Need this") },
                           { row.greed, not e.canTransmog, e.canGreed, reason(e.reasonGreed, "You can't Greed this") },
                           { row.tmog, e.canTransmog, true },
                           { row.pass, true, true } }) do
        local b = def[1]
        b.entry = e
        b:SetShown(open and def[2])
        UI.SetDisabled(b, not def[3])
        b.tip = not def[3] and def[4] or nil
    end
    local waiting = waitingOnRaid(e)
    row.pulse:SetShown(waiting)
    if waiting then if not row.pulse.anim:IsPlaying() then row.pulse.anim:Play() end else row.pulse.anim:Stop() end
    if e.flashAt and not e.flashed and not collapsed then
        e.flashed = true
        row.flash:Show()
        row.flash.anim:Play()
    end
    if collapsed then
        row.result:SetText("|cfff25959Pass|r")
        row.bar:Hide()
        row.flash:Hide()
        return
    end
    for code, b in pairs(row.tags) do UI.SetActive(b, e.tags:find(code, 1, true) ~= nil) end
    if not row.note:HasFocus() and row.note:GetText() ~= e.note then row.note:SetText(e.note) end
    row.note.hint:SetShown(e.note == "" and not row.note:HasFocus())
    local bits = {}
    if waiting then
        local list, done, total = LR:Waiting(e)
        if #list > 0 then bits[#bits + 1] = WAIT_HEX .. "Waiting on|r " .. nameList(list, 2) end
        row.count:SetText(total > 0 and (done .. " / " .. total .. " rolled") or "")
        row.cbar:SetShown(total > 0)
        row.cbar.fill:SetWidth(math.max(1, 118 * (total > 0 and done / total or 0)))
    else
        row.count:SetText("")
        row.cbar:Hide()
        local others = 0
        for _, p in pairs(e.picks) do if p.tags ~= "" or p.note ~= "" then others = others + 1 end end
        if e.ilvl then bits[#bits + 1] = "item level " .. e.ilvl end
        if e.bop then bits[#bits + 1] = "binds on pickup" end
        if e.pending and not e.closed then bits[#bits + 1] = "|cffffd94dconfirm the bind pop-up|r" end
        if others > 0 then bits[#bits + 1] = "|cff4fc3f7" .. others .. (others == 1 and " raider tagged it|r" or " raiders tagged it|r") end
    end
    if not e.closed and left > 0 then bits[#bits + 1] = UI.Clock(left) .. " left" end
    row.info:SetText(table.concat(bits, "  -  "))
    row.result:SetText(open and "" or (status(e) or ""))
    row.bar:SetShown(not e.closed and left > 0)
    if not e.closed then row.bar:SetWidth(math.max(1, (LIST_W - 8) * math.min(1, math.max(0, left) / (e.total or 60)))) end
end

function V:Refresh()
    if not self.frame then return end
    local items, rows = LR.items, self.rows
    -- scrolling goes by item; the last offset is the one that still fills the list
    local maxOff, h = 0, 0
    for i = #items, 1, -1 do
        h = h + rowHeight(items[i])
        if h > LIST_H - 8 then maxOff = i break end
    end
    self.offset = math.max(0, math.min(maxOff, self.offset or 0))
    self.empty:SetShown(#items == 0)
    local now, y = GetTime(), -4
    for i, row in ipairs(rows) do
        local e = items[i + self.offset]
        if e and -y + rowHeight(e) - 2 > LIST_H - 4 then e = nil end      -- no room left
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, y)
            row:SetPoint("RIGHT", -4, 0)
            y = y - rowHeight(e)
            self:DrawRow(row, e, now)
        end
    end
    self:RefreshDetail()
end

function V:RefreshDetail()
    local e = self.sel
    if e and not tContains(LR.items, e) then e = nil; self.sel = nil end
    for _, r in ipairs(self.dRows) do r:Hide() end
    for _, t in ipairs({ self.dWaitHead, self.dWaitCount, self.dWaitNames, self.dRolledHead, self.dPassNames }) do t:SetText("") end
    self.dPassBtn:Hide()
    if not e then
        self.dTitle:SetText("")
        self.dWinner:SetText("")
        self.dHint:SetText("")
        self.dEmpty:SetText("Click an item to see what the raid chose.")
        return
    end
    self.dEmpty:SetText("")
    self.dTitle:SetText(e.link or e.name or "?")
    local st = status(e)
    if not e.closed then
        local clock = "|cff8a8f9cRolling - " .. UI.Clock(math.max(0, e.expires - GetTime())) .. " left|r"
        st = st and (st .. "  |cff8a8f9c-|r  " .. clock) or clock
    end
    self.dWinner:SetText(st or "")
    local list = LR:Raiders(e)
    self.dHint:SetText(LR:TradeHint(e, list) or "")
    local y = -46 - ((self.dHint:GetText() or "") ~= "" and 40 or 0)
    local bottom = -(LIST_H - 4)

    -- waiting on
    if not e.closed then
        local waiting, done, total, fromGame = LR:Waiting(e, list)
        self.dWaitHead:ClearAllPoints(); self.dWaitHead:SetPoint("TOPLEFT", 8, y)
        self.dWaitCount:ClearAllPoints(); self.dWaitCount:SetPoint("TOPRIGHT", -8, y)
        self.dWaitHead:SetText("WAITING ON (" .. #waiting .. ")")
        self.dWaitCount:SetText(total > 0 and (done .. " / " .. total .. " ROLLED") or "")
        self.dWaitNames:ClearAllPoints(); self.dWaitNames:SetPoint("TOPLEFT", 8, y - 15)
        local names = #waiting > 0 and nameList(waiting) or "|cff8a8f9cEveryone has rolled.|r"
        if not fromGame then names = names .. "\n|cff8a8f9c(Titan Up users only - the game's list isn't in yet)|r" end
        self.dWaitNames:SetText(names)
        y = y - 15 - math.max(14, self.dWaitNames:GetStringHeight() or 14) - 10
    end

    -- rolled (passes go in their own line below)
    local rolled, passed = {}, {}
    for _, x in ipairs(list) do
        if x.passed then passed[#passed + 1] = x elseif not x.wait then rolled[#rolled + 1] = x end
    end
    self.dRolledHead:ClearAllPoints(); self.dRolledHead:SetPoint("TOPLEFT", 8, y)
    self.dRolledHead:SetText("ROLLED (" .. #rolled .. ")")
    y = y - 16
    local room = math.max(0, math.floor((y - bottom - (#passed > 0 and 28 or 0)) / RAIDER_H))
    local shown = math.min(RAIDER_ROWS, room)
    self.dOffset = math.max(0, math.min(math.max(0, #rolled - shown), self.dOffset or 0))
    for i = 1, shown do
        local x, r = rolled[i + self.dOffset], self.dRows[i]
        if not x then break end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r:Show()
        y = y - RAIDER_H
        -- gold: BIS for them (their tag here, or their wishlist)
        local bis = (x.tags or ""):find("B", 1, true) or x.wish == "B"
        local nameText = bis and ("|cffffd100" .. ns.Short(x.name) .. "|r") or UI.ClassName(x.name, x.class or ns.ClassOf(x.name))
        r.name:SetText((x.won and "|cff66e08c>|r " or "") .. nameText .. (x.name == ns.me and " |cff8a8f9c(you)|r" or ""))
        r.roll:SetText((x.won and "|cff66e08c" or "|cffffd94d") .. x.rollText .. "|r")
        local sub = LR.TagText(x.tags)
        if (x.note or "") ~= "" then sub = sub .. (sub ~= "" and "  -  " or "") .. "\"" .. x.note .. "\"" end
        if x.wish then sub = sub .. (sub ~= "" and "  -  " or "") .. "|cff4fc3f7wishlist: " .. (ns.Wishlist.TAG_NAME[x.wish] or "") .. "|r" end
        if sub == "" then sub = x.titan and "no tags" or "|cff5a5f6ano Titan Up tags|r" end
        r.sub:SetText(sub)
    end

    -- passed: one line, opens to their names
    if #passed > 0 then
        self.dPassBtn:ClearAllPoints()
        self.dPassBtn:SetPoint("TOPLEFT", 8, y - 6)
        self.dPassBtn.label:SetText((e.showPassed and "v  " or ">  ") .. "PASSED (" .. #passed .. ")")
        self.dPassBtn:Show()
        if e.showPassed then
            local out = {}
            for _, x in ipairs(passed) do
                out[#out + 1] = (x.name == ns.me and "You" or UI.ClassName(x.name, x.class or ns.ClassOf(x.name)))
                    .. (x.rollText == "no roll" and " |cff8a8f9c(no roll)|r" or "")
            end
            self.dPassNames:SetText(table.concat(out, "   "))
        end
    end
end
