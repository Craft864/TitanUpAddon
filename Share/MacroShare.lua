-- Titan Up - Share/MacroShare.lua
-- Macro Share (Raid Tools): the raid leader or an assistant sends a macro to
-- the raid - everyone, a role, a class, or one person. Recipients get a
-- toast, and the macro is listed in the Macro Share window with who sent
-- it and its full text. Dragging its icon onto a bar creates it as a
-- character macro (or updates one with the same name) and puts it on the
-- cursor in one go.
--   * Only in a raid, only from its leader / assistants - checked on the
--     sender's side AND again by every recipient.
--   * Over the guild channel, to raid members running Titan Up.
--   * WoW doesn't let addons create macros in combat: the icon says
--     "after combat" until the fight ends.
--   * The received list lasts until you log out (X removes one).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local MS = {}
ns.MacroShare = MS

local PREFIX = "TitanUpMS"
local CHUNK = 200
MS.NAME_MAX, MS.BODY_MAX = 16, 255

-- icons the sender can pick (names, as WoW's macro icons use)
MS.ICONS = {
    "INV_Misc_QuestionMark", "Spell_Holy_SealOfProtection", "INV_Stone_04", "INV_Potion_54",
    "Ability_Warrior_Charge", "Ability_Rogue_Sprint", "Spell_Shadow_Teleport", "Ability_Hunter_MarkedForDeath",
    "Spell_Nature_Reincarnation", "Spell_ChargePositive", "Spell_ChargeNegative", "INV_Misc_Bell_01",
}
-- an icon is a name from the list above, or any game icon's file ID (a
-- macro dragged in keeps its own icon)
local function iconPath(icon)
    if type(icon) == "number" then return icon end
    return "Interface\\Icons\\" .. (icon or "INV_Misc_QuestionMark")
end
function MS.CleanIcon(icon)
    local n = tonumber(icon)
    if n and n > 0 and n == math.floor(n) then return n end
    for _, ic in ipairs(MS.ICONS) do if ic == icon then return ic end end
    return MS.ICONS[1]
end
MS.IconPath = iconPath

MS.received = {}          -- this session only

function MS:Init()
    ns.Listen(PREFIX, "group", function(msg, sender) MS:OnMessage(msg, sender) end)
    ns.On("PLAYER_REGEN_ENABLED", function() if ns.MacroShareUI then ns.MacroShareUI:Refresh() end end)
    ns.On("PLAYER_REGEN_DISABLED", function() if ns.MacroShareUI then ns.MacroShareUI:Refresh() end end)
    ns.On("GROUP_ROSTER_UPDATE", function() if ns.MacroShareUI then ns.MacroShareUI:Refresh() end end)
    ns.On("CURSOR_CHANGED", function() if ns.MacroShareUI then ns.MacroShareUI:RefreshDrop() end end)
end

-- ---------------------------------------------------------------------
-- Who may share, and who gets it
-- ---------------------------------------------------------------------
local function unitFor(name) return ns.UnitForName(name) end

-- the raid leader or an assistant (a raid only)
function MS.IsLeadOrAssist(unit)
    if not unit then return false end
    return (ns.Safe.Bool(UnitIsGroupLeader(unit)) or ns.Safe.Bool(UnitIsGroupAssistant and UnitIsGroupAssistant(unit))) and true or false
end

function MS.CanSend()
    if not IsInRaid() then return false, "Macro Share works only in a raid." end
    if not MS.IsLeadOrAssist("player") then return false, "Only the raid leader or assistants can share macros." end
    if not ns.DataChannel() then return false, "Macro Share needs a guild." end
    return true
end

-- target: "all" | "role:TANK" | "class:MAGE" | "name:Kev-Medivh"
function MS.ForMe(target)
    if target == "all" then return true end
    local kind, v = (target or ""):match("^(%a+):(.+)$")
    if kind == "role" then return ns.Safe.Text(UnitGroupRolesAssigned("player")) == v end
    if kind == "class" then return ns.Safe.Class("player") == v end
    if kind == "name" then return v == ns.me end
    return false
end

