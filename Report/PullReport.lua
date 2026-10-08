-- Titan Up - Report/PullReport.lua
-- Pull Report (Raid Tools, raids only): who died each pull, and whether
-- they had a defensive, a health potion or a healthstone ready.
--   * Each player's own Titan Up records only its own player (all Midnight
--     lets an addon see): at death - which defensives were ready (from
--     ReportData, talent replacements resolved, tanks skipped), potions and
--     healthstones in the bags and off cooldown, and the last few hits from
--     the death recap. Cheat-death saves ("close calls") are recorded too.
--   * After the encounter, out of combat, each player sends their records
--     over the guild channel. The raid leader's report pops up after each
--     pull (others can turn that on). Raiders without Titan Up show as
--     "no data".
--   * Tonight's pulls are kept until the daily reset, with a scorecard and
--     a "Copy for Discord" export.
-- Nothing runs outside raid encounters, and the window is built on first use.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local D = ns.ReportData

local PR = {}
ns.PullReport = PR

local PREFIX = "TitanUpPR"
local CHUNK = 200
local MAX_HITS = 5

local function db() return ns.udb.pullReport end

-- ---------------------------------------------------------------------
-- Session (tonight's pulls)
-- ---------------------------------------------------------------------
local function today()
    if ns.Wowdle and ns.Wowdle.Today then return ns.Wowdle.Today() end
    return date("%Y%m%d")
end

function PR:Session()
    local d = db()
    local t = today()
    if not d.session or d.session.day ~= t then d.session = { day = t, pulls = {} } end
    return d.session
end

function PR:Init()
    local d = db()
    -- one time (0.25.2): the old default "When I'm raid leader" was saved for
    -- everyone; switch it to the new default once. Later choices are kept.
    if not d.popupReset then
        if d.popup == "leader" then d.popup = "never" end
        d.popupReset = true
    end
    ns.On("ENCOUNTER_START", function(id, name, diff, size) PR:OnEncounterStart(id, name, diff, size) end)
    ns.On("ENCOUNTER_END", function(id, name, diff, size, success) PR:OnEncounterEnd(id, name, diff, size, success) end)
    ns.On("PLAYER_DEAD", function() PR:OnPlayerDead() end)
    ns.On("UNIT_DIED", function(guid) PR:OnUnitDied(guid) end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if PR.outbox then C_Timer.After(1, function() PR:Flush() end) end
        if PR.wipeOut then C_Timer.After(1.5, function() PR:FlushWipe() end) end
    end)
    ns.Listen(PREFIX, "group", function(msg, sender) PR:OnMessage(msg, sender) end)
end

-- ---------------------------------------------------------------------
-- Your defensives, potions and healthstones
-- ---------------------------------------------------------------------
local function known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    return false
end

function PR.IsTank()
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
    return role == "TANK"
end

-- The defensives this character actually has right now: each entry resolves
-- to the one spell you know (talent replacements followed), or is skipped.
function PR.ResolveDefensives()
    local _, class = UnitClass("player")
    local out, skipped = {}, {}
    if PR.IsTank() then return out, skipped, true end
    for _, e in ipairs(D.DEFENSIVES[class] or {}) do
        local use
        for _, id in ipairs(e.ids) do
            local over = C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(id)
            if over and over ~= id and known(over) then use = over; break end
            if known(id) then use = id; break end
        end
        if use then
            local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(use)
            out[#out + 1] = { id = use, name = (type(nm) == "string" and nm ~= "") and nm or e.name, tier = e.tier }
        else
            skipped[#skipped + 1] = e
        end
    end
    return out, skipped, false
end

-- Other big cooldowns (like the analysis recorders track): every active,
-- on-spec spell in your spellbook with a 1-5 minute base cooldown that isn't
-- already on the defensive list. Shown as "other cooldowns ready" - never
-- lights the D square. Capped so it stays light.
local MAX_OTHER = 15
function PR.ScanOtherCooldowns(defs)
    local out = {}
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo and GetSpellBaseCooldown) then return out end
    local skip = {}
    for _, e in ipairs(D.DEFENSIVES[select(2, UnitClass("player"))] or {}) do for _, id in ipairs(e.ids) do skip[id] = true end end
    for _, d in ipairs(defs or {}) do skip[d.id] = true end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, SB.GetNumSpellBookSkillLines() do
        local info = SB.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide then
            for idx = (info.itemIndexOffset or 0) + 1, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0) do
                local item = SB.GetSpellBookItemInfo(idx, bank)
                local id = item and item.spellID
                local offSpec = SB.IsSpellBookItemOffSpec and SB.IsSpellBookItemOffSpec(idx, bank)
                if id and not ns.IsSecret(id) and not skip[id] and not offSpec and not (item.isPassive) then
                    local cd = GetSpellBaseCooldown(id)
                    if type(cd) == "number" and cd >= 60000 and cd <= 300000 then
                        local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                        out[#out + 1] = { id = id, name = (type(nm) == "string" and nm ~= "") and nm or tostring(id), tier = "other" }
                        skip[id] = true
                        if #out >= MAX_OTHER then return out end
                    end
                end
            end
        end
    end
    return out
end

-- Ready right now? true / false, or nil when the game won't say.
-- Like the analysis recorders that work in Midnight: the cooldown's
-- isActive / isOnGCD flags (still readable when the start time and duration
-- are hidden mid-fight); charges first for charge-based spells.
function PR.Ready(id)
    local ch = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
    if type(ch) == "table" and type(ch.currentCharges) == "number" and not ns.IsSecret(ch.currentCharges)
        and not ns.IsSecret(ch.maxCharges) and (ch.maxCharges or 1) > 1 then
        return ch.currentCharges > 0
    end
    local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
    if type(cd) ~= "table" then return nil end
    if cd.isActive ~= nil then
        if ns.IsSecret(cd.isActive) or ns.IsSecret(cd.isOnGCD) then return nil end
        return (not cd.isActive) or (cd.isOnGCD == true)
    end
    -- older clients without the flags: work it out from the timings
    local start, dur = cd.startTime, cd.duration
    if ns.IsSecret(start) or ns.IsSecret(dur) or type(dur) ~= "number" then return nil end
    if dur == 0 or dur <= 1.5 then return true end
    return (start + dur) <= GetTime() + 0.05
end

local bagItems = ns.RaidCheck.BagCount

local function itemReady(ids)
    for id in pairs(ids) do
        local start, dur = C_Container.GetItemCooldown(id)
        if type(start) == "number" and type(dur) == "number" and not ns.IsSecret(dur) then
            if dur == 0 or dur <= 1.5 or start + dur <= GetTime() + 0.05 then return true end
        end
    end
    return false
end

-- Potions share one cooldown, read through the health potion's spell;
-- healthstones through the healthstone spell (Demonic Healthstone if talented).
D.HEALTH_POTION_SPELL = 1295247
D.HEALTHSTONE_SPELL, D.DEMONIC_HEALTHSTONE_SPELL, D.DEMONIC_TALENT = 6262, 452930, 386689

function PR.Consumables()
    local pc, pids = bagItems(D.HEALTH_POTIONS)
    local hc, hids = bagItems(D.HEALTHSTONES)
    local function ready(count, spell, ids)
        if count <= 0 then return false end
        local r = PR.Ready(spell)
        if r ~= nil then return r end
        return itemReady(ids)                         -- fallback: the item's own cooldown
    end
    local demonic = known(D.DEMONIC_TALENT)
    return { pc = pc, pr = ready(pc, D.HEALTH_POTION_SPELL, pids),
             hc = hc, hr = ready(hc, demonic and D.DEMONIC_HEALTHSTONE_SPELL or D.HEALTHSTONE_SPELL, hids) }
end

-- ---------------------------------------------------------------------
-- During a raid encounter
-- ---------------------------------------------------------------------
function PR:OnEncounterStart(id, name, diff, size)
    if not ns.InRaidInstance() then return end
    local s = self:Session()
    local pull = { enc = id, name = (not ns.IsSecret(name)) and name or "Encounter", diff = diff, start = GetServerTime(),
                   t0 = GetTime(), deaths = {}, n = #s.pulls + 1 }
    -- who was there, and who led (for the Raid Scorecard and wipe-call marks)
    pull.roster = ns.GroupNames()
    if #pull.roster == 0 then pull.roster = { ns.me } end
    pull.leader = ns.LeaderName() or ns.me
    table.insert(s.pulls, pull)
    self.current, self.mine, self.auraSeen = pull, {}, {}
    self.defs = self.ResolveDefensives()
    self.others = self.ScanOtherCooldowns(self.defs)
    self:WatchAuras(true)
    self:SampleHealth(true)
    -- cast history: when each defensive / big cooldown was used / became ready again
    self.history = {}
    for _, list in ipairs({ self.defs, self.others }) do
        for _, dft in ipairs(list) do self.history[dft.name] = { since = (PR.Ready(dft.id) == true) and 0 or nil } end
    end
    self:WatchCasts(true)
end

function PR:OnEncounterEnd(id, name, diff, size, success)
    local pull = self.current
    if not pull then return end
    pull.dur = GetTime() - pull.t0
    pull.t0 = nil
    if not ns.IsSecret(success) then pull.result = (success == 1 or success == true) and "kill" or "wipe" end
    self.current = nil
    self:WatchAuras(false)
    self:SampleHealth(false)
    self:WatchCasts(false)
    if PR.IsShort(pull) then
        -- under 20 seconds and not a kill (a reset or a bad pull): not
        -- counted anywhere, and it gives its pull number back. Only tallied,
        -- so you can see how often it happened.
        local s = self:Session()
        for i = #s.pulls, 1, -1 do if s.pulls[i] == pull then table.remove(s.pulls, i) end end
        s.short = (s.short or 0) + 1
        self.mine, self.pendingSummary = nil, nil
        if ns.RaidScorecard and ns.RaidScorecard.CountShort and (pull.diff == 15 or pull.diff == 16) then
            ns.RaidScorecard:CountShort(pull)
        end
        local V = ns.PullReportUI
        if V then
            if V.pull == pull then V.pull, V.death = nil, nil end
            if V:IsShown() then V:Refresh() end
        end
        return
    end
    if self.pendingSummary then
        local rec = self.pendingSummary
        self.pendingSummary = nil
        C_Timer.After(1, function() PR:ShowSummary(rec) end)       -- held back for a battle rez: shown once, now
    end
    if self.mine and #self.mine > 0 then
        self.outbox = { key = pull.enc .. ":" .. pull.start, recs = self.mine }
        if not InCombatLockdown() then C_Timer.After(1, function() PR:Flush() end) end
    end
    self.mine = nil
    self:Archive(pull)
    if self:ShouldPopup() then C_Timer.After(4, function() if ns.PullReportUI then ns.PullReportUI:ShowPull(pull) end end) end
end

-- Pulls shorter than this (that aren't kills) aren't counted.
PR.MIN_PULL = 20
function PR.IsShort(pull)
    return pull.result ~= "kill" and (pull.dur or 0) < PR.MIN_PULL
end

function PR:ShouldPopup()
    local p = db().popup
    if p == "never" then return false end
    if p == "always" then return true end
    return UnitIsGroupLeader and UnitIsGroupLeader("player") or false
end

-- Recap: the last few hits you took (from the game's death recap)
local function recapEvents()
    local ok, events = pcall(C_DeathRecap and C_DeathRecap.GetRecapEvents)
    if ok and type(events) == "table" and #events > 0 then return events end
end

-- identifies a recap (its newest event), so an old one isn't reused
function PR.RecapSignature()
    local events = recapEvents()
    if not events then return nil end
    local best
    for _, e in ipairs(events) do
        if type(e.timestamp) == "number" and not ns.IsSecret(e.timestamp) and (not best or e.timestamp > best.timestamp) then best = e end
    end
    if not best then return nil end
    return ("%.3f:%s"):format(best.timestamp, tostring(not ns.IsSecret(best.amount) and best.amount or "?"))
end

function PR.ReadRecap(window)
    local events = recapEvents()
    if not events or events[1].overkill == -1 then return {} end              -- none, or no real death entry
    local hits, last = {}, nil
    for _, e in ipairs(events) do
        local ts, amt = e.timestamp, e.amount
        if type(ts) == "number" and not ns.IsSecret(ts) then last = math.max(last or ts, ts) end
        if type(amt) == "number" and not ns.IsSecret(amt) and amt > 0 then
            local spell = (type(e.spellName) == "string" and not ns.IsSecret(e.spellName)) and e.spellName or "Melee"
            local src = (type(e.sourceName) == "string" and not ns.IsSecret(e.sourceName)) and e.sourceName or ""
            hits[#hits + 1] = { ts = ts, spell = spell, amount = amt, src = src }
        end
    end
    table.sort(hits, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    local out = {}
    for _, h in ipairs(hits) do
        local t = (last and h.ts) and (h.ts - last) or 0
        if window then
            if t >= -window then out[#out + 1] = { t = t, spell = h.spell, amount = h.amount, src = h.src } end
        elseif #out < MAX_HITS then
            out[#out + 1] = { t = t, spell = h.spell, amount = h.amount, src = h.src }
        end
    end
    return out
end

function PR:Snapshot(kind, saver)
    local pull = self.current
    if not pull then return end
    local _, class = UnitClass("player")
    local rec = { kind = kind, ft = GetTime() - (pull.t0 or GetTime()), major = {}, minor = {}, saver = saver, hits = {}, class = class }
    rec.active, rec.unknown, rec.cds = {}, {}, {}
    for _, dft in ipairs(self.defs or {}) do
        local ready = PR.Ready(dft.id)
        if PR.Active(dft) then rec.active[#rec.active + 1] = dft.name
        elseif ready == true then table.insert(rec[dft.tier] or rec.minor, dft.name)
        elseif ready == nil then rec.unknown[#rec.unknown + 1] = dft.name end           -- the game wouldn't say
        local h = self.history and self.history[dft.name]
        if h then
            if ready == true and not h.since then h.since = rec.ft end
            rec.cds[#rec.cds + 1] = { name = dft.name, used = h.used, since = (ready == true) and h.since or nil }
        end
    end
    rec.other = {}
    for _, oc in ipairs(self.others or {}) do
        local ready = PR.Ready(oc.id)
        if ready == true then rec.other[#rec.other + 1] = oc.name end
        local h = self.history and self.history[oc.name]
        if h and (h.used or ready == true) then
            if ready == true and not h.since then h.since = rec.ft end
            rec.cds[#rec.cds + 1] = { name = oc.name, used = h.used, since = (ready == true) and h.since or nil, other = true }
        end
    end
    local c = PR.Consumables()
    rec.pc, rec.pr, rec.hc, rec.hr = c.pc, c.pr, c.hc, c.hr
    rec.tank = PR.IsTank()
    table.insert(self.mine, rec)
    self:AddDeath(pull, ns.me, rec)
    if kind == "death" then
        -- the death recap fills in a moment after dying - but only a NEW one:
        -- the game keeps the last recap until you die again
        local function fill()
            local h = PR.ReadRecap()
            if #h == 0 then return end
            local sig = PR.RecapSignature()
            if sig and sig == PR.lastRecapSig and not rec.recapSig then return end      -- an old death's recap
            rec.recapSig = sig
            rec.hits = h
            local w = PR.ReadRecap(5)
            if #w > 0 then rec.last5 = w end
            PR.lastRecapSig = sig
        end
        C_Timer.After(0.5, fill)
        C_Timer.After(1.5, fill)
        if db().personal then
            rec.health = self:HealthStrip()
            if PR.BattleRezReady() then
                self.pendingSummary = rec                                -- a rez may be coming: show it when the pull ends
            else
                C_Timer.After(1.7, function() PR:ShowSummary(rec) end)
            end
        end
    end
    return rec
end

-- Was this defensive running on you (its buff up) at the moment of death?
function PR.Active(dft)
    if not C_UnitAuras then return false end
    if C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, dft.id)
        if ok and a then return true end
    end
    if C_UnitAuras.GetAuraDataBySpellName then
        local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", dft.name, "HELPFUL")
        if ok and a then return true end
    end
    return false
end

-- The raid's shared battle-rez charges (Rebirth's charges are the shared pool
-- during an encounter). true only when a charge is clearly available.
function PR.BattleRezReady()
    local ch = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(20484)
    if type(ch) ~= "table" or ns.IsSecret(ch.currentCharges) then return false end
    return (ch.currentCharges or 0) > 0
end

-- Your health over the last few seconds (only while a raid boss is engaged
-- AND your death summary is on): sampled 10x a second into a short buffer.
local SAMPLES = 60
function PR:SampleHealth(on)
    if self.healthTicker then self.healthTicker:Cancel(); self.healthTicker = nil end
    self.hp, self.hpAt = {}, 0
    if not (on and db().personal) then return end
    self.healthTicker = C_Timer.NewTicker(0.1, function()
        PR.hpAt = PR.hpAt % SAMPLES + 1
        local v = PR.HealthNow()
        if type(v) == "nil" then v = false end
        PR.hp[PR.hpAt] = v
    end)
end

-- Your health as 0..1. Midnight's UnitHealthPercent may hand back a hidden
-- ("secret") value mid-fight - that's kept as-is: the strip's bars can still
-- be filled from it, the game just won't let us compare it.
function PR.HealthNow()
    if UnitHealthPercent then
        local curve = CurveConstants and CurveConstants.ZeroToOne
        local ok, v = pcall(UnitHealthPercent, "player", true, curve)
        if ok and type(v) ~= "nil" then
            if not ns.IsSecret(v) and type(v) == "number" and v > 1 then v = v / 100 end     -- a 0-100 answer
            return v
        end
    end
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    if not (ns.IsSecret(cur) or ns.IsSecret(max)) and type(cur) == "number" and type(max) == "number" and max > 0 then return cur / max end
    return nil
end

-- the last 5 seconds (50 samples), oldest first; nil if nothing at all was readable
function PR:HealthStrip()
    if not self.hp or self.hpAt == 0 then return nil end
    local out, readable = {}, false
    for k = 49, 0, -1 do
        local v = self.hp[((self.hpAt - 1 - k) % SAMPLES) + 1]
        if type(v) == "boolean" or type(v) == "nil" then v = 0 else readable = true end    -- type() only: safe for hidden values
        out[#out + 1] = v
    end
    return readable and out or nil
end

function PR:OnPlayerDead()
    if self.current then self:Snapshot("death") end
end

-- Your own casts and cooldown changes (only during raid encounters): used at
-- / ready since, for each of your defensives.
function PR:WatchCasts(on)
    if not self.castFrame then
        self.castFrame = CreateFrame("Frame")
        self.castFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then PR:OnCast(...) else PR:OnCooldowns() end
        end)
    end
    if on then
        self.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self.castFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self.castFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    else
        self.castFrame:UnregisterAllEvents()
    end
end

function PR:FightTime() return self.current and (GetTime() - (self.current.t0 or GetTime())) or 0 end

function PR:OnCast(unit, castGUID, spellID)
    if not (self.current and self.history) or ns.IsSecret(spellID) or type(spellID) ~= "number" then return end
    local base = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
    for _, list in ipairs({ self.defs or {}, self.others or {} }) do
        for _, dft in ipairs(list) do
            if dft.id == spellID or (base and dft.id == base) then
                local h = self.history[dft.name]
                h.used, h.since = self:FightTime(), nil
            end
        end
    end
end

function PR:OnCooldowns()
    if not (self.current and self.history) then return end
    for _, list in ipairs({ self.defs or {}, self.others or {} }) do
        for _, dft in ipairs(list) do
            local h = self.history[dft.name]
            if h and not h.since and PR.Ready(dft.id) == true then h.since = self:FightTime() end
        end
    end
end

-- cheat-death saves: watched only during raid encounters
function PR:WatchAuras(on)
    local list = D.CHEAT_DEATHS[select(2, UnitClass("player"))]
    if not list then return end
    if not self.auraFrame then
        self.auraFrame = CreateFrame("Frame")
        self.auraFrame:SetScript("OnEvent", function() PR:CheckAuras() end)
    end
    if on then self.auraFrame:RegisterUnitEvent("UNIT_AURA", "player") else self.auraFrame:UnregisterAllEvents() end
end

local function hasAura(name)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, filter)
        if ok and data then return true end
    end
    return false
end

function PR:CheckAuras()
    if not self.current then return end
    for _, cd in ipairs(D.CHEAT_DEATHS[select(2, UnitClass("player"))] or {}) do
        local on = hasAura(cd.aura)
        if on and not self.auraSeen[cd.aura] then self:Snapshot("save", cd.name) end
        self.auraSeen[cd.aura] = on
    end
end

-- Deaths of raiders without Titan Up (shown as "no data" until a report arrives)
function PR:OnUnitDied(guid)
    local pull = self.current
    if not pull or not guid or ns.IsSecret(guid) then return end
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if not ns.Safe.Text(unit) or ns.Safe.Bool(UnitIsUnit(unit, "player")) then return end
    if not (ns.Safe.Call(UnitInRaid, unit) or ns.Safe.Call(UnitInParty, unit)) then return end
    local name = ns.FullName(unit)
    if not name then return end
    self:AddDeath(pull, name, { kind = "death", ft = GetTime() - (pull.t0 or GetTime()), nodata = true, class = ns.Safe.Class(unit) })
end

-- One row per death; a report replaces a "no data" row for the same person.
function PR:AddDeath(pull, owner, rec)
    for i, d in ipairs(pull.deaths) do
        if d.owner == owner and d.nodata and not rec.nodata and math.abs((d.ft or 0) - (rec.ft or 0)) < 8 then
            rec.owner = owner
            pull.deaths[i] = rec
            return
        end
        if rec.nodata and d.owner == owner and math.abs((d.ft or 0) - (rec.ft or 0)) < 8 then return end
    end
    rec.owner = owner
    table.insert(pull.deaths, rec)
    table.sort(pull.deaths, function(a, b) return (a.ft or 0) < (b.ft or 0) end)
    if not self.current or pull ~= self.current then self:Archive(pull) end
end

-- Heroic / Mythic raid pulls are kept for the Raid Scorecard
function PR:Archive(pull)
    if not (pull.diff == 15 or pull.diff == 16) then return end
    if ns.RaidScorecard and ns.RaidScorecard.Store then ns.RaidScorecard:Store(pull) end
end

-- Wipe call: the pull's raid leader marks the death where they called it;
-- deaths after it don't count against anyone.
function PR.AfterWipe(pull, d)
    return pull.wipeAt ~= nil and d.kind ~= "save" and (d.ft or 0) > pull.wipeAt
end

-- A suggested wipe call: the first death of the first moment at least half
-- the raid (min 3) died within 5 seconds. Only a suggestion - nothing counts
-- until the raid leader confirms it.
PR.WIPE_WINDOW = 5
function PR.SuggestWipe(pull)
    if pull.wipeAt then return nil end
    local deaths = {}
    for _, d in ipairs(pull.deaths or {}) do if d.kind ~= "save" then deaths[#deaths + 1] = d end end
    table.sort(deaths, function(a, b) return (a.ft or 0) < (b.ft or 0) end)
    local size = math.max(#(pull.roster or {}), #deaths)
    local need = math.max(3, math.ceil(size / 2))
    for i = 1, #deaths do
        local n = 0
        for j = i, #deaths do
            if (deaths[j].ft or 0) - (deaths[i].ft or 0) <= PR.WIPE_WINDOW then n = n + 1 else break end
        end
        if n >= need then return deaths[i] end
    end
    return nil
end

function PR:CanMarkWipe(pull)
    return pull.leader == ns.me or (not pull.leader and UnitIsGroupLeader and UnitIsGroupLeader("player"))
end

function PR:MarkWipe(pull, ft)
    if not self:CanMarkWipe(pull) then return end
    pull.wipeAt = ft
    self:Archive(pull)
    self.wipeOut = ("W^%s^%s"):format(pull.enc .. ":" .. pull.start, ft and ("%.1f"):format(ft) or "-")
    self:FlushWipe()
    if ns.PullReportUI then ns.PullReportUI:Refresh() end
end

function PR:FlushWipe()
    if not self.wipeOut or InCombatLockdown() then return end
    ns.SendFields(PREFIX, self.wipeOut)
    self.wipeOut = nil
end

-- ---------------------------------------------------------------------
-- Sharing (guild channel, after the fight, out of combat)
-- ---------------------------------------------------------------------
local function clean(s) return (tostring(s or ""):gsub("[%^~:|\n]", " ")) end

function PR.EncodeCds(cds)
    local t = {}
    for _, c in ipairs(cds or {}) do
        t[#t + 1] = ("%s=%s=%s"):format(clean(c.name), c.used and ("%.0f"):format(c.used) or "", c.since and ("%.0f"):format(c.since) or "")
    end
    return table.concat(t, "~")
end

function PR.Encode(rec)
    local hits = {}
    for _, h in ipairs(rec.hits or {}) do hits[#hits + 1] = ("%.1f:%s:%d:%s"):format(h.t or 0, clean(h.spell), h.amount or 0, clean(h.src)) end
    return table.concat({ rec.kind == "save" and "s" or "d", ("%.1f"):format(rec.ft or 0), table.concat(rec.major, "~"), table.concat(rec.minor, "~"),
        rec.pc or 0, rec.pr and 1 or 0, rec.hc or 0, rec.hr and 1 or 0, clean(rec.saver), table.concat(hits, "~"), rec.class or "", rec.tank and 1 or 0,
        table.concat(rec.active or {}, "~"), PR.EncodeCds(rec.cds), table.concat(rec.unknown or {}, "~"),
        table.concat(rec.other or {}, "~") }, "^")
end

function PR.DecodeCds(x)
    local out = {}
    for item in (x or ""):gmatch("[^~]+") do
        local name, used, since = item:match("^([^=]*)=([%d%.]*)=([%d%.]*)$")
        if name then out[#out + 1] = { name = name, used = tonumber(used), since = tonumber(since) } end
    end
    return out
end

-- one readable line per defensive: used / ready since
function PR.CooldownLines(d)
    local lines = {}
    local active = {}
    for _, n in ipairs(d.active or {}) do active[n] = true end
    for _, c in ipairs(d.cds or {}) do
        local line
        if active[c.name] then line = ("%s: |cff73bfffactive when they died|r"):format(c.name)
        elseif c.since then
            line = (c.since <= 0 and not c.used) and ("%s: |cff66e08cready all fight - unused|r"):format(c.name)
                or ("%s: |cff66e08cready since %s - unused|r"):format(c.name, PR.Clock(c.since))
        elseif c.used then line = ("%s: on cooldown (used at %s)"):format(c.name, PR.Clock(c.used))
        else line = ("%s: |cff8a8f9cnot ready|r"):format(c.name) end
        lines[#lines + 1] = line
    end
    return lines
end

function PR.Decode(s)
    local f = ns.Split(s, "^")
    if #f < 12 then return nil end
    local function list(x) local t = {} for v in (x or ""):gmatch("[^~]+") do t[#t + 1] = v end return t end
    local hits = {}
    for h in (f[10] or ""):gmatch("[^~]+") do
        local t, spell, amt, src = h:match("^([%-%d%.]+):([^:]*):(%d+):(.*)$")
        if t then hits[#hits + 1] = { t = tonumber(t), spell = spell, amount = tonumber(amt), src = src } end
    end
    return { kind = f[1] == "s" and "save" or "death", ft = tonumber(f[2]) or 0, major = list(f[3]), minor = list(f[4]),
             pc = tonumber(f[5]) or 0, pr = f[6] == "1", hc = tonumber(f[7]) or 0, hr = f[8] == "1",
             saver = f[9] ~= "" and f[9] or nil, hits = hits, class = f[11] ~= "" and f[11] or nil, tank = f[12] == "1", active = list(f[13]),
             cds = PR.DecodeCds(f[14]), unknown = list(f[15]), other = list(f[16]) }
end

function PR:Flush()
    local box = self.outbox
    if not box or ns.Busy() then return end
    local ch = ns.DataChannel()
    self.outbox = nil
    if not ch then return end
    for i, rec in ipairs(box.recs) do
        local payload = PR.Encode(rec)
        local n = math.ceil(#payload / CHUNK)
        for p = 1, n do
            ns.Send(PREFIX, ("R^%s^%d^%d^%d^%s"):format(box.key, i, p, n, payload:sub((p - 1) * CHUNK + 1, p * CHUNK)), ch)
        end
    end
end

function PR:OnMessage(msg, sender)
    local wkey, wft = msg:match("^W%^([%d:]+)%^([%d%.%-]+)$")
    if wkey then
        local e, st = wkey:match("^(%d+):(%d+)$")
        local p = self:FindPull(tonumber(e), tonumber(st))
        if p and p.leader == sender then
            p.wipeAt = tonumber(wft)
            self:Archive(p)
            if ns.PullReportUI then ns.PullReportUI:Refresh() end
        end
        return
    end
    local kind, key, idx, part, n, chunk = msg:match("^(R)%^([%d:]+)%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    if not kind then return end
    idx, part, n = tonumber(idx), tonumber(part), tonumber(n)
    self.inbox = self.inbox or {}
    for k, b in pairs(self.inbox) do if GetTime() - b.at > 60 then self.inbox[k] = nil end end   -- never finished
    local id = sender .. "|" .. key .. "|" .. idx
    local box = self.inbox[id] or { parts = {}, got = 0, at = GetTime() }
    self.inbox[id] = box
    if not box.parts[part] then box.parts[part] = chunk; box.got = box.got + 1 end
    if box.got < n then return end
    self.inbox[id] = nil
    local rec = PR.Decode(table.concat(box.parts))
    if not rec then return end
    local enc, start = key:match("^(%d+):(%d+)$")
    local pull = self:FindPull(tonumber(enc), tonumber(start))
    if not pull then return end
    self:AddDeath(pull, sender, rec)
    if ns.PullReportUI then ns.PullReportUI:Refresh() end
end

-- the same pull on everyone's machine: same boss, started within 20 seconds
function PR:FindPull(enc, start)
    local best
    for _, p in ipairs(self:Session().pulls) do
        if p.enc == enc and math.abs(p.start - start) <= 20 then best = p end
    end
    return best
end

-- ---------------------------------------------------------------------
-- Scorecard + export
-- ---------------------------------------------------------------------
function PR:Scorecard()
    local by = {}
    for _, p in ipairs(self:Session().pulls) do
        for _, d in ipairs(p.deaths) do
            if not PR.AfterWipe(p, d) then                     -- deaths after the wipe call don't count
                local r = by[d.owner] or { owner = d.owner, class = d.class, deaths = 0, def = 0, pot = 0, hs = 0, saves = 0, nodata = 0 }
                by[d.owner] = r
                r.class = r.class or d.class
                if d.kind == "save" then r.saves = r.saves + 1
                else
                    r.deaths = r.deaths + 1
                    if d.nodata then r.nodata = r.nodata + 1
                    else
                        if #(d.major or {}) > 0 then r.def = r.def + 1 end
                        if d.pr then r.pot = r.pot + 1 end
                        if d.hr then r.hs = r.hs + 1 end
                    end
                end
            end
        end
    end
    local rows = {}
    for _, r in pairs(by) do rows[#rows + 1] = r end
    table.sort(rows, function(a, b)
        local pa, pb = a.def + a.pot + a.hs, b.def + b.pot + b.hs
        if pa ~= pb then return pa > pb end
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        return a.owner < b.owner
    end)
    return rows
end

local short, clock = UI.Short, UI.Clock
PR.Clock = clock

function PR:ExportText()
    local s = self:Session()
    local lines = { ("Titan Up - Pull Report (%d pulls)"):format(#s.pulls), "", "Scorecard - deaths (with: defensive / potion / healthstone unused), close calls" }
    for _, r in ipairs(self:Scorecard()) do
        lines[#lines + 1] = ("  %-14s %d deaths (%d / %d / %d)%s%s"):format(short(r.owner), r.deaths, r.def, r.pot, r.hs,
            r.saves > 0 and (", " .. r.saves .. " close calls") or "", r.nodata > 0 and (", " .. r.nodata .. " without data") or "")
    end
    for _, p in ipairs(s.pulls) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Pull %d - %s - %s %s"):format(p.n, p.name, p.result == "kill" and "Kill" or (p.result == "wipe" and "Wipe" or "?"), p.dur and clock(p.dur) or "")
        for _, d in ipairs(p.deaths) do
            local flags = {}
            if d.kind == "save" then flags[#flags + 1] = "saved by " .. (d.saver or "a cheat-death")
            elseif d.nodata then flags[#flags + 1] = "no data"
            else
                if #(d.major or {}) > 0 then flags[#flags + 1] = "defensive ready (" .. table.concat(d.major, ", ") .. ")"
                elseif #(d.minor or {}) > 0 then flags[#flags + 1] = "minor defensive ready (" .. table.concat(d.minor, ", ") .. ")" end
                if d.pr then flags[#flags + 1] = "potion ready" end
                if d.hr then flags[#flags + 1] = "healthstone ready" end
            end
            lines[#lines + 1] = ("  %s  %s  %s"):format(clock(d.ft), short(d.owner), table.concat(flags, "; "))
        end
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------
-- Window: pulls | deaths of the selected pull | details of the selected death
-- ---------------------------------------------------------------------
local V = {}
ns.PullReportUI = V
local COL1, COL2, COL3, H = 420, 340, 340, 470
local ROWS = 15
local GREEN, YELLOW, GREY, ORANGE, BLUE = { 0.40, 0.88, 0.55 }, { 1.0, 0.82, 0.3 }, { 0.32, 0.34, 0.40 }, { 1.0, 0.55, 0.15 }, { 0.45, 0.75, 1.0 }

local function resize(f, w) UI.ResizeKeepTab(f, w, H) end

local function dot(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetColorTexture(GREY[1], GREY[2], GREY[3], 1)
    return t
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpPullReport", "pullreport", "PULL REPORT", COL1, H,
        { cog = { "Pull Report settings", function() ns.Settings:Open("pullreport", V.frame) end } })

    -- column 1: tonight's pulls
    local c1 = CreateFrame("Frame", nil, f)
    c1:SetPoint("TOPLEFT", 0, 0); c1:SetSize(COL1, H)
    UI.Text(c1, "GameFontNormalSmall", C.accent, "TONIGHT'S PULLS", "TOPLEFT", 16, -14)
    self.shortText = UI.Text(c1, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", -16, -14)
    self.scoreBtn = UI.Button(c1, 92, 22, "Scorecard", "Deaths and unused defensives / potions / healthstones per player, for tonight", function()
        if V.mode == "score" then V.mode = nil else V.mode = "score" end          -- click again to close
        V.pull, V.death = nil, nil
        V:Refresh()
    end)
    self.scoreBtn:SetPoint("TOPLEFT", 16, -36)
    local export = UI.Button(c1, 132, 22, "Copy for Discord", "The scorecard and every pull as plain text", function()
        if ns.UI.Prompt then
            ns.UI.Prompt({ title = "Pull Report", help = "Press Ctrl+C to copy, then paste it in Discord.", text = PR:ExportText(), select = true })
        end
    end)
    export:SetPoint("LEFT", self.scoreBtn, "RIGHT", 6, 0)
    self.pullRows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, c1, "BackdropTemplate")
        r:SetSize(COL1 - 32, 24)
        r:SetPoint("TOPLEFT", 16, -66 - (i - 1) * 26)
        UI.Skin(r, C.panel, C.line)
        r.text = UI.Text(r, "GameFontHighlight", C.text, nil, "LEFT", 8, 0)
        r.right = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "RIGHT", -8, 0)
        r:SetScript("OnClick", function()
            V.mode, V.death = nil, nil
            if V.pull == r.pull then V.pull = nil else V.pull = r.pull end          -- click again to close
            V:Refresh()
        end)
        r:Hide()
        self.pullRows[i] = r
    end
    self.empty = UI.Text(c1, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 18, -72)
    self.empty:SetWidth(COL1 - 36); self.empty:SetJustifyH("LEFT")
    self.empty:SetText("No raid pulls yet tonight. After each boss pull the deaths show here - who died, and whether they had a defensive, a health potion or a healthstone ready.")

    -- column 2: deaths of the selected pull (or the scorecard)
    local c2 = CreateFrame("Frame", nil, f)
    c2:SetPoint("TOPLEFT", COL1, 0); c2:SetSize(COL2, H)
    local sep = c2:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", 0, -10); sep:SetPoint("BOTTOMLEFT", 0, 10); sep:SetWidth(1)
    self.c2 = c2
    self.h2 = UI.Text(c2, "GameFontNormalSmall", C.accent, nil, "TOPLEFT", 14, -14)
    -- a suggested wipe call (leader confirms)
    self.suggest = UI.Text(c2, "GameFontHighlightSmall", C.text, nil, "BOTTOMLEFT", 14, 52)
    self.confirmWipe = UI.Button(c2, 80, 22, "Confirm", "Mark the wipe call here - deaths after it won't count", function()
        local p = V.pull
        local sd = p and PR.SuggestWipe(p)
        if sd then PR:MarkWipe(p, sd.ft) end
    end)
    self.confirmWipe:SetPoint("BOTTOMRIGHT", -14, 48)
    -- the D / P / H reminder: at the bottom of this column
    self.legend = UI.Text(c2, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", 14, 10)
    self.legend:SetWidth(COL2 - 28); self.legend:SetJustifyH("LEFT")
    self.legend:SetText("D = defensive   P = health potion   H = healthstone\n" .. UI.ICON_YES .. " ready but unused     |TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t only a minor defensive")
    self.deathRows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, c2, "BackdropTemplate")
        r:SetSize(COL2 - 28, 24)
        r:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 26)
        UI.Skin(r, C.panel, C.line)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 6, 0)
        r.time = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "LEFT", 24, 0)
        r.name = UI.Text(r, "GameFontHighlight", C.text, nil, "LEFT", 62, 0); r.name:SetWidth(150); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.d, r.p, r.h = dot(r, 14), dot(r, 14), dot(r, 14)
        r.marks = {}
        for _, k in ipairs({ "d", "p", "h" }) do
            local m = r:CreateTexture(nil, "OVERLAY")
            m:SetSize(12, 12)
            m:SetPoint("CENTER", r[k], "CENTER")
            r.marks[k] = m
        end
        r.h:SetPoint("RIGHT", -8, 0); r.p:SetPoint("RIGHT", r.h, "LEFT", -4, 0); r.d:SetPoint("RIGHT", r.p, "LEFT", -4, 0)
        r.note = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "RIGHT", -8, 0)
        r:SetScript("OnClick", function()
            if V.death == r.death then V.death = nil else V.death = r.death end       -- click again to close
            V:Refresh()
        end)
        if i == 1 then
            -- D / P / H letters over the squares
            self.colHeads = {}
            for _, k in ipairs({ "d", "p", "h" }) do
                local t = UI.Text(c2, "GameFontNormalSmall", C.muted, k:upper(), "BOTTOM", r[k] or r, "TOP", 0, 4)
                self.colHeads[k] = t
            end
        end
        r:SetScript("OnEnter", function(s) V:Tooltip(s, s.death) end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        self.deathRows[i] = r
    end
    self.scoreText = UI.Text(c2, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 14, -40)
    self.scoreText:SetWidth(COL2 - 28); self.scoreText:SetJustifyH("LEFT")

    -- column 3: one death in detail
    local c3 = CreateFrame("Frame", nil, f)
    c3:SetPoint("TOPLEFT", COL1 + COL2, 0); c3:SetSize(COL3, H)
    local sep3 = c3:CreateTexture(nil, "ARTWORK"); sep3:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep3:SetPoint("TOPLEFT", 0, -10); sep3:SetPoint("BOTTOMLEFT", 0, 10); sep3:SetWidth(1)
    self.c3 = c3
    self.detail = UI.Text(c3, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 14, -14)
    self.detail:SetWidth(COL3 - 28); self.detail:SetJustifyH("LEFT"); self.detail:SetSpacing(3)
    -- raid leader: mark the death where the wipe was called
    self.wipeBtn = UI.Button(c3, 160, 22, "", "Deaths after this one won't count against anyone (scorecards)", function()
        local p, d = V.pull, V.death
        if not (p and d) then return end
        if p.wipeAt == d.ft then PR:MarkWipe(p, nil) else PR:MarkWipe(p, d.ft) end
    end)
    self.wipeBtn:SetPoint("BOTTOMLEFT", 14, 10)
end

local function color(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local classed = UI.ClassName
local function big(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or n end

-- pieces shared by the window and the death summary
local function stock(n, ready, onCd) return n > 0 and (ready and color(GREEN) .. n .. " ready|r" or n .. onCd) or "none" end
local function hiddenAndOther(out, d)
    if d.unknown and #d.unknown > 0 then out[#out + 1] = "|cff8a8f9cCouldn't tell (hidden by the game): " .. table.concat(d.unknown, ", ") .. "|r" end
    if d.other and #d.other > 0 then out[#out + 1] = "|cffbfbfbfOther cooldowns ready: " .. table.concat(d.other, ", ") .. "|r" end
end
local function cooldowns(lines, d)
    local cdl = d.tank and {} or PR.CooldownLines(d)
    if #cdl == 0 then return end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff4fc3f7COOLDOWNS|r"
    for _, l in ipairs(cdl) do lines[#lines + 1] = l end
end
local function hitLine(fmt, h)
    return fmt:format(h.t or 0, h.spell, big(h.amount), (h.src and h.src ~= "") and ("  |cff8a8f9c(" .. h.src .. ")|r") or "")
end

function V:Summary(d)
    if d.nodata then return "No data - they aren't running Titan Up." end
    local out = {}
    if d.kind == "save" then out[#out + 1] = color(ORANGE) .. "Close call: saved by " .. (d.saver or "a cheat-death") .. "|r" end
    local killer = d.hits and d.hits[1]
    if killer and d.kind ~= "save" then out[#out + 1] = ("Died to %s (%s)"):format(killer.spell, big(killer.amount)) end
    if d.active and #d.active > 0 then out[#out + 1] = color(BLUE) .. "Active: " .. table.concat(d.active, ", ") .. "|r" end
    if d.tank then out[#out + 1] = "Tank - defensives not checked."
    elseif #(d.major or {}) > 0 then out[#out + 1] = color(GREEN) .. "Ready: " .. table.concat(d.major, ", ") .. "|r"
    elseif #(d.minor or {}) > 0 then out[#out + 1] = color(YELLOW) .. "Ready (minor): " .. table.concat(d.minor, ", ") .. "|r"
    else out[#out + 1] = "No defensive ready." end
    hiddenAndOther(out, d)
    out[#out + 1] = ("Health potion: %s   Healthstone: %s"):format(stock(d.pc, d.pr, " (on cd)"), stock(d.hc, d.hr, " (on cd)"))
    return table.concat(out, "\n")
end

function V:Tooltip(owner, d)
    if not d then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%s  %s"):format(PR.Clock(d.ft), short(d.owner)), 1, 1, 1)
    GameTooltip:AddLine(self:Summary(d), 0.85, 0.87, 0.9, true)
    GameTooltip:AddLine("Click for details", 0.55, 0.57, 0.62)
    GameTooltip:Show()
end

local function light(tex, c) tex:SetColorTexture(c[1], c[2], c[3], 1) end
-- selected row: accent border (rows are plain frames, not UI buttons)
local function selected(r, on)
    local c = on and C.accent or C.line
    r:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

function V:Refresh()
    if not self.frame then return end
    local s = PR:Session()
    -- pulls
    self.empty:SetShown(#s.pulls == 0)
    local short = s.short or 0
    self.shortText:SetText(short > 0 and ("%d short pull%s not counted"):format(short, short == 1 and "" or "s") or "")
    for i, r in ipairs(self.pullRows) do
        local p = s.pulls[#s.pulls - i + 1]               -- newest first
        r.pull = p
        if p then
            local deaths, saves = 0, 0
            for _, d in ipairs(p.deaths) do if d.kind == "save" then saves = saves + 1 else deaths = deaths + 1 end end
            r.text:SetText(("%d   %s"):format(p.n, p.name))
            r.right:SetText(("%s %s   %d dead%s"):format(p.result and UI.ResultTag(p.result) or "|cffffd94dIn progress|r",
                p.dur and PR.Clock(p.dur) or "", deaths, saves > 0 and ("  " .. color(ORANGE) .. saves .. " close|r") or ""))
            selected(r, V.pull == p)
            r:Show()
        else
            r:Hide()
        end
    end
    UI.SetActive(self.scoreBtn, V.mode == "score")
    -- deaths / scorecard
    local show2 = V.pull ~= nil or V.mode == "score"
    self.c2:SetShown(show2)
    for _, r in ipairs(self.deathRows) do r:Hide() end
    self.scoreText:SetText("")
    self.legend:SetShown(V.pull ~= nil)          -- only useful while deaths are listed
    local suggested
    local sd = V.pull and PR.SuggestWipe(V.pull)
    self.suggest:SetShown(sd ~= nil and V.mode ~= "score")
    self.confirmWipe:SetShown(sd ~= nil and V.mode ~= "score" and PR:CanMarkWipe(V.pull) and true or false)
    if sd then self.suggest:SetText(("|cffffc070Suggested wipe call:|r %s (%s)"):format(clock(sd.ft), short(sd.owner))) end
    if V.mode == "score" then
        self.h2:SetText("SCORECARD - TONIGHT")
        local lines = { "|cff8a8f9cdeaths  (with defensive / potion / healthstone unused)  close calls|r" }
        for _, r in ipairs(PR:Scorecard()) do
            lines[#lines + 1] = ("%s  %d  (%d / %d / %d)%s%s"):format(classed(r.owner, r.class), r.deaths, r.def, r.pot, r.hs,
                r.saves > 0 and ("  " .. color(ORANGE) .. r.saves .. "|r") or "", r.nodata > 0 and ("  |cff8a8f9c" .. r.nodata .. " no data|r") or "")
        end
        if #lines == 1 then lines[2] = "|cff8a8f9cNo deaths tonight.|r" end
        self.scoreText:SetText(table.concat(lines, "\n"))
    elseif V.pull then
        local p = V.pull
        self.h2:SetText(("PULL %d - %s"):format(p.n, p.name:upper()))
        suggested = PR.SuggestWipe(p)
        for i, r in ipairs(self.deathRows) do
            local d = p.deaths[i]
            r.death = d
            if d then
                r.time:SetText(PR.Clock(d.ft))
                local after = PR.AfterWipe(p, d)
                local tag = (d.kind == "save" and ("  " .. color(ORANGE) .. "saved|r"))
                    or (p.wipeAt ~= nil and d.ft == p.wipeAt and ("  " .. color(ORANGE) .. "wipe called|r"))
                    or (suggested == d and "  |cffffc070suggested wipe|r")
                    or (after and "  |cff8a8f9cafter wipe|r") or ""
                r.name:SetText((after and ("|cff8a8f9c" .. short(d.owner) .. "|r") or classed(d.owner, d.class)) .. tag)
                if d.kind == "save" then
                    r.icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfProtection"); r.icon:SetVertexColor(1, 0.65, 0.3)
                else
                    r.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"); r.icon:SetVertexColor(1, 1, 1)
                end
                local showDots = not d.nodata
                r.d:SetShown(showDots); r.p:SetShown(showDots); r.h:SetShown(showDots)
                r.note:SetText(d.nodata and "no data" or "")
                if showDots then
                    local dState = d.tank and "off" or (#(d.major or {}) > 0 and "on" or (#(d.minor or {}) > 0 and "minor" or "off"))
                    light(r.d, dState == "on" and GREEN or (dState == "minor" and YELLOW or GREY))
                    light(r.p, d.pr and GREEN or GREY)
                    light(r.h, d.hr and GREEN or GREY)
                    -- a mark as well as the colour, so it reads without colour
                    local function mark(k, state)
                        local m = r.marks[k]
                        m:SetShown(state ~= "off")
                        if state == "on" then m:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                        elseif state == "minor" then m:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting") end
                    end
                    mark("d", dState)
                    mark("p", d.pr and "on" or "off")
                    mark("h", d.hr and "on" or "off")
                else
                    for _, m in pairs(r.marks) do m:Hide() end
                end
                selected(r, V.death == d)
                r:Show()
            end
        end
        if #p.deaths == 0 then self.scoreText:SetText("|cff8a8f9cNobody died this pull.|r") end
    end
    -- details
    local show3 = V.death ~= nil and V.pull ~= nil
    self.c3:SetShown(show3)
    local canMark = show3 and V.death.kind ~= "save" and PR:CanMarkWipe(V.pull)
    self.wipeBtn:SetShown(canMark and true or false)
    if canMark then
        if V.pull.wipeAt == V.death.ft then self.wipeBtn.label:SetText("Remove wipe mark") else self.wipeBtn.label:SetText("Wipe called here") end
    end
    if show3 then
        local d = V.death
        local lines = { ("|cffffffff%s|r  %s"):format(classed(d.owner, d.class), PR.Clock(d.ft)), "", self:Summary(d) }
        if V.pull.wipeAt ~= nil and d.ft == V.pull.wipeAt then table.insert(lines, 2, color(ORANGE) .. "The wipe was called here.|r")
        elseif PR.AfterWipe(V.pull, d) then table.insert(lines, 2, "|cff8a8f9cAfter the wipe call - doesn't count.|r") end
        if d.hits and #d.hits > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff4fc3f7LAST HITS|r"
            for _, h in ipairs(d.hits) do lines[#lines + 1] = hitLine("%.1fs  %s  %s%s", h) end
        elseif not d.nodata and d.kind ~= "save" then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff8a8f9cNo damage details (the game didn't share a new death recap).|r"
        end
        cooldowns(lines, d)
        if not d.nodata and not d.tank and #(d.minor or {}) > 0 and #(d.major or {}) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = color(YELLOW) .. "Also ready: " .. table.concat(d.minor, ", ") .. "|r"
        end
        self.detail:SetText(table.concat(lines, "\n"))
    end
    resize(self.frame, COL1 + (show2 and COL2 or 0) + (show3 and COL3 or 0))
end

function V:ShowPull(pull)
    self:EnsureFrame()
    self.mode, self.pull, self.death = nil, pull, nil
    self.frame:Show()
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- My death summary (off until turned on): a small box when you die - or,
-- if the raid had a battle rez ready, once the pull ends.
-- ---------------------------------------------------------------------
local SW, BARS, BAR_H = 360, 50, 40

function PR:EnsureSummary()
    if self.summary then return self.summary end
    local f = UI.Window("TitanUpDeathSummary", SW, 200, { point = { "TOP", 0, -170 }, strata = "DIALOG", border = { 1, 0.35, 0.35, 1 },
        drag = true, noTop = true })
    f.title = UI.Text(f, "GameFontNormal", { 1, 0.45, 0.45 }, nil, "TOPLEFT", 12, -10)
    local close = UI.Button(f, 22, 20, "X", "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    f.body = UI.Text(f, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 12, -32)
    f.body:SetWidth(SW - 24); f.body:SetJustifyH("LEFT"); f.body:SetSpacing(2)
    -- health strip: one bar per tenth of a second, last 5 seconds
    local strip = CreateFrame("Frame", nil, f)
    strip:SetSize(BARS * 6, BAR_H)
    f.strip = strip
    strip.bg = strip:CreateTexture(nil, "BACKGROUND"); strip.bg:SetAllPoints(); strip.bg:SetColorTexture(0, 0, 0, 0.35)
    -- one tiny vertical health bar per tenth of a second: the game fills
    -- each from the recorded value, even one it hides from addons
    strip.bars = {}
    for i = 1, BARS do
        local b = CreateFrame("StatusBar", nil, strip)
        b:SetSize(5, BAR_H)
        b:SetPoint("BOTTOMLEFT", (i - 1) * 6, 0)
        b:SetOrientation("VERTICAL")
        b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        b:SetMinMaxValues(0, 1)
        strip.bars[i] = b
    end
    f.stripLabel = UI.Text(f, "GameFontHighlightSmall", C.muted, "-5s                           your health                           death", "TOPLEFT", strip, "BOTTOMLEFT", 0, -2)
    f.noHealth = UI.Text(f, "GameFontHighlightSmall", C.muted)
    self.summary = f
    return f
end

function PR:SummaryText(rec)
    local lines = {}
    local killer = (rec.last5 and rec.last5[1]) or (rec.hits and rec.hits[1])
    if killer then lines[#lines + 1] = ("Killed by |cffffffff%s|r (%s)"):format(killer.spell, big(killer.amount)) end
    if rec.active and #rec.active > 0 then lines[#lines + 1] = color(BLUE) .. "Active: " .. table.concat(rec.active, ", ") .. "|r" end
    if rec.tank then
        lines[#lines + 1] = "Tank - defensives not checked."
    else
        local ready = {}
        for _, n in ipairs(rec.major or {}) do ready[#ready + 1] = n end
        for _, n in ipairs(rec.minor or {}) do ready[#ready + 1] = n end
        lines[#lines + 1] = #ready > 0 and (color(GREEN) .. "Ready but unused: " .. table.concat(ready, ", ") .. "|r") or "No defensive ready."
    end
    lines[#lines + 1] = ("Health potions: %s   Healthstones: %s"):format(stock(rec.pc, rec.pr, " (on cooldown)"), stock(rec.hc, rec.hr, " (on cooldown)"))
    hiddenAndOther(lines, rec)
    cooldowns(lines, rec)
    local hits = rec.last5 or rec.hits or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff4fc3f7LAST 5 SECONDS|r"
    if #hits == 0 then lines[#lines + 1] = "|cff8a8f9cThe game didn't share what hit you.|r" end
    for i = 1, math.min(10, #hits) do lines[#lines + 1] = hitLine("|cff8a8f9c%5.1fs|r  %s  %s%s", hits[i]) end
    return table.concat(lines, "\n")
end

function PR:ShowSummary(rec)
    if not rec then return end
    local f = self:EnsureSummary()
    f.title:SetText(("You died - %s"):format(clock(rec.ft)))
    f.body:SetText(self:SummaryText(rec))
    local bodyH = f.body:GetStringHeight()
    if type(bodyH) ~= "number" or bodyH <= 0 then bodyH = 14 * 12 end
    f.strip:ClearAllPoints()
    f.strip:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -10)
    local hp = rec.health
    f.strip:SetShown(hp ~= nil)
    f.stripLabel:SetShown(hp ~= nil)
    f.noHealth:ClearAllPoints()
    f.noHealth:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -10)
    f.noHealth:SetText(hp and "" or "|cff8a8f9cNo health readings this time.|r")
    if hp then
        for i, b in ipairs(f.strip.bars) do
            local v = hp[i]
            if type(v) == "boolean" or type(v) == "nil" then v = 0 end
            pcall(b.SetValue, b, v)                                  -- works for hidden values too
            local c = BLUE
            if not ns.IsSecret(v) and type(v) == "number" then c = v > 0.5 and GREEN or (v > 0.25 and YELLOW or { 1, 0.35, 0.35 }) end
            b:SetStatusBarColor(c[1], c[2], c[3], 0.9)
        end
    end
    f:SetHeight(32 + bodyH + (hp and (10 + BAR_H + 18) or 24) + 10)
    f:Show()
end

ns.RegisterModule({
    key = "pullreport", name = "Pull Report", icon = ns.MEDIA .. "PullReport", group = "tools", order = 5,
    desc = "Who died each raid pull - and whether they had a defensive, potion or healthstone ready.",
    view = V,
})
