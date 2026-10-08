-- Titan Up - Share/MacroBuilder.lua
-- Macro Workstation > Builder: helps players who aren't good with macros.
-- Pick an ability (your spellbook, or any class's hand-picked list), tick
-- where it should land (whoever you hover, your focus, the ground under
-- the mouse, yourself, your target), add extras (a hold-a-key target,
-- stop casting first, one or both trinkets before / after it), and read
-- the macro text and a plain-English "what this does" as you go. Then save
-- it as one of your character macros (it lands on your cursor, ready for a
-- bar) or hand it to the Share tab to send.
--   * Your class's interrupt is always the first pick (the one your spec
--     actually has).
--   * Other classes: a hand-picked list per class (talents included), so
--     you can build a macro for someone else and send it to them.
--   * Trinkets go by slot (/use 13, /use 14), so a macro keeps working
--     after you swap trinkets. Drag a trinket, potion or Healthstone in.
--   * WoW doesn't let addons create macros in combat: Save waits.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local MB = {}
ns.MacroBuilder = MB

MB.QUESTION = 134400            -- the "?" macro icon: with #showtooltip the game shows the spell's own

-- ---------------------------------------------------------------------
-- Hand-picked spells per class. The macro uses the name; the ID is only
-- for the icon (and the client's own spelling outside English).
-- kind: harm | help | rez | ground | self
-- ---------------------------------------------------------------------
MB.CLASS_ORDER = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
MB.CLASS_NAMES = {
    DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", DRUID = "Druid", EVOKER = "Evoker", HUNTER = "Hunter", MAGE = "Mage",
    MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}
-- interrupts: the first one you know wins; note = who has it
MB.INTERRUPTS = {
    DEATHKNIGHT = { { 47528, "Mind Freeze" } },
    DEMONHUNTER = { { 183752, "Disrupt" } },
    DRUID       = { { 106839, "Skull Bash", "Feral and Guardian" }, { 78675, "Solar Beam", "Balance" } },
    EVOKER      = { { 351338, "Quell" } },
    HUNTER      = { { 147362, "Counter Shot", "Beast Mastery and Marksmanship" }, { 187707, "Muzzle", "Survival" } },
    MAGE        = { { 2139, "Counterspell" } },
    MONK        = { { 116705, "Spear Hand Strike" } },
    PALADIN     = { { 96231, "Rebuke" } },
    PRIEST      = { { 15487, "Silence", "Shadow" } },
    ROGUE       = { { 1766, "Kick" } },
    SHAMAN      = { { 57994, "Wind Shear" } },
    WARLOCK     = { { 19647, "Spell Lock", "needs the Felhunter" } },
    WARRIOR     = { { 6552, "Pummel" } },
}
MB.SPELLS = {
    DEATHKNIGHT = { { 49576, "Death Grip", "harm" }, { 61999, "Raise Ally", "rez" }, { 51052, "Anti-Magic Zone", "ground" }, { 43265, "Death and Decay", "ground" },
                    { 221562, "Asphyxiate", "harm" }, { 48792, "Icebound Fortitude", "self" } },
    DEMONHUNTER = { { 217832, "Imprison", "harm" }, { 207684, "Sigil of Misery", "ground" }, { 202137, "Sigil of Silence", "ground" }, { 278326, "Consume Magic", "harm" },
                    { 196718, "Darkness", "self" }, { 198589, "Blur", "self" } },
    DRUID       = { { 20484, "Rebirth", "rez" }, { 29166, "Innervate", "help" }, { 102342, "Ironbark", "help" }, { 88423, "Nature's Cure", "help" },
                    { 2782, "Remove Corruption", "help" }, { 33786, "Cyclone", "harm" }, { 2908, "Soothe", "harm" }, { 102793, "Ursol's Vortex", "ground" },
                    { 106898, "Stampeding Roar", "self" }, { 22812, "Barkskin", "self" } },
    EVOKER      = { { 370665, "Rescue", "help" }, { 357170, "Time Dilation", "help" }, { 374251, "Cauterizing Flame", "help" }, { 360823, "Naturalize", "help" },
                    { 365585, "Expunge", "help" }, { 360806, "Sleep Walk", "harm" }, { 358385, "Landslide", "ground" }, { 374968, "Time Spiral", "self" },
                    { 363916, "Obsidian Scales", "self" } },
    HUNTER      = { { 34477, "Misdirection", "help" }, { 19801, "Tranquilizing Shot", "harm" }, { 109248, "Binding Shot", "ground" }, { 187650, "Freezing Trap", "ground" },
                    { 187698, "Tar Trap", "ground" }, { 186265, "Aspect of the Turtle", "self" } },
    MAGE        = { { 118, "Polymorph", "harm" }, { 30449, "Spellsteal", "harm" }, { 475, "Remove Curse", "help" }, { 113724, "Ring of Frost", "ground" },
                    { 342245, "Alter Time", "self" }, { 45438, "Ice Block", "self" } },
    MONK        = { { 115078, "Paralysis", "harm" }, { 116849, "Life Cocoon", "help" }, { 116841, "Tiger's Lust", "help" }, { 115450, "Detox", "help" },
                    { 116844, "Ring of Peace", "ground" }, { 119381, "Leg Sweep", "self" }, { 115203, "Fortifying Brew", "self" } },
    PALADIN     = { { 6940, "Blessing of Sacrifice", "help" }, { 1044, "Blessing of Freedom", "help" }, { 1022, "Blessing of Protection", "help" },
                    { 633, "Lay on Hands", "help" }, { 4987, "Cleanse", "help" }, { 213644, "Cleanse Toxins", "help" }, { 391054, "Intercession", "rez" },
                    { 853, "Hammer of Justice", "harm" }, { 642, "Divine Shield", "self" } },
    PRIEST      = { { 17, "Power Word: Shield", "help" }, { 10060, "Power Infusion", "help" }, { 33206, "Pain Suppression", "help" }, { 47788, "Guardian Spirit", "help" },
                    { 73325, "Leap of Faith", "help" }, { 527, "Purify", "help" }, { 213634, "Purify Disease", "help" }, { 528, "Dispel Magic", "harm" },
                    { 32375, "Mass Dispel", "ground" }, { 121536, "Angelic Feather", "ground" }, { 8122, "Psychic Scream", "self" } },
    ROGUE       = { { 57934, "Tricks of the Trade", "help" }, { 2094, "Blind", "harm" }, { 408, "Kidney Shot", "harm" }, { 6770, "Sap", "harm" },
                    { 36554, "Shadowstep", "harm" }, { 31224, "Cloak of Shadows", "self" } },
    SHAMAN      = { { 51514, "Hex", "harm" }, { 370, "Purge", "harm" }, { 51886, "Cleanse Spirit", "help" }, { 77130, "Purify Spirit", "help" },
                    { 192058, "Capacitor Totem", "ground" }, { 98008, "Spirit Link Totem", "ground" }, { 192077, "Wind Rush Totem", "ground" },
                    { 2484, "Earthbind Totem", "ground" }, { 383013, "Poison Cleansing Totem", "self" }, { 8143, "Tremor Totem", "self" }, { 108271, "Astral Shift", "self" } },
    WARLOCK     = { { 30283, "Shadowfury", "ground" }, { 111771, "Demonic Gateway", "ground" }, { 5782, "Fear", "harm" }, { 710, "Banish", "harm" },
                    { 6789, "Mortal Coil", "harm" }, { 20707, "Soulstone", "help" }, { 104773, "Unending Resolve", "self" } },
    WARRIOR     = { { 3411, "Intervene", "help" }, { 64382, "Shattering Throw", "harm" }, { 6544, "Heroic Leap", "ground" }, { 97462, "Rallying Cry", "self" },
                    { 23920, "Spell Reflection", "self" } },
}
-- every hand-picked name -> its kind (also used for your own spellbook)
MB.KIND_BY_NAME = {}
for _, list in pairs(MB.SPELLS) do for _, s in ipairs(list) do MB.KIND_BY_NAME[s[2]] = s[3] end end
for _, list in pairs(MB.INTERRUPTS) do for _, s in ipairs(list) do MB.KIND_BY_NAME[s[2]] = "harm" end end

-- ---------------------------------------------------------------------
-- What each kind of ability can be aimed at
-- ---------------------------------------------------------------------
--   any     = a spell from your book we know nothing about (everything offered)
--   trinket = one or both trinket slots on their own
--   useitem = an item from your bags (potion, Healthstone): no target
MB.TARGETS = {
    { id = "mouseover", label = "Whoever I'm hovering",       tip = "Raid frames, or the player or enemy under your mouse in the world." },
    { id = "focus",     label = "My focus",                   tip = "Set one with /focus. Great for interrupts." },
    { id = "cursor",    label = "The ground under my mouse",  tip = "Drops right where you point - no circle to click." },
    { id = "player",    label = "Myself",                     tip = "Always lands on you." },
    { id = "target",    label = "My target",                  tip = "The normal fallback." },
}
MB.ALLOWED = {
    harm = { mouseover = true, focus = true, target = true },
    help = { mouseover = true, focus = true, player = true, target = true },
    rez = { mouseover = true, focus = true, target = true },
    ground = { cursor = true, player = true, target = true },
    self = {}, useitem = {},
    any = { mouseover = true, focus = true, cursor = true, player = true, target = true },
    trinket = { mouseover = true, focus = true, player = true, target = true },
}
MB.DEFAULTS = {
    harm = { "mouseover", "target" }, help = { "mouseover", "target" }, rez = { "mouseover", "target" },
    ground = { "cursor" }, self = {}, useitem = {}, any = {}, trinket = {},
}
MB.INTERRUPT_DEFAULTS = { "focus", "mouseover", "target" }
local FLAGS = { harm = ",harm,nodead", help = ",help,nodead", rez = ",help,dead", any = ",exists", trinket = ",exists,nodead", ground = "" }
local CHECKS = { harm = " if it's an enemy that's alive", help = " if it's a friendly player that's alive", rez = " if it's a dead friendly player",
                 any = " if there's someone there", trinket = " if there's someone there" }
local SAY = { mouseover = "the one under your mouse", focus = "your focus", cursor = "the ground under your mouse", player = "you", target = "your target" }
MB.SLOT_NAME = { [13] = "your top trinket", [14] = "your bottom trinket" }
MB.KIND_TEXT = { harm = "Enemy", help = "Helpful", rez = "Battle rez", ground = "Ground-targeted", self = "Self only", any = "Spell", useitem = "Item" }

-- The order the target options are tried in (an interrupt tries focus first).
function MB.Order(sel)
    local out = {}
    for _, t in ipairs(MB.TARGETS) do out[#out + 1] = t end
    if sel and sel.interrupt then out[1], out[2] = out[2], out[1] end
    return out
end

local function cond(id, kind)
    if id == "cursor" then return "[@cursor]" end
    if id == "player" then return "[@player]" end
    if id == "target" then return "[]" end
    return ("[@%s%s]"):format(id, FLAGS[kind] or "")
end

-- st = { sel = { name, kind, interrupt } or nil, targets = { id = true },
--        mod = { on, key, unit }, stop, tip, trinkets = { [13] = true }, order = "before" | "after" }
-- -> the macro text and the plain-English steps (nil when nothing is picked)
function MB.Compose(st)
    local sel = st.sel
    local slots = {}
    for _, s in ipairs({ 13, 14 }) do if st.trinkets and st.trinkets[s] then slots[#slots + 1] = s end end
    if not sel and #slots == 0 then return nil, {} end
    local kind = sel and sel.kind or "trinket"
    local allowed = MB.ALLOWED[kind] or {}
    local parts, steps = {}, {}
    if st.mod and st.mod.on and next(allowed) then
        parts[#parts + 1] = ("[mod:%s,@%s]"):format(st.mod.key, st.mod.unit)
        steps[#steps + 1] = ("Holding %s: lands on %s."):format(st.mod.key:upper(), SAY[st.mod.unit] or st.mod.unit)
    end
    for _, t in ipairs(MB.Order(sel)) do
        if st.targets[t.id] and allowed[t.id] then
            parts[#parts + 1] = cond(t.id, kind)
            local plain = (t.id == "mouseover" or t.id == "focus") and (CHECKS[kind] or "") or ""
            steps[#steps + 1] = ("Otherwise %s%s."):format(SAY[t.id], plain)
        end
    end
    -- a lone "[]" says nothing
    if #parts == 1 and parts[1] == "[]" then parts = {}; steps = {} end
    if steps[1] then steps[1] = steps[1]:gsub("^Otherwise (.)", function(c) return c:upper() end) end
    local c = #parts > 0 and (table.concat(parts) .. " ") or ""
    local lines = {}
    -- with a trinket line first, #showtooltip names the ability (or the button shows the trinket)
    local first = sel and kind ~= "useitem" and #slots > 0 and st.order ~= "after"
    if st.tip then lines[#lines + 1] = first and ("#showtooltip " .. sel.name) or "#showtooltip" end
    if st.stop then lines[#lines + 1] = "/stopcasting"; table.insert(steps, 1, "Stops what you're casting.") end
    local whose = {}
    for _, s in ipairs(slots) do whose[#whose + 1] = MB.SLOT_NAME[s] end
    whose = table.concat(whose, " and ")
    if sel then
        if kind == "self" then steps[#steps + 1] = "Casts on you." end
        if kind == "useitem" then steps[#steps + 1] = "Uses one from your bags." end
        if #parts == 0 and kind ~= "self" and kind ~= "useitem" then steps[#steps + 1] = "Casts it the normal way." end
        local main = (kind == "useitem" and "/use " or "/cast ") .. c .. sel.name
        local tr = {}
        if kind ~= "useitem" then for _, s in ipairs(slots) do tr[#tr + 1] = "/use " .. s end end
        if #tr > 0 then
            steps[#steps + 1] = st.order == "after" and ("Fires the ability, then " .. whose .. ".") or ("Fires " .. whose .. " first, then the ability.")
        end
        if st.order == "after" then
            lines[#lines + 1] = main
            for _, l in ipairs(tr) do lines[#lines + 1] = l end
        else
            for _, l in ipairs(tr) do lines[#lines + 1] = l end
            lines[#lines + 1] = main
        end
    else
        for _, s in ipairs(slots) do lines[#lines + 1] = "/use " .. c .. s end
        steps[#steps + 1] = "Uses " .. whose .. " - whatever you have equipped there."
    end
    return table.concat(lines, "\n"), steps
end

-- ---------------------------------------------------------------------
-- The game: classes, spells, trinkets
-- ---------------------------------------------------------------------
function MB.MyClass()
    local cl = ns.Safe.Class("player")
    if cl and MB.SPELLS[cl] then return cl end
    return "WARRIOR"
end

local function spellInfo(id)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return info end
end

local function knows(id)
    for _, fn in ipairs({ C_SpellBook and C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown }) do
        if fn then
            local ok, r = pcall(fn, id)
            if ok and r == true then return true end
        end
    end
    -- a pet's spell (Spell Lock)
    if IsSpellKnown then
        local ok, r = pcall(IsSpellKnown, id, true)
        if ok and r == true then return true end
    end
    return false
end
MB.Knows = knows

-- A hand-picked entry as an ability: the client's own name when the ID
-- resolves (other languages), our name otherwise; its icon when it matches.
local english = not GetLocale or GetLocale() == "enUS" or GetLocale() == "enGB"
function MB.Entry(id, name, kind, extra)
    local e = { id = id, name = name, kind = kind, icon = MB.QUESTION }
    local info = spellInfo(id)
    local real = info and ns.Safe.Text(info.name)
    if real and (not english or real == name) then
        e.name = real
        e.icon = ns.Safe.Num(info.iconID) or MB.QUESTION
    end
    if extra then for k, v in pairs(extra) do e[k] = v end end
    return e
end

-- Your class's interrupt (the one you know), or another class's first.
function MB.Interrupt(class, mine)
    local list = MB.INTERRUPTS[class]
    if not list then return nil end
    local pick = list[1]
    if mine then for _, s in ipairs(list) do if knows(s[1]) then pick = s; break end end end
    local note = (not mine and #list > 1) and (list[2][2] .. " for " .. list[2][3]) or (pick[3] and pick[3]:find("needs") and pick[3]) or nil
    return MB.Entry(pick[1], pick[2], "harm", { interrupt = true, note = note })
end

-- How to aim one of your own spells: our list first, then the game's
-- helpful / harmful flags, otherwise every option is offered.
function MB.KindOf(id, name)
    if MB.KIND_BY_NAME[name] then return MB.KIND_BY_NAME[name] end
    if C_Spell then
        if C_Spell.IsSpellHarmful then local ok, r = pcall(C_Spell.IsSpellHarmful, id); if ok and r == true then return "harm" end end
        if C_Spell.IsSpellHelpful then local ok, r = pcall(C_Spell.IsSpellHelpful, id); if ok and r == true then return "help" end end
    end
    return "any"
end

-- Your spellbook: active spells of your class and spec (talents you've
-- taken are in it), plus the General tab. Nil when the game won't say.
function MB.MySpells()
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo) then return nil end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local out, seen = {}, {}
    local okN, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okN or type(n) ~= "number" then return nil end
    for line = 1, n do
        local ok, li = pcall(C_SpellBook.GetSpellBookSkillLineInfo, line)
        if ok and type(li) == "table" and not li.offSpecID and not li.shouldHide then
            local first, count = ns.Safe.Num(li.itemIndexOffset) or 0, ns.Safe.Num(li.numSpellBookItems) or 0
            for i = first + 1, first + count do
                local ok2, it = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                local name = ok2 and type(it) == "table" and ns.Safe.Text(it.name)
                local id = name and ns.Safe.Num(it.spellID)
                if id and (spellType == nil or it.itemType == spellType) and not it.isPassive and not it.isOffSpec and not seen[name] then
                    seen[name] = true
                    out[#out + 1] = { id = id, name = name, kind = MB.KindOf(id, name), icon = ns.Safe.Num(it.iconID) or MB.QUESTION }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return #out > 0 and out or nil
end

-- The list to pick from: yours (spellbook) or another class's hand-picked
-- one, without the interrupt (it's pinned above the list).
function MB.SpellList(class, mine)
    local int = MB.Interrupt(class, mine)
    local list = mine and MB.MySpells() or nil
    if not list then
        list = {}
        for _, s in ipairs(MB.SPELLS[class] or {}) do
            if not mine or knows(s[1]) or not (C_SpellBook or IsPlayerSpell) then list[#list + 1] = MB.Entry(s[1], s[2], s[3]) end
        end
    end
    local out = {}
    for _, e in ipairs(list) do if not (int and e.name == int.name) then out[#out + 1] = e end end
    return out, int
end

-- A trinket slot: { slot, itemID, name, icon, onUse }
local function itemName(id)
    if C_Item and C_Item.GetItemNameByID then local ok, n = pcall(C_Item.GetItemNameByID, id); if ok and n then return ns.Safe.Text(n) end end
    if GetItemInfo then local ok, n = pcall(GetItemInfo, id); if ok and n then return ns.Safe.Text(n) end end
end
MB.ItemName = itemName
local function itemSpell(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return nil end
    local ok, n = pcall(fn, id)
    if ok then return n and true or false end
end
function MB.Trinket(slot)
    local id = GetInventoryItemID and ns.Safe.Num((GetInventoryItemID("player", slot)))
    local t = { slot = slot, itemID = id }
    if id then
        t.name = itemName(id)
        t.icon = GetInventoryItemTexture and ns.Safe.Num((GetInventoryItemTexture("player", slot))) or nil
        if t.name then t.onUse = itemSpell(id) end     -- nil: the game hasn't loaded it yet
    end
    return t
end

-- ---------------------------------------------------------------------
-- Saving it as one of your macros
-- ---------------------------------------------------------------------
function MB.CleanName(name)
    return ns.MacroShare.CleanName(name)
end

function MB:Save(name, icon, body)
    name = MB.CleanName(name)
    if name == "" then ns.Print("Give the macro a name.") return false end
    if #body > ns.MacroShare.BODY_MAX then ns.Print("That macro is too long for WoW (255 characters).") return false end
    return ns.MacroShare:PickUp({ name = name, icon = icon, body = body })
end

function MB:Init()
    ns.On("PLAYER_REGEN_ENABLED", function() if ns.MacroBuilderUI then ns.MacroBuilderUI:Refresh() end end)
    ns.On("PLAYER_REGEN_DISABLED", function() if ns.MacroBuilderUI then ns.MacroBuilderUI:Refresh() end end)
    ns.On("PLAYER_EQUIPMENT_CHANGED", function() if ns.MacroBuilderUI then ns.MacroBuilderUI:Refresh() end end)
    ns.On("CURSOR_CHANGED", function() if ns.MacroBuilderUI then ns.MacroBuilderUI:RefreshDrop() end end)
    ns.On("SPELLS_CHANGED", function() if ns.MacroBuilderUI then ns.MacroBuilderUI.dirty = true end end)
end

-- ---------------------------------------------------------------------
-- Window: pick (left) | aim, extras, preview (right)
-- ---------------------------------------------------------------------
local V = {}
ns.MacroBuilderUI = V
local W, H, COL = 880, 570, 440
local PER_PAGE, BTN_W, BTN_H = 12, 200, 28

local function check(parent, label, tip, get, set)
    local c = UI.Check(parent, label, tip, get, set)
    c:SetScript("OnClick", function(s) if s.off then return end set(not get()); s:Refresh(); V:Build() end)
    return c
end

-- a button with an icon on its left and a line of text
local function pickButton(parent, w, h, onClick)
    local b = UI.Button(parent, w, h, "", nil, onClick)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(h - 6, h - 6)
    b.icon:SetPoint("LEFT", 3, 0)
    b.keepIconColor = true
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", h + 2, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    return b
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpMacroBuilder", "macrobuilder", "MACRO BUILDER", W, H)
    self.class = MB.MyClass()
    self.page = 1
    self.st = { targets = {}, mod = { on = false, key = "alt", unit = "player" }, stop = false, tip = true, trinkets = {}, order = "before" }

    -- left: pick an ability
    UI.Text(f, "GameFontNormalSmall", C.accent, "1  PICK AN ABILITY", "TOPLEFT", 16, -14)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "or drag a spell or item in", "TOPLEFT", 150, -15)
    self.classBtn = UI.Button(f, 140, 24, "", "See another class's spells (to build a macro for them)", function() V:ClassMenu() end)
    self.classBtn:SetPoint("TOPLEFT", 16, -34)
    self.search = UI.EditBox(f, COL - 16 - 150 - 16, 24, { inset = 6 })
    self.search:SetPoint("TOPLEFT", 164, -34)
    self.search:SetScript("OnTextChanged", function() V.page = 1; V:RefreshList() end)
    self.searchHint = UI.Text(self.search, "GameFontHighlightSmall", C.muted, "Search", "LEFT", 8, 0)

    self.pin = pickButton(f, COL - 32, 34, function() V:Pick(V.interrupt) end)
    self.pin:SetPoint("TOPLEFT", 16, -66)
    self.pin.tag = UI.Text(self.pin, "GameFontNormalSmall", C.accent, "", "RIGHT", -8, 0)
    self.pin.label:SetPoint("RIGHT", -120, 0)

    self.btns = {}
    for i = 1, PER_PAGE do
        local b = pickButton(f, BTN_W, BTN_H, nil)
        b:SetScript("OnClick", function(s) if s.entry then V:Pick(s.entry) end end)
        b:SetPoint("TOPLEFT", 16 + ((i - 1) % 2) * (BTN_W + 8), -108 - math.floor((i - 1) / 2) * (BTN_H + 4))
        self.btns[i] = b
    end
    self.prev = UI.Button(f, 24, 20, "<", "Previous page", function() V.page = V.page - 1; V:RefreshList() end)
    self.prev:SetPoint("TOPLEFT", 16, -306)
    self.pageText = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "LEFT", self.prev, "RIGHT", 8, 0)
    self.next = UI.Button(f, 24, 20, ">", "Next page", function() V.page = V.page + 1; V:RefreshList() end)
    self.next:SetPoint("LEFT", self.pageText, "RIGHT", 8, 0)
    self.none = UI.Text(f, "GameFontHighlightSmall", C.muted, "No spells match.", "TOPLEFT", 18, -112)

    self.gearHead = UI.Text(f, "GameFontNormalSmall", C.accent, "YOUR TRINKETS", "TOPLEFT", 16, -338)
    self.gearHint = UI.Text(f, "GameFontHighlightSmall", C.muted, "click to add to the ability - or on their own", "LEFT", self.gearHead, "RIGHT", 8, 0)
    self.gear = {}
    for i, slot in ipairs({ 13, 14 }) do
        local b = pickButton(f, BTN_W, BTN_H, function() V:ToggleTrinket(slot) end)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * (BTN_W + 8), -356)
        b.slot = slot
        self.gear[i] = b
    end
    local drop = CreateFrame("Button", nil, f, "BackdropTemplate")
    drop:SetSize(COL - 32, 34)
    drop:SetPoint("TOPLEFT", 16, -394)
    UI.Skin(drop, C.canvas, C.line)
    drop.text = UI.Text(drop, "GameFontHighlightSmall", C.muted, nil, "CENTER")
    drop:SetScript("OnClick", function() V:TakeCursor() end)
    drop:SetScript("OnReceiveDrag", function() V:TakeCursor() end)
    self.drop = drop
    self.other = UI.Text(f, "GameFontHighlightSmall", C.warn, nil, "TOPLEFT", 16, -440)
    self.other:SetWidth(COL - 32); self.other:SetJustifyH("LEFT")
    for _, w in ipairs({ self.pin, self.search }) do w:SetScript("OnReceiveDrag", function() V:TakeCursor() end) end

    -- right: where it lands, extras, preview
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", COL, -10); sep:SetPoint("BOTTOMLEFT", COL, 10); sep:SetWidth(1)
    local X = COL + 16
    UI.Text(f, "GameFontNormalSmall", C.accent, "2  WHERE SHOULD IT LAND?", "TOPLEFT", X, -14)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "tried top to bottom", "TOPLEFT", X + 170, -15)
    self.targetChecks = {}
    for i = 1, #MB.TARGETS do
        local c
        c = check(f, "", nil, function() return c and c.id and V.st.targets[c.id] or false end,
            function(v) if c.id then V.st.targets[c.id] = v or nil end end)
        c:SetPoint("TOPLEFT", X, -34 - (i - 1) * 22)
        self.targetChecks[i] = c
    end
    self.selfNote = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", X, -36)

    UI.Text(f, "GameFontNormalSmall", C.accent, "3  EXTRAS", "TOPLEFT", X, -148)
    self.modCheck = check(f, "Hold", "Holding the key sends it there, even while you hover someone else.",
        function() return V.st.mod.on end, function(v) V.st.mod.on = v end)
    self.modCheck:SetPoint("TOPLEFT", X, -168)
    self.modKey = UI.Button(f, 60, 20, "", "Which key", function() V:ModMenu("key") end)
    self.modKey:SetPoint("LEFT", self.modCheck.text, "RIGHT", 6, 0)
    self.modTo = UI.Text(f, "GameFontHighlightSmall", C.text, "to cast it on", "LEFT", self.modKey, "RIGHT", 6, 0)
    self.modUnit = UI.Button(f, 90, 20, "", "Who", function() V:ModMenu("unit") end)
    self.modUnit:SetPoint("LEFT", self.modTo, "RIGHT", 6, 0)
    self.stopCheck = check(f, "Stop what I'm casting first", "For interrupts and emergency buttons.",
        function() return V.st.stop end, function(v) V.st.stop = v end)
    self.stopCheck:SetPoint("TOPLEFT", X, -192)
    self.tipCheck = check(f, "Show the spell's icon and cooldown on the button", nil,
        function() return V.st.tip end, function(v) V.st.tip = v end)
    self.tipCheck:SetPoint("TOPLEFT", X, -214)
    self.orderText = UI.Text(f, "GameFontHighlightSmall", C.text, "Trinkets go", "TOPLEFT", X + 22, -238)
    self.orderBtn = UI.Button(f, 64, 20, "", "Trinkets don't wait on the global cooldown, so either order fires everything. Before: the buff is already up when the ability lands.", function()
        V.st.order = V.st.order == "before" and "after" or "before"; V:Build()
    end)
    self.orderBtn:SetPoint("LEFT", self.orderText, "RIGHT", 6, 0)
    self.orderTail = UI.Text(f, "GameFontHighlightSmall", C.text, "the ability", "LEFT", self.orderBtn, "RIGHT", 6, 0)

    UI.Text(f, "GameFontNormalSmall", C.accent, "PREVIEW", "TOPLEFT", X, -266)
    self.count = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", f, "TOPRIGHT", -16, -266)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", X, -282); box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -282); box:SetHeight(104)
    UI.Skin(box, C.canvas, C.line)
    self.preview = UI.Text(box, "ChatFontNormal", C.text, nil, "TOPLEFT", 8, -6)
    self.preview:SetPoint("RIGHT", -8, 0); self.preview:SetJustifyH("LEFT"); self.preview:SetJustifyV("TOP")
    UI.Text(f, "GameFontNormalSmall", C.accent, "WHAT IT DOES", "TOPLEFT", X, -394)
    self.plain = UI.Text(f, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", X, -410)
    self.plain:SetPoint("RIGHT", f, "RIGHT", -16, 0); self.plain:SetJustifyH("LEFT"); self.plain:SetJustifyV("TOP")
    self.plain:SetHeight(72)

    UI.Text(f, "GameFontHighlightSmall", C.muted, "Name", "TOPLEFT", X, -494)
    self.nameBox = UI.EditBox(f, 170, 24, { inset = 6 })
    self.nameBox:SetPoint("TOPLEFT", X + 40, -488)
    self.nameBox:SetMaxLetters(ns.MacroShare.NAME_MAX)
    self.saveBtn = UI.Button(f, 170, 28, "Save to my macros", "Adds it to your character macros and puts it on your cursor - drop it on a bar.", function() V:Save() end)
    self.saveBtn:SetPoint("TOPLEFT", X, -522)
    UI.SetActive(self.saveBtn, true)
    self.shareBtn = UI.Button(f, 150, 28, "Send to Share tab", "Fills in the Share tab so you can send it to someone.", function() V:ToShare() end)
    self.shareBtn:SetPoint("LEFT", self.saveBtn, "RIGHT", 8, 0)
    self.status = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", X + 230, -494)
    self.status:SetPoint("RIGHT", f, "RIGHT", -16, 0); self.status:SetJustifyH("LEFT")

    self:LoadClass(self.class)
end

function V:Mine() return self.class == MB.MyClass() end

function V:LoadClass(class)
    self.class = class
    self.page = 1
    self.list, self.interrupt = MB.SpellList(class, self:Mine())
    self.dirty = nil
    self:Pick(self.interrupt, true)
end

function V:ClassMenu()
    local mine = MB.MyClass()
    local items = {}
    for _, cl in ipairs(MB.CLASS_ORDER) do
        local nm = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cl]) or MB.CLASS_NAMES[cl]
        items[#items + 1] = { text = UI.ClassName(nm .. (cl == mine and " (you)" or ""), cl), checked = cl == V.class,
                              onClick = function() V.search:SetText(""); V:LoadClass(cl) end }
    end
    UI.Menu(self.classBtn, items)
end

function V:ModMenu(which)
    local items = {}
    local opts = which == "key" and { { "alt", "Alt" }, { "shift", "Shift" }, { "ctrl", "Ctrl" } }
        or { { "player", "myself" }, { "focus", "my focus" }, { "target", "my target" }, { "mouseover", "my mouseover" } }
    for _, o in ipairs(opts) do
        items[#items + 1] = { text = o[2], checked = V.st.mod[which] == o[1], onClick = function() V.st.mod[which] = o[1]; V:Build() end }
    end
    UI.Menu(which == "key" and self.modKey or self.modUnit, items)
end

-- Choosing an ability (clicking the chosen one again drops it, leaving
-- the trinkets on their own).
function V:Pick(entry, keep)
    if not keep and entry and self.st.sel and entry.name == self.st.sel.name and entry.kind == self.st.sel.kind then entry = nil end
    self.st.sel = entry
    self.st.targets = {}
    local def = entry and (entry.interrupt and MB.INTERRUPT_DEFAULTS or MB.DEFAULTS[entry.kind]) or {}
    for _, id in ipairs(def) do self.st.targets[id] = true end
    self.st.stop = entry and entry.interrupt and true or false
    if entry then self.nameBox:SetText(MB.CleanName(entry.name))
    elseif next(self.st.trinkets) then self.nameBox:SetText("Trinkets") end
    self:Refresh()
end

function V:ToggleTrinket(slot)
    if not self:Mine() then return end
    local t = MB.Trinket(slot)
    if t.onUse == false then ns.Print("That trinket has nothing to press - it works on its own.") return end
    self.st.trinkets[slot] = not self.st.trinkets[slot] or nil
    if not self.st.sel then
        self.st.targets = {}
        self.nameBox:SetText("Trinkets")
    end
    self:Refresh()
end

-- A spell or an item on the cursor: a spell becomes the ability, a
-- trinket you're wearing adds its slot, any other item is used by name.
function V:TakeCursor()
    if not GetCursorInfo then return false end
    local kind, a, _, d = GetCursorInfo()
    if kind == "spell" then
        local id = ns.Safe.Num(d) or ns.Safe.Num(a)
        local info = id and spellInfo(id)
        local name = info and ns.Safe.Text(info.name)
        if not name then return false end
        ClearCursor()
        if not self:Mine() then self.search:SetText(""); self:LoadClass(MB.MyClass()) end
        self.st.sel = nil
        self:Pick({ id = id, name = name, kind = MB.KindOf(id, name), icon = ns.Safe.Num(info.iconID) or MB.QUESTION })
        return true
    elseif kind == "item" then
        local id = ns.Safe.Num(a)
        if not id then return false end
        ClearCursor()
        if not self:Mine() then self.search:SetText(""); self:LoadClass(MB.MyClass()) end
        for _, slot in ipairs({ 13, 14 }) do
            if MB.Trinket(slot).itemID == id then
                if not self.st.trinkets[slot] then self:ToggleTrinket(slot) end
                return true
            end
        end
        local name = itemName(id)
        if not name then ns.Print("The game hasn't loaded that item yet - try again.") return false end
        if itemSpell(id) == false then ns.Print(name .. " has nothing to use.") return false end
        local iconFn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        local icon = iconFn and ns.Safe.Num((iconFn(id))) or MB.QUESTION
        self.st.sel = nil
        self:Pick({ id = id, name = name, kind = "useitem", icon = icon, item = true })
        return true
    elseif kind == "macro" then
        ns.Print("To share a macro you already have, drop it on the Share tab.")
    end
    return false
end

function V:Build()
    if not self.frame then return end
    local st = self.st
    local text, steps = MB.Compose(st)
    self.text = text
    -- target checks: what fits this ability, dimmed otherwise
    local kind = st.sel and st.sel.kind or (next(st.trinkets) and "trinket") or nil
    local allowed = kind and MB.ALLOWED[kind] or {}
    local none = kind and not next(allowed)
    for i, t in ipairs(MB.Order(st.sel)) do
        local c = self.targetChecks[i]
        c.id = t.id
        local ok = allowed[t.id] and true or false
        c.off = not ok
        c.text:SetText(t.label)
        local col = ok and C.text or C.muted
        c.text:SetTextColor(col[1], col[2], col[3])
        c:SetAlpha(ok and 1 or 0.4)
        c:SetShown(not none)
        UI.Tip(c, t.label, "ANCHOR_TOP", ok and t.tip or "Doesn't fit this kind of ability.")
        c:Refresh()
    end
    self.selfNote:SetText(none and "Nothing to pick: this one only ever lands on you." or (not kind and "Pick an ability or a trinket first." or ""))
    self.modKey.label:SetText(st.mod.key:gsub("^%l", string.upper) .. "  v")
    local unitText = { player = "myself", focus = "my focus", target = "my target", mouseover = "my mouseover" }
    self.modUnit.label:SetText(unitText[st.mod.unit] .. "  v")
    for _, c in ipairs({ self.modCheck, self.stopCheck, self.tipCheck }) do c:Refresh() end
    local showOrder = st.sel and st.sel.kind ~= "useitem" and next(st.trinkets) and true or false
    for _, w in ipairs({ self.orderText, self.orderBtn, self.orderTail }) do w:SetShown(showOrder) end
    self.orderBtn.label:SetText(st.order)

    self.preview:SetText(text or "|cff8a8f9cNothing picked yet.|r")
    local n = text and #text or 0
    local over = n > ns.MacroShare.BODY_MAX
    self.count:SetText(("%s%d / %d|r"):format(over and "|cffff5a5a" or "|cff8a8f9c", n, ns.MacroShare.BODY_MAX))
    local lines = {}
    for i, s in ipairs(steps) do lines[#lines + 1] = i .. ". " .. s end
    self.plain:SetText(table.concat(lines, "\n"))
    local combat = InCombatLockdown()
    UI.SetDisabled(self.saveBtn, not text or over or combat or not self:Mine())
    UI.SetDisabled(self.shareBtn, not text or over)
    self.status:SetText(not self:Mine() and "Another class: send it to them." or (combat and "|cffffa340Save waits until combat ends.|r" or ""))
end

function V:RefreshList()
    if not self.frame then return end
    if self.dirty and self:Mine() then self.list, self.interrupt = MB.SpellList(self.class, true); self.dirty = nil end
    local q = (self.search:GetText() or ""):lower()
    self.searchHint:SetShown(q == "")
    local shown = {}
    for _, e in ipairs(self.list or {}) do
        if q == "" or e.name:lower():find(q, 1, true) then shown[#shown + 1] = e end
    end
    local pages = math.max(1, math.ceil(#shown / PER_PAGE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local sel = self.st.sel
    for i, b in ipairs(self.btns) do
        local e = shown[(self.page - 1) * PER_PAGE + i]
        b.entry = e
        b:SetShown(e ~= nil)
        if e then
            b.icon:SetTexture(e.icon or MB.QUESTION)
            b.label:SetText(e.name)
            b.tip = MB.KIND_TEXT[e.kind] or nil
            UI.SetActive(b, sel ~= nil and sel.name == e.name)
        end
    end
    self.none:SetShown(#shown == 0)
    for _, w in ipairs({ self.prev, self.pageText, self.next }) do w:SetShown(pages > 1) end
    self.pageText:SetText(("%d / %d"):format(self.page, pages))
    UI.SetDisabled(self.prev, self.page <= 1)
    UI.SetDisabled(self.next, self.page >= pages)
    -- the pinned interrupt
    local int = self.interrupt
    local showPin = int and (q == "" or int.name:lower():find(q, 1, true)) and true or false
    self.pin:SetShown(showPin)
    if int then
        self.pin.icon:SetTexture(int.icon or MB.QUESTION)
        self.pin.label:SetText(int.name .. (int.note and ("  |cff8a8f9c(" .. int.note .. ")|r") or ""))
        self.pin.tag:SetText(self:Mine() and "YOUR INTERRUPT" or "THEIR INTERRUPT")
        UI.SetActive(self.pin, sel ~= nil and sel.interrupt == true)
    end
    local nm = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.class]) or MB.CLASS_NAMES[self.class]
    self.classBtn.label:SetText(UI.ClassName(nm, self.class) .. (self:Mine() and " (you)" or "") .. "  v")
    self.other:SetText(self:Mine() and "" or ("Building for " .. MB.CLASS_NAMES[self.class] .. "s: \"Send to Share tab\" hands it to them."))
end

function V:RefreshGear()
    if not self.frame then return end
    local mine = self:Mine()
    for _, w in ipairs({ self.gearHead, self.gearHint, self.drop }) do w:SetShown(mine) end
    for _, b in ipairs(self.gear) do
        b:SetShown(mine)
        local t = MB.Trinket(b.slot)
        local where = b.slot == 13 and "Top trinket" or "Bottom trinket"
        b.icon:SetTexture(t.icon or MB.QUESTION)
        local name = t.itemID and (t.name or where) or (where .. ": empty")
        b.label:SetText(name .. (t.onUse == false and "  |cff8a8f9c(passive)|r" or ""))
        b.tip = t.onUse == false and "Nothing to press - it works on its own." or (where .. " (slot " .. b.slot .. "). The macro uses the slot, so it keeps working after a swap.")
        UI.SetActive(b, self.st.trinkets[b.slot] and true or false)
        UI.SetDisabled(b, not t.itemID or t.onUse == false)
        if b.disabled then self.st.trinkets[b.slot] = nil end
    end
    self:RefreshDrop()
end

function V:RefreshDrop()
    if not self.drop then return end
    local kind = GetCursorInfo and GetCursorInfo()
    local holding = kind == "spell" or kind == "item"
    local c = holding and C.accent or C.line
    self.drop:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    self.drop.text:SetText(holding and "|cffffffffDrop it here|r" or "Drag a spell, trinket, potion or Healthstone here")
end

function V:Refresh()
    if not self.frame then return end
    self:RefreshList()
    self:RefreshGear()
    self:Build()
end

function V:Icon()
    local sel = self.st.sel
    if self.st.tip or not sel then return MB.QUESTION end
    return sel.icon or MB.QUESTION
end

function V:Save()
    if not self.text then return end
    if MB:Save(self.nameBox:GetText(), self:Icon(), self.text) then
        self.status:SetText("|cff66e08cSaved - drop it on a bar.|r")
    end
end

function V:ToShare()
    if not self.text then return end
    local S = ns.MacroShareUI
    ns.Nav:Switch("macroshare")
    if not S.frame then return end
    S.nameBox:SetText(MB.CleanName(self.nameBox:GetText()))
    S.bodyBox:SetText(self.text)
    S.icon = ns.MacroShare.CleanIcon(self:Icon())
    S.iconBtn.icon:SetTexture(ns.MacroShare.IconPath(S.icon))
    S:Refresh()
end

ns.RegisterModule({
    key = "macrobuilder", name = "Macro Builder", icon = ns.MEDIA .. "MacroShare", group = "tools", order = 7,
    desc = "Build a macro step by step: pick an ability, choose where it lands, add your trinkets - then save it or share it.",
    rail = "macros", railName = "Macro Workstation", tab = "Builder",
    railDesc = "Build macros step by step, and share them with your raid or a friend.",
    view = V,
})
