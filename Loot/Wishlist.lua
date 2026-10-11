-- Titan Up - Loot/Wishlist.lua
-- Loot wishlists (0.37.0, on by default): pick the items you want from the
-- Adventure Guide (any instance, boss, difficulty), tagged BIS, Sidegrade
-- or just "want". Everyone's wishlist is shared with the guild over the
-- background lane (Guild/Shared.lua), so when something drops the Loot
-- window and the roll window can show who wanted it - gold names for BIS.
--
-- The item lists come straight from the game's Adventure Guide, so a new
-- season's raids and dungeons work without an update. The Adventure Guide
-- has one "selected instance / difficulty / filter" shared with Blizzard's
-- own window, so Titan Up only reads it while that window is closed, and
-- puts every selection back the way it was afterwards.
--
-- A wishlist (prefix TitanUpLW): item:tag,item:tag,...   (item in base36;
-- tag B = BIS, S = Sidegrade, W = want)
local ADDON, ns = ...

local WL = {}
ns.Wishlist = WL

local Shared = ns.Shared
local PREFIX = "TitanUpLW"
local MAX_ITEMS = 150

WL.TAGS = {
    { "B", "BIS", "Best in slot for me" },
    { "S", "Sidegrade", "An upgrade, but not my best in slot" },
    { "W", "Want", "I'd like it" },
}
WL.TAG_NAME = { B = "BIS", S = "Sidegrade", W = "Wishlist" }
WL.GOLD = "|cffffd100"

local function db() return ns.udb.wishlist end
function WL:Enabled() return db().share and true or false end

-- this character's wishlist: { [itemID] = tag }
function WL:Mine()
    local m = db().mine
    m[ns.me] = m[ns.me] or {}
    return m[ns.me]
end

