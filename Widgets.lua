-- TitanBoard - Widgets.lua
-- Small flat UI kit: colors, skinned panels, buttons and a prompt dialog.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BD = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

UI.C = {
    bg        = { 0.050, 0.060, 0.085, 0.97 },
    panel     = { 0.080, 0.092, 0.125, 1 },
    canvas    = { 0.035, 0.040, 0.055, 1 },
    line      = { 0.19, 0.22, 0.29, 1 },
    btn       = { 0.115, 0.130, 0.175, 1 },
    btnHover  = { 0.160, 0.180, 0.240, 1 },
    accent    = { 0.31, 0.76, 0.97, 1 },
    accentDim = { 0.10, 0.30, 0.42, 1 },
    text      = { 0.90, 0.92, 0.96 },
    muted     = { 0.52, 0.56, 0.64 },
    good      = { 0.40, 0.90, 0.55 },
    warn      = { 1.00, 0.64, 0.25 },
    bad       = { 0.95, 0.35, 0.35 },
}
local C = UI.C

function UI.Skin(frame, bg, border)
    frame:SetBackdrop(BD)
    bg = bg or C.panel
    border = border or C.line
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function UI.Panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Skin(f, C.panel, C.line)
    return f
end

-- UI.Text(parent, template, color, text, point...): a font string; the
-- text and the first anchor are optional (UI.Text(f, nil, nil, "Hi", "TOP", 0, -8))
function UI.Text(parent, template, color, text, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3])
    if text then fs:SetText(text) end
    if (...) then fs:SetPoint(...) end
    return fs
end

-- A skinned edit box. o.inset (all sides, or { l, r, t, b }), o.max letters,
-- o.numeric, o.center, o.multi; Enter / Esc drop the focus unless o.keys == false.
function UI.EditBox(parent, w, h, o)
    o = o or {}
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    UI.Skin(e, C.canvas, C.line)
    e:SetSize(w, h)
    e:SetFontObject("ChatFontNormal")
    local i = o.inset
    if type(i) == "number" then e:SetTextInsets(i, i, 0, 0) elseif i then e:SetTextInsets(i[1], i[2], i[3], i[4]) end
    if o.center then e:SetJustifyH("CENTER") end
    if o.numeric then e:SetNumeric(true) end
    if o.max then e:SetMaxLetters(o.max) end
    if o.multi then e:SetMultiLine(true) end
    e:SetAutoFocus(false)
    if o.keys ~= false then
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:SetScript("OnEnterPressed", e.ClearFocus)
    end
    return e
end

-- A plain tooltip on any frame: a white title and optional grey lines.
function UI.Tip(frame, title, anchor, ...)
    local lines = { ... }
    frame:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, anchor or "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.8, 0.82, 0.86, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A list row: a button with a hover glow (and an optional "selected"
-- background, row.hl) and one line of text (row.text).
function UI.Row(parent, h, hover, selected, font, plain)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(h)
    if selected then
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(selected[1], selected[2], selected[3], selected[4])
        r.hl:Hide()
    end
    local glow = r:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, hover or 0.05)
    -- plain: the font's own colour (no UI.Text tint)
    r.text = plain and r:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall") or UI.Text(r, font or "GameFontHighlightSmall")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    return r
end

-- An on-screen piece you can drag (when canDrag() allows, or whenever its
-- mouse is on); its spot is kept in store().pos as { point, relPoint, x, y }.
-- f:Place() puts it there, f:ResetPlace() back at the default spot; f.hint
-- is the line above it ("Drag to move").
function UI.Draggable(f, store, default, hint, hintFont, canDrag)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not canDrag or canDrag() then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        store().pos = { p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
    end)
    f.hint = f:CreateFontString(nil, "OVERLAY", hintFont or "GameFontHighlightSmall")
    f.hint:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.hint:SetText(hint)
    f.hint:Hide()
    function f:Place()
        local p = store().pos or default
        self:ClearAllPoints()
        self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    function f:ResetPlace()
        store().pos = { default[1], default[2], default[3], default[4] }
        self:Place()
    end
