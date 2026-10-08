-- Titan Up - Nav.lua
-- Module registry and the Titan Up window frame every module shares:
--
--   [emblem] TITAN UP | Section > MODULE  [tabs]         [cog] | [X]
--   ---------------------------------------------------------------
--   Home             |
--   RAID TOOLS       |   the module's own window
--     TitanBoard     |
--     ...            |
--   Settings     [<] |
--
-- Each module keeps its own window; the title bar and the rail on its left
-- are drawn around it (Nav:Window). Only one module shows at a time, and
-- every module opens with the rail in the same spot, so switching modules
-- reads as one window changing its content. The rail never moves under the
-- mouse: windows grow to the right and down from their top-left corner.
--
-- A module registers itself once:
--   ns.RegisterModule({ key = "board", name = "TitanBoard", icon = path,
--       desc = "one line for the hub", show = fn, hide = fn, isShown = fn,
--       frame = function() return theWindow end })
-- Home, the rail and Settings are built from this list, so a new module
-- shows up everywhere without any extra wiring.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local Nav = {}
ns.Nav = Nav
Nav.modules = {}
Nav.byKey = {}
Nav.sections = {}
Nav.sectionByKey = {}
Nav.headers = {}            -- key -> the title bar + rail built for that window
Nav.lastInRail = {}         -- rail group -> the module last opened in it