function MS.TargetText(target)
    if target == "all" then return "the whole raid" end
    local kind, v = (target or ""):match("^(%a+):(.+)$")
    if kind == "role" then return ({ TANK = "tanks", HEALER = "healers", DAMAGER = "DPS" })[v] or v end
    if kind == "class" then
        local nm = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[v]
        return (nm or v:sub(1, 1) .. v:sub(2):lower()) .. "s"
    end
    if kind == "name" then return UI.Short(v) end
    return "?"
end

-- ---------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------
function MS.CleanName(s) return (tostring(s or ""):gsub("[%c|\t]", ""):gsub("^%s+", ""):gsub("%s+$", "")):sub(1, MS.NAME_MAX) end
function MS.CleanBody(s) return (tostring(s or ""):gsub("\r", ""):gsub("[\t%z]", " ")):sub(1, MS.BODY_MAX) end

function MS:Send(name, icon, body, target)
    local ok, why = MS.CanSend()
    if not ok then ns.Print(why) return false end
    name, body = MS.CleanName(name), MS.CleanBody(body)
    if name == "" then ns.Print("Give the macro a name.") return false end
    if body:gsub("%s", "") == "" then ns.Print("The macro is empty.") return false end
    self.seq = (self.seq or 0) + 1
    local id = ("%d%d"):format((GetServerTime and GetServerTime() or time()) % 100000, self.seq)
    local payload = table.concat({ target, name, tostring(MS.CleanIcon(icon)), body }, "\t")
    local n = math.ceil(#payload / CHUNK)
    for i = 1, n do
        ns.Send(PREFIX, ("M^%s^%d^%d^%s"):format(id, i, n, payload:sub((i - 1) * CHUNK + 1, i * CHUNK)), ns.DataChannel())
    end
    ns.Print(("Shared \"%s\" with %s."):format(name, MS.TargetText(target)))
    return true
end

-- ---------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------
MS.inbox = {}
function MS:OnMessage(msg, sender)
    local id, part, n, chunk = msg:match("^M%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    if not id then return end
    part, n = tonumber(part), tonumber(n)
    if not (part and n and n >= 1 and n <= 4 and part >= 1 and part <= n) then return end
    local key = sender .. ":" .. id
    for k, b in pairs(self.inbox) do if GetTime() - b.at > 60 then self.inbox[k] = nil end end   -- never finished
    local box = self.inbox[key] or { parts = {}, got = 0, at = GetTime() }
    self.inbox[key] = box
    if not box.parts[part] then box.parts[part] = chunk; box.got = box.got + 1 end
    if box.got < n then return end
    self.inbox[key] = nil
    local target, name, icon, body = table.concat(box.parts):match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if not target then return end
    -- re-checked here: a raid, and the sender leads or assists it
    if not IsInRaid() or not MS.IsLeadOrAssist(unitFor(sender)) then return end
    if not MS.ForMe(target) then return end
    name, body = MS.CleanName(name), MS.CleanBody(body)
    if name == "" or body == "" then return end
    icon = MS.CleanIcon(icon)
    -- a re-share of the same name from the same sender replaces the older entry
    for i = #self.received, 1, -1 do
        local r = self.received[i]
        if r.name == name and r.from == sender then table.remove(self.received, i) end
    end
    table.insert(self.received, 1, { name = name, icon = icon, body = body, from = sender, target = target, at = time and time() or 0 })
    self:Toast(self.received[1])
    if ns.MacroShareUI then ns.MacroShareUI:Refresh() end
end

function MS:Remove(entry)
    for i, r in ipairs(self.received) do if r == entry then table.remove(self.received, i) break end end
    if ns.MacroShareUI then ns.MacroShareUI:Refresh() end
end

-- ---------------------------------------------------------------------
-- Creating it and putting it on the cursor (dragging the icon)
-- ---------------------------------------------------------------------
function MS:PickUp(entry)
    if InCombatLockdown() then ns.Print("Macros can't be made in combat - drag it again after the fight.") return false end
    local idx = GetMacroIndexByName(entry.name)
    if idx and idx > 0 then
        EditMacro(idx, entry.name, entry.icon, entry.body)            -- same name: update it
    else
        local _, numChar = GetNumMacros()
        local max = MAX_CHARACTER_MACROS or 18
        if (numChar or 0) >= max then
            ns.Print(("Your character macros are full (%d) - delete one in /macro, then drag again."):format(max))
            return false
        end
        idx = CreateMacro(entry.name, entry.icon, entry.body, true)
    end
    if not idx or idx == 0 then ns.Print("The game didn't create the macro - try again.") return false end
    PickupMacro(idx)
    entry.added = true
    return true
end

-- ---------------------------------------------------------------------
-- Toast
-- ---------------------------------------------------------------------
function MS:Toast(entry)
    local t = self.toast
    if not t then
        t = CreateFrame("Button", "TitanUpMacroToast", UIParent, "BackdropTemplate")
        t:SetSize(320, 46)
        t:SetPoint("TOP", 0, -120)
        t:SetFrameStrata("DIALOG")
        UI.Skin(t, C.bg, C.accent)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(30, 30)
        t.icon:SetPoint("LEFT", 8, 0)
        t.text = UI.Text(t, "GameFontHighlightSmall", C.text, nil, "LEFT", t.icon, "RIGHT", 8, 0)
        t.text:SetPoint("RIGHT", -8, 0)
        t.text:SetJustifyH("LEFT")
        t:SetScript("OnClick", function(s) s:Hide(); ns.Nav:Switch("macroshare") end)
        self.toast = t
    end
    t.icon:SetTexture(iconPath(entry.icon))
    t.text:SetText(("%s shared a macro: |cffffffff%s|r\n|cff8a8f9cClick to open Macro Share|r"):format(UI.Short(entry.from), entry.name))
    t:Show()
    self.toastSeq = (self.toastSeq or 0) + 1
    local seq = self.toastSeq
    C_Timer.After(10, function() if MS.toastSeq == seq then t:Hide() end end)
end

-- ---------------------------------------------------------------------
-- Window: share (left) | received (right)
-- ---------------------------------------------------------------------
local V = {}
ns.MacroShareUI = V
local W, H, COL = 780, 470, 380
local ROWS = 5

local function editBox(parent, w, h, multi)
    local b = UI.EditBox(parent, w, h, { inset = { 6, 6, 4, 4 }, multi = multi, keys = false })   -- Enter: a new line
    b:SetScript("OnEscapePressed", b.ClearFocus)
    b:SetScript("OnEditFocusLost", function() V:Refresh() end)
    return b
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpMacroShare", "macroshare", "MACRO SHARE", W, H)
    self.target, self.icon = "all", MS.ICONS[1]

    -- left: share a macro
    UI.Text(f, "GameFontNormalSmall", C.accent, "SHARE A MACRO", "TOPLEFT", 16, -14)
    self.iconBtn = UI.IconButton(f, 36, iconPath(self.icon), "Pick an icon (or drop a macro here)", function()
        if not V:TakeCursorMacro() then V:IconMenu() end
    end)
    self.iconBtn:SetPoint("TOPLEFT", 16, -38)
    self.iconBtn.icon:SetVertexColor(1, 1, 1, 1)            -- a real spell icon, not a UI glyph
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Name", "TOPLEFT", 62, -36)
    self.nameBox = editBox(f, 160, 24)
    self.nameBox:SetPoint("TOPLEFT", 62, -50)
    self.nameBox:SetMaxLetters(MS.NAME_MAX)
    self.nameBox:SetScript("OnTextChanged", function() V:RefreshCounts() end)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Macro text", "TOPLEFT", 16, -86)
    self.count = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", f, "TOPLEFT", COL - 8, -86)
    self.bodyBox = editBox(f, COL - 24, 170, true)
    self.bodyBox:SetPoint("TOPLEFT", 16, -102)
    self.bodyBox:SetMaxLetters(MS.BODY_MAX)
    self.bodyBox:SetScript("OnTextChanged", function() V:RefreshCounts() end)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Send to", "TOPLEFT", 16, -286)
    self.targetBtn = UI.Button(f, COL - 24, 24, "", "Who gets it", function() V:TargetMenu() end)
    self.targetBtn:SetPoint("TOPLEFT", 16, -302)
    self.sendBtn = UI.Button(f, 140, 30, "Send", nil, function()
        if MS:Send(V.nameBox:GetText(), V.icon, V.bodyBox:GetText(), V.target) then V.bodyBox:ClearFocus(); V.nameBox:ClearFocus() end
    end)
    self.sendBtn:SetPoint("TOPLEFT", 16, -344)
    UI.SetActive(self.sendBtn, true)
    self.why = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "LEFT", self.sendBtn, "RIGHT", 10, 0)
    self.why:SetWidth(COL - 180); self.why:SetJustifyH("LEFT")
    -- drop a macro here (or on the icon / name / text) to fill the form
    local drop = CreateFrame("Button", nil, f, "BackdropTemplate")
    drop:SetSize(COL - 24, 56)
    drop:SetPoint("TOPLEFT", 16, -390)
    UI.Skin(drop, C.canvas, C.line)
    drop.text = UI.Text(drop, "GameFontHighlightSmall", C.muted, nil, "CENTER")
    self.drop = drop
    drop:SetScript("OnClick", function() V:TakeCursorMacro() end)        -- a click while holding one
    for _, w in ipairs({ drop, self.iconBtn, self.nameBox, self.bodyBox }) do
        w:SetScript("OnReceiveDrag", function() V:TakeCursorMacro() end)
    end
    for _, w in ipairs({ self.nameBox, self.bodyBox }) do
        w:HookScript("OnMouseUp", function() V:TakeCursorMacro() end)
    end

    -- right: received
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", COL, -10); sep:SetPoint("BOTTOMLEFT", COL, 10); sep:SetWidth(1)
    UI.Text(f, "GameFontNormalSmall", C.accent, "RECEIVED - DRAG AN ICON ONTO YOUR BARS", "TOPLEFT", COL + 16, -14)
    self.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f, "BackdropTemplate")
        r:SetSize(W - COL - 32, 76)
        r:SetPoint("TOPLEFT", COL + 16, -36 - (i - 1) * 80)
        UI.Skin(r, C.panel, C.line)
        local ic = CreateFrame("Button", nil, r)
        ic:SetSize(40, 40)
        ic:SetPoint("TOPLEFT", 8, -8)
        ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints()
        ic.hl = ic:CreateTexture(nil, "HIGHLIGHT"); ic.hl:SetAllPoints(); ic.hl:SetColorTexture(1, 1, 1, 0.15)
        ic:RegisterForDrag("LeftButton")
        ic:SetScript("OnDragStart", function() if r.entry and MS:PickUp(r.entry) then V:Refresh() end end)
        ic:SetScript("OnClick", function() if r.entry and MS:PickUp(r.entry) then V:Refresh() end end)
        ic:SetScript("OnEnter", function(s)
            if not r.entry then return end
            GameTooltip:SetOwner(s, "ANCHOR_LEFT")
            GameTooltip:SetText(r.entry.name, 1, 1, 1)
            GameTooltip:AddLine(r.entry.body, 0.85, 0.87, 0.9, true)
            GameTooltip:AddLine(InCombatLockdown() and "After combat: drag it onto a bar" or "Drag onto a bar (or click to pick it up)", 0.55, 0.57, 0.62)
            GameTooltip:Show()
        end)
        ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.icon = ic
        r.combat = UI.Text(r, "GameFontHighlightSmall", { 1, 0.65, 0.3 }, "after combat", "TOP", ic, "BOTTOM", 0, -2)
        r.name = UI.Text(r, "GameFontHighlight", C.text, nil, "TOPLEFT", 56, -8)
        r.from = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "LEFT", r.name, "RIGHT", 8, 0)
        r.body = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 56, -26)
        r.body:SetWidth(W - COL - 32 - 56 - 30); r.body:SetJustifyH("LEFT"); r.body:SetJustifyV("TOP")
        r.body:SetHeight(44)
        r.x = UI.Button(r, 20, 18, "X", "Remove from this list (your macro stays)", function() if r.entry then MS:Remove(r.entry) end end)
        r.x:SetPoint("TOPRIGHT", -4, -4)
        r:Hide()
        self.rows[i] = r
    end
    self.empty = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", COL + 18, -40)
    self.empty:SetWidth(W - COL - 36); self.empty:SetJustifyH("LEFT")
    self.empty:SetText("Macros your raid leader or assistants share show up here until you log out.")
