-- Titan Up - RaidCheck/RaidCheck.lua
-- Raid readiness for Heroic and Mythic raids (never Normal/LFR).
--
-- Every Titan Up player's addon reports on its OWN character (the game
-- always lets an addon read its own buffs, bags and durability; other
-- people's bags and durability can't be read at all):
--   raid buffs, flask, food, weapon enchant (oil / stone / class imbue),
--   Vantus Rune, the weekly raid buff, combat potions, healthstones,
--   lowest item durability.
-- Reports go out on a ready check (automatically) and when a leader or
-- assist types /pull. The /pull check waits ~1 second for reports, then
-- pulls right away if everyone's ready, or shows what's missing with
-- "Pull anyway" / "Cancel".
--
-- Messages ("TitanUpRC"):
--   Q id kind                      "send me your report" (kind: pull / manual)
--   R id buffs flask food weapon vantus weekly pots hs dur   one report
local ADDON, ns = ...

local RC = {}
ns.RaidCheck = RC

local PREFIX = "TitanUpRC"
local SEP = "^"
RC.COLLECT_TIME = 1.2

-- Raid buffs: key, cast spell (for the localized name + icon), English
-- fallback name, providing class.
RC.RAID_BUFFS = {
    { key = "int", spell = 1459, name = "Arcane Intellect", class = "MAGE" },
    { key = "fort", spell = 21562, name = "Power Word: Fortitude", class = "PRIEST" },
    { key = "shout", spell = 6673, name = "Battle Shout", class = "WARRIOR" },
    { key = "motw", spell = 1126, name = "Mark of the Wild", class = "DRUID" },
    { key = "bronze", spell = 364342, name = "Blessing of the Bronze", class = "EVOKER" },
    { key = "sky", spell = 462854, name = "Skyfury", class = "SHAMAN" },
}
-- Current-tier consumables (Midnight). Since 0.37.0 they're matched by
-- item and spell number, so every game language works: each list has the
-- item IDs (both quality ranks), the spells the items use, and the English
-- names as a last resort (an item the client hasn't loaded yet). The names
-- the game gives in your own language are matched too, so a cauldron flask
-- (another item with the same name) still counts. Any food buff counts.
-- (IDs from the 12.1.5 game data.)
RC.FLASKS = { names = { "Flask of Thalassian Resistance", "Flask of the Blood Knights", "Flask of the Magisters", "Flask of the Shattered Sun" },
              items = { 241320, 241321, 241324, 241325, 241322, 241323, 241326, 241327 } }
RC.POTIONS = { names = { "Light's Potential", "Potion of Recklessness", "Potion of Zealotry", "Liquid Luster" },
               items = { 241308, 241309, 241288, 241289, 241296, 241297, 271886, 271887 } }
RC.HEALTH_POTIONS = { names = { "Silvermoon Health Potion", "Concentrated Silvermoon Health Potion" },
                      spells = { 1234768, 1295247 } }
RC.HEALTHSTONES = { names = { "Healthstone", "Demonic Healthstone" }, items = { 5512, 224464 }, spells = { 6262, 452930 },
                    contains = { item = 5512, english = "healthstone" } }       -- any kind of healthstone
-- Auras: a spell whose name (in your language) is the buff's name
RC.WEEKLY = "Fury of the Dead"          -- (no spell number known yet: English clients only)
RC.VANTUS = { spell = 1290561, english = "Vantus Rune" }      -- "Vantus Rune: <boss>": the part before the colon
RC.FOOD = { spells = { 19705, 462209 }, english = { "Well Fed", "Hearty Well Fed" } }

RC.CHECKS = {
    { key = "flask", label = "Flask" },
    { key = "food", label = "Hearty feast food" },
    { key = "weapon", label = "Weapon oil / imbue" },
    { key = "vantus", label = "Vantus Rune" },
    { key = "weekly", label = "Fury of the Dead" },
    { key = "pots", label = "Combat potions (5+)" },
    { key = "hpots", label = "Health potions (5+)" },
    { key = "hs", label = "Healthstone", needsClass = "WARLOCK" },
    { key = "dur", label = "Durability (20%+)" },
}

local function settings() return ns.udb.raidcheck end

-- Heroic and Mythic raids (difficulty IDs): Raid Check, the Pull Report's
-- archive and the Raid Scorecard all count only these.
RC.HEROIC_MYTHIC = { [15] = "Heroic", [16] = "Mythic" }
function RC.HeroicOrMythic(diff) return RC.HEROIC_MYTHIC[diff] ~= nil end

-- ---------------------------------------------------------------------
-- When it applies
-- ---------------------------------------------------------------------
function RC:Active()
    if not IsInRaid() or not ns.DataChannel() then return false end      -- reports travel over your guild channel
    local _, kind, diffID = GetInstanceInfo()
    return kind == "raid" and RC.HeroicOrMythic(diffID)
end

-- Only the raid leader gets the results window (whoever types /pull still
-- gets the pull alert).
function RC:IsLeader() return UnitIsGroupLeader("player") and true or false end

function RC:CanLead()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- ---------------------------------------------------------------------
-- Your own report
-- ---------------------------------------------------------------------
local function spellName(id, fallback)
    local f = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    local ok, name = pcall(f, id)
    return (ok and type(name) == "string" and name) or fallback
end

-- ---------------------------------------------------------------------
-- Names in the player's own language, from the game (item names can take a
-- moment to load: until then the English name stands in)
-- ---------------------------------------------------------------------
local function itemName(id)
    local f = C_Item and C_Item.GetItemNameByID
    local name = f and ns.Safe.Call(f, id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name
end

local spellOf = {}           -- item ID -> the spell it uses (false: none), once known
local function itemSpell(id)
    local known = spellOf[id]
    if known ~= nil then return known or nil end
    local f = C_Item and C_Item.GetItemSpell
    if not f then return nil end
    local ok, name, spellID = pcall(f, id)
    spellID = ok and ns.Safe.Num(spellID) or nil
    if spellID then spellOf[id] = spellID
    elseif ok and name == nil and C_Item.GetItemNameByID and ns.Safe.Call(C_Item.GetItemNameByID, id) then spellOf[id] = false end
    return spellID
end

local function lowerSet(list, out)
    out = out or {}
    for _, n in ipairs(list or {}) do if type(n) == "string" then out[n:lower()] = true end end
    return out
end

-- a list spec -> { ids = {}, spells = {}, names = {} (lowercase), contains = {} (lowercase) }
local matchers = {}
function RC.Matcher(spec)
    local plain = spec[1] ~= nil and not spec.names
    if plain then spec = { names = spec } end          -- a plain list of names (not remembered)
    local m = not plain and matchers[spec]
    if m and m.done then return m end
    m = { ids = {}, spells = {}, names = lowerSet(spec.names), contains = {} }
    local done = true
    for _, id in ipairs(spec.items or {}) do
        m.ids[id] = true
        local n = itemName(id)
        if n then m.names[n:lower()] = true else done = false end
        local sp = itemSpell(id)
        if sp then m.spells[sp] = true end
    end
    for _, id in ipairs(spec.spells or {}) do m.spells[id] = true end
    if spec.contains then
        m.contains[spec.contains.english] = true
        local n = itemName(spec.contains.item)
        if n then m.contains[n:lower()] = true else done = false end
    end
    -- only remembered once every name has loaded (or there's no item API at all)
    m.done = done or not (C_Item and C_Item.GetItemNameByID)
    if not plain then matchers[spec] = m end
    m.plain = plain
    return m
end

-- does a bag item (id, link) match?
function RC.Matches(m, id, lname)
    if id and m.ids[id] then return true end
    if lname then
        if m.names[lname] then return true end
        for part in pairs(m.contains) do if lname:find(part, 1, true) then return true end end
    end
    if id and next(m.spells) then
        local sp = itemSpell(id)
        if sp and m.spells[sp] then return true end
    end
    return false
end

-- localized buff names from spell IDs (+ English)
local function spellNames(spells, english)
    local out = lowerSet(type(english) == "table" and english or { english })
    for _, id in ipairs(spells or {}) do
        local n = spellName(id)
        if n then out[n:lower()] = true end
    end
    return out
end

-- "Vantus Rune" in your language: the part of a Vantus Rune buff's name before the colon
local function vantusPrefix()
    local n = spellName(RC.VANTUS.spell)
    local p = n and n:match("^(.-)%s*[:：]")
    return (p and p ~= "" and p:lower()) or RC.VANTUS.english:lower()
end

local function playerAuras()
    local list = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list end
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if ns.Safe.Text(a.name) and ns.Safe.Num(a.spellId) then list[#list + 1] = a end
    end
    return list
end

-- The plain item name from a link. Crafted items carry their quality icon
-- inside the name ("[Light's Potential |A:...Tier2...|a]"), and links can
-- hold texture/color codes too - strip all of that before comparing.
function RC.ItemName(link)
    local inner = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
    if not inner then return nil end
    inner = inner:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (inner:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- How many of each list's items are in your bags (any quality), and their
-- item IDs - every list in one pass over the bags:
-- RC.BagCounts({ pots = RC.POTIONS, hs = RC.HEALTHSTONES }) -> { pots = { count, ids }, ... }.
-- A list is a spec like RC.POTIONS (item IDs, spells, names) or a plain
-- list of names; asking for "Healthstone" by name counts every kind.
function RC.BagCounts(lists)
    local ms, out = {}, {}
    for key, spec in pairs(lists) do
        out[key] = { count = 0, ids = {} }
        local m = RC.Matcher(spec)
        if m.plain and m.names.healthstone then m.contains.healthstone = true end
        ms[key] = m
    end
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local name = info.hyperlink and RC.ItemName(info.hyperlink)
                local lname = name and name:lower()
                for key, m in pairs(ms) do
                    if RC.Matches(m, info.itemID, lname) then
                        local o = out[key]
                        o.count = o.count + (info.stackCount or 1)
                        if info.itemID then o.ids[info.itemID] = true end
                    end
                end
            end
        end
    end
    return out
end

-- one list: count, ids
function RC.BagCount(names)
    local o = RC.BagCounts({ x = names }).x
    return o.count, o.ids
end

local function lowestDurability()
    local low = 100
    for slot = 1, 17 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then low = math.min(low, math.floor(cur / max * 100)) end
    end
    return low
end

function RC:Snapshot()
    local auras = playerAuras()
    local byName = {}
    for _, a in ipairs(auras) do byName[a.name] = a end
    local buffs = {}
    for i, b in ipairs(self.RAID_BUFFS) do
        buffs[i] = byName[spellName(b.spell, b.name)] and "1" or "0"
    end
    local flask, food, vantus, weekly = 0, 0, 0, 0
    local flasks = RC.Matcher(self.FLASKS)
    local foods = spellNames(self.FOOD.spells, self.FOOD.english)
    local runePrefix = vantusPrefix()
    for _, a in ipairs(auras) do
        local lname = a.name:lower()
        if flasks.spells[a.spellId] or flasks.names[lname] then flask = a.spellId end
        if foods[lname] then food = a.spellId
        else
            for f in pairs(foods) do if lname:find(f, 1, true) then food = a.spellId break end end
        end
        if lname:sub(1, #runePrefix) == runePrefix then vantus = 1 end
        if a.name == self.WEEKLY then weekly = 1 end
    end
    -- Weapon oil / stone on the main hand. GetWeaponEnchantInfo was removed
    -- in 12.1.0; C_PaperDollInfo.GetTemporaryEnchantmentInfo returns a table,
    -- or nothing when there's no temporary enchant. Old call kept as fallback.
    local hasMain
    if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, INVSLOT_MAINHAND or 16)
        hasMain = ok and type(info) == "table"
    elseif GetWeaponEnchantInfo then
        hasMain = GetWeaponEnchantInfo()
    end
    local bags = RC.BagCounts({ pots = self.POTIONS, hs = self.HEALTHSTONES, hpots = self.HEALTH_POTIONS })
    return {
        buffs = table.concat(buffs), flask = flask, food = food, weapon = hasMain and 1 or 0,
        vantus = vantus, weekly = weekly, pots = bags.pots.count, hs = bags.hs.count, hpots = bags.hpots.count,
        dur = lowestDurability(),
    }
end

local function encode(id, s)
    return table.concat({ "R", id, s.buffs, s.flask, s.food, s.weapon, s.vantus, s.weekly, s.pots, s.hs, s.dur, s.hpots or 0 }, SEP)
end

local function decode(f)
    return {
        buffs = f[3] or "", flask = tonumber(f[4]) or 0, food = tonumber(f[5]) or 0, weapon = tonumber(f[6]) or 0,
        vantus = tonumber(f[7]) or 0, weekly = tonumber(f[8]) or 0, pots = tonumber(f[9]) or 0,
        hs = tonumber(f[10]) or 0, dur = tonumber(f[11]) or 100, hpots = tonumber(f[12]) or 0,
    }
end

-- ---------------------------------------------------------------------
-- Messaging + collecting
-- ---------------------------------------------------------------------
function RC:Send(...)
    if IsInGroup() then ns.SendFields(PREFIX, ...) end
end

RC.current = nil      -- { id, kind, by, t, reports = { [name] = report }, watching }

function RC:NewCheck(kind, by)
    local id = ns.Short(by) .. tostring(math.floor(GetTime() * 10) % 100000)
    self.current = { id = id, kind = kind, by = by, t = time(), reports = {} }
    self.current.reports[ns.me] = self:Snapshot()
    return self.current
end

function RC:Init()
    ns.Listen(PREFIX, "group", function(text, sender) RC:OnMessage(text, sender) end)
    -- Ready check: everyone reports on their own; only the raid leader sees
    -- the results.
    ns.On("READY_CHECK", function(initiator)
        if not RC:Active() then return end
        local by = ns.NormalizeSender(ns.Safe.Text(initiator)) or ns.LeaderName() or "?"
        local check = RC:NewCheck("ready", by)
        check.id = "rc"                     -- everyone uses the same id for a ready check
        RC:Send(encode("rc", check.reports[ns.me]))
        if RC:IsLeader() and ns.RaidCheckUI then ns.RaidCheckUI:ShowResults(true) end
    end)
    ns.On("ENCOUNTER_START", function()
        if ns.RaidCheckUI then ns.RaidCheckUI:CloseAll() end
    end)
    ns.On("ADDON_LOADED", function() RC:HookPull() end)
    ns.On("PLAYER_ENTERING_WORLD", function() RC:HookPull() end)
    self:HookPull()
end

-- the raid leader or an assist (only they ask for checks)
local function leads(name)
    local unit = ns.UnitForName(name)
    return unit and (ns.Safe.Call(UnitIsGroupLeader, unit) or ns.Safe.Call(UnitIsGroupAssistant, unit)) and true or false
end

function RC:OnMessage(text, sender)
    local f = ns.Split(text, SEP)
    local kind, id = f[1], f[2]
    if not id or id == "" or #id > 40 then return end
    if kind == "Q" then
        if not self:Active() or not leads(sender) then return end
        -- the leader or an assist asked: record their check locally and answer
        local check = { id = id, kind = f[3] or "manual", by = sender, t = time(), reports = {} }
        check.reports[ns.me] = self:Snapshot()
        self.current = check
        self:Send(encode(id, check.reports[ns.me]))
        if RC:IsLeader() and ns.RaidCheckUI then ns.RaidCheckUI:ShowResults(true) end
    elseif kind == "R" then
        local c = self.current
        if c and c.id == id then
            c.reports[sender] = decode(f)
            if ns.RaidCheckUI then ns.RaidCheckUI:OnReport() end
        end
    end
end

function RC:RequestCheck(kind)
    local check = self:NewCheck(kind, ns.me)
    self:Send("Q", check.id, kind)
    return check
end

-- ---------------------------------------------------------------------
-- Evaluating a check
-- ---------------------------------------------------------------------
-- The raid roster with classes: { { name, class }, ... }
function RC:Roster()
    local out = {}
    for _, m in ipairs(ns.GroupRoster()) do
        out[#out + 1] = { name = m.name, class = ns.ClassOf(m.name), online = m.online }
    end
    return out
end

-- Returns { total, buffs = { {def, have, missing = {names}} },
--           checks = { {def, have, missing} }, noReply = {names}, issues = n }
function RC:Evaluate(check)
    check = check or self.current
    if not check then return nil end
    local s = settings()
    local roster = self:Roster()
    local classes = {}
    for _, m in ipairs(roster) do if m.class then classes[m.class] = true end end
    local result = { total = #roster, buffs = {}, checks = {}, noReply = {}, issues = 0 }
    local function row(def)
        return { def = def, have = 0, missing = {} }
    end
    for i, b in ipairs(self.RAID_BUFFS) do
        if classes[b.class] then
            local r = row(b)
            r.index = i
            result.buffs[#result.buffs + 1] = r
        end
    end
    for _, c in ipairs(self.CHECKS) do
        if not c.needsClass or classes[c.needsClass] then result.checks[#result.checks + 1] = row(c) end
    end
    for _, m in ipairs(roster) do
        local rep = check.reports[m.name]
        if not rep then
            result.noReply[#result.noReply + 1] = m.name
            for _, r in ipairs(result.buffs) do r.missing[#r.missing + 1] = m.name end
            for _, r in ipairs(result.checks) do r.missing[#r.missing + 1] = m.name end
        else
            for _, r in ipairs(result.buffs) do
                if rep.buffs:sub(r.index, r.index) == "1" then r.have = r.have + 1 else r.missing[#r.missing + 1] = m.name end
            end
            for _, r in ipairs(result.checks) do
                local k, ok = r.def.key, false
                if k == "flask" then ok = rep.flask ~= 0          -- any current-tier flask, any quality / cauldron
                elseif k == "food" then ok = rep.food ~= 0        -- any food buff
                elseif k == "weapon" then ok = rep.weapon == 1
                elseif k == "vantus" then ok = rep.vantus == 1
                elseif k == "weekly" then ok = rep.weekly == 1
                elseif k == "pots" then ok = rep.pots >= s.potMin
                elseif k == "hpots" then ok = rep.hpots >= s.hpotMin
                elseif k == "hs" then ok = rep.hs >= 1
                elseif k == "dur" then ok = rep.dur >= s.durMin end
                if ok then r.have = r.have + 1 else r.missing[#r.missing + 1] = m.name end
            end
        end
    end
    for _, list in ipairs({ result.buffs, result.checks }) do
        for _, r in ipairs(list) do
            table.sort(r.missing)
            if #r.missing > 0 then result.issues = result.issues + 1 end
        end
    end
    table.sort(result.noReply)
    return result
end

-- ---------------------------------------------------------------------
-- /pull: check first, then pull (or ask)
-- ---------------------------------------------------------------------
RC.SCAN_GAP = 5              -- look for /pull at most this often (addons load in bursts)

function RC:HookPull()
    if self.pullHooked then return end
    local now = GetTime()
    if self.scannedAt and now - self.scannedAt < RC.SCAN_GAP then
        if not self.scanQueued then
            self.scanQueued = true
            C_Timer.After(RC.SCAN_GAP - (now - self.scannedAt), function() RC.scanQueued = nil; RC:HookPull() end)
        end
        return
    end
    self.scannedAt = now
    for key, fn in pairs(SlashCmdList) do
        for i = 1, 12 do
            local cmd = _G["SLASH_" .. key .. i]
            if not cmd then break end
            if type(cmd) == "string" and cmd:lower() == "/pull" and type(fn) == "function" and key ~= "TITANUPPULL" then
                self.pullHooked = key
                SlashCmdList[key] = function(msg, editBox)
                    RC:OnPull(msg, function() fn(msg, editBox) end)
                end
                if hash_SlashCmdList then hash_SlashCmdList["/PULL"] = SlashCmdList[key] end
                return
            end
        end
    end
end

local function allReady(result) return result.issues == 0 and #result.noReply == 0 end

function RC:OnPull(msg, doPull)
    if not (settings().pullCheck and self:Active() and self:CanLead()) or InCombatLockdown() then
        return doPull()
    end
    if self.pendingPull then return end
    local check = self:RequestCheck("pull")
    self.pendingPull = true
    C_Timer.After(self.COLLECT_TIME, function()
        RC.pendingPull = nil
        local result = RC:Evaluate(check)
        if allReady(result) or not ns.RaidCheckUI then doPull()
        else ns.RaidCheckUI:ShowPullAlert(result, msg, doPull) end
    end)
end