function WL:Payload()
    if not self:Enabled() then return "" end
    local ids = {}
    for id in pairs(self:Mine()) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for i, id in ipairs(ids) do
        if i > MAX_ITEMS then break end
        out[#out + 1] = Shared.B36(id) .. ":" .. (self:Mine()[id] or "W")
    end
    return table.concat(out, ",")
end

local function parse(p)
    local out = {}
    for item in (p or ""):gmatch("[^,]+") do
        local id, tag = item:match("^(%w+):([BSW])$")
        id = id and tonumber(id, 36)
        if id then out[id] = tag end
    end
    return out
end
WL.Parse = parse

function WL:Init()
    self.sync = Shared.New({
        prefix = PREFIX, name = "Loot wishlist", max = 1600,
        store = function() return db().people end,
        mine = function() return WL:Payload() end,
        changed = function() WL:Changed() end,
    })
    self.sync:Init()
    ns.On("EJ_LOOT_DATA_RECIEVED", function() ns.Debounce("wishlist-loot", 0.3, function() WL:LootLoaded() end) end)
end

function WL:SetEnabled(on)
    db().share = on and true or false
    self.sync:Refresh()
end

-- tag: "B", "S", "W", or nil to take it off
function WL:Set(itemID, tag)
    if not itemID then return false end
    local m = self:Mine()
    if tag and not m[itemID] then
        local n = 0
        for _ in pairs(m) do n = n + 1 end
        if n >= MAX_ITEMS then ns.Print(("Your wishlist is full (%d items) - take something off first."):format(MAX_ITEMS)) return false end
    end
    m[itemID] = tag
    self.sync:Refresh()
    self:Changed()
    return true
end

function WL:Tag(itemID) return self:Mine()[itemID] end

-- ---------------------------------------------------------------------
-- Who wants an item
-- ---------------------------------------------------------------------
local parsed = {}            -- owner -> { h, list }
function WL:Changed()
    for _, name in ipairs({ "WishlistUI", "LootUI", "LootRolls" }) do
        local v = ns[name]
        local frame = v and (v.frame or (v.V and v.V.frame))
        if frame and frame:IsShown() then
            ns.Debounce("wishlist-redraw-" .. name, 0.4, function()
                if name == "LootRolls" then v.V:Refresh() else v:Refresh() end
            end)
        end
    end
end

-- { { name, tag }, ... }: BIS first, then Sidegrade, then the rest; your group first within each
function WL:Wanters(itemID)
    local out = {}
    if not itemID then return out end
    for owner, e in pairs(db().people) do
        if e.p and e.p ~= "" then
            local c = parsed[owner]
            if not c or c.h ~= e.h then c = { h = e.h, list = parse(e.p) } parsed[owner] = c end
            local tag = c.list[itemID]
            if tag then out[#out + 1] = { name = owner, tag = tag, group = ns.InMyGroup(owner) } end
        end
    end
    local rank = { B = 1, S = 2, W = 3 }
    table.sort(out, function(a, b)
        if rank[a.tag] ~= rank[b.tag] then return rank[a.tag] < rank[b.tag] end
        if a.group ~= b.group then return a.group end
        return a.name < b.name
    end)
    return out
end

-- a name for a "who wants it" list: gold for BIS, else class colour
function WL.NameText(name, tag, class)
    if tag == "B" then return WL.GOLD .. ns.Short(name) .. "|r" end
    return ns.UI.ClassName(name, class or ns.ClassOf(name))
end

-- ---------------------------------------------------------------------
-- The Adventure Guide (EJ_* functions), always put back as it was
-- ---------------------------------------------------------------------
function WL:CanBrowse()
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_SelectInstance and EJ_GetNumLoot) then
        return false, "This game version doesn't offer the Adventure Guide's loot lists."
    end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then
        return false, "Close the Adventure Guide to browse loot here (they share one list)."
    end
    return true
end

local function journal()
    local J = C_EncounterJournal
    local s = {
        tier = EJ_GetCurrentTier and ns.Safe.Call(EJ_GetCurrentTier),
        diff = EJ_GetDifficulty and ns.Safe.Call(EJ_GetDifficulty),
        slot = J and J.GetSlotFilter and ns.Safe.Call(J.GetSlotFilter),
        instance = EncounterJournal and ns.Safe.Num(EncounterJournal.instanceID),
        encounter = EncounterJournal and ns.Safe.Num(EncounterJournal.encounterID),
    }
    if EJ_GetLootFilter then
        local ok, class, spec = pcall(EJ_GetLootFilter)
        if ok then s.class, s.spec = class, spec end
    end
    return s
end

local function restore(s)
    local J = C_EncounterJournal
    if s.tier and EJ_SelectTier then pcall(EJ_SelectTier, s.tier) end
    if s.instance and s.instance > 0 then pcall(EJ_SelectInstance, s.instance) end
    if s.encounter and s.encounter > 0 and EJ_SelectEncounter then pcall(EJ_SelectEncounter, s.encounter) end
    if s.diff and EJ_SetDifficulty then pcall(EJ_SetDifficulty, s.diff) end
    if EJ_SetLootFilter and s.class then pcall(EJ_SetLootFilter, s.class, s.spec or 0) end
    if s.slot and J and J.SetSlotFilter then pcall(J.SetSlotFilter, s.slot) end
end

-- run fn with the journal, then put it back
local function withJournal(fn)
    local ok, why = WL:CanBrowse()
    if not ok then return nil, why end
    local saved = journal()
    local res = { pcall(fn) }
    restore(saved)
    if not res[1] then
        if geterrorhandler then geterrorhandler()(res[2]) end
        return nil, "The Adventure Guide didn't answer - try again."
    end
    return res[2]
end

-- { { tier, name } }, newest last
function WL:Tiers()
    return withJournal(function()
        local out = {}
        for i = 1, EJ_GetNumTiers() or 0 do
            local name = EJ_GetTierInfo and EJ_GetTierInfo(i)
            out[#out + 1] = { tier = i, name = name or ("Tier " .. i) }
        end
        return out
    end)
end

-- { { id, name, raid } }: raids first, then dungeons
function WL:Instances(tier)
    return withJournal(function()
        EJ_SelectTier(tier)
        local out = {}
        for _, raid in ipairs({ true, false }) do
            for i = 1, 60 do
                local id, name = EJ_GetInstanceByIndex(i, raid)
                if not id then break end
                out[#out + 1] = { id = id, name = name or "?", raid = raid }
            end
        end
        return out
    end)
end

function WL:Encounters(instanceID)
    return withJournal(function()
        EJ_SelectInstance(instanceID)
        local out = {}
        for i = 1, 30 do
            local name, _, encounterID = EJ_GetEncounterInfoByIndex(i, instanceID)
            if not name then break end
            out[#out + 1] = { id = encounterID, name = name }
        end
        return out
    end)
end

WL.RAID_DIFFS = { { 17, "Raid Finder" }, { 14, "Normal" }, { 15, "Heroic" }, { 16, "Mythic" } }
WL.DUNGEON_DIFFS = { { 1, "Normal" }, { 2, "Heroic" }, { 23, "Mythic" }, { 8, "Mythic+" } }

-- the difficulties this instance has (from the journal)
function WL:Difficulties(instanceID, raid)
    local list = raid and WL.RAID_DIFFS or WL.DUNGEON_DIFFS
    local valid = withJournal(function()
        EJ_SelectInstance(instanceID)
        local out = {}
        for _, d in ipairs(list) do
            if not EJ_IsValidInstanceDifficulty or EJ_IsValidInstanceDifficulty(d[1]) then out[#out + 1] = d end
        end
        return out
    end)
    return (valid and #valid > 0) and valid or list
end

-- Stats the filter knows (the game's own short names, else English)
WL.STATS = {
    { key = "ITEM_MOD_CRIT_RATING_SHORT", name = "Crit" },
    { key = "ITEM_MOD_HASTE_RATING_SHORT", name = "Haste" },
    { key = "ITEM_MOD_MASTERY_RATING_SHORT", name = "Mastery" },
    { key = "ITEM_MOD_VERSATILITY", name = "Versatility" },
}
for _, s in ipairs(WL.STATS) do
    local g = _G[s.key]
    if type(g) == "string" and g ~= "" then s.name = g end
end

WL.SLOTS = {
    { "head", "Head", { INVTYPE_HEAD = true } },
    { "neck", "Neck", { INVTYPE_NECK = true } },
    { "shoulder", "Shoulder", { INVTYPE_SHOULDER = true } },
    { "back", "Back", { INVTYPE_CLOAK = true } },
    { "chest", "Chest", { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
    { "wrist", "Wrist", { INVTYPE_WRIST = true } },
    { "hands", "Hands", { INVTYPE_HAND = true } },
    { "waist", "Waist", { INVTYPE_WAIST = true } },
    { "legs", "Legs", { INVTYPE_LEGS = true } },
    { "feet", "Feet", { INVTYPE_FEET = true } },
    { "finger", "Ring", { INVTYPE_FINGER = true } },
    { "trinket", "Trinket", { INVTYPE_TRINKET = true } },
    { "weapon", "Weapon", { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
                            INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true } },
    { "offhand", "Off hand / shield", { INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true } },
}
local SLOT_OF = {}
for _, s in ipairs(WL.SLOTS) do for loc in pairs(s[3]) do SLOT_OF[loc] = s[1] end end

function WL.SlotOf(itemID)
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not f then return "other" end
    local ok, _, _, _, loc = pcall(f, itemID)
    return (ok and SLOT_OF[loc]) or "other"
end

function WL.StatsOf(link)
    local f = C_Item and C_Item.GetItemStats or GetItemStats
    local out = {}
    if not (f and link) then return out end
    local ok, t = pcall(f, link)
    if not ok or type(t) ~= "table" then return out end
    for _, s in ipairs(WL.STATS) do if t[s.key] and t[s.key] ~= 0 then out[s.key] = true end end
    return out
end

-- The loot for one instance (+ boss, or nil = every drop) at one difficulty.
-- mySpec: only what your spec can use (the journal's own filter).
-- Returns { { itemID, name, link, icon, encounterID, slot, stats } } or nil, why.
function WL:Loot(instanceID, encounterID, diff, mySpec)
    return withJournal(function()
        EJ_SelectInstance(instanceID)
        if encounterID and EJ_SelectEncounter then EJ_SelectEncounter(encounterID) end
        if diff and EJ_SetDifficulty then EJ_SetDifficulty(diff) end
        if mySpec and EJ_SetLootFilter then
            local _, _, classID = UnitClass("player")
            local spec = GetSpecialization and GetSpecialization()
            local specID = spec and GetSpecializationInfo and GetSpecializationInfo(spec)
            EJ_SetLootFilter(classID or 0, specID or 0)
        elseif EJ_ResetLootFilter then
            EJ_ResetLootFilter()
        end
        local J = C_EncounterJournal
        if J and J.SetSlotFilter and Enum.ItemSlotFilterType and Enum.ItemSlotFilterType.NoFilter then
            J.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
        end
        local out, missing = {}, false
        for i = 1, EJ_GetNumLoot() or 0 do
            local info = J and J.GetLootInfoByIndex and J.GetLootInfoByIndex(i)
            if type(info) == "table" and info.itemID then
                if not info.name or not info.link then missing = true end
                if not encounterID or info.encounterID == encounterID then
                    out[#out + 1] = { itemID = info.itemID, name = info.name or ("item " .. info.itemID), link = info.link,
                                      icon = info.icon, encounterID = info.encounterID, slot = WL.SlotOf(info.itemID),
                                      stats = WL.StatsOf(info.link), quality = info.itemQuality }
                end
            end
        end
        out.missing = missing
        return out
    end)
end

-- the game finished loading some loot: redraw an open wishlist
function WL:LootLoaded()
    local V = ns.WishlistUI
    if V and V.frame and V.frame:IsShown() and V.waitingLoot then V.waitingLoot = nil; V:Reload() end
end

-- does an item pass the filters? f = { search, slot, stats = { [key] = true }, both, onlyMine }
function WL.Passes(item, f)
    if f.onlyMine and not WL:Tag(item.itemID) then return false end
    if f.slot and item.slot ~= f.slot then return false end
    if f.search and f.search ~= "" and not (item.name or ""):lower():find(f.search, 1, true) then return false end
    local want = 0
    for _ in pairs(f.stats or {}) do want = want + 1 end
    if want > 0 then
        local have = 0
        for key in pairs(f.stats) do if item.stats[key] then have = have + 1 end end
        if f.both then return have == want end
        return have > 0
    end
    return true
end
