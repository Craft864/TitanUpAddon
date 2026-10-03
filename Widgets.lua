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

function UI.Text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
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
function UI.Watermark(frame, size, alpha, yOffset)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetTexture(ns.MEDIA .. "TitanUpLogo")
    t:SetSize(size, size)
    t:SetPoint("CENTER", 0, yOffset or 0)
    t:SetAlpha(alpha or 0.07)
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
            r = CreateFrame("Button", nil, menu)
            r:SetHeight(20)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetPoint("RIGHT", -8, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
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
    local d = CreateFrame("Frame", "TitanBoardDialog", UIParent, "BackdropTemplate")
    d:SetSize(480, 150)
    d:SetPoint("CENTER", 0, 120)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetToplevel(true)
    UI.Skin(d, C.bg, C.accent)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()
    tinsert(UISpecialFrames, "TitanBoardDialog")

    d.title = UI.Text(d, "GameFontNormal", C.accent)
    d.title:SetPoint("TOPLEFT", 14, -12)
    d.help = UI.Text(d, "GameFontHighlightSmall", C.muted)
    d.help:SetPoint("TOPLEFT", 14, -32)
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
    dialog.box:SetText(opts.text or "")
    dialog.box:SetShown(not opts.noInput)
    dialog.onAccept = opts.onAccept
    dialog.ok.label:SetText(opts.accept or "OK")
    dialog.ok:SetShown(opts.onAccept ~= nil)
    dialog:Show()
    if not opts.noInput then dialog.box:SetFocus() end
    if opts.select then dialog.box:HighlightText() end
end
