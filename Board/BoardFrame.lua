-- Titan Up - Board/BoardFrame.lua
-- TitanBoard's window: building it (Create) and laying it out - the normal
-- board with collapsible side panels, the combat mini view and viewer mode.
-- Split out of Board.lua; the drawing code there gets the canvas through
-- Board:_attachCanvas.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local Model = ns.Model
local Board = ns.Board

local FW, FH = 1220, 696
local LEFT_W, RIGHT_W, PAD = 220, 214, 8
local TOOL_W = 66
local TITLE_H, BAR_H, FOOT_H = 8, 30, 24          -- no title row: the tab sits above the window
local TITLE_COMPACT = 32          -- mini view / viewer mode keep a compact title row
local MINI_W, MINI_H = 380, 300
local ROW_H = 20
local DOT = ns.MEDIA .. "dot"
local ICONS = ns.MEDIA .. "Tools\\"
local RAID_ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local STAMPS = { { 1, "Tank" }, { 2, "Healer" }, { 3, "DPS" } }
for i = 1, 8 do STAMPS[#STAMPS + 1] = { 10 + i, RAID_ICON_NAMES[i] } end
local ZONES = { { 20, "Soak zone", "A filled circle in the selected color. Its size follows the stroke size." } }

local function settings() return ns.db.settings end

-- ---------------------------------------------------------------------
-- Layout: normal (with either side panel collapsible), mini (combat),
-- and viewer mode (full screen, map only).
-- ---------------------------------------------------------------------
local function rotateCaret(btn, pointLeft)
    btn.icon:SetRotation(pointLeft and -math.pi / 2 or math.pi / 2)
end

-- The plan name gets whatever room is left in the options row, so the row
-- never overlaps (room picker and shape option come and go).
function Board:FitOptionsBar()
    if not (self.optBar and self.optLead) or self.mini or self.fullscreen then return end
    local s = settings()
    local left = PAD + (s.leftCollapsed and 0 or (LEFT_W + PAD)) + TOOL_W + 6
    local barW = FW - PAD - left
    local function w(fr, gap) return (fr and fr:IsShown()) and ((fr:GetWidth() or 0) + (gap or 0)) or 0 end
    local leftFixed = self.optLeftW + w(self.shapeOpt, 24)
    local rightFixed = w(self.titleClose, 8) + w(self.miniBtn, 4) + w(self.viewerBtn, 8) + w(self.pill, 10)
        + w(self.clearBtn, 4) + 54 + w(self.roomBtn, 12)
    local ctxW = math.max(60, math.min(220, barW - leftFixed - rightFixed - 16))
    self.ctxText:SetWidth(ctxW - 10)
    self.optLead:ClearAllPoints()
    self.optLead:SetPoint("LEFT", self.optBar, "LEFT", ctxW, 0)
end

function Board:ApplyLayout()
    local f, canvas = self.frame, self.canvas
    if not f then return end
    local s = settings()
    local full = self.fullscreen
    local mini = self.mini and not full
    local edit = not full and not mini
    local showLeft = edit and not s.leftCollapsed
    local showRight = edit and not s.rightCollapsed

    -- Window geometry
    if full then
        if not self._savedPos then self._savedPos = { f:GetLeft(), f:GetTop() } end
        f:ClearAllPoints()
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("FULLSCREEN")
    else
        local left, top
        if self._savedPos then
            left, top = self._savedPos[1], self._savedPos[2]
            self._savedPos = nil
        else
            left, top = f:GetLeft(), f:GetTop()
        end
        f:ClearAllPoints()
        f:SetFrameStrata("HIGH")
        if mini then f:SetSize(MINI_W + PAD * 2, MINI_H + TITLE_COMPACT + PAD) else f:SetSize(FW, FH) end
        if left and top then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) else f:SetPoint("CENTER") end
    end

    -- Panels
    self.left:SetShown(showLeft)
    self.right:SetShown(showRight)
    for _, part in ipairs({ self.strip, self.optBar, self.footLeft, self.footRight }) do part:SetShown(edit) end

    local strip = self.strip
    strip:ClearAllPoints()
    if showLeft then
        strip:SetPoint("TOPLEFT", self.left, "TOPRIGHT", PAD, 0)
        strip:SetPoint("BOTTOMLEFT", self.left, "BOTTOMRIGHT", PAD, 0)
    else
        -- left pane collapsed: its arrow sits above the tool column
        strip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_H - 26)
        strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, FOOT_H)
    end
    local bar = self.optBar
    bar:ClearAllPoints()
    -- the options row runs the full width (Live Viewers starts below it)
    bar:SetPoint("TOPLEFT", strip, "TOPRIGHT", 6, showLeft and 0 or 26)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -TITLE_H)
    canvas:ClearAllPoints()
    if edit then
        canvas:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
        if showRight then
            canvas:SetPoint("BOTTOMRIGHT", self.right, "BOTTOMLEFT", -PAD, 0)
        else
            canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOT_H)
        end
    else
        canvas:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_COMPACT)
        canvas:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    end

    -- The navigation tab (above the window) shows in the normal board only;
    -- mini view and viewer mode stay compact
    self.header.tab:SetShown(edit)

    -- Pane arrows: bottom of each pane's inner edge, pointing toward the
    -- window edge it collapses to; when collapsed, at that window edge
    -- pointing back in. The footer text makes room for them.
    local lt, rt = self.leftToggle, self.rightToggle
    lt:SetShown(edit)
    rt:SetShown(edit)
    lt:ClearAllPoints()
    rt:ClearAllPoints()
    if showLeft then lt:SetPoint("TOPRIGHT", self.left, "TOPRIGHT", -6, -6)         -- Encounters header
    else lt:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_H - 2) end                 -- above the tool column
    if showRight then rt:SetPoint("TOPRIGHT", self.right, "TOPRIGHT", -6, -6)       -- Live Viewers header
    else rt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(TITLE_H + BAR_H + 6)) end   -- where the pane's top was
    lt:SetFrameLevel(f:GetFrameLevel() + 30)
    rt:SetFrameLevel(f:GetFrameLevel() + 30)

    -- Normal board: the options row holds everything -
    --   [plan name] [colors] [size] ...  [Undo] [Clear] [LOCAL] [Viewer mode] [Mini] [X]
    -- and the slide arrows sit at the bottom-center of the map.
    -- Mini view / viewer mode: a compact title row, from the X leftward.
    local x = self.titleClose
    x:ClearAllPoints()
    local chain
    if edit then
        x:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        chain = { self.miniBtn, self.viewerBtn, self.pill }
    else
        x:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
        chain = mini and { self.miniBtn, self.miniNav } or { self.viewerBtn, self.pill, self.miniNav }
    end
    local prev = x
    for _, part in ipairs(chain) do
        part:ClearAllPoints()
        local gap = (part == self.pill) and -8 or (part == self.miniNav and -6 or (prev == x and -8 or -4))
        part:SetPoint("RIGHT", prev, "LEFT", gap, 0)
        prev = part
    end
    self.ctxText:ClearAllPoints()
    if edit then
        self.clearBtn:ClearAllPoints()
        self.clearBtn:SetPoint("RIGHT", self.pill, "LEFT", -10, 0)
        self.ctxText:SetPoint("LEFT", bar, "LEFT", 2, 0)
        self.miniNav:ClearAllPoints()
        self.miniNav:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 8)
        self:FitOptionsBar()
    else
        self.ctxText:SetPoint("LEFT", f, "TOPLEFT", 12, -TITLE_COMPACT / 2)
        self.ctxText:SetWidth(300)
    end
    self.emptyText:ClearAllPoints()
    self.emptyText:SetPoint("BOTTOM", 0, (edit and not showLeft) and 44 or 14)   -- above the slide arrows
    rotateCaret(self.leftToggle, showLeft)
    rotateCaret(self.rightToggle, not showRight)
    self.leftToggle.tip = showLeft and "Hide encounters, plans & slides" or "Show encounters, plans & slides"
    self.rightToggle.tip = showRight and "Hide live viewers & sharing" or "Show live viewers & sharing"
    self.pill:SetShown(not mini)
    self.ctxText:SetShown(not mini)
    self.viewerBtn:SetShown(not mini)
    self.miniNav:SetFrameLevel(canvas:GetFrameLevel() + 20)
    self.viewerBtn.label:SetText(full and "Exit viewer mode" or "Viewer mode")
    self.viewerBtn:SetWidth(full and 116 or 92)
    self.miniBtn:SetShown(not full)
    self.miniBtn.label:SetText(mini and "Expand" or "Mini")
    self.miniBtn:SetWidth(mini and 56 or 44)
    -- Slide navigation in the title bar whenever the slide list isn't visible
    self.miniNav:SetShown(not showLeft)
    self.miniPrev:SetShown(ns.IsOwner())        -- only the leader changes the slide
    self.miniNext:SetShown(ns.IsOwner())

    C_Timer.After(0, function() if Board:IsShown() then Board:RenderAll() end end)