end

-- A macro on the cursor (from the macro book or an action bar)? Fill the
-- form from it. Returns true if it took one.
function V:TakeCursorMacro()
    local kind, idx = GetCursorInfo()
    if kind ~= "macro" or not idx then return false end
    local name, icon, body = GetMacroInfo(idx)
    if not name then return false end
    ClearCursor()
    self.nameBox:SetText(MS.CleanName(name))
    self.bodyBox:SetText(MS.CleanBody(body or ""))
    self.icon = MS.CleanIcon(icon)
    self.iconBtn.icon:SetTexture(iconPath(self.icon))
    self:Refresh()
    return true
end

function V:HoldingMacro() return (GetCursorInfo()) == "macro" end

function V:RefreshDrop()
    if not self.drop then return end
    local holding = self:HoldingMacro()
    local c = holding and C.accent or C.line
    self.drop:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    self.drop.text:SetText(holding and "|cffffffffDrop it here to share it|r" or "Drag a macro here from your macro book (or an action bar)")
end

function V:IconMenu()
    local items = {}
    for _, ic in ipairs(MS.ICONS) do
        items[#items + 1] = { text = ("|T%s:16:16|t  %s"):format(iconPath(ic), ic:gsub("_", " ")), checked = V.icon == ic,
                              onClick = function() V.icon = ic; V.iconBtn.icon:SetTexture(iconPath(ic)) end }
    end
    UI.Menu(self.iconBtn, items)
