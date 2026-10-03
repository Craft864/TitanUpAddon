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
-- Current-tier consumables (Midnight). Matched by name so every quality
-- rank counts; flask/food quality is checked against "approved" buffs
-- the raid leader teaches with the Learn button.
RC.FLASKS = { "Flask of Thalassian Resistance", "Flask of the Blood Knights", "Flask of the Magisters", "Flask of the Shattered Sun" }
RC.POTIONS = { "Light's Potential", "Potion of Recklessness" }
RC.WEEKLY = "Fury of the Dead"
RC.VANTUS = "Vantus Rune"
RC.FOOD = "Well Fed"

RC.CHECKS = {
    { key = "flask", label = "Flask" },
    { key = "food", label = "Hearty feast food" },
    { key = "weapon", label = "Weapon oil / imbue" },
    { key = "vantus", label = "Vantus Rune" },
    { key = "weekly", label = "Fury of the Dead" },
    { key = "pots", label = "Combat potions (10+)" },
    { key = "hs", label = "Healthstone", needsClass = "WARLOCK" },
    { key = "dur", label = "Durability (20%+)" },
}

local function settings() return ns.udb.raidcheck end
local function bad(v) return v == nil or ns.IsSecret(v) end

-- ---------------------------------------------------------------------
-- When it applies
-- ---------------------------------------------------------------------
function RC:Active()
    if not IsInRaid() then return false end
    local _, kind, diffID = GetInstanceInfo()
    return kind == "raid" and (diffID == 15 or diffID == 16)    -- Heroic / Mythic
end

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

local function playerAuras()
    local list = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return list end
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if not bad(a.name) and not bad(a.spellId) then list[#list + 1] = a end
    end
    return list
end

local function bagCount(names)
    local want = {}
    for _, n in ipairs(names) do want[n:lower()] = true end
    local total = 0
    if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
    for bag = 0, 5 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            local name = link and link:match("%[(.-)%]")
            if name then
                local lname = name:lower()
                if want[lname] then total = total + (info.stackCount or 1)
                elseif want.healthstone and lname:find("healthstone", 1, true) then total = total + (info.stackCount or 1) end
            end
        end
    end
    return total
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
    local flaskNames = {}
    for _, n in ipairs(self.FLASKS) do flaskNames[n] = true end
    for _, a in ipairs(auras) do
        if flaskNames[a.name] then flask = a.spellId end
        if a.name == self.FOOD or a.name:find(self.FOOD, 1, true) then food = a.spellId end
        if a.name:find(self.VANTUS, 1, true) then vantus = 1 end
        if a.name == self.WEEKLY then weekly = 1 end
    end
    local hasMain = GetWeaponEnchantInfo and GetWeaponEnchantInfo()
    return {
        buffs = table.concat(buffs), flask = flask, food = food, weapon = hasMain and 1 or 0,
        vantus = vantus, weekly = weekly, pots = bagCount(self.POTIONS), hs = bagCount({ "Healthstone" }),
        dur = lowestDurability(),
    }
end

local function encode(id, s)
    return table.concat({ "R", id, s.buffs, s.flask, s.food, s.weapon, s.vantus, s.weekly, s.pots, s.hs, s.dur }, SEP)
end

local function decode(f)
    return {
        buffs = f[3] or "", flask = tonumber(f[4]) or 0, food = tonumber(f[5]) or 0, weapon = tonumber(f[6]) or 0,
        vantus = tonumber(f[7]) or 0, weekly = tonumber(f[8]) or 0, pots = tonumber(f[9]) or 0,
        hs = tonumber(f[10]) or 0, dur = tonumber(f[11]) or 100,
    }
end

-- ---------------------------------------------------------------------
-- Messaging + collecting
-- ---------------------------------------------------------------------
function RC:Send(...)
    if ns.InLockdown() or not IsInGroup() then return end
    local ch = ns.GroupChannel()
    if ch then pcall(C_ChatInfo.SendAddonMessage, PREFIX, table.concat({ ... }, SEP), ch) end
end

RC.current = nil      -- { id, kind, by, t, reports = { [name] = report }, watching }

function RC:NewCheck(kind, by)
    local id = ns.Short(by) .. tostring(math.floor(GetTime() * 10) % 100000)
    self.current = { id = id, kind = kind, by = by, t = time(), reports = {} }
    self.current.reports[ns.me] = self:Snapshot()
    return self.current
end

function RC:Init()
    ns.udb.raidcheck = ns.udb.raidcheck or {}
    local s = ns.udb.raidcheck
    s.approved = s.approved or { flask = {}, food = {} }
    s.potMin = s.potMin or 10
    s.durMin = s.durMin or 20
    if s.pullCheck == nil then s.pullCheck = true end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
        if prefix ~= PREFIX or bad(text) or bad(sender) then return end
        sender = ns.NormalizeSender(sender)
        if sender and sender ~= ns.me then RC:OnMessage(text, sender) end
    end)
    -- Ready check: everyone reports on their own; the initiator and the
    -- raid leader see the results.
    ns.On("READY_CHECK", function(initiator)
        if not RC:Active() then return end
        local by = (not bad(initiator) and ns.NormalizeSender(initiator)) or ns.LeaderName() or ns.me
        local check = RC:NewCheck("ready", by)
        check.id = "rc"                     -- everyone uses the same id for a ready check
        RC:Send(encode("rc", check.reports[ns.me]))
        if by == ns.me or UnitIsGroupLeader("player") then
            if ns.RaidCheckUI then ns.RaidCheckUI:ShowResults() end
        end
    end)
    ns.On("ADDON_LOADED", function() RC:HookPull() end)
    ns.On("PLAYER_ENTERING_WORLD", function() RC:HookPull() end)
    self:HookPull()
