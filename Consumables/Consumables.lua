-- Titan Up - Consumables/Consumables.lua
-- The consumable shopping list (0.40.0): for each consumable you bring,
-- how many are in your bags (each quality rank on its own line), how many
-- you want, and how many you're short. Per character, nothing is sent to
-- anyone. Optional: a quiet notice when you zone into a raid while short
-- (off by default).
--
-- Saved: udb.consumables = { remind, chars = { [Name-Realm] = { want = { [itemID] = n },
--   mine = { { id, group } } } }, learned = { [spellID] = { itemID, ... } } }
-- Built-in items are item numbers (names, icons and the language come from
-- the game). Health potions are known only by the spell they use: their
-- item numbers are learned the first time one is in your bags.
local ADDON, ns = ...

local CO = {}
ns.Consumables = CO

-- The groups, in order. "mine" holds what players add themselves.
CO.GROUPS = {
    { key = "flask", name = "Flasks" },
    { key = "potion", name = "Combat potions" },
    { key = "health", name = "Health potions" },
    { key = "food", name = "Food" },
    { key = "other", name = "Other" },
    { key = "mine", name = "My items" },
}
CO.GROUP_NAME = {}
for _, g in ipairs(CO.GROUPS) do CO.GROUP_NAME[g.key] = g.name end

-- This season's consumables (Midnight, 12.1.5 game data). ranks = { rank 1, rank 2 }.
CO.BUILTIN = {
    { group = "flask", ranks = { 241321, 241320 } },      -- Flask of Thalassian Resistance
    { group = "flask", ranks = { 241325, 241324 } },      -- Flask of the Blood Knights
    { group = "flask", ranks = { 241323, 241322 } },      -- Flask of the Magisters
    { group = "flask", ranks = { 241327, 241326 } },      -- Flask of the Shattered Sun
    { group = "potion", ranks = { 241309, 241308 } },     -- Light's Potential
    { group = "potion", ranks = { 241289, 241288 } },     -- Potion of Recklessness
    { group = "potion", ranks = { 241297, 241296 } },     -- Potion of Zealotry
    { group = "potion", ranks = { 271886, 271887 } },     -- Liquid Luster
    { group = "health", spell = 1234768, english = "Silvermoon Health Potion" },
    { group = "health", spell = 1295247, english = "Concentrated Silvermoon Health Potion" },
    { group = "other", ids = { 259085 } },                -- Void-Touched Augment Rune
    { group = "food", ids = { 242744, 242745, 242746, 242747, 242748, 242749, 242750, 242752, 242753, 242754, 242755,
                              242756, 242757, 242758, 242759, 242760, 242761, 242762, 242763, 242764, 242765, 242766,
                              242767, 242768, 242769, 242770, 242771, 242772, 242773, 242774, 242775, 242776, 266985,
                              266996, 268679, 268680, 275259, 275262, 275263, 275267, 275268, 275269 } },   -- hearty food and feasts
}
CO.MAX_WANT = 999
CO.MAX_MINE = 60

-- ---------------------------------------------------------------------
-- Saved data
-- ---------------------------------------------------------------------
function CO:DB()
    local u = ns.udb
    u.consumables = u.consumables or { remind = false, chars = {}, learned = {} }
    local db = u.consumables
    db.chars = db.chars or {}
    db.learned = db.learned or {}
    return db
end

-- this character's list
function CO:Mine(who)
    local db = self:DB()
    who = who or ns.me or "?"
    local c = db.chars[who]
    if not c then
        c = { want = {}, mine = {} }
        db.chars[who] = c
    end
    c.want = c.want or {}
    c.mine = c.mine or {}
    return c
end

function CO:Reminds() return self:DB().remind == true end
function CO:SetRemind(on) self:DB().remind = on and true or false end

