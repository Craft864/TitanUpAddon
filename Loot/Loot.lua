-- Titan Up - Loot/Loot.lua
-- Tracks loot from the moment it drops until someone equips it:
--   * Raid (group loot): WoW's loot history (C_LootHistory) gives everyone in
--     the group every drop, everyone's Need/Greed/Transmog choice and roll,
--     and the winner. Recorded as soon as a roll finishes.
--   * Dungeons / Mythic+ (personal loot): nobody rolls - the game picks who
--     gets items. Recorded from the encounter loot event and loot messages.
--   * Trades: when a tracked item changes hands in a trade, the hop is added
--     to its history and shared with the group, so everyone's copy shows the
--     same chain (needs Titan Up on at least one side of the trade).
--   * Equipped: when the current owner equips it, tracking ends (equipping
--     makes it soulbound for good). Needs Titan Up on the owner's side.
--
-- Every client builds the same id for the same drop (server date, boss or
-- instance, winner, item), so shared trade/equip updates line up.
-- Only the two people in a trade can report it; only the person who
-- equipped an item can report that.
--
-- Messages ("TitanUpLT"):
--   T id from to      a trade (sender must be from or to)
--   Q id who          equipped (sender must be who)
local ADDON, ns = ...

local LT = {}
ns.Loot = LT

local PREFIX = "TitanUpLT"
local SEP = "^"
local KEEP = 1500             -- newest drops kept

LT.ROLL_NAMES = { [0] = "Need", [1] = "Need (off-spec)", [2] = "Transmog", [3] = "Greed", [4] = "No roll", [5] = "Pass" }

local function db() return ns.udb.loot end
local function now() return (GetServerTime and GetServerTime()) or time() end
local function day() return date("!%Y%m%d", now()) end

function LT.ItemID(link) return tonumber(tostring(link or ""):match("item:(%d+)")) end

-- Quality from the item cache, or from the link's color if not cached yet.
local COLOR_QUALITY = { ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7, ["1eff00"] = 2 }
function LT.Quality(link)
    -- C_Item.GetItemInfo (12.1.5 removed the old global GetItemInfo)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local q = getInfo and select(3, getInfo(link))
    if q then return q end
    local hex = tostring(link or ""):lower():match("|cff(%x%x%x%x%x%x)")
    return hex and COLOR_QUALITY[hex] or nil
end

function LT.ItemLevel(link)
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    local ok, lvl = pcall(f, link)
    return ok and lvl or nil
end

local function bad(v) return v == nil or ns.IsSecret(v) end

local function refresh()
    if ns.LootUI and ns.LootUI:IsShown() then ns.LootUI:Refresh() end
end

function LT:Wanted(link)
    if bad(link) or not LT.ItemID(link) then return false end
    local q = LT.Quality(link)
    return q ~= nil and q >= (db().minQuality or 4)
end

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
function LT:Init()
    ns.On("LOOT_HISTORY_UPDATE_DROP", function(encounterID, lootListID) LT:OnDrop(encounterID, lootListID) end)
    ns.On("LOOT_HISTORY_UPDATE_ENCOUNTER", function(encounterID) LT:SweepEncounter(encounterID) end)
    ns.On("ENCOUNTER_LOOT_RECEIVED", function(encounterID, itemID, link, quantity, player, class)
        LT:OnPersonalLoot(link, player, class, encounterID)
    end)
    ns.On("CHAT_MSG_LOOT", function(msg) LT:OnLootMessage(msg) end)
    ns.On("CHALLENGE_MODE_START", function() LT.keyRun = true end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        local inInstance = IsInInstance()
        if not inInstance then LT.keyRun = nil end
    end)
    ns.On("PLAYER_EQUIPMENT_CHANGED", function(slot) LT:OnEquip(slot) end)
    -- trades: which tracked items changed hands
    ns.WatchTrades(function(t)
        t.give, t.get = t.give or {}, t.get or {}
        for i = 1, 6 do
            local give = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
            local get = GetTradeTargetItemLink and GetTradeTargetItemLink(i)
            t.give[i] = (not bad(give)) and give or nil
            t.get[i] = (not bad(get)) and get or nil
        end
    end, function(t) LT:OnTradeComplete(t) end)
    ns.Listen(PREFIX, "guild", function(text, sender) LT:OnMessage(text, sender) end)
end

local function instanceInfo()
    local name, kind, diffID, diffName, _, _, _, instID = GetInstanceInfo()
    return name, kind, diffID, diffName, instID