end

-- the small "v" of a dropdown, on button b
function UI.Caret(b, ...)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ns.MEDIA .. "Down")
    t:SetSize(12, 12)
    t:SetPoint(...)
    return t
end

-- The standard window frame: skinned, clamped to the screen, movable, closes
-- on Esc, hidden until shown. o.y (centre offset, 40), o.point, o.strata
-- ("HIGH"), o.border, o.drag (the whole window drags - else only its tab),
-- o.onDragStop, o.noTop, o.noClamp, o.noEsc.
function UI.Window(name, w, h, o)
    o = o or {}
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    if o.point then f:SetPoint(unpack(o.point)) else f:SetPoint("CENTER", 0, o.y or 40) end
    f:SetFrameStrata(o.strata or "HIGH")
    if not o.noTop then f:SetToplevel(true) end
    if not o.noClamp then f:SetClampedToScreen(true) end
    f:SetMovable(true)
    f:EnableMouse(true)
    if o.drag then
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", o.onDragStop or f.StopMovingOrSizing)
    end
    UI.Skin(f, C.bg, o.border or C.line)
    f:Hide()
    if name and not o.noEsc then tinsert(UISpecialFrames, name) end
    return f
end

function UI.Paint(b)
    local bg, bd
    if b.disabled then
        bg, bd = C.btn, C.line
    elseif b.active then
        bg, bd = C.accentDim, C.accent
    elseif b.hover then
        bg, bd = C.btnHover, C.accent
    else
        bg, bd = C.btn, C.line
    end
    b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
    if b.label then
        local t = b.disabled and C.muted or C.text
        b.label:SetTextColor(t[1], t[2], t[3])
    end
end

function UI.Button(parent, w, h, text, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop(BD)
    b:RegisterForClicks("LeftButtonUp")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    b.tip = tip
    b:SetScript("OnEnter", function(s)
        s.hover = true
        UI.Paint(s)
        if s.tip then
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s)
        s.hover = nil
        UI.Paint(s)
        GameTooltip:Hide()
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    UI.Paint(b)
    return b
end

-- Faint Titan Up logo behind a window's contents.
-- The faded Titan Up logo behind a window's content. It never spills past
-- the window: it shrinks to fit a short or narrow window (with a small
-- margin), keeps its offset only as far as it still fits, and re-fits
-- whenever the window changes size.
-- ---------------------------------------------------------------------
-- Shared helpers (one copy for every window)
-- ---------------------------------------------------------------------
-- Resize a window and keep its top-left corner (and so the rail beside
-- it) exactly where it is. (The name is from when windows had a tab.)
function UI.ResizeKeepTab(f, w, h)
    local l, t = f:GetLeft(), f:GetTop()
    f:SetSize(w, h)
    if f:IsShown() and type(l) == "number" and type(t) == "number" then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
end
UI.ResizeKeepCorner = UI.ResizeKeepTab

-- "Name-Realm" -> "Name" (nil stays nil; ns.Short gives "?")
function UI.Short(name) return name and ns.Short(name) end

-- a group member's class colour as r, g, b (fr, fg, fb - or white - when unknown)
function UI.ClassRGB(name, fr, fg, fb)
    local class = name and ns.ClassOf(name)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b end
    return fr or 1, fg or 1, fb or 1
end

-- ---------------------------------------------------------------------
-- UI.ScrollArea(parent, w, h, step): a clipped view that scrolls with the
-- mouse wheel, with a draggable scroll bar beside it (shown only when the
-- content is taller than the view). Anchor sa.view; sa:SetContent(region,
-- height) puts a region (a frame or a font string inside sa.view) in it.
-- ---------------------------------------------------------------------
local Scroll = {}
Scroll.__index = Scroll

function UI.ScrollArea(parent, w, h, step)
    local sa = setmetatable({ offset = 0, contentH = 0, viewH = h }, Scroll)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(w, h)
    if view.SetClipsChildren then view:SetClipsChildren(true) end
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, d) sa:ScrollBy(-d * (step or 40)) end)
    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPLEFT", view, "TOPRIGHT", 8, 0)
    track:SetSize(8, h)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.06)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function()
        local _, cy = GetCursorPosition()
        local from, start = cy / (UIParent:GetEffectiveScale() or 1), sa.offset
        thumb:SetScript("OnUpdate", function()
            local _, ny = GetCursorPosition()
            ny = ny / (UIParent:GetEffectiveScale() or 1)
            local span = sa.viewH - (thumb:GetHeight() or 1)
            if span > 0 then sa:ScrollTo(start + (from - ny) / span * sa:MaxScroll()) end
        end)
    end)
    thumb:SetScript("OnDragStop", function() thumb:SetScript("OnUpdate", nil) end)
    sa.view, sa.track, sa.thumb = view, track, thumb
    track:Hide()
    return sa