end

function Board:TogglePanel(side)
    local s = settings()
    if side == "left" then s.leftCollapsed = not s.leftCollapsed else s.rightCollapsed = not s.rightCollapsed end
    self:ApplyLayout()
end

function Board:SetMini(on)
    if not self.frame or self.mini == on then return end
    if on then self:CancelGesture() end
    self.mini = on
    self:ApplyLayout()               -- (redraws the board on the next frame)
    ns.Presence:Announce("P")
    self:ResetView()
end

-- Viewer mode: the map fills the screen. Drawers can still draw with the
-- current tool and step through slides; Esc leaves viewer mode.
function Board:SetFullscreen(on)
    if not self.frame or (self.fullscreen and true or false) == on then return end
    self.fullscreen = on or nil
    if on then
        self.mini = nil
        self._autoMini = nil
    end
    self:ApplyLayout()
end

local SELECTED = { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.6 }      -- a selected list row

-- a dropdown-style button: its label on the left, a small caret on the right
local function dropButton(b, labelInset, caret, caretX)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -labelInset, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ICONS .. "caret")
    t:SetSize(caret, caret)
    t:SetPoint("RIGHT", -caretX, 0)
    t:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 1)
end

function Board:Create()
    -- Standard Titan Up title bar: the tab above with the module icons, the X;
    -- board-only controls line up to the left of the X.
    local f, header = ns.Nav:Window(self, "TitanBoardFrame", "board", "TITANBOARD", FW, FH, { railMin = true, mark = false,
        onShow = function() Board:_onShow() end, onClose = function() Board:Hide() end, canDrag = function() return not Board.fullscreen end })
    f:SetScript("OnHide", function() Board:_onHide() end)

    -- Ctrl+Z undo without eating other keys
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    -- Keys the board uses are captured; everything else passes through to
    -- the game. Capture is always switched back off when a key is released
    -- and when combat starts (it can't be changed during combat).
    f:SetScript("OnKeyDown", function(frame, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" and Board.fullscreen then
            frame:SetPropagateKeyboardInput(false)
            Board:SetFullscreen(false)
        elseif key == "Z" and IsControlKeyDown() then
            frame:SetPropagateKeyboardInput(false)
            Board:Undo()
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    f:SetScript("OnKeyUp", function(frame)
        if not InCombatLockdown() then frame:SetPropagateKeyboardInput(true) end
    end)

    local title = header
    self.titleClose = header.close

    -- pane collapse arrows live at the bottom of each pane's inner edge
    -- (placed in ApplyLayout), pointing toward the edge they collapse to
    self.leftToggle = UI.IconButton(f, 20, ICONS .. "caret", "", function() Board:TogglePanel("left") end)
    self.ctxText = UI.Text(title, "GameFontHighlight")
    self.ctxText:SetPoint("LEFT", header, "LEFT", 12, 0)     -- the board's name is in the tab above
    self.ctxText:SetWidth(560)
    self.ctxText:SetJustifyH("LEFT")
    self.ctxText:SetWordWrap(false)

    self.rightToggle = UI.IconButton(f, 20, ICONS .. "caret", "", function() Board:TogglePanel("right") end)
    self.miniBtn = UI.Button(title, 44, 22, "Mini", "Toggle the compact view (opens automatically in combat)", function()
        Board._autoMini = nil
        Board:SetMini(not Board.mini)
    end)
    self.viewerBtn = UI.Button(title, 92, 22, "Viewer mode", "Full screen, map only (Esc to leave). You can still step through slides from the title bar.", function()
        Board:SetFullscreen(not Board.fullscreen)
    end)

    local pill = CreateFrame("Frame", nil, title, "BackdropTemplate")
    UI.Skin(pill, C.bg, C.muted)
    pill:SetSize(96, 20)
    pill.text = UI.Text(pill, "GameFontNormalSmall", nil, nil, "CENTER")
    self.pill = pill

    -- Mini view: previous/next slide in the title bar
    local nav = CreateFrame("Frame", nil, title)
    nav:SetSize(130, 20)
    nav:Hide()
    self.miniNav = nav
    self.miniNext = UI.Button(nav, 20, 20, ">", "Next slide", function()
        if Model.plan then Board:SetPage(math.min(Model:SlideCount(), Model.plan.page + 1)) end
    end)
    self.miniNext:SetPoint("RIGHT")
    self.miniSlideText = UI.Text(nav, "GameFontHighlightSmall", nil, nil, "RIGHT", self.miniNext, "LEFT", -6, 0)
    self.miniPrev = UI.Button(nav, 20, 20, "<", "Previous slide", function()
        if Model.plan then Board:SetPage(math.max(1, Model.plan.page - 1)) end
    end)
    self.miniPrev:SetPoint("RIGHT", self.miniSlideText, "LEFT", -6, 0)

    -- Left: encounter list + phases -----------------------------------
    local left = UI.Panel(f)
    left:SetPoint("TOPLEFT", PAD, -TITLE_H)
    left:SetPoint("BOTTOMLEFT", PAD, FOOT_H)
    left:SetWidth(LEFT_W)
    self.left = left

    UI.Text(left, "GameFontNormalSmall", C.muted, "ENCOUNTERS", "TOPLEFT", 10, -10)

    local hereBtn = UI.Button(left, 64, 18, "Locate", "Jump to the instance you're standing in", function()
        local ctx = ns.Content:CurrentContext()
        if not ctx then ns.Print("You're not in an instance.") return end
        if Board:Following("encounter") then return end
        Board:SelectContext(ctx, 1)
        Board:RefreshList(true)
    end)
    hereBtn:SetPoint("BOTTOMRIGHT", -8, 322)       -- just above the Encounters / Plan separator

    local listArea = CreateFrame("Frame", nil, left)
    listArea:SetPoint("TOPLEFT", 4, -30)
    listArea:SetPoint("BOTTOMRIGHT", -4, 344)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, d)
        Board.listOffset = (Board.listOffset or 0) - d * 3
        Board:RefreshList()
    end)
    self.listRows = {}
    local listH = FH - TITLE_H - FOOT_H - 30 - 344
    for i = 1, math.floor(listH / ROW_H) do
        local row = UI.Row(listArea, ROW_H, 0.05, SELECTED, nil, true)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(s) Board:_listClick(s.item) end)
        self.listRows[i] = row
    end

    local function divider(yy, parent)
        local d = (parent or left):CreateTexture(nil, "ARTWORK")
        d:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        d:SetHeight(1)
        d:SetPoint("BOTTOMLEFT", 8, yy)
        d:SetPoint("BOTTOMRIGHT", -8, yy)
    end
    self.ownerButtons = {}
    local thirdW = math.floor((LEFT_W - 16 - 8) / 3)

    -- PLAN: which saved plan for this encounter
    divider(316)
    UI.Text(left, "GameFontNormalSmall", C.muted, "PLAN", "BOTTOMLEFT", 10, 296)
    self.planCount = UI.Text(left, "GameFontHighlightSmall", C.muted, nil, "BOTTOMRIGHT", -10, 296)
    self.planBtn = UI.Button(left, LEFT_W - 16, 24, "", "Click to switch between saved plans for this encounter.\nEverything saves automatically as you draw.", function() Board:ShowPlanMenu() end)
    self.planBtn:SetPoint("BOTTOMLEFT", 8, 266)
    dropButton(self.planBtn, 22, 12, 8)
    local planDefs = {
        { "New", "Start a blank plan for this encounter", function() Board:NewPlan() end },
        { "Save as", "Save a copy under a new name", function() Board:SavePlanAs() end },
        { "Delete", "Delete this plan", function() Board:DeletePlan() end },
    }
    for i, d in ipairs(planDefs) do
        local b = UI.Button(left, thirdW, 22, d[1], d[2], d[3])
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * (thirdW + 4), 238)
        table.insert(self.ownerButtons, b)
    end

    -- SLIDES: click one to show it to everyone
    divider(228)
    local slh = UI.Text(left, "GameFontNormalSmall", C.muted, "SLIDES", "BOTTOMLEFT", 10, 208)
    self.slideCountText = UI.Text(left, "GameFontHighlightSmall", C.muted, nil, "LEFT", slh, "RIGHT", 8, 0)
    local addSlide = UI.Button(left, 54, 20, "+ Add", "Add a slide after this one (starts with the current view)", function() Board:AddSlide() end)
    addSlide:SetPoint("BOTTOMRIGHT", -8, 204)
    table.insert(self.ownerButtons, addSlide)

    local slideArea = CreateFrame("Frame", nil, left)
    slideArea:SetPoint("BOTTOMLEFT", 4, 34)
    slideArea:SetPoint("BOTTOMRIGHT", -4, 34)
    slideArea:SetHeight(164)
    slideArea:EnableMouseWheel(true)
    slideArea:SetScript("OnMouseWheel", function(_, d)
        Board.slideOffset = (Board.slideOffset or 0) - d
        Board:RefreshSlides(true)                -- scrolling doesn't snap back to the current slide
    end)
    self.slideRows = {}
    for i = 1, 8 do
        local row = UI.Row(slideArea, 20, 0.05, SELECTED, nil, true)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 20 - 2)
        row:SetPoint("RIGHT")
        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.num:SetPoint("LEFT", 6, 0)
        row.num:SetWidth(18)
        row.num:SetJustifyH("RIGHT")
        row.num:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.count:SetPoint("RIGHT", -6, 0)
        row.count:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        row.text:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        row:SetScript("OnClick", function(s) Board:SetPage(s.index) end)
        UI.Tip(row, "Click to show this slide to everyone", "ANCHOR_RIGHT", "The number on the right is how many drawings it has.")
        self.slideRows[i] = row
    end

    local slideDefs = {
        { 26, "up", "Move this slide up", function() Board:MoveSlide(-1) end },
        { 26, "down", "Move this slide down", function() Board:MoveSlide(1) end },
        { 42, "Rename", "Rename this slide", function() Board:RenameSlide() end },
        { 36, "Copy", "Duplicate this slide", function() Board:DuplicateSlide() end },
        { 42, "Delete", "Delete this slide", function() Board:DeleteSlide() end },
    }
    local sx = 8
    for _, d in ipairs(slideDefs) do
        local b
        if d[2] == "up" or d[2] == "down" then
            b = UI.IconButton(left, 22, ICONS .. "caret", d[3], d[4])
            b:SetWidth(d[1])
            b.icon:ClearAllPoints()
            b.icon:SetSize(12, 12)
            b.icon:SetPoint("CENTER")
            if d[2] == "up" then b.icon:SetTexCoord(0, 1, 1, 0) end
        else
            b = UI.Button(left, d[1], 22, d[2], d[3], d[4])
        end
        b:SetPoint("BOTTOMLEFT", sx, 8)
        sx = sx + d[1] + 3
        table.insert(self.ownerButtons, b)
    end

    -- Right: viewers ----------------------------------------------------
    local right = UI.Panel(f)
    right:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + BAR_H + 6))      -- below the options row
    right:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H)
    right:SetWidth(RIGHT_W)
    self.right = right

    UI.Text(right, "GameFontNormalSmall", C.muted, "LIVE VIEWERS", "TOPLEFT", 10, -10)
    self.countText = UI.Text(right, "GameFontHighlightSmall", nil, nil, "TOPLEFT", 10, -28)

    local vArea = CreateFrame("Frame", nil, right)
    vArea:SetPoint("TOPLEFT", 4, -48)
    vArea:SetPoint("BOTTOMRIGHT", -4, 104)
    vArea:EnableMouseWheel(true)
    vArea:SetScript("OnMouseWheel", function(_, d)
        Board.viewerOffset = (Board.viewerOffset or 0) - d * 3
        Board:UpdateViewers()
    end)
    self.viewerRows = {}
    local vH = FH - TITLE_H - BAR_H - 6 - FOOT_H - 48 - 104
    for i = 1, math.floor(vH / 18) do
        local row = UI.Row(vArea, 18, 0.05, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.5 }, nil, true)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
        row:SetPoint("RIGHT")
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetTexture(DOT)
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("LEFT", 6, 0)
        row.name = row.text
        row.name:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
        row.name:SetWidth(96)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("RIGHT", -4, 0)
        row.status:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(s) Board:_viewerClick(s.entry) end)
        row:SetScript("OnEnter", function(s)
            local e = s.entry
            if not e or e.header then return end
            GameTooltip:SetOwner(s, "ANCHOR_LEFT")
            GameTooltip:SetText(e.name)
            if e.ver then GameTooltip:AddLine("TitanBoard " .. e.ver, 0.6, 0.6, 0.6) end
            GameTooltip:AddLine("Leader: click to grant or remove drawing rights.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.viewerRows[i] = row
    end

    divider(96, right)
    UI.Text(right, "GameFontNormalSmall", C.muted, "SHARE", "BOTTOMLEFT", 10, 74)
    local shareW = math.floor((RIGHT_W - 16 - 8) / 3)
    local shareDefs = {
        { "Invite", "Ping the group to open the board", function() ns.Invite:Send() end },
        { "Export", "Copy this encounter's plan (all phases) as a string", function() ns.ImportExport:ShowExport() end },
        { "Import", "Paste a plan string", function() ns.ImportExport:ShowImport() end },
    }
    for i, d in ipairs(shareDefs) do
        local b = UI.Button(right, shareW, 24, d[1], d[2], d[3])
        b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * (shareW + 4), 40)
    end
    self.syncBtn = UI.Button(right, RIGHT_W - 16, 24, "Send full plan", "Leader: resend everything to the group. Viewer: ask the leader for the current board.", function()
        if ns.IsOwner() then
            ns.Sync:SendAll(true)
            if ns.Comms:Mode() == "local" then ns.Print("Solo - nothing to send.") end
        else
            ns.Sync:RequestSnapshot()
        end
    end)
    self.syncBtn:SetPoint("BOTTOM", 0, 10)

    -- Tool strip (left of the canvas): tools, then stamps -------------
    local strip = UI.Panel(f)
    strip:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD, 0)
    strip:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", PAD, 0)
    strip:SetWidth(TOOL_W)
    self.strip = strip

    local function sectionLabel(text, yy) UI.Text(strip, "GameFontNormalSmall", C.muted, text, "TOP", 0, yy) end
    -- a tool or stamp button's tooltip: its name and what it does
    local function tip(b, name, text)
        b:SetScript("OnEnter", function(s)
            s.hover = true
            UI.Paint(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 1, 1)
            GameTooltip:AddLine(text, 0.75, 0.78, 0.84, true)
            GameTooltip:Show()
        end)
    end
    local function gridPos(i, yy)
        return 5 + ((i - 1) % 2) * 28, yy - math.floor((i - 1) / 2) * 28
    end

    sectionLabel("TOOLS", -10)
    self.toolBtns = {}
    local y = -28
    for i, def in ipairs(Board.TOOLS) do
        local mode = def[1]
        local b = UI.IconButton(strip, 26, ICONS .. def[4], nil, function() Board:SetTool(mode) end)
        b:SetPoint("TOPLEFT", gridPos(i, y))
        tip(b, def[2], def[3])
        self.toolBtns[mode] = b
    end
    y = y - math.ceil(#Board.TOOLS / 2) * 28 - 4
    self.toolName = UI.Text(strip, "GameFontHighlightSmall", C.accent, nil, "TOP", 0, y)
    y = y - 22

    self.stampBtns = {}
    local function stampButtons(list, yy)
        for i, def in ipairs(list) do
            local k = def[1]
            local b = UI.IconButton(strip, 26, nil, nil, function() Board:SetStamp(k) end)
            b.keepIconColor = true
            b:SetPoint("TOPLEFT", gridPos(i, yy))
            b.icon:SetPoint("TOPLEFT", 3, -3)
            b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            Board.StampTexture(b.icon, k)
            if k == 20 then b.icon:SetVertexColor(0.31, 0.86, 0.97, 0.8) end
            tip(b, def[2], (def[3] or def[2]) .. "\n|cff8a8f9cShift-click on the board to add a name|r")
            self.stampBtns[k] = b
        end
        return yy - math.ceil(#list / 2) * 28
    end
    sectionLabel("STAMPS", y)
    y = stampButtons(STAMPS, y - 18) - 8
    sectionLabel("ZONES", y)
    stampButtons(ZONES, y - 18)

    -- Options bar (above the canvas): settings for the active tool --------
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", strip, "TOPRIGHT", 6, 0)
    bar:SetPoint("TOPRIGHT", right, "TOPLEFT", -PAD, 0)
    bar:SetHeight(BAR_H)
    self.optBar = bar

    -- the plan name sits at the row's left end; colors and size follow it
    -- (FitOptionsBar moves this lead point to fit the name)
    local lead = CreateFrame("Frame", nil, bar)
    lead:SetSize(1, 1)
    lead:SetPoint("LEFT", bar, "LEFT", 150, 0)
    self.optLead = lead
    local x = 0
    self.colorBtns = {}
    for i, col in ipairs(self.COLORS) do
        local b = UI.Button(bar, 20, 20, "", nil, function() Board:SetColor(i) end)
        b:SetPoint("LEFT", lead, "LEFT", x, 0)
        local sw = b:CreateTexture(nil, "ARTWORK")
        sw:SetPoint("TOPLEFT", 3, -3)
        sw:SetPoint("BOTTOMRIGHT", -3, 3)
        sw:SetColorTexture(col[1], col[2], col[3], 1)
        x = x + 22
        self.colorBtns[i] = b
    end
    x = x + 10
    local sl = UI.Text(bar, "GameFontHighlightSmall", C.muted, "Size", "LEFT", lead, "LEFT", x, 0)
    self.optLeftW = x + 125              -- colors + size controls, for FitOptionsBar
    local minus = UI.Button(bar, 20, 22, "-", "Smaller stroke (Ctrl + mouse wheel)", function() Board:SetWidth(settings().width - 1) end)
    minus:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    local prev = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    UI.Skin(prev, C.canvas, C.line)
    prev:SetSize(26, 22)
    prev:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    self.sizeDot = prev:CreateTexture(nil, "ARTWORK")
    self.sizeDot:SetTexture(DOT)
    self.sizeDot:SetPoint("CENTER")
    local plus = UI.Button(bar, 20, 22, "+", "Bigger stroke (Ctrl + mouse wheel)", function() Board:SetWidth(settings().width + 1) end)
    plus:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    self.sizeText = UI.Text(bar, "GameFontHighlightSmall", C.muted, nil, "LEFT", plus, "RIGHT", 5, 0)

    self.shapeOpt = UI.Button(bar, 90, 24, "", "Click or mouse wheel to change. Shift + wheel on the board also works, even mid-drag.", function()
        Board:CycleShapeOption(1)
    end)
    self.shapeOpt:SetPoint("LEFT", plus, "RIGHT", 24, 0)
    self.shapeOpt:EnableMouseWheel(true)
    self.shapeOpt:SetScript("OnMouseWheel", function(_, d) Board:CycleShapeOption(d) end)
    self.shapeOpt:Hide()

    self.clearBtn = UI.Button(bar, 54, 24, "Clear", "Erase this phase (click twice)", function() Board:ClearPage() end)
    self.clearBtn:SetPoint("RIGHT", 0, 0)
    local undoBtn = UI.Button(bar, 54, 24, "Undo", "Undo (Ctrl+Z)", function() Board:Undo() end)
    undoBtn:SetPoint("RIGHT", self.clearBtn, "LEFT", -4, 0)

    self.roomBtn = UI.Button(bar, 128, 24, "", "Background for this slide. New slides start with the same room.", function() Board:ShowRoomMenu() end)
    self.roomBtn:SetPoint("RIGHT", undoBtn, "LEFT", -12, 0)
    dropButton(self.roomBtn, 20, 10, 7)
    self.roomBtn:Hide()

    -- Center: canvas ----------------------------------------------------
    local canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.Skin(canvas, C.canvas, C.line)
    canvas:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    canvas:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -PAD, 0)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    canvas:SetScript("OnMouseDown", function(_, b) Board:_down(b) end)
    canvas:SetScript("OnMouseUp", function(_, b) Board:_up(b) end)
    canvas:SetScript("OnMouseWheel", function(_, d) Board:_wheel(d) end)
    canvas:SetScript("OnUpdate", function() Board:_update() end)
    canvas:SetScript("OnSizeChanged", function() if Board:IsShown() then Board:RenderCanvas() end end)
    self.canvas = canvas

    local layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints()
    local overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(layer:GetFrameLevel() + 10)
    self:_attachCanvas(canvas, layer, overlay)

    self.bossPin = layer:CreateTexture(nil, "BORDER")
    self.bossPin:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    self.bossPin:SetSize(22, 22)
    self.bossPin:SetAlpha(0.55)
    self.bossPin:Hide()

    self.bannerBg = overlay:CreateTexture(nil, "BACKGROUND")
    self.bannerBg:SetColorTexture(0, 0, 0, 0.6)
    self.banner = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.banner:SetPoint("TOP", 0, -8)
    self.bannerBg:SetPoint("TOPLEFT", self.banner, "TOPLEFT", -8, 4)
    self.bannerBg:SetPoint("BOTTOMRIGHT", self.banner, "BOTTOMRIGHT", 8, -4)
    self.bannerBg:Hide()

    self.emptyText = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.emptyText:SetPoint("BOTTOM", 0, 14)
    self.emptyText:SetText("Pick an encounter on the left, or just start drawing.")

    -- Footer ------------------------------------------------------------
    self.footLeft = UI.Text(f, "GameFontHighlightSmall", C.muted, "Left: draw   Right-drag: pan   Right-click: delete   Wheel: zoom   Ctrl+drag: move item   Ctrl+Wheel: resize   Alt+drag: laser   Ctrl+Z: undo", "BOTTOMLEFT", PAD + 4, 6)
    self.footRight = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "BOTTOMRIGHT", -PAD - 4, 6)

    self:SetTool("P")
    self:SetColor(settings().color)
    self:UpdateSizePreview()
    self:ApplyLayout()
end
