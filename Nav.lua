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
Nav.sections = {}
Nav.sectionByKey = {}

-- def.group = the section a module is listed under (e.g. "tools", "games");
-- def.order sorts modules within their section.
-- def.view = V fills in show / hide / isShown / frame from the view (see ns.View).
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

-- A module's window: the standard frame (UI.Window), the faded logo
-- (o.mark = { size, alpha, y }), its title tab, an optional settings cog
-- (o.cog = { tip, onClick }), and view:Refresh() whenever it's shown.
function Nav:Window(view, name, key, title, w, h, o)
    o = o or {}
    local f = UI.Window(name, w, h, o)
    view.frame = f
    f:SetScript("OnShow", o.onShow or function() view:Refresh() end)
    local m = o.mark == nil and { 300, 0.04, -20 } or o.mark          -- false: no logo
    if m then UI.Watermark(f, m[1], m[2], m[3]) end
    view.header = self:CreateHeader(f, key, { title = title, onClose = o.onClose, canDrag = o.canDrag })
    if o.cog then view.cog = self:AddCog(view.header, f, o.cog[1], o.cog[2]) end
    return f, view.header
end

-- A section is a heading in the hub ("Raid Tools", "Games") and a group of
-- icons on the module bar.
function ns.RegisterSection(def)
    assert(def.key and def.name, "section needs key, name")
    if Nav.sectionByKey[def.key] then return end
    def.order = def.order or (100 + #Nav.sections)
    Nav.sections[#Nav.sections + 1] = def
    Nav.sectionByKey[def.key] = def
end

-- side: which end of the tab the section's icons sit on
ns.RegisterSection({ key = "tools", name = "Raid Tools", order = 1, side = "left" })
ns.RegisterSection({ key = "uitweaks", name = "UI Tweaks", order = 2, side = "left" })
ns.RegisterSection({ key = "games", name = "Games", order = 3, side = "right" })

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

-- Every module in hub/bar order.
function Nav:Ordered()
    local out = {}
    for _, g in ipairs(self:Grouped()) do
        for _, m in ipairs(g.modules) do out[#out + 1] = m end
    end
    return out
end

-- A window's top-center in screen coordinates (where its tab sits).
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

-- Go to another module (or "home" = the hub), closing the one you came from.
-- The new window is placed so its top-center - where the tab sits - lands
-- exactly where the old window's was: the tab never moves.
function Nav:Switch(toKey, fromKey)
    if toKey == fromKey then return end
    if toKey ~= "home" and not self.byKey[toKey] then return end
    local fromFrame = fromKey and self:FrameFor(fromKey)
    local cx, top
    if fromFrame and fromFrame:IsShown() then cx, top = Nav.TopCenter(fromFrame) end
    if toKey == "home" then ns.Hub:Show() else self.byKey[toKey].show() end
    local toFrame = self:FrameFor(toKey)
    if toFrame and cx and top then
        toFrame:ClearAllPoints()
        toFrame:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, top)
    end
    if fromKey then hideKey(fromKey) end
    if toKey ~= "home" then hideKey("home") end
end

-- ---------------------------------------------------------------------
-- The title row + the navigation tab
-- ---------------------------------------------------------------------
-- Every window gets:
--   * a slim trapezoid tab sitting on top of the window, one row:
--        [Raid Tools icons]      [<-] NAME      [Games icons]
--     The highlighted icon shows where you are (hover any icon for its
--     name). A side with DROPDOWN_AT or more modules (counted per side, all
--     its sections together) collapses into one dropdown so the row never
--     gets crowded. The back arrow
--     returns to the hub (none on the hub itself).
--   * the X in the window's top-right corner, on its first row of content
--     (there's no separate title row). h is an invisible anchor frame at
--     the top of the window that modules can hang controls from.
Nav.TAB_H = 32
Nav.DROPDOWN_AT = 5      -- this many modules (or more) on one side -> a dropdown
local SLANT = 32            -- width of each slanted end
local ICON = 20
local ICON_GAP = 4

-- The tab is the same width on every window, so it never changes as you
-- switch modules. It matches the narrowest window (the hub), so it never
-- overhangs any of them.
Nav.TAB_W = 420

function Nav:CreateHeader(frame, key, opts)
    opts = opts or {}
    local function startMove() if not opts.canDrag or opts.canDrag() then frame:StartMoving() end end
    local function stopMove() frame:StopMovingOrSizing() end

    -- title row
    local h = CreateFrame("Frame", nil, frame)
    h:SetPoint("TOPLEFT")
    h:SetPoint("TOPRIGHT")
    h:SetHeight(1)
    h.close = UI.Button(h, 24, 22, "X", "Close", opts.onClose or function() frame:Hide() end)
    h.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    h.close:SetFrameLevel(frame:GetFrameLevel() + 20)

    -- the tab
    local tab = CreateFrame("Frame", nil, frame)
    tab:SetHeight(self.TAB_H)
    tab:SetPoint("BOTTOM", frame, "TOP", 0, -1)
    tab:EnableMouse(true)
    tab:RegisterForDrag("LeftButton")
    tab:SetScript("OnDragStart", startMove)
    tab:SetScript("OnDragStop", stopMove)
    h.tab = tab
    local function piece(texture, layer, sub, col, flip)
        local t = tab:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(texture)
        t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
        if flip then t:SetTexCoord(1, 0, 0, 1) end
        return t
    end
    local lf = piece(ns.MEDIA .. "TabSideFill", "BACKGROUND", 0, C.bg)
    lf:SetPoint("TOPLEFT"); lf:SetPoint("BOTTOMLEFT"); lf:SetWidth(SLANT)
    local le = piece(ns.MEDIA .. "TabSideEdge", "BORDER", 0, C.line)
    le:SetAllPoints(lf)
    local rf = piece(ns.MEDIA .. "TabSideFill", "BACKGROUND", 0, C.bg, true)
    rf:SetPoint("TOPRIGHT"); rf:SetPoint("BOTTOMRIGHT"); rf:SetWidth(SLANT)
    local re = piece(ns.MEDIA .. "TabSideEdge", "BORDER", 0, C.line, true)
    re:SetAllPoints(rf)
    local mid = tab:CreateTexture(nil, "BACKGROUND")
    mid:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], C.bg[4] or 1)
    mid:SetPoint("TOPLEFT", lf, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", rf, "BOTTOMLEFT")
    local top = tab:CreateTexture(nil, "BORDER")
    top:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", lf, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", rf, "TOPLEFT")

    -- center: [<-] NAME (the hub's center is just TITAN UP)
    h.title = UI.Text(tab, "GameFontNormal", C.accent, opts.title or "")
    if key ~= "home" then
        h.title:SetPoint("CENTER", tab, "CENTER", 12, -1)
        h.back = UI.IconButton(tab, 20, ns.MEDIA .. "Back", "Back to Titan Up", function() Nav:Switch("home", key) end)
        h.back:SetPoint("RIGHT", h.title, "LEFT", -6, 0)
    else
        h.title:SetPoint("CENTER", tab, "CENTER", 0, -1)
    end

    -- left / right: the module icons by section
    h.bar = self:CreateBar(tab, key)
    self:FitTitle(h)

    -- fixed width; the screen-clamp area includes any overhang so the tab
    -- can't be dragged off screen
    tab:SetWidth(self.TAB_W)
    local function clamp()
        if not frame.SetClampRectInsets then return end
        local w = frame:GetWidth()
        local over = (type(w) == "number" and w > 0) and math.max(0, (self.TAB_W - w) / 2) or 0
        frame:SetClampRectInsets(-over, over, self.TAB_H, 0)
    end
    clamp()
    if frame.HookScript then frame:HookScript("OnSizeChanged", clamp) end
    return h
end

-- Center "<- NAME" in the free space between the two sides, so it can't
-- run into the Tools dropdown or the icons. A long name drops to a smaller
-- font, and as a last resort is shortened with "...".
Nav.TITLE_PAD = 8
function Nav:FitTitle(h)
    local W, edge = self.TAB_W, SLANT + 10
    local left = edge + (h.bar.sideW.left or 0) + self.TITLE_PAD
    local right = W - edge - (h.bar.sideW.right or 0) - self.TITLE_PAD
    local avail = right - left
    local arrow = h.back and 26 or 0
    local center = (left + right) / 2 - W / 2
    h.title:SetFontObject("GameFontNormal")
    h.title:SetWidth(0)
    local function width() local w = h.title:GetStringWidth() return type(w) == "number" and w or 0 end
    if width() + arrow > avail then h.title:SetFontObject("GameFontNormalSmall") end
    if width() + arrow > avail then
        h.title:SetWidth(avail - arrow)
        h.title:SetWordWrap(false)
    end
    h.title:ClearAllPoints()
    h.title:SetPoint("CENTER", h.tab, "CENTER", center + arrow / 2, -1)
end

-- The module icons in the tab, by side (each section says which side it's
-- on). A side with DROPDOWN_AT or more modules becomes one dropdown; a side
-- mixing sections lists them under grey headings.
function Nav:CreateBar(tab, currentKey)
    local bar = { buttons = {}, sideW = { left = 0, right = 0 } }
    local y = -math.floor((self.TAB_H - ICON) / 2)
    local sides = { left = {}, right = {} }
    for _, g in ipairs(self:Grouped()) do
        table.insert(sides[g.section.side == "left" and "left" or "right"], g)
    end
    for _, sideName in ipairs({ "left", "right" }) do
        local groups = sides[sideName]
        local left = sideName == "left"
        local count = 0
        for _, g in ipairs(groups) do count = count + #g.modules end
        if count == 0 then
            -- nothing on this side
        elseif count >= self.DROPDOWN_AT then
            local label = (#groups == 1) and groups[1].section.name or (left and "Tools" or "More")
            local here = false
            for _, g in ipairs(groups) do for _, m in ipairs(g.modules) do if m.key == currentKey then here = true end end end
            local dd = UI.Button(tab, 80, 22, "", label .. ": pick a module", nil)
            dd.label:ClearAllPoints()
            dd.label:SetPoint("LEFT", 8, 0)
            dd.label:SetText(label)
            local caret = dd:CreateTexture(nil, "OVERLAY")
            caret:SetTexture(ns.MEDIA .. "Down")
            caret:SetSize(10, 10)
            caret:SetPoint("RIGHT", -6, 0)
            if left then dd:SetPoint("LEFT", tab, "LEFT", SLANT + 8, -1) else dd:SetPoint("RIGHT", tab, "RIGHT", -(SLANT + 8), -1) end
            dd:SetScript("OnClick", function()
                local items = {}
                for _, g in ipairs(groups) do
                    if #groups > 1 then items[#items + 1] = { text = g.section.name:upper(), muted = true } end
                    for _, m in ipairs(g.modules) do
                        items[#items + 1] = { text = (#groups > 1 and "  " or "") .. m.name, checked = m.key == currentKey,
                            onClick = function() Nav:Switch(m.key, currentKey) end }
                    end
                end
                UI.Menu(dd, items)
            end)
            UI.SetActive(dd, here)
            bar.sideW[sideName] = 80
        else
            -- icons, in order; a small extra gap between sections
            local list = {}
            for gi, g in ipairs(groups) do
                for _, m in ipairs(g.modules) do list[#list + 1] = { m = m, g = g, gap = (gi > 1 and _ == 1) } end
            end
            local n = #list
            local offsets, x = {}, 0
            for i, it in ipairs(list) do
                if it.gap then x = x + 6 end
                offsets[i] = x
                x = x + ICON + ICON_GAP
            end
            local total = x - ICON_GAP
            bar.sideW[sideName] = total
            for i, it in ipairs(list) do
                local m, g = it.m, it.g
                local current = m.key == currentKey
                local b = UI.IconButton(tab, ICON, m.icon, nil, function() Nav:Switch(m.key, currentKey) end)
                b.keepIconColor = true
                b.icon:SetVertexColor(1, 1, 1, 1)
                b.icon:ClearAllPoints()
                b.icon:SetPoint("TOPLEFT", 2, -2)
                b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
                if left then
                    b:SetPoint("TOPLEFT", tab, "TOPLEFT", SLANT + 10 + offsets[i], y)
                else
                    b:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -(SLANT + 10) - (total - offsets[i] - ICON), y)
                end
                local tipText = current and "You're here" or (m.desc or ("Switch to " .. m.name))
                b:SetScript("OnEnter", function(s)
                    s.hover = true
                    UI.Paint(s)
                    GameTooltip:SetOwner(s, "ANCHOR_TOP")
                    GameTooltip:SetText(m.name, 1, 1, 1)
                    GameTooltip:AddLine(g.section.name, 0.31, 0.76, 0.97)
                    GameTooltip:AddLine(tipText, 0.75, 0.78, 0.84, true)
                    GameTooltip:Show()
                end)
                bar.buttons[m.key] = b
            end
        end
    end
    function bar:Refresh()
        for key, b in pairs(self.buttons) do UI.SetActive(b, key == currentKey) end
    end
    bar:Refresh()
    return bar
end

-- ---------------------------------------------------------------------
-- Settings cog beside the X (same size, thin separator between them) and
-- the small options panel it opens. Shared so every window matches.
-- ---------------------------------------------------------------------
function Nav:AddCog(header, frame, tip, onClick)
    local cog = UI.IconButton(header, 22, ns.MEDIA .. "Cog", tip, onClick)
    cog:SetSize(24, 22)
    cog:SetPoint("RIGHT", header.close, "LEFT", -9, 0)
    cog:SetFrameLevel(header.close:GetFrameLevel())
    local sep = header:CreateTexture(nil, "OVERLAY")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetSize(1, 16)
    sep:SetPoint("RIGHT", header.close, "LEFT", -4, 0)
    header.cog, header.cogSep = cog, sep
    return cog
end

-- =====================================================================
-- The hub and minimap button (formerly Hub.lua)
-- =====================================================================
do
-- The hub (every module, under "Raid Tools" and "Games" headings) and the
-- minimap button (left-click: hub, right-click: TitanBoard, drag: move).

local UI = ns.UI
local C = UI.C

local Hub = {}
ns.Hub = Hub

-- Only the minimap button exists at login; the hub is built the first time
-- it's opened.
function Hub:Init()
    self:CreateMinimapButton()
end

function Hub:EnsureHome()
    if not self.frame then self:Build() end
    return self.frame
end

function Hub:Show() self:EnsureHome():Show() end
function Hub:ShowSection() self:Show() end        -- sections are headings in the hub now

function Hub:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

local HUB_W = 420
local TILE_H, TILE_GAP = 50, 6
local HEAD_H = 28

-- The hub: standard title bar, then each section as a heading
-- ("---- RAID TOOLS ----") with its modules as tiles underneath.
function Hub:Build()
    local groups = ns.Nav:Grouped()
    local count = 0
    for _, g in ipairs(groups) do count = count + #g.modules end
    -- tiles + headings, plus room for the version at the bottom
    local height = 30 + #groups * HEAD_H + count * (TILE_H + TILE_GAP) + 8
    local f = UI.Window("TitanUpHub", HUB_W, height, { y = 80, drag = true })
    self.frame = f

    UI.Watermark(f, 320, 0.07, -10)
    local header = ns.Nav:CreateHeader(f, "home", { title = "TITAN UP", icon = ns.MEDIA .. "TitanUpEmblem" })
    -- the cog beside X: every module's settings on one page
    self.settingsCog = ns.Nav:AddCog(header, f, "Settings - every module's options on one page", function() ns.Settings:Toggle(f) end)
    self.header = header
    local ver = UI.Text(f, "GameFontDisableSmall", nil, "v" .. ns.VERSION, "BOTTOM", 0, 8)
    ver:SetTextColor(0.55, 0.57, 0.62)

    local y = -10
    for _, g in ipairs(groups) do
        -- section heading, centered between two lines
        local label = UI.Text(f, "GameFontNormalSmall", C.accent, g.section.name:upper(), "TOP", 0, y - 8)
        local l1 = f:CreateTexture(nil, "ARTWORK")
        l1:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        l1:SetHeight(1)
        l1:SetPoint("LEFT", f, "TOPLEFT", 40, y - 14)
        l1:SetPoint("RIGHT", label, "LEFT", -10, 0)
        local l2 = f:CreateTexture(nil, "ARTWORK")
        l2:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        l2:SetHeight(1)
        l2:SetPoint("LEFT", label, "RIGHT", 10, 0)
        l2:SetPoint("RIGHT", f, "TOPRIGHT", -40, y - 14)       -- clear of the X
        y = y - HEAD_H
        for _, m in ipairs(g.modules) do
            local tile = UI.Button(f, HUB_W - 24, TILE_H, "", nil, function() ns.Nav:Switch(m.key, "home") end)
            tile:SetPoint("TOPLEFT", 12, y)
            local ic = tile:CreateTexture(nil, "ARTWORK")
            ic:SetTexture(m.icon)
            ic:SetSize(34, 34)
            ic:SetPoint("LEFT", 10, 0)
            local name = UI.Text(tile, "GameFontNormal", C.text, m.name, "TOPLEFT", ic, "TOPRIGHT", 10, -1)
            local desc = UI.Text(tile, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", name, "BOTTOMLEFT", 0, -3)
            desc:SetPoint("RIGHT", -10, 0)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(false)
            desc:SetText(m.desc or "")
            y = y - (TILE_H + TILE_GAP)
        end
    end
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
        GameTooltip:AddLine("Left-click: open Titan Up", 0.8, 0.82, 0.86)
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