-- ---------------------------------------------------------------------
-- Items: names and icons from the game
-- ---------------------------------------------------------------------
local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and ns.Safe.Call(C_Item.GetItemNameByID, id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return ns.Safe.Text(n)
end
CO.ItemName = itemName

function CO.ItemIcon(id)
    local icon = C_Item and C_Item.GetItemIconByID and ns.Safe.Call(C_Item.GetItemIconByID, id)
    return icon or 134400
end

local function spellName(id)
    local n = C_Spell and C_Spell.GetSpellName and ns.Safe.Call(C_Spell.GetSpellName, id)
    return ns.Safe.Text(n)
end

local function itemSpell(id)
    if not (C_Item and C_Item.GetItemSpell) then return nil end
    local ok, _, sid = pcall(C_Item.GetItemSpell, id)
    return ok and ns.Safe.Num(sid) or nil
end

-- the quality rank of an item you added yourself (nil: none or unknown)
local function craftedRank(id)
    local f = C_TradeSkillUI and C_TradeSkillUI.GetItemCraftedQualityByItemInfo
    local q = f and ns.Safe.Call(f, id)
    q = ns.Safe.Num(q)
    return (q and q > 0) and q or nil
end

-- ---------------------------------------------------------------------
-- Bags: every item number and how many (bags only - not the bank)
-- ---------------------------------------------------------------------
function CO:BagCounts()
    local out = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and ns.Safe.Num(info.itemID)
            if id then out[id] = (out[id] or 0) + (ns.Safe.Num(info.stackCount) or 1) end
        end
    end
    return out
end

-- Health potions are known by the spell they use: remember the item
-- numbers of any in your bags (account-wide, so every character knows them).
function CO:Learn(counts)
    local spells = {}
    for _, b in ipairs(self.BUILTIN) do if b.spell then spells[b.spell] = true end end
    local learned = self:DB().learned
    local changed = false
    for id in pairs(counts or self:BagCounts()) do
        local sid = itemSpell(id)
        if sid and spells[sid] then
            local list = learned[sid] or {}
            learned[sid] = list
            local have = false
            for _, x in ipairs(list) do if x == id then have = true end end
            if not have then
                list[#list + 1] = id
                table.sort(list)                    -- lower number first: rank 1 before rank 2
                changed = true
            end
        end
    end
    return changed
end

-- ---------------------------------------------------------------------
-- The list: one entry per item (each rank its own), grouped
-- ---------------------------------------------------------------------
-- entry = { id, group, rank, name, icon, have, want, short, builtin, mine, spell }
function CO:Entries()
    local c = self:Mine()
    local counts = self:BagCounts()
    local learned = self:DB().learned
    local out, seen = {}, {}
    local function add(id, group, rank, o)
        if seen[id] then return end
        seen[id] = true
        local want = c.want[id] or 0
        local have = counts[id] or 0
        local e = { id = id, group = group, rank = rank, name = itemName(id) or (o and o.english) or ("Item " .. id),
                    icon = self.ItemIcon(id), have = have, want = want, short = math.max(0, want - have) }
        if o then for k, v in pairs(o) do if e[k] == nil then e[k] = v end end end
        out[#out + 1] = e
    end
    for _, b in ipairs(self.BUILTIN) do
        if b.ranks then
            for r, id in ipairs(b.ranks) do add(id, b.group, r, { builtin = true }) end
        elseif b.ids then
            for _, id in ipairs(b.ids) do add(id, b.group, nil, { builtin = true }) end
        elseif b.spell then
            local ids = learned[b.spell]
            if ids and #ids > 0 then
                for r, id in ipairs(ids) do add(id, b.group, #ids > 1 and r or nil, { builtin = true, english = b.english }) end
            else
                -- not seen yet: a placeholder until one is in your bags
                out[#out + 1] = { group = b.group, spell = b.spell, name = spellName(b.spell) or b.english,
                                  icon = 134830, have = 0, want = 0, short = 0, builtin = true, pending = true }
            end
        end
    end
    for _, m in ipairs(c.mine) do
        add(m.id, m.group or "mine", craftedRank(m.id), { mine = true })
    end
    return out
end

-- grouped and sorted for the window; all = every item, else only tracked
-- ones (a Want above 0). Returns a list of { header = group } / entry rows.
function CO:Rows(all)
    local byGroup = {}
    for _, e in ipairs(self:Entries()) do
        if all or e.want > 0 then
            byGroup[e.group] = byGroup[e.group] or {}
            table.insert(byGroup[e.group], e)
        end
    end
    local rows = {}
    for _, g in ipairs(self.GROUPS) do
        local list = byGroup[g.key]
        if list and #list > 0 then
            if g.key == "food" or g.key == "mine" then
                table.sort(list, function(a, b) if a.name ~= b.name then return a.name < b.name end return (a.rank or 0) < (b.rank or 0) end)
            end
            rows[#rows + 1] = { header = g.key, name = g.name }
            for _, e in ipairs(list) do rows[#rows + 1] = e end
        end
    end
    return rows
end

-- what you're short on: list of entries, and how many things
function CO:Short()
    local out = {}
    for _, e in ipairs(self:Entries()) do
        if e.short > 0 then out[#out + 1] = e end
    end
    return out
end

function CO:Tracked()
    local n = 0
    for _, e in ipairs(self:Entries()) do if e.want > 0 then n = n + 1 end end
    return n
end

function CO:SetWant(id, n)
    if not id then return end
    n = math.max(0, math.min(self.MAX_WANT, math.floor(tonumber(n) or 0)))
    self:Mine().want[id] = n > 0 and n or nil
end

-- ---------------------------------------------------------------------
-- Adding your own items (item number only: any language, any patch)
-- ---------------------------------------------------------------------
function CO:IsListed(id)
    for _, e in ipairs(self:Entries()) do if e.id == id then return e end end
    return nil
end

-- text: an item link, an item number, or a name the game knows (an item
-- in your bags, or one it has loaded). Returns the item number or nil, why.
function CO:Resolve(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "Shift-click an item into the box, drag one in, or type its name." end
    local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^(%d+)$"))
    if id then return id end
    local name = text:lower()
    for _, e in ipairs(self:Entries()) do               -- already listed (any language: the game's names)
        if e.id and e.name:lower() == name then return e.id end
    end
    for bid in pairs(self:BagCounts()) do
        local n = itemName(bid)
        if n and n:lower() == name then return bid end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local iid = ns.Safe.Call(C_Item.GetItemInfoInstant, text)
        iid = ns.Safe.Num(iid)
        if iid then return iid end
    end
    return nil, "The game doesn't know \"" .. text .. "\" by name yet. Shift-click or drag the item in instead."
end

function CO:Add(text, group)
    local id, why = self:Resolve(text)
    if not id then return false, why end
    local listed = self:IsListed(id)
    if listed then
        return false, (listed.name or "That item") .. " is already on the list (" .. (self.GROUP_NAME[listed.group] or "") .. ")."
    end
    local c = self:Mine()
    if #c.mine >= self.MAX_MINE then return false, "Your list is full (" .. self.MAX_MINE .. " items of your own)." end
    group = self.GROUP_NAME[group] and group or "mine"
    c.mine[#c.mine + 1] = { id = id, group = group }
    return true, id
end

function CO:Remove(id)
    local c = self:Mine()
    for i, m in ipairs(c.mine) do
        if m.id == id then
            table.remove(c.mine, i)
            c.want[id] = nil
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Copy another of your characters' lists onto this one
-- ---------------------------------------------------------------------
function CO:OtherChars()
    local out = {}
    for name, c in pairs(self:DB().chars) do
        if name ~= ns.me and (next(c.want or {}) or #(c.mine or {}) > 0) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function CO:CopyFrom(who)
    local src = self:DB().chars[who]
    if not src or who == ns.me then return false end
    local c = self:Mine()
    c.want, c.mine = {}, {}
    for id, n in pairs(src.want or {}) do c.want[id] = n end
    for _, m in ipairs(src.mine or {}) do c.mine[#c.mine + 1] = { id = m.id, group = m.group } end
    return true
end

-- ---------------------------------------------------------------------
-- The reminder: zoning into a raid while short (off by default)
-- ---------------------------------------------------------------------
local function inRaidInstance()
    local inside, kind = IsInInstance()
    return inside and kind == "raid"
end

local function instanceKey()
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    return tostring(id or name or "?")
end

-- the line in the notice: "Short on 3: Flask of the Magisters, ..."
function CO:ShortText(list)
    list = list or self:Short()
    if #list == 0 then return nil end
    local names = {}
    for i, e in ipairs(list) do
        if i > 2 then break end
        names[#names + 1] = e.name .. (e.rank and (" (rank " .. e.rank .. ")") or "")
    end
    local more = #list > 2 and (" +" .. (#list - 2) .. " more") or ""
    return ("Consumables: short on %d - %s%s"):format(#list, table.concat(names, ", "), more)
end

function CO:CheckRaid()
    if not self:Reminds() then return end
    if not inRaidInstance() then self.remindedFor = nil return end
    local key = instanceKey()
    if self.remindedFor == key then return end          -- once each time you zone in
    if InCombatLockdown() then self.waitCombat = true return end
    self.remindedFor = key
    local text = self:ShortText()
    if text and ns.Dock and ns.Dock.Notice then
        ns.Dock:Notice(text, "Open list", function() ns.ConsumablesUI:Open() end)
    end
end

function CO:Init()
    self:DB()
    self:Mine()
    local function bags()
        ns.Debounce("consumables-bags", 0.5, function()
            local changed = CO:Learn()
            local V = ns.ConsumablesUI
            if V and V.frame and V.frame:IsShown() then V:Refresh() elseif changed and V then V.dirty = true end
        end)
    end
    ns.On("BAG_UPDATE_DELAYED", bags)
    local function zone() ns.Debounce("consumables-zone", 3, function() CO:CheckRaid() end) end
    ns.On("PLAYER_ENTERING_WORLD", zone)
    ns.On("ZONE_CHANGED_NEW_AREA", zone)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if CO.waitCombat then CO.waitCombat = nil; zone() end
    end)
    bags()
end
