-- Titan Up - Nav.lua
-- Module registry, the shared module bar, and the standard title bar every
-- Titan Up window uses:
--
--   [icon] MODULE NAME   ...module's own controls...   [home | modules] [X]
--
-- The module icons always sit just left of the close button, and switching
-- modules opens the new window with its top-right corner where the old
-- one's was, so the icons never move under your mouse.
--
-- A module registers itself once:
--   ns.RegisterModule({ key = "board", name = "TitanBoard", icon = path,
--       desc = "one line for the hub", show = fn, hide = fn, isShown = fn,
--       frame = function() return theWindow end })
-- The hub tiles and every module bar are built from this list, so a new
-- module shows up everywhere without any extra wiring.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local Nav = {}
ns.Nav = Nav
Nav.modules = {}
Nav.byKey = {}
Nav.bars = {}
Nav.sections = {}
Nav.sectionByKey = {}

-- def.group = a section key (e.g. "games") puts the module inside that
-- section's launcher instead of at the top level. def.order sorts entries.
function ns.RegisterModule(def)
    assert(def.key and def.name and def.show and def.hide, "module needs key, name, show, hide")
    if Nav.byKey[def.key] then return end
    def.order = def.order or (100 + #Nav.modules)
    Nav.modules[#Nav.modules + 1] = def
    Nav.byKey[def.key] = def
end

-- A section is a launcher page grouping modules (e.g. Games).
function ns.RegisterSection(def)
    assert(def.key and def.name, "section needs key, name")
    if Nav.sectionByKey[def.key] then return end
    def.order = def.order or (100 + #Nav.sections)
    def.isSection = true
    Nav.sections[#Nav.sections + 1] = def
    Nav.sectionByKey[def.key] = def
end

ns.RegisterSection({
    key = "games", name = "Games", icon = ns.MEDIA .. "Games", order = 4,
    desc = "Death Roll, Wheel of Fortune and more to play with the guild.",
})

local function byOrder(a, b) return a.order < b.order end

-- Top level of the hub and the module bar: ungrouped modules + sections.
function Nav:TopLevel()
    local out = {}
    for _, m in ipairs(self.modules) do if not m.group then out[#out + 1] = m end end
    for _, s in ipairs(self.sections) do
        if #self:InSection(s.key) > 0 then out[#out + 1] = s end
    end
    table.sort(out, byOrder)
    return out
end

function Nav:InSection(key)
    local out = {}
    for _, m in ipairs(self.modules) do if m.group == key then out[#out + 1] = m end end
    table.sort(out, byOrder)
    return out
end

-- Which top-level entry a module/section/home lives under (for highlighting).
function Nav:TopKeyOf(key)
    local m = self.byKey[key]
    return (m and m.group) or key
end

function Nav:FrameFor(key)
    if key == "home" then return ns.Hub and ns.Hub.frame end
    if self.sectionByKey[key] then return ns.Hub and ns.Hub.launchers and ns.Hub.launchers[key] and ns.Hub.launchers[key].frame end
    local m = self.byKey[key]
    return m and m.frame and m.frame()
end

local function hideKey(key)
    if key == "home" then
        if ns.Hub.frame then ns.Hub.frame:Hide() end
    elseif Nav.sectionByKey[key] then
        local f = Nav:FrameFor(key)
        if f then f:Hide() end
    else
        local m = Nav.byKey[key]
        if m then m.hide() end
    end
end

-- Go to another module (or "home" = the hub), closing the one you came from.
-- The new window is placed so its top-right corner (where the module icons
-- are) lands exactly where the old window's was.
function Nav:Switch(toKey, fromKey)
    if toKey == fromKey then return end
    local isSection = self.sectionByKey[toKey] ~= nil
    if toKey ~= "home" and not isSection and not self.byKey[toKey] then return end
    local fromFrame = fromKey and self:FrameFor(fromKey)
    local right, top
    if fromFrame and fromFrame:IsShown() then right, top = fromFrame:GetRight(), fromFrame:GetTop() end
    if toKey == "home" then ns.Hub:Show()
    elseif isSection then ns.Hub:ShowSection(toKey)
    else self.byKey[toKey].show() end
    local toFrame = self:FrameFor(toKey)
    if toFrame and right and top then
        toFrame:ClearAllPoints()
        toFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    end
    -- leaving: close where you came from, and any launcher left open
    if fromKey then hideKey(fromKey) end
    if toKey ~= "home" then hideKey("home") end
    for _, s in ipairs(self.sections) do
        if s.key ~= toKey then hideKey(s.key) end
    end
end

-- The standard title bar. opts: title, icon, onClose, leftInset (room for
-- extra controls before the icon), canDrag (function -> false to block).
Nav.HEADER_H = 32
function Nav:CreateHeader(frame, key, opts)
    opts = opts or {}
    local h = CreateFrame("Frame", nil, frame)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(self.HEADER_H)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function()
        if not opts.canDrag or opts.canDrag() then frame:StartMoving() end
    end)
    h:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    h.close = UI.Button(h, 24, 22, "X", "Close", opts.onClose or function() frame:Hide() end)
    h.close:SetPoint("RIGHT", -6, 0)
    h.bar = self:CreateBar(h, key)
    h.bar:SetPoint("RIGHT", h.close, "LEFT", -8, 0)

    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetTexture(opts.icon)
    h.icon:SetSize(20, 20)
    h.icon:SetPoint("LEFT", opts.leftInset or 10, 0)
    h.title = UI.Text(h, "GameFontNormal", C.accent)
    h.title:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.title:SetText(opts.title or "")
    return h
end

local BTN = 24
local GAP = 2

-- A bar for the module `currentKey`, parented to its title bar.
function Nav:CreateBar(parent, currentKey)
    local bar = CreateFrame("Frame", nil, parent)
    bar.buttons = {}
    local x = 0
    local function add(key, icon, tip)
        local b = UI.IconButton(bar, BTN, icon, nil, function() Nav:Switch(key, currentKey) end)
        b.keepIconColor = true
        b.icon:SetVertexColor(1, 1, 1, 1)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b:SetPoint("LEFT", x, 0)
        b:SetScript("OnEnter", function(s)
            s.hover = true
            UI.Paint(s)
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tip.title, 1, 1, 1)
            if tip.text then GameTooltip:AddLine(tip.text, 0.75, 0.78, 0.84, true) end
            GameTooltip:Show()
        end)
        x = x + BTN + GAP
        bar.buttons[key] = b
        return b
    end
    add("home", ns.MEDIA .. "TitanUpEmblem", { title = "Titan Up", text = "Back to the Titan Up hub" })
    -- thin divider between home and the modules
    local div = bar:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    div:SetSize(1, BTN - 6)
    div:SetPoint("LEFT", x + 2, 0)
    x = x + 6
    local here = self:TopKeyOf(currentKey)
    for _, m in ipairs(self:TopLevel()) do
        local current = m.key == here
        local tip = current and "You're here" or ("Switch to " .. m.name)
        if m.isSection then tip = (current and currentKey ~= m.key) and ("Back to all " .. m.name) or (m.desc or tip) end
        add(m.key, m.icon, { title = m.name, text = tip })
    end
    bar:SetSize(x - GAP, BTN)
    function bar:Refresh()
        for key, b in pairs(self.buttons) do UI.SetActive(b, key == here) end
    end
    bar:Refresh()
    self.bars[#self.bars + 1] = bar
    return bar
end