-- def.group = the section a module is listed under (e.g. "tools", "games");
-- def.order sorts modules within their section.
-- def.view = V fills in show / hide / isShown / frame from the view (see ns.View).
-- def.rail = a shared rail entry: modules with the same rail id share one
-- item on the rail (def.railName, first module's icon) and switch between
-- each other with tabs in the title bar (def.tab = the tab's label).
-- def.badge = function returning a small number for the rail (or nil).
-- def.onSwitch = run when the rail or Home switches to the module.
function ns.RegisterModule(def)
    local V = def.view and ns.View(def.view)
    if V then
        def.show = def.show or function() V:Show() end
        def.hide = def.hide or function() V:Hide() end
        def.isShown = def.isShown or function() return V:IsShown() end
        def.frame = def.frame or function() return V.frame end
    end
    assert(def.key and def.name and def.show and def.hide, "module needs key, name, show, hide")
    if Nav.byKey[def.key] then return end
    def.order = def.order or (100 + #Nav.modules)
    def.group = def.group or "tools"
    Nav.modules[#Nav.modules + 1] = def
    Nav.byKey[def.key] = def
end

-- The usual plumbing for a window view V (its window V.frame is built by
-- V:Create() the first time it's needed). Anything V defines itself is kept.
function ns.View(V)
    V.EnsureFrame = V.EnsureFrame or function(self) if not self.frame then self:Create() end return self.frame end
    V.IsShown = V.IsShown or function(self) return self.frame and self.frame:IsShown() or false end
    V.Show = V.Show or function(self) self:EnsureFrame():Show() end
    V.Hide = V.Hide or function(self) if self.frame then self.frame:Hide() end end
    V.Toggle = V.Toggle or function(self) if self:IsShown() then self:Hide() else self:Show() end end
    return V
end

-- Sizes. Most modules use the standard size; TitanBoard keeps its own
-- larger size (with the rail narrowed to icons so it still fits a screen).
Nav.TITLE_H = 30
Nav.RAIL_W, Nav.RAIL_MIN = 190, 40         -- 190: "Macro Workstation" and other long names fit (0.31.1)
Nav.STD_W, Nav.STD_H = 880, 570

-- A module's window: the standard frame (UI.Window), the faded logo
-- (o.mark = { size, alpha, y }), the title bar and rail around it, an
-- optional settings cog in the title bar (o.cog = { tip, onClick }), and
-- view:Refresh() whenever it's shown. o.railMin: always the narrow rail.
function Nav:Window(view, name, key, title, w, h, o)
    o = o or {}
    local f = UI.Window(name, w, h, o)
    view.frame = f
    local onShow = o.onShow or function() view:Refresh() end
    f:SetScript("OnShow", function(s)
        Nav:Activate(key)
        onShow(s)
    end)
    local m = o.mark == nil and { 300, 0.04, -20 } or o.mark          -- false: no logo
    if m then UI.Watermark(f, m[1], m[2], m[3]) end
    view.header = self:CreateHeader(f, key, { title = title, onClose = o.onClose, canDrag = o.canDrag, railMin = o.railMin, cog = o.cog })
    view.cog = view.header.cog
    return f, view.header
end

-- A section is a heading on the rail ("Raid Tools", "Games").
function ns.RegisterSection(def)
    assert(def.key and def.name, "section needs key, name")
    if Nav.sectionByKey[def.key] then return end
    def.order = def.order or (100 + #Nav.sections)
    Nav.sections[#Nav.sections + 1] = def
    Nav.sectionByKey[def.key] = def
end

ns.RegisterSection({ key = "tools", name = "Raid Tools", order = 1 })
ns.RegisterSection({ key = "uitweaks", name = "UI Tweaks", order = 2 })
ns.RegisterSection({ key = "games", name = "Games", order = 3 })

local function byOrder(a, b) return a.order < b.order end

function Nav:InSection(key)
    local out = {}
    for _, m in ipairs(self.modules) do if m.group == key then out[#out + 1] = m end end
    table.sort(out, byOrder)
    return out
end

-- { { section = def, modules = { ... } }, ... } - only sections with modules
function Nav:Grouped()
    local secs = {}
    for _, sec in ipairs(self.sections) do secs[#secs + 1] = sec end
    table.sort(secs, byOrder)
    local out = {}
    for _, sec in ipairs(secs) do
        local mods = self:InSection(sec.key)
        if #mods > 0 then out[#out + 1] = { section = sec, modules = mods } end
    end
    return out
end

-- Every module in rail order.
function Nav:Ordered()
    local out = {}
    for _, g in ipairs(self:Grouped()) do
        for _, m in ipairs(g.modules) do out[#out + 1] = m end
    end
    return out
end

-- The rail's entries by section: modules sharing a rail id are one entry
-- ({ key = first module, keys = { all of them }, name, icon, section }).
function Nav:RailItems()
    local out = {}
    for _, g in ipairs(self:Grouped()) do
        local items, byRail = {}, {}
        for _, m in ipairs(g.modules) do
            local it = m.rail and byRail[m.rail]
            if it then
                it.keys[#it.keys + 1] = m.key
            else
                it = { key = m.key, keys = { m.key }, name = m.railName or m.name, icon = m.icon, desc = m.railDesc or m.desc, rail = m.rail, section = g.section }
                if m.rail then byRail[m.rail] = it end
                items[#items + 1] = it
            end
        end
        out[#out + 1] = { section = g.section, items = items }
    end
    return out
end

-- Where a rail entry goes: the module last opened in its group.
function Nav:ItemTarget(it)
    local last = it.rail and self.lastInRail[it.rail]
    return last or it.key
end

-- The modules sharing m's rail entry (just m when it has none).
function Nav:Siblings(m)
    if not (m and m.rail) then return { m } end
    local out = {}
    for _, x in ipairs(self:Ordered()) do if x.rail == m.rail then out[#out + 1] = x end end
    return out
end

-- A window's top-center in screen coordinates.
function Nav.TopCenter(f)
    local l, r, t = f:GetLeft(), f:GetRight(), f:GetTop()
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" then return nil end
    return (l + r) / 2, t
end

function Nav:FrameFor(key)
    if key == "home" then return ns.Hub and ns.Hub.frame end
    local m = self.byKey[key]
    return m and m.frame and m.frame()
end

local function hideKey(key)
    if key == "home" then
        if ns.Hub.frame then ns.Hub.frame:Hide() end
    else
        local m = Nav.byKey[key]
        if m then m.hide() end
    end
end

-- The module the Titan Up window is showing now (nil when it's closed).
-- A window whose title bar and rail are hidden (TitanBoard's mini view and
-- viewer mode) is on its own, not in the Titan Up window.
function Nav:ShellKey()
    for key, h in pairs(self.headers) do
        if h.frame:IsShown() and h.tab:IsShown() then return key end
    end
end

-- May a pop-up open module `key` without being asked? Only when it
-- wouldn't replace something the player opened (Home doesn't count).
function Nav:ShellFree(key)
    local cur = self:ShellKey()
    return cur == nil or cur == key or cur == "home"
end

-- Go to another module (or "home"), closing the one you came from.
function Nav:Switch(toKey, fromKey)
    if toKey == fromKey then return end
    if toKey ~= "home" and not self.byKey[toKey] then return end
    local m = self.byKey[toKey]
    if m and m.onSwitch then m.onSwitch() end
    if toKey == "home" then ns.Hub:Show() else m.show() end
    self:Activate(toKey)                -- (already open: no OnShow, so do it here)
end

-- A window just opened (or its title bar came back): make it the one the
-- Titan Up window shows. Whatever else it was showing closes, and the
-- window goes where the Titan Up window is.
function Nav:Activate(key)
    local h = self.headers[key]
    if not (h and h.frame:IsShown() and h.tab:IsShown()) then return end
    for k, other in pairs(self.headers) do
        if k ~= key and other.frame:IsShown() and other.tab:IsShown() then hideKey(k) end
    end
    local m = self.byKey[key]
    if m and m.rail then self.lastInRail[m.rail] = key end
    self.current = key
    self:Place(key)
    self:RefreshChrome(h)
end

-- ---------------------------------------------------------------------
-- Where the Titan Up window is
-- ---------------------------------------------------------------------
-- Saved as the top-left corner of the whole window (rail and title bar
-- included), so modules of any size open with the rail in the same spot.
local function store() return ns.udb and ns.udb.nav end

function Nav:RailWidth(h)
    local s = store()
    return (h and h.railMin or (s and s.railMin)) and self.RAIL_MIN or self.RAIL_W
end

function Nav:Pos()
    local s = store()
    if s and s.pos then return s.pos[1], s.pos[2] end
    -- first time: centred on the standard size, a little above the middle
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local w, hh = self.RAIL_W + self.STD_W, self.TITLE_H + self.STD_H
    if type(sw) ~= "number" or type(sh) ~= "number" or sw <= 0 or sh <= 0 then return 100, 700 end
    return math.floor(math.max(0, (sw - w) / 2)), math.floor(math.min(sh, (sh + hh) / 2 + 40))
end

function Nav:Place(key)
    local h = self.headers[key]
    if not h then return end
    local x, y = self:Pos()
    local f = h.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + self:RailWidth(h) - 1, y - self.TITLE_H + 1)
end

-- after a drag: remember where the whole window is now
function Nav:SavePos(key)
    local h = self.headers[key]
    local s = store()
    if not (h and s) then return end
    local l, t = h.frame:GetLeft(), h.frame:GetTop()
    if type(l) ~= "number" or type(t) ~= "number" then return end
    s.pos = { math.floor(l - self:RailWidth(h) + 1 + 0.5), math.floor(t + self.TITLE_H - 1 + 0.5) }
    self:Place(key)
end

-- The rail: full width with names, or narrowed to icons (saved).
function Nav:SetRailMin(on)
    local s = store()
    if not s then return end
    s.railMin = on and true or false
    for key, h in pairs(self.headers) do
        self:ApplyRail(h)
        if h.frame:IsShown() and h.tab:IsShown() then self:Place(key) end
    end
end

-- ---------------------------------------------------------------------
-- The title bar and the rail
-- ---------------------------------------------------------------------
-- Every window gets:
--   * a title bar above it: the emblem, where you are, tabs (modules that
--     share a rail entry), the cog for this module's settings, and the X;
--   * the rail on its left: Home, each section's modules, Settings, and a
--     button that narrows the rail to icons;
--   * an X inside the window that only shows when the title bar is hidden
--     (TitanBoard's mini view / viewer mode). h is an invisible anchor at
--     the top of the window that modules can hang controls from, and
--     h.close is where that X sits.
local ICON = 20
local ITEM_H, HEAD_H = 28, 20

function Nav:CreateHeader(frame, key, opts)
    opts = opts or {}
    local m = self.byKey[key]
    local function startMove() if not opts.canDrag or opts.canDrag() then frame:StartMoving() end end
    local function stopMove() frame:StopMovingOrSizing(); Nav:SavePos(key) end
    local function close() if opts.onClose then opts.onClose() else frame:Hide() end end

    local h = CreateFrame("Frame", nil, frame)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(1)
    h.frame, h.key, h.railMin = frame, key, opts.railMin
    h.close = UI.Button(h, 24, 22, "X", "Close", close)
    h.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    h.close:SetFrameLevel(frame:GetFrameLevel() + 20)

    -- everything outside the window hangs off one frame, so hiding it hides
    -- the title bar and rail together (h.tab, as modules know it)
    local chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints(frame)
    h.tab = chrome
    chrome:SetScript("OnShow", function()
        h.close:Hide()
        Nav:Clamp(h)
        Nav:Activate(key)
    end)
    chrome:SetScript("OnHide", function()
        h.close:Show()
        Nav:Clamp(h)
    end)
    h.close:Hide()

    -- title bar
    local bar = CreateFrame("Frame", nil, chrome, "BackdropTemplate")
    UI.Skin(bar, C.bg, C.line)
    bar:SetHeight(self.TITLE_H)
    bar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", startMove)
    bar:SetScript("OnDragStop", stopMove)
    h.bar = bar
    h.emblem = bar:CreateTexture(nil, "ARTWORK")
    h.emblem:SetTexture(ns.MEDIA .. "TitanUp")
    h.emblem:SetSize(18, 18)
    h.emblem:SetPoint("LEFT", 11, 0)
    h.brand = UI.Text(bar, "GameFontNormal", C.accent, "TITAN UP", "LEFT", h.emblem, "RIGHT", 6, 0)
    h.crumb = UI.Text(bar, "GameFontHighlightSmall", C.muted, nil)
    h.title = UI.Text(bar, "GameFontNormal", C.text, nil, "LEFT", h.crumb, "RIGHT", 6, 0)
    local sec = m and self.sectionByKey[m.group]
    local name = (m and m.rail and m.railName) or opts.title or ""
    h.crumb:SetText(sec and (sec.name .. "  >") or "")
    h.title:SetText(name:upper())
    h.title:SetWordWrap(false)

    h.x = UI.Button(bar, 24, 20, "X", "Close", close)
    h.x:SetPoint("RIGHT", -5, 0)
    local edge = h.x              -- the leftmost of the X / cog: tabs line up to its left
    if opts.cog then
        local cog = UI.IconButton(bar, 20, ns.MEDIA .. "Cog", opts.cog[1], opts.cog[2])
        cog:SetSize(24, 20)
        cog:SetPoint("RIGHT", h.x, "LEFT", -9, 0)
        local sep = bar:CreateTexture(nil, "OVERLAY")
        sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        sep:SetSize(1, 14)
        sep:SetPoint("RIGHT", h.x, "LEFT", -4, 0)
        h.cog, h.cogSep = cog, sep
        edge = cog
    end

    -- tabs: the other modules on the same rail entry ([Tonight] [This week]),
    -- right-aligned just left of the cog / X; the title stops before them
    h.tabs = {}
    local sibs = m and m.rail and self:Siblings(m) or {}
    if #sibs < 2 then sibs = {} end
    local right = edge
    for i = #sibs, 1, -1 do
        local s = sibs[i]
        local b = UI.Button(bar, 78, 20, s.tab or s.name, s.desc, function() Nav:Switch(s.key, key) end)
        b:SetPoint("RIGHT", right, "LEFT", right == edge and -12 or -4, 0)
        UI.SetActive(b, s.key == key)
        table.insert(h.tabs, 1, b)
        right = b
    end
    h.title:SetPoint("RIGHT", right, "LEFT", -12, 0)
    h.title:SetJustifyH("LEFT")         -- reads on from the section: "Raid Tools  >  REPORTS"

    -- rail
    local rail = CreateFrame("Frame", nil, chrome, "BackdropTemplate")
    UI.Skin(rail, C.bg, C.line)
    rail:SetPoint("TOPRIGHT", frame, "TOPLEFT", 1, 0)
    rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 1, 0)
    rail:EnableMouse(true)
    h.rail = rail
    self:BuildRail(h)
    self:ApplyRail(h)
    self.headers[key] = h
    return h
end

-- the rail's buttons: Home, each section's entries, then Settings at the bottom
local function railButton(h, it)
    local b = UI.Button(h.rail, 100, ITEM_H - 2, "", nil, function()
        Nav:Switch(it.home and "home" or Nav:ItemTarget(it), h.key)
    end)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 32, 0)
    b.label:SetPoint("RIGHT", -24, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetText(it.name)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(it.icon)
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT", 5, 0)
    b.keepIconColor = true
    b.badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    UI.Skin(b.badge, C.warn, C.warn)
    b.badge:SetSize(16, 14)
    b.badge:SetPoint("RIGHT", -5, 0)
    b.badge.text = UI.Text(b.badge, "GameFontHighlightSmall", { 0.1, 0.07, 0.02 }, nil, "CENTER", 0, 0)
    b.badge:Hide()
    b.item = it
    b:SetScript("OnEnter", function(s)
        s.hover = true
        UI.Paint(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.name, 1, 1, 1)
        if it.section then GameTooltip:AddLine(it.section.name, C.accent[1], C.accent[2], C.accent[3]) end
        if it.desc then GameTooltip:AddLine(it.desc, 0.75, 0.78, 0.84, true) end
        GameTooltip:Show()
    end)
    return b
end

function Nav:BuildRail(h)
    local rail = h.rail
    h.railButtons, h.railHeads = {}, {}
    local list = { { home = true, key = "home", keys = { "home" }, name = "Home", icon = ns.MEDIA .. "TitanUp", desc = "Tonight at a glance, and every module" } }
    for _, g in ipairs(self:RailItems()) do
        list[#list + 1] = { head = g.section.name }
        for _, it in ipairs(g.items) do list[#list + 1] = it end
    end
    local y = -6
    for _, it in ipairs(list) do
        if it.head then
            local t = UI.Text(rail, "GameFontDisableSmall", C.muted, it.head:upper(), "TOPLEFT", 12, y - 7)
            local line = rail:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 8, y - 10)
            line:SetPoint("TOPRIGHT", -8, y - 10)
            h.railHeads[#h.railHeads + 1] = { text = t, line = line }
            y = y - HEAD_H
        else
            local b = railButton(h, it)
            b:SetPoint("TOPLEFT", 6, y)
            b:SetPoint("RIGHT", -6, 0)
            h.railButtons[#h.railButtons + 1] = b
            y = y - ITEM_H
        end
    end
    -- bottom: Settings, and the narrow / widen button
    if self.byKey.settings then
        local s = self.byKey.settings
        local b = railButton(h, { key = "settings", keys = { "settings" }, name = s.name, icon = s.icon, desc = s.desc })
        b:SetPoint("BOTTOMLEFT", 6, 30)
        b:SetPoint("RIGHT", -6, 0)
        h.railButtons[#h.railButtons + 1] = b
    end
    h.narrow = UI.Button(rail, 26, 20, "", nil, function()
        local s = store()
        Nav:SetRailMin(not (s and s.railMin))
    end)
    h.narrow:SetPoint("BOTTOMRIGHT", -6, 6)
end

-- rail width, and names or icons only
function Nav:ApplyRail(h)
    local w = self:RailWidth(h)
    local min = w == self.RAIL_MIN
    h.rail:SetWidth(w)
    h.bar:SetPoint("BOTTOMLEFT", h.frame, "TOPLEFT", -(w - 1), -1)
    h.brand:SetShown(not min)
    h.crumb:ClearAllPoints()
    h.crumb:SetPoint("LEFT", h.bar, "LEFT", min and 38 or (w + 8), 0)
    for _, b in ipairs(h.railButtons) do
        b.label:SetShown(not min)
        b.icon:ClearAllPoints()
        b.icon:SetPoint(min and "CENTER" or "LEFT", min and 0 or 5, 0)
        b.badge:ClearAllPoints()
        if min then b.badge:SetSize(8, 8); b.badge:SetPoint("TOPRIGHT", 1, 1) else b.badge:SetSize(16, 14); b.badge:SetPoint("RIGHT", -5, 0) end
        b.badge.text:SetShown(not min)
    end
    for _, hd in ipairs(h.railHeads) do hd.text:SetShown(not min) end
    -- the forced-narrow rail (TitanBoard) has nothing to toggle
    h.narrow:SetShown(not h.railMin)
    h.narrow.label:SetText(min and ">" or "<")
    h.narrow.tip = min and "Show module names" or "Narrow the rail to icons"
    self:Clamp(h)
end

-- the window can't be dragged so far that its title bar or rail leave the screen
function Nav:Clamp(h)
    local f = h.frame
    if not f.SetClampRectInsets then return end
    if h.tab:IsShown() then f:SetClampRectInsets(-(self:RailWidth(h) - 1), 0, self.TITLE_H - 1, 0)
    else f:SetClampRectInsets(0, 0, 0, 0) end
end

-- which entry is lit, and the badges
function Nav:RefreshChrome(h)
    h = h or self.headers[self.current or ""]
    if not h then return end
    for _, b in ipairs(h.railButtons) do
        local on = false
        for _, k in ipairs(b.item.keys) do if k == h.key then on = true end end
        UI.SetActive(b, on)
        local n
        for _, k in ipairs(b.item.keys) do
            local m = self.byKey[k]
            if m and m.badge then
                local ok, v = pcall(m.badge)
                if ok and type(v) == "number" and v > 0 then n = (n or 0) + v end
            end
        end
        b.badge:SetShown(n ~= nil)
        if n then b.badge.text:SetText(n > 9 and "9+" or tostring(n)) end
    end
end

-- Settings cog in the title bar (kept for callers of the old helper).
function Nav:AddCog(header, frame, tip, onClick)
    return header.cog
end

-- =====================================================================
-- Home and the minimap button
-- =====================================================================
do
-- Home: tonight at a glance (cards that open their module) and every
-- module as a tile. The minimap button: left-click opens / closes Titan
-- Up, right-click TitanBoard, drag to move.

local Hub = {}
ns.Hub = Hub

-- Only the minimap button exists at login; Home is built the first time
-- it's opened.
function Hub:Init()
    self:CreateMinimapButton()
end

function Hub:EnsureHome()
    if not self.frame then self:Build() end
    return self.frame
end

function Hub:Show() self:EnsureHome():Show() end
function Hub:ShowSection() self:Show() end        -- sections are rail headings now

-- Open Titan Up on Home, or close it (whatever module it's showing).
function Hub:Toggle()
    local cur = ns.Nav:ShellKey()
    if cur then
        if cur == "home" then self.frame:Hide() else ns.Nav.byKey[cur].hide() end
    else
        self:Show()
    end
end

-- (16px margins: 3 cards / 6 tiles fill the 848px between them)
local CARD_W, CARD_H, GAP = 272, 116, 16
local TILE_W, TILE_H, TILE_GAP = 134, 72, 8

local function myLootToTrade()
    local d = ns.udb and ns.udb.loot
    local now = (GetServerTime and GetServerTime()) or time()
    local n = 0
    for _, r in pairs(d and d.drops or {}) do
        if r.owner == ns.me and not r.equipped and r.kind == "raid" and now - (r.t or 0) < 7200 then n = n + 1 end
    end
    return n
end
Hub.LootToTrade = myLootToTrade

-- One card per thing worth knowing tonight. Each returns its lines:
-- big number / word, small line, action text; click opens the module.
Hub.CARDS = {
    { key = "pullreport", icon = "PullReport", title = "TONIGHT'S PULLS", fill = function()
        local PR = ns.PullReport
        local s = PR:Session()
        if #s.pulls == 0 then return "-", "No raid pulls yet tonight.", "Open Reports" end
        local kills, deaths = 0, 0
        for _, p in ipairs(s.pulls) do
            if p.result == "kill" then kills = kills + 1 end
            for _, d in ipairs(p.deaths) do if d.kind ~= "save" then deaths = deaths + 1 end end
        end
        local unused = 0
        for _, r in ipairs(PR:Scorecard()) do unused = unused + (r.def or 0) end
        return tostring(#s.pulls), ("%d kill%s  -  %d death%s%s"):format(kills, kills == 1 and "" or "s", deaths, deaths == 1 and "" or "s",
            unused > 0 and ("  -  |cffffa340" .. unused .. " with a defensive unused|r") or ""), "Open Reports"
    end },
    { key = "raidcheck", icon = "RaidCheck", title = "LAST RAID CHECK", fill = function()
        local RC = ns.RaidCheck
        local check = RC.current
        if not check then return "-", "No check yet - it runs on ready check and /pull.", "Open Raid Check" end
        local result = RC:Evaluate(check)
        local missing = {}
        for _, list in ipairs({ result.buffs, result.checks }) do
            for _, r in ipairs(list) do for _, n in ipairs(r.missing) do missing[n] = true end end
        end
        local n = 0
        for _ in pairs(missing) do n = n + 1 end
        local big = n == 0 and "|cff66e08cAll set|r" or ("|cffffa340" .. n .. "|r")
        return big, (n == 0 and "Everyone reported ready" or (n == 1 and "raider missing something" or "raiders missing something")) .. date("  -  %H:%M", check.t), "Open Raid Check"
    end },
    { key = "loot", icon = "Loot", title = "YOUR LOOT", fill = function()
        local n = myLootToTrade()
        if n == 0 then return "-", "Nothing waiting to be traded or equipped.", "Open Loot" end
        return tostring(n), (n == 1 and "item" or "items") .. " won in the last 2 hours, not equipped yet", "Open Loot"
    end },
    { key = "versions", icon = "TitanUp", title = "VERSIONS", fill = function()
        local UP = ns.Updates
        if not UP.roster then return "v" .. ns.VERSION, "Check which version your group runs.", "Check my group" end
        local latest, cur, total = UP:Latest(), 0, 0
        for _, r in pairs(UP.roster) do
            total = total + 1
            if r.v and r.v == latest then cur = cur + 1 end
        end
        return ("%d|cff8a8f9c / %d|r"):format(cur, total), "on the newest version (v" .. latest .. ")", "See who"
    end, run = function() ns.Updates:Check() end },
    { key = "wowdle", icon = "Wowdle", title = "WOWDLE", fill = function()
        local WD = ns.Wowdle
        WD:CheckDay()
        local d = ns.udb.wowdle
        local solved = 0
        for name, r in pairs(d.standings or {}) do
            if name ~= ns.me and r.day == d.day and (r.n or -1) > 0 then solved = solved + 1 end
        end
        local who = solved > 0 and (solved .. " guildmate" .. (solved == 1 and "" or "s") .. " solved it") or "Today's word is waiting"
        if not d.done then return "|cffffd94dNot played|r", who, "Play today's" end
        return d.won and ("|cff66e08c" .. #d.guesses .. " / 6|r") or "|cffff5a5aX / 6|r", who, "See standings"
    end },
    { key = "deathroll", icon = "DeathRoll", title = "DEATH ROLL", fill = function()
        local L = ns.DRLedger
        local _, by = L:Stats()
        local me = by[ns.me] or { wins = 0, losses = 0, net = 0 }
        local unpaid = #L:MyUnpaid()
        local net = (me.net >= 0 and "|cff66e08c+" or "|cffff5a5a-") .. ns.DeathRoll.Fmt(math.abs(me.net)) .. "g|r"
        return net, ("Won %d  Lost %d%s"):format(me.wins, me.losses, unpaid > 0 and ("  -  |cffffa340" .. unpaid .. " unpaid|r") or ""), "Open Death Roll"
    end },
}

-- Home: the cards, then every rail entry as a tile, version at the bottom.
function Hub:Build()
    local f = Nav:Window(self, "TitanUpHub", "home", "HOME", Nav.STD_W, Nav.STD_H, { mark = { 360, 0.05, -20 },
        cog = { "Settings - every module's options", function() ns.Settings:Open("titanup") end } })
    self.frame = f
    local ver = UI.Text(f, "GameFontDisableSmall", nil, "Titan Up v" .. ns.VERSION, "BOTTOMRIGHT", -14, 10)
    ver:SetTextColor(0.55, 0.57, 0.62)

    UI.Text(f, "GameFontNormalSmall", C.accent, "TONIGHT", "TOPLEFT", 16, -14)
    self.when = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 80, -14)
    self.cards = {}
    for i, def in ipairs(self.CARDS) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local card = UI.Button(f, CARD_W, CARD_H, "", nil, function()
            if def.run then def.run() else Nav:Switch(def.key, "home") end
        end)
        card:SetPoint("TOPLEFT", 16 + col * (CARD_W + GAP), -34 - row * (CARD_H + GAP))
        local ic = card:CreateTexture(nil, "ARTWORK")
        ic:SetTexture(ns.MEDIA .. def.icon)
        ic:SetSize(18, 18)
        ic:SetPoint("TOPLEFT", 12, -10)
        UI.Text(card, "GameFontNormalSmall", C.text, def.title, "LEFT", ic, "RIGHT", 8, 0)
        card.big = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        card.big:SetPoint("TOPLEFT", 12, -38)
        card.big:SetTextColor(C.text[1], C.text[2], C.text[3])
        card.small = UI.Text(card, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 12, -70)
        card.small:SetWidth(CARD_W - 24); card.small:SetJustifyH("LEFT"); card.small:SetWordWrap(false)
        card.act = UI.Text(card, "GameFontHighlightSmall", C.accent, nil, "BOTTOMLEFT", 12, 10)
        card.def = def
        self.cards[i] = card
    end

    local ty = -34 - 2 * (CARD_H + GAP) - 8
    UI.Text(f, "GameFontNormalSmall", C.accent, "ALL MODULES", "TOPLEFT", 16, ty)
    local i = 0
    for _, g in ipairs(Nav:RailItems()) do
        for _, it in ipairs(g.items) do
            local col, row = i % 6, math.floor(i / 6)
            local tile = UI.Button(f, TILE_W, TILE_H, "", it.desc, function() Nav:Switch(Nav:ItemTarget(it), "home") end)
            tile:SetPoint("TOPLEFT", 16 + col * (TILE_W + TILE_GAP), ty - 20 - row * (TILE_H + TILE_GAP))
            local ic = tile:CreateTexture(nil, "ARTWORK")
            ic:SetTexture(it.icon)
            ic:SetSize(32, 32)
            ic:SetPoint("TOP", 0, -10)
            local name = UI.Text(tile, "GameFontHighlightSmall", C.text, it.name, "BOTTOM", 0, 9)
            name:SetWidth(TILE_W - 8); name:SetWordWrap(false)
            i = i + 1
        end
    end
end

function Hub:Refresh()
    if not self.cards then return end
    local _, _, _, diffName = GetInstanceInfo()
    self.when:SetText(date("%A %b %d") .. ((diffName and diffName ~= "") and ("  -  " .. diffName) or ""))
    for _, card in ipairs(self.cards) do
        local ok, big, small, act = pcall(card.def.fill)
        if not ok then big, small, act = "-", "", "" end
        card.big:SetText(big or "-")
        card.small:SetText(small or "")
        card.act:SetText(act or "")
    end
    ns.Nav:RefreshChrome(ns.Nav.headers.home)
end

-- ---------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------
local function placeButton(b)
    local a = math.rad(ns.udb.minimap.angle or 200)
    local r = (math.min(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function Hub:CreateMinimapButton()
    local b = CreateFrame("Button", "TitanUpMinimapButton", Minimap)
    self.minimapButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.MEDIA .. "TitanUp")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns.Board:Toggle() else Hub:Toggle() end
    end)
    b:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            ns.udb.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeButton(s)
        end)
    end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Titan Up", 1, 1, 1)
        GameTooltip:AddLine("Left-click: open / close Titan Up", 0.8, 0.82, 0.86)
        GameTooltip:AddLine("Right-click: TitanBoard", 0.8, 0.82, 0.86)
        GameTooltip:AddLine("Drag to move   (/tu minimap hides it)", 0.55, 0.58, 0.64)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:UpdateMinimapButton()
end

function Hub:UpdateMinimapButton()
    local b = self.minimapButton
    if not b then return end
    if ns.udb.minimap.hidden then b:Hide() else b:Show(); placeButton(b) end
end
end

-- =====================================================================
-- The alert dock
-- =====================================================================
-- Pop-ups that appear on their own (the /pull alert, your death summary,
-- the key vote, What's new, challenges, shared macros) stack in one place,
-- newest on top, instead of each landing somewhere near the middle of the
-- screen. Drag any of them to move the whole stack; the spot is saved
-- (Settings > Titan Up resets it).
do
local Dock = { frames = {}, seq = 0 }
ns.Dock = Dock
Dock.GAP = 6
Dock.DEFAULT = { 0, -140 }        -- top-centre of the stack, from the top of the screen

local function pos()
    local d = ns.udb and ns.udb.dock
    local p = d and d.pos
    if p then return p[1], p[2] end
    return Dock.DEFAULT[1], Dock.DEFAULT[2]
end

-- f: a pop-up window. Call once, after its own OnShow / OnHide scripts are set.
function Dock:Add(f)
    if f.docked then return end
    f.docked = true
    f.dockSeq = 0
    f:HookScript("OnShow", function(s)
        Dock.seq = Dock.seq + 1
        s.dockSeq = Dock.seq
        Dock:Layout()
    end)
    f:HookScript("OnHide", function() Dock:Layout() end)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); Dock:Moved(s) end)
    self.frames[#self.frames + 1] = f
    if f:IsShown() then self:Layout() end
end

function Dock:Visible()
    local list = {}
    for _, f in ipairs(self.frames) do if f:IsShown() then list[#list + 1] = f end end
    table.sort(list, function(a, b) return (a.dockSeq or 0) > (b.dockSeq or 0) end)
    return list
end

function Dock:Layout()
    local x, y = pos()
    local prev
    for _, f in ipairs(self:Visible()) do
        f:ClearAllPoints()
        if prev then f:SetPoint("TOP", prev, "BOTTOM", 0, -self.GAP)
        else f:SetPoint("TOP", UIParent, "TOP", x, y) end
        prev = f
    end
end

-- one of them was dragged: move the whole stack to match
function Dock:Moved(f)
    local d = ns.udb and ns.udb.dock
    local l, r, t = f:GetLeft(), f:GetRight(), f:GetTop()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if d and type(l) == "number" and type(r) == "number" and type(t) == "number" and type(sw) == "number" and type(sh) == "number" then
        local above = 0
        for _, g in ipairs(self:Visible()) do
            if g == f then break end
            local gh = g:GetHeight()
            above = above + (type(gh) == "number" and gh or 0) + self.GAP
        end
        d.pos = { math.floor((l + r) / 2 - sw / 2 + 0.5), math.floor(t + above - sh + 0.5) }
    end
    self:Layout()
end

function Dock:Reset()
    local d = ns.udb and ns.udb.dock
    if d then d.pos = nil end
    self:Layout()
end

-- A short note with one button ("Raid Check results are in  [Open]"), for
-- when something would have opened a module but you're busy in another.
function Dock:Notice(text, button, onClick)
    local n = self.notice
    if not n then
        n = UI.Window("TitanUpNotice", 360, 64, { strata = "DIALOG", border = C.accent, noTop = true })
        n.icon = n:CreateTexture(nil, "ARTWORK")
        n.icon:SetTexture(ns.MEDIA .. "TitanUp")
        n.icon:SetSize(24, 24)
        n.icon:SetPoint("LEFT", 12, 0)
        n.text = UI.Text(n, "GameFontHighlight", C.text, nil, "LEFT", n.icon, "RIGHT", 10, 0)
        n.text:SetPoint("RIGHT", -110, 0)
        n.text:SetJustifyH("LEFT")
        n.go = UI.Button(n, 64, 22, "", nil, function() n:Hide(); if n.onClick then n.onClick() end end)
        n.go:SetPoint("RIGHT", -36, 0)
        UI.SetActive(n.go, true)
        local x = UI.Button(n, 22, 20, "X", "Dismiss", function() n:Hide() end)
        x:SetPoint("RIGHT", -8, 0)
        self.notice = n
        self:Add(n)
    end
    n.text:SetText(text)
    n.go.label:SetText(button or "Open")
    n.onClick = onClick
    local token = {}
    n.token = token
    if n:IsShown() then n:Hide() end
    n:Show()
    C_Timer.After(30, function() if n.token == token then n:Hide() end end)
end
end