end

function RC:OnMessage(text, sender)
    local f = ns.Split(text, SEP)
    local kind, id = f[1], f[2]
    if kind == "Q" then
        if not self:Active() then return end
        -- someone (leader/assist) asked: record their check locally and answer
        local check = { id = id, kind = f[3] or "manual", by = sender, t = time(), reports = {} }
        check.reports[ns.me] = self:Snapshot()
        self.current = check
        self:Send(encode(id, check.reports[ns.me]))
        if UnitIsGroupLeader("player") and ns.RaidCheckUI then ns.RaidCheckUI:ShowResults() end
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

local function approvedOrAny(list, id)
    if id == 0 then return false end
    if not next(list) then return true end          -- nothing learned: any counts
    return list[id] == true
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
                if k == "flask" then ok = approvedOrAny(s.approved.flask, rep.flask)
                elseif k == "food" then ok = approvedOrAny(s.approved.food, rep.food)
                elseif k == "weapon" then ok = rep.weapon == 1
                elseif k == "vantus" then ok = rep.vantus == 1
                elseif k == "weekly" then ok = rep.weekly == 1
                elseif k == "pots" then ok = rep.pots >= s.potMin
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
-- Approved flask / food (taught by the raid leader)
-- ---------------------------------------------------------------------
function RC:LearnApproved()
    local s = settings()
    local flaskNames = {}
    for _, n in ipairs(self.FLASKS) do flaskNames[n] = true end
    local learned = {}
    for _, a in ipairs(playerAuras()) do
        if flaskNames[a.name] and not s.approved.flask[a.spellId] then
            s.approved.flask[a.spellId] = true
            learned[#learned + 1] = a.name .. " (" .. a.spellId .. ")"
        elseif a.name:find(self.FOOD, 1, true) and not s.approved.food[a.spellId] then
            s.approved.food[a.spellId] = true
            learned[#learned + 1] = a.name .. " (" .. a.spellId .. ")"
        end
    end
    if #learned == 0 then
        ns.Print("No new flask or food buff found on you. Eat the feast / take the flask first, then click Learn.")
    else
        ns.Print("Approved: " .. table.concat(learned, ", "))
    end
    return #learned
end

function RC:ResetApproved()
    settings().approved = { flask = {}, food = {} }
    ns.Print("Approved flask/food cleared - any current-tier flask and any food buff count until you Learn again.")
end

-- ---------------------------------------------------------------------
-- /pull: check first, then pull (or ask)
-- ---------------------------------------------------------------------
function RC:HookPull()
    if self.pullHooked then return end
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
        if result.issues == 0 and #result.noReply == 0 then
            doPull()
        elseif ns.RaidCheckUI then
            ns.RaidCheckUI:ShowPullAlert(result, msg, doPull)
        else
            doPull()
        end
    end)
end
