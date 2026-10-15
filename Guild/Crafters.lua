-- Titan Up - Guild/Crafters.lua
-- The Crafters directory (0.37.0, sharing on by default): who in the guild
-- can make what.
--   * Your recipes are read from the game when you open a profession window
--     (nothing about recipes is built into Titan Up, so a new patch's or
--     expansion's recipes show up on their own). Only the newest expansion's
--     recipes by default ("Include older expansions" adds the rest).
--   * Each character's list is shared with the guild over the background
--     lane (Guild/Shared.lua) and kept by everyone, so crafters show even
--     when they're offline. Only recipe numbers travel: every client reads
--     the names and icons in its own language.
--   * Outside crafters: anyone can add a crafter from another guild or
--     server for an item (with a note). They travel in the adder's own list;
--     the adder can remove them, and so can an officer (guild rank 0 or 1),
--     whose removals travel in the officer's list.
--
-- A character's list (prefix TitanUpCR):
--   profs # outside # removed
--   profs:   base:skill:max:tier:recipes[,!quality] ; ...  (base36; recipes as gaps)
--   quality: gap=MPCB . gap=MPCB ...  (0.44.0; recipes with quality ranks only;
--            one digit each: M top rank, P best rank you can make with the
--            best materials, C the same with Concentration, B best rank seen
--            crafted; 0 = unknown). Older clients stop reading the recipe
--            list at the "!" and never see it.
--   outside: item~crafter~text~note~time ; ...    (item base36, 0 = typed text)
--   removed: adder/time , ...                     (officer removals)
local ADDON, ns = ...

local CR = {}
ns.Crafters = CR

local Shared = ns.Shared
local B36, FromB36 = Shared.B36, Shared.FromB36
local PREFIX = "TitanUpCR"
local NOTE_MAX, TEXT_MAX = 60, 60
local OUTSIDE_MAX = 40            -- outside crafters one player can add

local function db() return ns.udb.crafters end
function CR:Enabled() return db().share and true or false end

-- English names for profession skill lines (the game's own name is used when it gives one)
CR.PROF_NAMES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [182] = "Herbalism",
    [773] = "Inscription", [755] = "Jewelcrafting", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
    [197] = "Tailoring", [185] = "Cooking", [356] = "Fishing",
}

function CR.ProfName(base)
    local T = C_TradeSkillUI
    local n = T and T.GetTradeSkillDisplayName and ns.Safe.Call(T.GetTradeSkillDisplayName, base)
    return (n and n ~= "" and n) or CR.PROF_NAMES[base] or ("Profession " .. tostring(base))
end

-- ---------------------------------------------------------------------
-- Guild roster: who's online, their class, their rank (officers: 0 or 1)
-- ---------------------------------------------------------------------
local roster
function ns.GuildRoster()
    local now = GetTime()
    if roster and now - roster.at < 10 then return roster end
    local r = { at = now, online = {}, class = {}, rank = {}, inGuild = {}, n = 0 }
    if GetNumGuildMembers and GetGuildRosterInfo then
        local ok, total = pcall(GetNumGuildMembers)
        if ok and type(total) == "number" and not ns.IsSecret(total) then
            for i = 1, total do
                local ok2, name, _, rank, _, _, _, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
                name = ok2 and type(name) == "string" and not ns.IsSecret(name) and ns.NormalizeSender(name)
                if name then
                    r.n = r.n + 1
                    r.inGuild[name] = true
                    if type(rank) == "number" and not ns.IsSecret(rank) then r.rank[name] = rank end
                    if type(class) == "string" and not ns.IsSecret(class) then r.class[name] = class end
                    if online and not ns.IsSecret(online) then r.online[name] = true end
                end
            end
        end
    end
    r.loaded = r.n > 0
    roster = r
    return r
end
ns.On("GUILD_ROSTER_UPDATE", function() if roster then roster.at = -100 end end)

function CR.IsOfficer(name)
    if name == ns.me then
        local _, _, rank = GetGuildInfo("player")
        return type(rank) == "number" and not ns.IsSecret(rank) and rank <= 1
    end
    local rank = ns.GuildRoster().rank[name]
    return rank ~= nil and rank <= 1
end

-- ---------------------------------------------------------------------
-- Your own professions (per character; saved per account)
-- ---------------------------------------------------------------------
local function mineAll()
    db().mine = db().mine or {}
    return db().mine
end
local function myProfs()
    local all = mineAll()
    all[ns.me] = all[ns.me] or { profs = {}, outside = {}, removed = {} }
    local m = all[ns.me]
    m.profs, m.outside, m.removed = m.profs or {}, m.outside or {}, m.removed or {}
    return m
end
CR.MyData = myProfs

local function clean(s, max) return ns.CleanField(s, max, "[~;#:,/]") end

-- this character's list as text (empty with sharing off: the guild forgets it)
function CR:Payload()
    if not self:Enabled() then return "" end
    local m = myProfs()
    local profs = {}
    local bases = {}
    for base in pairs(m.profs) do bases[#bases + 1] = base end
    table.sort(bases)
    for _, base in ipairs(bases) do
        local p = m.profs[base]
        local ids = {}
        for id in pairs(p.recipes or {}) do ids[#ids + 1] = id end
        if #ids > 0 then
            local packed = Shared.PackIds(ids)
            local q = CR.PackQuality(p.q, m.best, p.recipes)
            if q ~= "" then packed = packed .. ",!" .. q end
            profs[#profs + 1] = table.concat({ B36(base), B36(p.skill or 0), B36(p.max or 0), B36(p.tier or 0), packed }, ":")
        end
    end
    local outside = {}
    for _, o in ipairs(m.outside) do
        outside[#outside + 1] = table.concat({ B36(o.item or 0), o.crafter, clean(o.text, TEXT_MAX), clean(o.note, NOTE_MAX), B36(o.t or 0) }, "~")
    end
    local removed = {}
    for id in pairs(m.removed) do removed[#removed + 1] = id end
    table.sort(removed)
    local s = table.concat(profs, ";") .. "#" .. table.concat(outside, ";") .. "#" .. table.concat(removed, ",")
    if s == "##" then return "" end
    return s
end

-- quality ranks: { [recipe] = { m, p, c, b } } <-> "gap=MPCB.gap=MPCB"
local function digit(v) v = tonumber(v) or 0; return tostring(math.max(0, math.min(9, math.floor(v)))) end
function CR.PackQuality(pred, best, recipes)
    local ids = {}
    for id in pairs(recipes or {}) do
        if (pred and pred[id]) or (best and best[id]) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local out, last = {}, 0
    for _, id in ipairs(ids) do
        local q = pred and pred[id] or {}
        local b = best and best[id] or 0
        out[#out + 1] = B36(id - last) .. "=" .. digit(q.m) .. digit(q.p) .. digit(q.c) .. digit(b)
        last = id
    end
    return table.concat(out, ".")
end

function CR.UnpackQuality(s)
    local out, last = {}, 0
    for gap, m, p, c, b in (s or ""):gmatch("(%w+)=(%d)(%d)(%d)(%d)") do
        local d = FromB36(gap)
        if not d then break end
        last = last + d
        out[last] = { m = tonumber(m), p = tonumber(p), c = tonumber(c), b = tonumber(b) }
    end
    return out
end

local function parse(p)
    local out = { profs = {}, outside = {}, removed = {} }
    if not p or p == "" then return out end
    local a, b, c = p:match("^([^#]*)#?([^#]*)#?([^#]*)$")
    for item in (a or ""):gmatch("[^;]+") do
        local base, skill, max, tier, ids = item:match("^(%w+):(%w*):(%w*):(%w*):(.*)$")
        base = base and FromB36(base)
        if base then
            local list, q = (ids or ""):match("^(.-),!(.*)$")
            out.profs[#out.profs + 1] = { base = base, skill = FromB36(skill) or 0, max = FromB36(max) or 0,
                                          tier = FromB36(tier) or 0, recipes = Shared.UnpackIds(list or ids),
                                          quality = CR.UnpackQuality(q) }
        end
    end
    for item in (b or ""):gmatch("[^;]+") do
        local it, crafter, text, note, t = item:match("^(%w*)~([^~]*)~([^~]*)~([^~]*)~(%w*)$")
        if crafter and crafter:match("^[^%-]+%-.+$") then
            out.outside[#out.outside + 1] = { item = FromB36(it) or 0, crafter = crafter, text = text, note = note, t = FromB36(t) or 0 }
        end
    end
    for id in (c or ""):gmatch("[^,]+") do out.removed[id] = true end
    return out
end
CR.Parse = parse

-- ---------------------------------------------------------------------
-- Reading your profession window
-- ---------------------------------------------------------------------
function CR:CanScan()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return false end
    for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging" }) do
        if T[f] and ns.Safe.Call(T[f]) then return false end           -- someone else's or a special window
    end
    return true
end

-- the newest expansion tier of the profession that's open (highest skill line ID)
local function newestTier()
    local T = C_TradeSkillUI
    local list = T.GetChildProfessionInfos and ns.Safe.Call(T.GetChildProfessionInfos)
    local best
    for _, c in ipairs(type(list) == "table" and list or {}) do
        local id = ns.Safe.Num(c.professionID)
        if id and (not best or id > best.professionID) then best = c end
    end
    if not best and T.GetChildProfessionInfo then best = ns.Safe.Call(T.GetChildProfessionInfo) end
    return best
end

function CR:Scan()
    if not self:CanScan() then return false end
    local T = C_TradeSkillUI
    local base = ns.Safe.Call(T.GetBaseProfessionInfo)
    local baseID = base and ns.Safe.Num(base.professionID)
    if not baseID or baseID == 0 then return false end
    local tier = newestTier()
    local tierID = tier and ns.Safe.Num(tier.professionID) or 0
    local ids = ns.Safe.Call(T.GetAllRecipeIDs)
    if type(ids) ~= "table" or #ids == 0 then return false end
    local recipes, newest, n = {}, {}, 0
    local old = db().oldTiers
    for _, id in ipairs(ids) do
        local info = ns.Safe.Call(T.GetRecipeInfo, id)
        if type(info) == "table" and info.learned == true and not info.isDummyRecipe then
            local current = tierID == 0
            if not current and T.GetProfessionInfoByRecipeID then
                local pi = ns.Safe.Call(T.GetProfessionInfoByRecipeID, id)
                current = type(pi) == "table" and ns.Safe.Num(pi.professionID) == tierID
            end
            if old or current then recipes[id] = true; n = n + 1 end
            if current then newest[id] = true end
        end
    end
    local m = myProfs()
    local prev = m.profs[baseID]
    local skill = tier and ns.Safe.Num(tier.skillLevel) or ns.Safe.Num(base.skillLevel) or 0
    -- the window fires many list updates: work the ranks out again at most every 30 s
    local q, qt = prev and prev.q, prev and prev.qt
    if not q or not qt or ns.Now() - qt >= 30 or prev.skill ~= skill then
        q, qt = self:PredictQuality(newest), ns.Now()       -- this expansion's recipes only
    end
    m.profs[baseID] = { recipes = recipes, tier = tierID, name = ns.Safe.Text(base.professionName), skill = skill,
                        max = tier and ns.Safe.Num(tier.maxSkillLevel) or ns.Safe.Num(base.maxSkillLevel) or 0, t = ns.Now(),
                        q = q, qt = qt }
    self.lastScan = { base = baseID, count = n }
    self.sync:Refresh()
    return true, n
end

-- ---------------------------------------------------------------------
-- Quality ranks (0.44.0): the best rank you can make, worked out by the
-- game from your skill, specialization points, tools and gear, assuming
-- the best materials (with and without Concentration); and the best rank
-- the addon has seen you craft.
-- ---------------------------------------------------------------------
local function rank(v)
    v = ns.Safe.Num(v)
    return (v and v >= 1 and v <= 9) and math.floor(v) or nil
end

-- the materials list for a recipe: every required basic slot filled with its
-- best-quality material
local function bestReagents(id)
    local T = C_TradeSkillUI
    local sch = T.GetRecipeSchematic and ns.Safe.Call(T.GetRecipeSchematic, id, false)
    if type(sch) ~= "table" or type(sch.reagentSlotSchematics) ~= "table" then return nil end
    local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    local qualityOf = T.GetItemReagentQualityByItemInfo
    local out = {}
    for _, slot in ipairs(sch.reagentSlotSchematics) do
        if slot.reagentType == BASIC and slot.required ~= false and type(slot.reagents) == "table" and #slot.reagents > 0 then
            local pick, pickQ
            for i, r in ipairs(slot.reagents) do
                local item = type(r) == "table" and ns.Safe.Num(r.itemID)
                if item then
                    local rq = (qualityOf and rank(ns.Safe.Call(qualityOf, item))) or i
                    if not pick or rq >= pickQ then pick, pickQ = r, rq end
                end
            end
            if pick then
                out[#out + 1] = { reagent = { itemID = pick.itemID }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired or 1 }
            end
        end
    end
    return out
end

-- { [recipe] = { m = top rank, p = with best materials, c = with Concentration } }
function CR:PredictQuality(recipes)
    local T = C_TradeSkillUI
    local out = {}
    if not (T and T.GetCraftingOperationInfo and T.GetRecipeInfo) then return out end
    for id in pairs(recipes) do
        local info = ns.Safe.Call(T.GetRecipeInfo, id)
        local top = type(info) == "table" and info.supportsQualities == true and rank(info.maxQuality)
        if top and top > 1 then
            local mats = bestReagents(id)
            if mats then
                local a = ns.Safe.Call(T.GetCraftingOperationInfo, id, mats, nil, false)
                local c = ns.Safe.Call(T.GetCraftingOperationInfo, id, mats, nil, true)
                local p = type(a) == "table" and rank(a.craftingQuality)
                local pc = type(c) == "table" and rank(c.craftingQuality)
                if p or pc then
                    out[id] = { m = top, p = p and math.min(p, top) or 0, c = pc and math.min(math.max(pc, p or 0), top) or 0 }
                end
            end
        end
    end
    return out
end

-- your crafts: the cast's spell is the recipe, then the game reports the result
function CR:OnCast(spellID)
    spellID = ns.Safe.Num(spellID)
    if not spellID then return end
    for _, p in pairs(myProfs().profs) do
        if p.recipes and p.recipes[spellID] then self.lastCraft = { id = spellID, at = GetTime() } return end
    end
end

function CR:OnCrafted(data)
    local last = self.lastCraft
    if type(data) ~= "table" or not last or GetTime() - last.at > 15 then return end
    local T = C_TradeSkillUI
    local link = ns.Safe.Text(data.hyperlink)
    local q = link and T and T.GetItemCraftedQualityByItemInfo and rank(ns.Safe.Call(T.GetItemCraftedQualityByItemInfo, link))
    q = q or rank(data.craftingQuality)
    if not q then return end
    local m = myProfs()
    m.best = m.best or {}
    if (m.best[last.id] or 0) < q then
        m.best[last.id] = q
        self.sync:Refresh()
    end
end

-- drop professions this character no longer has
function CR:CheckProfessions()
    if not GetProfessions or not GetProfessionInfo then return end
    local ok, a, b, arch, fish, cook = pcall(GetProfessions)
    if not ok then return end
    local have, any = {}, false
    for _, idx in ipairs({ a, b, arch, fish, cook }) do
        if type(idx) == "number" then
            local ok2, _, _, _, _, _, _, line = pcall(GetProfessionInfo, idx)
            if ok2 and type(line) == "number" then have[line] = true; any = true end
        end
    end
    if not any then return end
    local m, changed = myProfs(), false
    for base in pairs(m.profs) do
        if not have[base] then m.profs[base] = nil; changed = true end
    end
    if changed then self.sync:Refresh() end
end

-- ---------------------------------------------------------------------
-- Start-up
-- ---------------------------------------------------------------------
function CR:Init()
    self.sync = Shared.New({
        prefix = PREFIX, name = "Crafters", max = 9000,
        store = function() return db().people end,
        mine = function() return CR:Payload() end,
        changed = function() CR:Changed() end,
    })
    self.sync:Init()
    local function later() ns.Debounce("crafters-scan", 1.5, function() CR:Scan() end) end
    for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do ns.On(ev, later) end
    self.castFrame = CreateFrame("Frame")
    self.castFrame:SetScript("OnEvent", function(_, _, _, _, spellID) CR:OnCast(spellID) end)
    self.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    self.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ns.On("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(data) CR:OnCrafted(data) end)
    ns.On("SKILL_LINES_CHANGED", function() ns.Debounce("crafters-profs", 3, function() CR:CheckProfessions() end) end)
    C_Timer.After(12, function() CR:CheckProfessions() end)
end

function CR:SetEnabled(on)
    db().share = on and true or false
    self.sync:Refresh()
end

function CR:SetOldTiers(on)
    db().oldTiers = on and true or false
    ns.Print("Open each profession window once to " .. (on and "add your older recipes." or "drop your older recipes."))
end

-- ---------------------------------------------------------------------
-- Outside crafters
-- ---------------------------------------------------------------------
-- what someone typed or shift-clicked: an item link or plain text
function CR.ItemFrom(text)
    text = tostring(text or "")
    local id = tonumber(text:match("|Hitem:(%d+)"))
    local name = ns.RaidCheck and ns.RaidCheck.ItemName and text:find("|H", 1, true) and ns.RaidCheck.ItemName(text) or text
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return id, name
end

function CR.ValidCrafter(s)
    s = tostring(s or ""):gsub("%s", "")
    local name, realm = s:match("^([^%-]+)%-(.+)$")
    if not name then return nil end
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    realm = realm:gsub("[%-']", "")
    if #name < 2 or #name > 24 or realm == "" then return nil end
    return clean(name .. "-" .. realm, 60)
end

function CR:AddOutside(itemText, crafter, note)
    local id, text = CR.ItemFrom(itemText)
    local who = CR.ValidCrafter(crafter)
    if not who then return false, "Type the crafter as Name-Server (for example Thrall-Medivh)." end
    if (text == "" or not text) and not id then return false, "Shift-click an item into the item box, or type what they craft." end
    local m = myProfs()
    if #m.outside >= OUTSIDE_MAX then return false, ("You can add up to %d outside crafters - remove one first."):format(OUTSIDE_MAX) end
    local t = ns.Now()
    for _, o in ipairs(m.outside) do if o.t == t then t = t + 1 end end
    m.outside[#m.outside + 1] = { item = id or 0, crafter = who, text = clean(text, TEXT_MAX), note = clean(note, NOTE_MAX), t = t }
    self.sync:Refresh()
    self:Changed()
    return true
end

-- id: "adder/time"
function CR.OutsideId(adder, t) return adder .. "/" .. B36(t or 0) end

function CR:CanRemove(entry) return entry.by == ns.me or CR.IsOfficer(ns.me) end

function CR:RemoveOutside(entry)
    local m = myProfs()
    if entry.by == ns.me then
        for i = #m.outside, 1, -1 do if m.outside[i].t == entry.t then table.remove(m.outside, i) end end
    elseif CR.IsOfficer(ns.me) then
        m.removed[CR.OutsideId(entry.by, entry.t)] = true
    else
        return false
    end
    self.sync:Refresh()
    self:Changed()
    return true
end

-- ---------------------------------------------------------------------
-- The directory: every recipe someone knows, and who
-- ---------------------------------------------------------------------
function CR:Changed()
    self.catalog = nil
    if ns.CraftersUI and ns.CraftersUI.frame and ns.CraftersUI.frame:IsShown() then
        ns.Debounce("crafters-redraw", 0.5, function() ns.CraftersUI:Refresh() end)
    end
end

local spellNameCache = {}
function CR.RecipeName(id)
    local n = spellNameCache[id]
    if n then return n end
    local f = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    n = f and ns.Safe.Call(f, id)
    if n then spellNameCache[id] = n end
    return n or ("Recipe " .. id)
end

function CR.RecipeIcon(id)
    local f = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    return f and ns.Safe.Call(f, id) or 134400
end

-- { recipes = { [id] = { id, crafters = { { name, base, skill, max, q } } } }, outside = { ... }, profs = { [base] = true } }
function CR:Catalog()
    if self.catalog then return self.catalog end
    local cat = { recipes = {}, outside = {}, profs = {} }
    local removed = {}
    local lists = {}
    for owner, e in pairs(db().people) do
        if e.p and e.p ~= "" then lists[owner] = parse(e.p) end
    end
    -- officer removals (an officer's list, read only if they're still an officer)
    for owner, l in pairs(lists) do
        if next(l.removed) and CR.IsOfficer(owner) then for id in pairs(l.removed) do removed[id] = true end end
    end
    for owner, l in pairs(lists) do
        for _, p in ipairs(l.profs) do
            cat.profs[p.base] = true
            for _, id in ipairs(p.recipes) do
                local r = cat.recipes[id]
                if not r then r = { id = id, base = p.base, crafters = {} } cat.recipes[id] = r end
                r.crafters[#r.crafters + 1] = { name = owner, base = p.base, skill = p.skill, max = p.max, q = p.quality[id] }
            end
        end
        for _, o in ipairs(l.outside) do
            if not removed[CR.OutsideId(owner, o.t)] then
                cat.outside[#cat.outside + 1] = { by = owner, crafter = o.crafter, item = o.item, text = o.text, note = o.note, t = o.t }
            end
        end
    end
    self.catalog = cat
    return cat
end

local function itemName(id)
    if not id or id == 0 then return nil end
    local f = C_Item and C_Item.GetItemNameByID
    return f and ns.Safe.Call(f, id) or nil
end
CR.ItemName = itemName

-- Search results: rows { kind = "recipe", id, name, base, crafters } and
-- { kind = "outside", name, entries } (outside crafters grouped by item),
-- sorted by name. prof: a profession base ID, or nil for all.
function CR:Search(text, prof)
    local cat = self:Catalog()
    local want = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    for id, r in pairs(cat.recipes) do
        if not prof or r.base == prof then
            local name = CR.RecipeName(id)
            if want == "" or name:lower():find(want, 1, true) then
                rows[#rows + 1] = { kind = "recipe", id = id, name = name, base = r.base, crafters = r.crafters }
            end
        end
    end
    if not prof then
        local byItem = {}
        for _, o in ipairs(cat.outside) do
            local name = itemName(o.item) or (o.text ~= "" and o.text) or "?"
            if want == "" or name:lower():find(want, 1, true) or o.crafter:lower():find(want, 1, true) or (o.note or ""):lower():find(want, 1, true) then
                local k = name:lower()
                local g = byItem[k]
                if not g then g = { kind = "outside", name = name, item = o.item, entries = {} } byItem[k] = g; rows[#rows + 1] = g end
                g.entries[#g.entries + 1] = o
            end
        end
        -- an outside crafter also shows under a recipe of the same name
        for _, row in ipairs(rows) do
            if row.kind == "recipe" then
                local g = byItem[row.name:lower()]
                if g then row.outside = g.entries; g.merged = true end
            end
        end
        for i = #rows, 1, -1 do if rows[i].merged then table.remove(rows, i) end end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return (a.id or 0) < (b.id or 0)
    end)
    return rows
end

-- how many guildmates have shared lists, and when you last scanned
function CR:Counts()
    local people = 0
    for _, e in pairs(db().people) do if e.p and e.p ~= "" then people = people + 1 end end
    return people
end

function CR.Whisper(name)
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then pcall(tell, name) end
end