end

function Scroll:SetContent(region, height)
    self.content, self.contentH = region, height or 0
    self:ScrollTo(0)
end

function Scroll:SetViewHeight(h)
    self.viewH = h
    self.view:SetHeight(h)
    self.track:SetHeight(h)
    self:ScrollTo(self.offset)
end

function Scroll:MaxScroll() return math.max(0, self.contentH - self.viewH) end
function Scroll:ScrollBy(d) self:ScrollTo(self.offset + d) end

function Scroll:ScrollTo(v)
    local max = self:MaxScroll()
    self.offset = math.max(0, math.min(max, v or 0))
    local c = self.content
    if c then c:ClearAllPoints(); c:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, self.offset) end
    self.track:SetShown(max > 0)
    if max > 0 then
        local th = math.max(24, self.viewH * self.viewH / self.contentH)
        self.thumb:SetHeight(th)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -((self.viewH - th) * self.offset / max))
    end
end

-- a short name in its class colour
function UI.ClassName(name, class)
    local s = UI.Short(name) or ""
    class = ns.Safe and ns.Safe.Text(class) or class
    local col = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return col and col:WrapTextInColorCode(s) or s
end

-- a group member's short name in their class colour ("?" for nobody)
function UI.Named(name) return name and UI.ClassName(name, ns.ClassOf(name)) or "?" end

-- Kill / Wipe tags with a symbol as well as colour (readable without colour)
UI.ICON_YES = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
UI.ICON_NO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"
function UI.ResultTag(result)
    if result == "kill" then return UI.ICON_YES .. " |cff66e08cKill|r" end
    if result == "wipe" then return UI.ICON_NO .. " |cff8a8f9cWipe|r" end
    return ""
end