end

-- ---------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------
function LT:Add(id, rec)
    local drops = db().drops
    local have = drops[id]
    if have then
        -- fill in anything the first sighting didn't have (rolls, ilvl)
        for k, v in pairs(rec) do if have[k] == nil then have[k] = v end end
        return have, false
    end
    rec.id = id
    rec.chain = rec.chain or {}
    rec.owner = rec.owner or rec.winner
    drops[id] = rec
    self._added = (self._added or 0) + 1
    if self._added % 100 == 0 then self:Trim() end
    refresh()
    return rec, true
end

function LT:Trim()
    local list = {}
    for _, r in pairs(db().drops) do list[#list + 1] = r end
    if #list <= KEEP then return end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    for i = KEEP + 1, #list do db().drops[list[i].id] = nil end
end

-- Raid group loot: one finished roll
function LT:OnDrop(encounterID, lootListID)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) or bad(encounterID) or bad(lootListID) then return end
    local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
    if ok and drop then self:RecordGroupDrop(encounterID, drop) end
end

function LT:SweepEncounter(encounterID)
    if not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) or bad(encounterID) then return end
    local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
    if not ok or type(drops) ~= "table" then return end
    for _, drop in ipairs(drops) do self:RecordGroupDrop(encounterID, drop) end
end

function LT:RecordGroupDrop(encounterID, drop)
    local link = drop.itemHyperlink
    local w = drop.winner
    if not w or bad(w.playerName) or not self:Wanted(link) then return end
    local winner = ns.NormalizeSender(w.playerName)
    local itemID = LT.ItemID(link)
    local id = table.concat({ "G", day(), encounterID, winner, itemID, drop.lootListID or 0 }, "-")
    local boss
    if C_LootHistory.GetInfoForEncounter then
        local ok, info = pcall(C_LootHistory.GetInfoForEncounter, encounterID)
        boss = ok and info and not bad(info.encounterName) and info.encounterName or nil
    end
    local inst, kind, _, diffName = instanceInfo()
    local rolls = {}
    for _, r in ipairs(drop.rollInfos or {}) do
        if not bad(r.playerName) then
            rolls[#rolls + 1] = { n = ns.NormalizeSender(r.playerName), s = r.state, r = r.roll, c = r.playerClass }
        end
    end
    self:Add(id, {
        t = now(), kind = "raid", inst = (kind == "raid") and inst or nil, diff = (kind == "raid") and diffName or nil,
        encID = encounterID, boss = boss, link = link, item = itemID, ilvl = LT.ItemLevel(link),
        winner = winner, class = w.playerClass, wstate = w.state, wroll = w.roll, rolls = rolls,
    })
end

-- Personal loot (dungeons, Mythic+): no roll, the game picks who gets it
function LT:OnPersonalLoot(link, player, class, encounterID)
    if bad(player) or not self:Wanted(link) then return end
    local inst, kind, diffID, diffName, instID = instanceInfo()
    if kind == "raid" then return end          -- raids are recorded from the loot history
    local who = ns.NormalizeSender(player)
    local mplus = LT.keyRun or diffID == 8
    local level
    if mplus and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, lvl = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and lvl and lvl > 0 then level = lvl end
    end
    local itemID = LT.ItemID(link)
    local id = table.concat({ "P", day(), instID or 0, who, itemID }, "-")
    self:Add(id, {
        t = now(), kind = mplus and "mplus" or "dungeon", inst = inst, diff = mplus and (level and ("+" .. level) or "Mythic+") or diffName,
        encID = encounterID, link = link, item = itemID, ilvl = LT.ItemLevel(link), winner = who, class = class,
    })
end

-- "Brakk receives loot: [Item]." - catches the end-of-run Mythic+ chest
local lootPatterns
local function buildPatterns()
    lootPatterns = {}
    local function pat(fmt, self)
        if not fmt then return end
        local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
        p = p:gsub("%%s", "(.+)")
        lootPatterns[#lootPatterns + 1] = { "^" .. p .. "$", self }
    end
    pat(LOOT_ITEM_SELF, true); pat(LOOT_ITEM_PUSHED_SELF, true)
    pat(LOOT_ITEM, false); pat(LOOT_ITEM_PUSHED, false)
end

function LT:OnLootMessage(msg)
    if bad(msg) then return end
    local inInstance, kind = IsInInstance()
    if not inInstance or kind ~= "party" then return end
    if not lootPatterns then buildPatterns() end
    for _, p in ipairs(lootPatterns) do
        local a, b = msg:match(p[1])
        if a then
            if p[2] then self:OnPersonalLoot(a, ns.me) else self:OnPersonalLoot(b, a) end
            return
        end
    end
end

-- ---------------------------------------------------------------------
-- Ownership: trades and equips
-- ---------------------------------------------------------------------
-- The tracked, not-yet-equipped item `owner` holds that matches `link`
-- (exact link first, then same item), newest first.
function LT:FindOwned(owner, link)
    local itemID = LT.ItemID(link)
    if not itemID then return nil end
    local best, exact
    for _, r in pairs(db().drops) do
        if r.owner == owner and not r.equipped and r.item == itemID then
            local isExact = r.link == link
            if not best or (isExact and not exact) or (isExact == exact and (r.t or 0) > (best.t or 0)) then
                best, exact = r, isExact
            end
        end
    end
    return best
end

function LT:Transfer(rec, from, to, share)
    local last = rec.chain[#rec.chain]
    if last and last.f == from and last.to == to then return false end      -- already have it
    rec.chain[#rec.chain + 1] = { f = from, to = to, t = now() }
    rec.owner = to
    if share then self:Send("T", rec.id, from, to) end
    refresh()
    return true
end

function LT:SetEquipped(rec, who, share)
    if rec.equipped then return false end
    rec.equipped = { by = who, t = now() }
    if share then self:Send("Q", rec.id, who) end
    refresh()
    return true
end

function LT:OnTradeComplete(t)
    if not t.partner then return end
    for i = 1, 6 do
        local give, get = t.give[i], t.get[i]
        if give then
            local rec = self:FindOwned(ns.me, give)
            if rec then self:Transfer(rec, ns.me, t.partner, true) end
        end
        if get then
            local rec = self:FindOwned(t.partner, get)
            if rec then self:Transfer(rec, t.partner, ns.me, true) end
        end
    end
end

function LT:OnEquip(slot)
    if bad(slot) then return end
    local link = GetInventoryItemLink("player", slot)
    if bad(link) then return end
    local rec = self:FindOwned(ns.me, link)
    if rec then self:SetEquipped(rec, ns.me, true) end
end

-- ---------------------------------------------------------------------
-- Sharing trades/equips
-- ---------------------------------------------------------------------
function LT:Send(...)
    if not ns.InLockdown() then ns.SendFields(PREFIX, ...) end
end

function LT:OnMessage(text, sender)
    local f = ns.Split(text, SEP)
    local kind, id = f[1], f[2]
    local rec = id and db().drops[id]
    if not rec then return end
    if kind == "T" then
        local from, to = f[3], f[4]
        if not from or not to or (sender ~= from and sender ~= to) then return end   -- only the traders
        if rec.equipped then return end
        self:Transfer(rec, from, to, false)
    elseif kind == "Q" then
        local who = f[3]
        if who ~= sender or rec.owner ~= who then return end                         -- only the owner
        self:SetEquipped(rec, who, false)
    end
end

-- ---------------------------------------------------------------------
-- Queries for the window
-- ---------------------------------------------------------------------
function LT:Drops(filter, search)
    local out = {}
    search = search and search ~= "" and search:lower() or nil
    for _, r in pairs(db().drops) do
        local okKind = not filter or filter == "all" or r.kind == filter or (filter == "mplus" and r.kind == "dungeon")
        local okSearch = true
        if search then
            local hay = ((r.link or ""):match("%[(.-)%]") or "") .. " " .. (r.winner or "") .. " " .. (r.boss or "") .. " " .. (r.inst or "")
            for _, step in ipairs(r.chain) do hay = hay .. " " .. step.to end
            okSearch = hay:lower():find(search, 1, true) ~= nil
        end
        if okKind and okSearch then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

-- Group drops into raid nights / dungeon runs by local date + instance.
function LT:Sessions(drops)
    local by, list = {}, {}
    for _, r in ipairs(drops) do
        local d = date("%Y-%m-%d", r.t or 0)
        local where = r.inst or r.boss or "Unknown"
        local key = d .. "|" .. r.kind .. "|" .. where
        local s = by[key]
        if not s then
            s = { key = key, date = d, label = date("%a %b %d", r.t or 0), where = where, kind = r.kind, diff = r.diff, drops = {}, t = r.t or 0 }
            by[key] = s
            list[#list + 1] = s
        end
        s.drops[#s.drops + 1] = r
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end