end

function V:TargetMenu()
    local items = {
        { text = "The whole raid", target = "all" },
        { text = "Tanks", target = "role:TANK" }, { text = "Healers", target = "role:HEALER" }, { text = "DPS", target = "role:DAMAGER" },
    }
    local classes, people = {}, {}
    for _, u in ipairs(ns.GroupUnits()) do
        if UnitExists(u) then
            local cl, nm = ns.Safe.Class(u), ns.FullName(u)
            if cl and not classes[cl] then classes[cl] = true end
            if nm and nm ~= ns.me then people[#people + 1] = { nm, cl } end
        end
    end
    local cls = {}
    for cl in pairs(classes) do cls[#cls + 1] = cl end
    table.sort(cls)
    for _, cl in ipairs(cls) do items[#items + 1] = { text = MS.TargetText("class:" .. cl):gsub("^%l", string.upper), target = "class:" .. cl } end
    table.sort(people, function(a, b) return a[1] < b[1] end)
    for _, p in ipairs(people) do items[#items + 1] = { text = UI.ClassName(p[1], p[2]), target = "name:" .. p[1] } end
    for _, it in ipairs(items) do
        local t = it.target
        it.checked = V.target == t
        it.onClick = function() V.target = t; V:Refresh() end
    end
    UI.Menu(self.targetBtn, items)
end

function V:RefreshCounts()
    if not self.frame then return end
    local n = #(self.bodyBox:GetText() or "")
    self.count:SetText(("%d / %d"):format(n, MS.BODY_MAX))
end

function V:Refresh()
    if not self.frame then return end
    self:RefreshCounts()
    self:RefreshDrop()
    self.targetBtn.label:SetText(("Send to: %s  v"):format(MS.TargetText(V.target)))
    local ok, why = MS.CanSend()
    UI.SetDisabled(self.sendBtn, not ok)
    self.why:SetText(ok and "" or why)
    local combat = InCombatLockdown()
    self.empty:SetShown(#MS.received == 0)
    for i, r in ipairs(self.rows) do
        local e = MS.received[i]
        r.entry = e
        r:SetShown(e ~= nil)
        if e then
            r.icon.tex:SetTexture(iconPath(e.icon))
            r.icon.tex:SetDesaturated(combat)
            r.combat:SetShown(combat)
            r.name:SetText(e.name)
            r.from:SetText(("from %s%s"):format(UI.Short(e.from), e.added and "  |cff66e08cadded|r" or ""))
            r.body:SetText(e.body)
        end
    end
end

ns.RegisterModule({
    key = "macroshare", name = "Macro Share", icon = ns.MEDIA .. "MacroShare", group = "tools", order = 7,
    desc = "Raid leader & assists: send a macro to the raid, a role, a class or one person - they drag it onto their bars.",
    view = V,
})