-- A small checkbox with a label: UI.Check(parent, "Announce in chat", tip, get, set)
-- check:Refresh() redraws it from get().
function UI.Check(parent, label, tip, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(16, 16)
    c.box = CreateFrame("Frame", nil, c, "BackdropTemplate")
    c.box:SetAllPoints()
    UI.Skin(c.box, C.canvas, C.line)
    -- on the box (not the button): the box is a child frame, so it draws over
    -- anything on the button itself - a mark there was hidden under it
    c.mark = c.box:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("CENTER")
    c.mark:SetSize(16, 16)
    c.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c.text = UI.Text(c, "GameFontHighlightSmall", C.text, label, "LEFT", c, "RIGHT", 6, 0)
    function c:Refresh() self.mark:SetShown(get() and true or false) end
    c:SetScript("OnClick", function(self) set(not get()); self:Refresh(); if ns.SettingsChanged then ns.SettingsChanged() end end)
    if tip then UI.Tip(c, label, "ANCHOR_TOP", tip) end
    c:Refresh()
    return c
end

-- seconds -> "m:ss"
function UI.Clock(t)
    t = math.floor(t or 0)
    return ("%d:%02d"):format(math.floor(t / 60), t % 60)
end

function UI.Watermark(frame, size, alpha, yOffset)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetTexture(ns.MEDIA .. "TitanUpLogo")
    t:SetAlpha(alpha or 0.07)
    local function fit()
        local w, h = frame:GetWidth(), frame:GetHeight()
        local s = size
        if type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
            s = math.max(0, math.min(size, w - 16, h - 16))
        end
        local room = (type(h) == "number" and h > 0) and math.max(0, (h - 16 - s) / 2) or math.abs(yOffset or 0)
        local y = math.max(-room, math.min(room, yOffset or 0))
        t:SetSize(s, s)
        t:ClearAllPoints()
        t:SetPoint("CENTER", 0, y)
    end
    fit()
    if frame.HookScript then frame:HookScript("OnSizeChanged", fit) end
    t.Fit = fit
    return t
end

function UI.SetActive(b, on)
    b.active = on and true or nil
    UI.Paint(b)
    if b.icon and not b.keepIconColor then
        local c = on and C.accent or C.text
        b.icon:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

-- Square button with a texture icon (tinted accent when active).
function UI.IconButton(parent, size, texture, tip, onClick)
    local b = UI.Button(parent, size, size, "", tip, onClick)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    if texture then
        b.icon:SetTexture(texture)
        b.icon:SetVertexColor(C.text[1], C.text[2], C.text[3], 1)
    end
    return b
end

-- Simple dropdown: UI.Menu(anchorButton, { { text, onClick, checked }, ... })
local menu, blocker
function UI.Menu(anchor, items)
    if not menu then
        blocker = CreateFrame("Button", nil, UIParent)
        blocker:SetAllPoints(UIParent)
        blocker:SetFrameStrata("FULLSCREEN_DIALOG")
        blocker:RegisterForClicks("AnyUp")
        blocker:Hide()
        menu = CreateFrame("Frame", "TitanBoardMenu", UIParent, "BackdropTemplate")
        UI.Skin(menu, C.bg, C.accent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
        menu:EnableMouse(true)
        menu.rows = {}
        menu:Hide()
        menu:SetScript("OnHide", function() blocker:Hide() end)
        blocker:SetScript("OnClick", function() menu:Hide() end)
        tinsert(UISpecialFrames, "TitanBoardMenu")
    end
    for _, r in ipairs(menu.rows) do r:Hide() end
    for i, it in ipairs(items) do
        local r = menu.rows[i]
        if not r then
            r = UI.Row(menu, 20, 0.08, nil, nil, true)
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetPoint("RIGHT", -8, 0)
            menu.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 2, -4 - (i - 1) * 20)
        r:SetPoint("RIGHT", -2, 0)
        r.text:SetText(it.text)
        local c = it.checked and C.accent or (it.muted and C.muted or C.text)
        r.text:SetTextColor(c[1], c[2], c[3])
        r:SetScript("OnClick", function()
            menu:Hide()
            if it.onClick then it.onClick() end
        end)
        r:Show()
    end
    menu:SetSize(math.max(anchor:GetWidth(), 160), #items * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    blocker:Show()
    menu:Show()
end

function UI.SetDisabled(b, on)
    b.disabled = on and true or nil
    if on then b:Disable() else b:Enable() end
    UI.Paint(b)
end

-- ---------------------------------------------------------------------
-- Prompt dialog: one reusable box for text labels, export and import.
-- UI.Prompt{ title=, help=, text=, accept="OK", onAccept=function(text) }
-- ---------------------------------------------------------------------
local dialog
local function buildDialog()
    local d = UI.Window("TitanBoardDialog", 480, 150, { y = 120, strata = "FULLSCREEN_DIALOG", border = C.accent, drag = true, noClamp = true })

    d.title = UI.Text(d, "GameFontNormal", C.accent, nil, "TOPLEFT", 14, -12)
    d.help = UI.Text(d, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 14, -32)
    d.help:SetPoint("RIGHT", -14, 0)
    d.help:SetJustifyH("LEFT")

    local box = CreateFrame("EditBox", nil, d, "BackdropTemplate")
    UI.Skin(box, C.canvas, C.line)
    box:SetPoint("TOPLEFT", 14, -58)
    box:SetPoint("RIGHT", -14, 0)
    box:SetHeight(28)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetScript("OnEscapePressed", function() d:Hide() end)
    box:SetScript("OnEnterPressed", function() d.ok:Click() end)
    d.box = box

    d.ok = UI.Button(d, 100, 24, "OK", nil, function()
        local cb = d.onAccept
        local text = d.box:GetText()
        d:Hide()
        if cb then cb(text) end
    end)
    d.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    d.cancel = UI.Button(d, 100, 24, "Close", nil, function() d:Hide() end)
    d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
    return d
end

function UI.Prompt(opts)
    dialog = dialog or buildDialog()
    dialog.title:SetText(opts.title or "TitanBoard")
    dialog.help:SetText(opts.help or "")
    dialog.box:SetMaxLetters(opts.max or 0)             -- 0: no limit
    dialog.box:SetText(opts.text or "")
    dialog.box:SetShown(not opts.noInput)
    dialog.onAccept = opts.onAccept
    dialog.ok.label:SetText(opts.accept or "OK")
    dialog.ok:SetShown(opts.onAccept ~= nil)
    dialog:Show()
    if not opts.noInput then dialog.box:SetFocus() end
    if opts.select then dialog.box:HighlightText() end
end

-- ---------------------------------------------------------------------
-- Toast: a docked pop-up with an icon, a line of text and a row of buttons.
-- UI.Toast(name, icon, buttons, o): buttons = { { key=, text=, w=, tip=,
-- click = function(t) }, ... } (each hides the toast, then runs click; the
-- button is t[key]). o: w, h, y, iconSize, pad, font, silent (no sound),
-- onClick (the whole toast is a button). t:Pop(text, secs) shows it for
-- secs seconds; t:Layout() lines up the buttons that are shown.
-- ---------------------------------------------------------------------
function UI.Toast(name, icon, buttons, o)
    o = o or {}
    local t = CreateFrame(o.onClick and "Button" or "Frame", name, UIParent, "BackdropTemplate")
    UI.Skin(t, C.bg, C.accent)
    t:SetSize(o.w or 380, o.h or 74)
    t:SetPoint("TOP", 0, o.y or -140)
    t:SetFrameStrata("DIALOG")
    t:Hide()
    local size = o.iconSize or 36
    t.icon = t:CreateTexture(nil, "ARTWORK")
    if icon then t.icon:SetTexture(icon) end
    t.icon:SetSize(size, size)
    t.icon:SetPoint("LEFT", o.pad or 12, 0)
    t.buttons = {}
    if buttons and #buttons > 0 then
        t.text = UI.Text(t, o.font or "GameFontHighlight", nil, nil, "TOPLEFT", t.icon, "TOPRIGHT", 10, 2)
        t.text:SetPoint("RIGHT", -10, 0)
    else
        t.text = UI.Text(t, o.font or "GameFontHighlight", C.text, nil, "LEFT", t.icon, "RIGHT", 8, 0)
        t.text:SetPoint("RIGHT", -8, 0)
    end
    t.text:SetJustifyH("LEFT")
    for i, spec in ipairs(buttons or {}) do
        local b = UI.Button(t, spec.w or 70, 22, spec.text, spec.tip, function()
            t:Hide()
            if spec.click then spec.click(t) end
        end)
        t[spec.key] = b
        t.buttons[i] = b
    end
    if o.onClick then t:SetScript("OnClick", function(s) s:Hide(); o.onClick(s) end) end
    function t:Layout()
        local prev
        for _, b in ipairs(self.buttons) do
            if b:IsShown() then
                b:ClearAllPoints()
                if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", self.icon, "BOTTOMRIGHT", 10, -6) end
                prev = b
            end
        end
    end
    function t:Pop(text, secs)
        self.text:SetText(text)
        self:Layout()
        self:Show()
        if not o.silent and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
        local token = {}
        self.token = token
        C_Timer.After(secs or 20, function() if self.token == token then self:Hide() end end)
    end
    ns.Dock:Add(t)                  -- stacks with the other pop-ups
    return t
end
