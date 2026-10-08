-- TitanBoard - Board.lua
-- The board window: encounter list (left), tools (top), canvas (center),
-- live viewers (right), plus the combat mini view.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local Model = ns.Model
local U = ns.U

local Board = {}
ns.Board = Board

local FW, FH = 1220, 696
local LEFT_W, RIGHT_W, PAD = 220, 214, 8
local TOOL_W = 66
local TITLE_H, BAR_H, FOOT_H = 8, 30, 24          -- no title row: the tab sits above the window
local TITLE_COMPACT = 32          -- mini view / viewer mode keep a compact title row
local MINI_W, MINI_H = 380, 300
local ROW_H = 20
local DOT = ns.MEDIA .. "dot"
local SHAPES = ns.MEDIA .. "Shapes\\"
local FILL_SCALE = 512 / 504   -- shape textures leave a small antialiasing margin
local PIE_ANGLES = { 30, 45, 60, 90, 120, 180, 270 }
local DONUT_HOLES = { 30, 40, 50, 60, 70, 80 }

-- the value in list nearest to v
local function snap(v, list)
    local best = list[1]
    for _, x in ipairs(list) do
        if v and math.abs(x - v) < math.abs(best - v) then best = x end
    end
    return best
end

Board.Snap, Board.PIE_ANGLES = snap, PIE_ANGLES      -- (the Raidstrats import snaps cones too)

Board.COLORS = {
    { 0.96, 0.30, 0.30 }, { 1.00, 0.60, 0.20 }, { 1.00, 0.88, 0.25 }, { 0.38, 0.90, 0.45 },
    { 0.31, 0.86, 0.97 }, { 0.38, 0.55, 1.00 }, { 0.80, 0.48, 1.00 }, { 1.00, 1.00, 1.00 },
}

local ICONS = ns.MEDIA .. "Tools\\"
local TOOLS = {
    { "V", "Move", "Drag any item to reposition it. Tip: Ctrl + drag moves items with any tool.", "move" },
    { "P", "Pen", "Freehand drawing", "pen" },
    { "L", "Line", "Click and drag", "line" },
    { "A", "Arrow", "Click and drag", "arrow" },
    { "C", "Circle", "Drag out from the center", "circle" },
    { "W", "Pie", "Cone / pie slice: drag from the tip toward where it points. Shift+wheel or the Angle button changes the width", "pie" },
    { "D", "Donut", "Ring: drag from the center to the outer edge. Shift+wheel or the Hole button changes the hole size", "donut" },
    { "T", "Text", "Click to place a label", "text" },
    { "E", "Erase", "Drag over items to delete them", "erase" },
    { "R", "Laser", "Point without drawing: hold the left mouse button and everyone sees your pointer. Alt + drag does the same with any tool. Raiders who can't draw always point.", "laser" },
}

local RAID_ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local STAMPS = { { 1, "Tank" }, { 2, "Healer" }, { 3, "DPS" } }
for i = 1, 8 do STAMPS[#STAMPS + 1] = { 10 + i, RAID_ICON_NAMES[i] } end
local ZONES = { { 20, "Soak zone", "A filled circle in the selected color. Its size follows the stroke size." } }

-- Role icons: first atlas that exists on this client wins.
local ROLE_ATLASES = {
    { "groupfinder-icon-role-large-tank", "UI-LFG-RoleIcon-Tank", "roleicon-tiny-tank" },
    { "groupfinder-icon-role-large-heal", "UI-LFG-RoleIcon-Healer", "roleicon-tiny-healer" },
    { "groupfinder-icon-role-large-dps", "UI-LFG-RoleIcon-DPS", "roleicon-tiny-dps" },
}
local ROLE_FALLBACK_COLOR = { { 0.35, 0.55, 1 }, { 0.38, 0.9, 0.45 }, { 0.96, 0.3, 0.3 } }

local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local view = { zoom = 1, cx = U / 2, cy = U / 2 }
local cw, ch, bw, bh = 700, 540, 700, 540
local canvas, layer, overlay
local tool = { mode = "P", stamp = 1 }
local undo = {}
-- shared with BoardPanels.lua (same tables, never reassigned)
Board._view, Board._undo = view, undo
local pools = { line = {}, tex = {}, fs = {} }
local bgTex, bgLines = {}, {}

-- ---------------------------------------------------------------------
-- Coordinates: board units (0..4095) <-> canvas pixels (x right, y down)
-- ---------------------------------------------------------------------
local function toPx(x, y)
    return (x - view.cx) / U * bw * view.zoom + cw / 2,
           (y - view.cy) / U * bh * view.zoom + ch / 2
end

local function fromPx(px, py)
    return (px - cw / 2) / (bw * view.zoom) * U + view.cx,
           (py - ch / 2) / (bh * view.zoom) * U + view.cy
end

local function cursor()
    local x, y = GetCursorPosition()
    local s = canvas:GetEffectiveScale()
    return x / s - canvas:GetLeft(), canvas:GetTop() - y / s
end

local function clampView()
    local hx = cw / (bw * view.zoom) * U / 2
    local hy = ch / (bh * view.zoom) * U / 2
    if hx >= U / 2 then view.cx = U / 2 else view.cx = math.max(hx, math.min(U - hx, view.cx)) end
    if hy >= U / 2 then view.cy = U / 2 else view.cy = math.max(hy, math.min(U - hy, view.cy)) end
end

local function settings() return ns.db.settings end

-- ---------------------------------------------------------------------
-- Region pools
-- ---------------------------------------------------------------------
local function getLine()
    local l = table.remove(pools.line)
    if not l then l = layer:CreateLine(nil, "ARTWORK") end
    l:Show()
    return l
end

local function getTex(drawLayer)
    local t = table.remove(pools.tex)
    if not t then t = layer:CreateTexture(nil, "OVERLAY") end
    t:SetDrawLayer(drawLayer or "OVERLAY")
    t:ClearAllPoints()
    t:SetTexCoord(0, 1, 0, 1)
    t:SetRotation(0)
    t:SetVertexColor(1, 1, 1, 1)
    t:Show()
    return t
end

local function getFS()
    local f = table.remove(pools.fs)
    if not f then f = layer:CreateFontString(nil, "OVERLAY") end
    f:ClearAllPoints()
    f:Show()
    return f
end

function Board:ReleaseOp(op)
    local r = op._r
    if not r then return end
    for _, l in ipairs(r.l) do l:Hide(); pools.line[#pools.line + 1] = l end
    for _, t in ipairs(r.t) do t:Hide(); pools.tex[#pools.tex + 1] = t end
    for _, f in ipairs(r.f) do f:Hide(); pools.fs[#pools.fs + 1] = f end
    op._r = nil
end

Board.CLASS_ICONS = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "DeathKnight", "Shaman",
    "Mage", "Warlock", "Monk", "Druid", "DemonHunter", "Evoker" }

function Board.StampTexture(tx, k)
    if k >= 1 and k <= 3 then
        for _, name in ipairs(ROLE_ATLASES[k]) do
            if atlasExists(name) then
                tx:SetAtlas(name)
                return
            end
        end
        local c = ROLE_FALLBACK_COLOR[k]
        tx:SetTexture(DOT)
        tx:SetTexCoord(0, 1, 0, 1)
        tx:SetVertexColor(c[1], c[2], c[3], 1)
    elseif k >= 11 and k <= 18 then
        tx:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (k - 10))
        tx:SetTexCoord(0, 1, 0, 1)
    elseif k >= 31 and k <= 43 then
        -- class icons (used by Raidstrats imports)
        tx:SetTexture("Interface\\Icons\\ClassIcon_" .. Board.CLASS_ICONS[k - 30])
        tx:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        tx:SetTexture(DOT)
        tx:SetTexCoord(0, 1, 0, 1)
    end
end

-- ---------------------------------------------------------------------
-- Rendering ops
-- ---------------------------------------------------------------------
-- On-screen sizes of the "sized" items, shared by drawing and hit-testing.
local function stampPx(op) return math.max(12, math.min(64, (16 + (op.w or 3) * 3) * math.sqrt(view.zoom))) end
local function soakPx(op) return math.max(8, (24 + (op.w or 3) * 10) * view.zoom * bw / 700) end
local function textPx(op) return math.max(8, math.min(40, (10 + (op.w or 3) * 2) * math.sqrt(view.zoom))) end
-- an item's first two points on screen, and the distance between them
local function ends(pts)
    local x1, y1 = toPx(pts[1], pts[2])
    local x2, y2 = toPx(pts[3] or pts[1], pts[4] or pts[2])
    return x1, y1, x2, y2, math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end
-- the point at angle ang on a circle
local function rim(x, y, rad, ang) return x + math.cos(ang) * rad, y + math.sin(ang) * rad end

function Board:RenderOp(op)
    if not self.frame then return end
    self:ReleaseOp(op)
    local plan = Model.plan
    if not plan or plan.pages[plan.page].byId[op.id] ~= op then return end
    local r = { l = {}, t = {}, f = {} }
    op._r = r
    local col = self.COLORS[op.c] or self.COLORS[8]
    local cr, cg, cb = col[1], col[2], col[3]
    local a = op.live and 0.75 or 0.95
    local thick = math.max(1, math.min(48, (op.w or 3) * 1.4 * view.zoom))
    local pts = op.pts

    local function seg(x1, y1, x2, y2)
        local ln = getLine()
        ln:SetColorTexture(cr, cg, cb, a)
        ln:SetThickness(thick)
        ln:SetStartPoint("TOPLEFT", layer, x1, -y1)
        ln:SetEndPoint("TOPLEFT", layer, x2, -y2)
        r.l[#r.l + 1] = ln
    end
    local function dot(x, y, size, alpha, drawLayer)
        local t = getTex(drawLayer or "ARTWORK")
        t:SetTexture(DOT)
        t:SetVertexColor(cr, cg, cb, alpha or a)
        t:SetSize(size, size)
        t:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
        r.t[#r.t + 1] = t
    end

    -- n segments along an arc (angles from -> to)
    local function arc(x, y, rad, from, to, n)
        local lx, ly = rim(x, y, rad, from)
        for i = 1, n do
            local nx, ny = rim(x, y, rad, from + (to - from) * i / n)
            seg(lx, ly, nx, ny)
            lx, ly = nx, ny
        end
    end
    local function circle(x, y, rad) arc(x, y, rad, 0, 2 * math.pi, math.max(16, math.min(72, math.floor(rad / 3)))) end

    local t = op.t
    if t == "P" then
        local n = #pts / 2
        local px, py = toPx(pts[1], pts[2])
        if n == 1 then dot(px, py, thick * 1.3) end
        for i = 2, n do
            local qx, qy = toPx(pts[2 * i - 1], pts[2 * i])
            seg(px, py, qx, qy)
            if thick >= 4 then dot(qx, qy, thick) end
            px, py = qx, qy
        end
    elseif t == "L" or t == "A" then
        local x1, y1, x2, y2 = ends(pts)
        seg(x1, y1, x2, y2)
        if thick >= 4 then dot(x1, y1, thick) end
        if t == "A" then
            local ang = math.atan2(y2 - y1, x2 - x1)
            local hl = math.max(10, thick * 3.5)
            seg(x2, y2, x2 - math.cos(ang + 0.5) * hl, y2 - math.sin(ang + 0.5) * hl)
            seg(x2, y2, x2 - math.cos(ang - 0.5) * hl, y2 - math.sin(ang - 0.5) * hl)
        end
        if thick >= 4 then dot(x2, y2, thick) end
    elseif t == "C" then
        local x1, y1, _, _, rad = ends(pts)
        circle(x1, y1, rad)
    elseif t == "W" or t == "D" then
        local x1, y1, x2, y2, rad = ends(pts)
        if rad >= 2 then
            -- Translucent fill from a pre-made texture, outline from lines.
            local fill = getTex("BORDER")
            fill:SetSize(rad * 2 * FILL_SCALE, rad * 2 * FILL_SCALE)
            fill:SetPoint("CENTER", layer, "TOPLEFT", x1, -y1)
            r.t[#r.t + 1] = fill
            if t == "W" then
                local spread = snap(op.k, PIE_ANGLES)
                local dir = math.atan2(y2 - y1, x2 - x1)     -- screen angle (y points down)
                fill:SetTexture(SHAPES .. "wedge" .. spread)
                fill:SetRotation(-dir)                        -- UI rotation is counter-clockwise
                local half = math.rad(spread) / 2
                seg(x1, y1, rim(x1, y1, rad, dir - half))
                seg(x1, y1, rim(x1, y1, rad, dir + half))
                arc(x1, y1, rad, dir - half, dir + half, math.max(6, math.min(72, math.floor(rad * half * 2 / 6))))
            else
                local hole = snap(op.k, DONUT_HOLES)
                fill:SetTexture(SHAPES .. "ring" .. hole)
                circle(x1, y1, rad)
                circle(x1, y1, rad * hole / 100)
            end
            fill:SetVertexColor(cr, cg, cb, op.live and 0.18 or 0.28)
        end
    elseif t == "T" then
        local x, y = toPx(pts[1], pts[2])
        local fs = getFS()
        local size = textPx(op)
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        fs:SetTextColor(cr, cg, cb)
        fs:SetText(op.text or "")
        fs:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
        r.f[#r.f + 1] = fs
    elseif t == "M" then
        local x, y = toPx(pts[1], pts[2])
        local k = op.k or 1
        local size
        if k == 20 then
            size = soakPx(op)
            dot(x, y, size, 0.32, "BORDER")
        else
            size = stampPx(op)
            local tx = getTex("OVERLAY")
            tx:SetSize(size, size)
            tx:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
            Board.StampTexture(tx, k)
            if k == 30 then tx:SetVertexColor(cr, cg, cb, 1) end   -- generic colored marker
            r.t[#r.t + 1] = tx
        end
        if op.text and op.text ~= "" then
            local fs = getFS()
            fs:SetFont(STANDARD_TEXT_FONT, math.max(9, math.min(18, 10 * math.sqrt(view.zoom))), "OUTLINE")
            fs:SetTextColor(1, 1, 1)
            fs:SetText(op.text)
            fs:SetPoint("TOP", layer, "TOPLEFT", x, -y - size / 2)
            r.f[#r.f + 1] = fs
        end
    end
end

-- ---------------------------------------------------------------------
-- Laser pointers (drawn above everything, on the overlay)
-- ---------------------------------------------------------------------
local laserTex, laserFS = {}, {}
function Board:RenderLasers()
    if not overlay then return end
    for _, t in ipairs(laserTex) do t:Hide() end
    for _, f in ipairs(laserFS) do f:Hide() end
    local nt, nf = 0, 0
    local function tex(x, y, size, r, g, b, a)
        nt = nt + 1
        local t = laserTex[nt]
        if not t then
            t = overlay:CreateTexture(nil, "OVERLAY")
            t:SetTexture(DOT)
            laserTex[nt] = t
        end
        t:ClearAllPoints()
        t:SetSize(size, size)
        t:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
        t:SetVertexColor(r, g, b, a)
        t:Show()
    end
    for name, p in pairs(ns.Laser.pointers) do
        local alpha = p.alpha or 1
        if alpha > 0.02 then
            local class = ns.ClassOf(name)
            local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            local r, g, b = cc and cc.r or 1, cc and cc.g or 0.25, cc and cc.b or 0.25
            local tr = p.trail
            local n = #tr / 2
            for i = 1, n do
                local x, y = toPx(tr[2 * i - 1], tr[2 * i])
                local f = i / (n + 1)
                tex(x, y, 3 + f * 7, r, g, b, f * 0.5 * alpha)
            end
            local x, y = toPx(p.dx, p.dy)
            tex(x, y, 30, r, g, b, 0.30 * alpha)
            tex(x, y, 13, 1, 1, 1, alpha)
            tex(x, y, 9, r, g, b, alpha)
            if name ~= ns.me then
                nf = nf + 1
                local fs = laserFS[nf]
                if not fs then
                    fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    laserFS[nf] = fs
                end
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", overlay, "TOPLEFT", x + 12, -y + 10)
                fs:SetText(ns.Short(name))
                fs:SetTextColor(r, g, b, alpha)
                fs:Show()
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Background: custom room image > Blizzard map art > blank grid
-- ---------------------------------------------------------------------
function Board:_layout()
    cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not cw or cw < 10 then cw, ch = 700, 540 end
    local ctx = Model.plan and Model.plan.ctx
    local bg = { kind = "none", aspect = 1.4 }
    local sl = Model:Page()
    local room = ctx and ns.Rooms:Get(ctx, sl and sl.bg)
    if room then
        bg = { kind = "img", aspect = room.width / room.height, room = room }
    elseif ctx and ctx.map then
        local ok, layers = pcall(C_Map.GetMapArtLayers, ctx.map)
        local L1 = ok and layers and layers[1]
        if L1 and L1.layerWidth and L1.layerWidth > 0 then
            local ok2, tex = pcall(C_Map.GetMapArtLayerTextures, ctx.map, 1)
            if ok2 and tex and #tex > 0 then
                bg = { kind = "map", aspect = L1.layerWidth / L1.layerHeight, layer = L1, tex = tex }
            end
        end
    end
    self.bg = bg
    if cw / ch > bg.aspect then
        bh = ch; bw = ch * bg.aspect
    else
        bw = cw; bh = cw / bg.aspect
    end
end

function Board:RenderBG()
    for _, t in ipairs(bgTex) do t:Hide() end
    for _, l in ipairs(bgLines) do l:Hide() end
    local n, nl = 0, 0
    local function tex()
        n = n + 1
        local t = bgTex[n]
        if not t then
            t = layer:CreateTexture(nil, "BACKGROUND")
            bgTex[n] = t
        end
        t:ClearAllPoints()
        t:SetDrawLayer("BACKGROUND", 0)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetTexCoord(0, 1, 0, 1)
        t:Show()
        return t
    end
    local function rect(t, x0, y0, x1, y1)
        local px0, py0 = toPx(x0, y0)
        local px1, py1 = toPx(x1, y1)
        t:SetPoint("TOPLEFT", layer, "TOPLEFT", px0, -py0)
        t:SetSize(math.max(1, px1 - px0), math.max(1, py1 - py0))
    end

    local bg = self.bg
    if bg.kind == "map" then
        local L1 = bg.layer
        local cols = math.ceil(L1.layerWidth / L1.tileWidth)
        for i, fid in ipairs(bg.tex) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local x0, y0 = col * L1.tileWidth, row * L1.tileHeight
            local x1 = math.min(L1.layerWidth, x0 + L1.tileWidth)
            local y1 = math.min(L1.layerHeight, y0 + L1.tileHeight)
            if x1 > x0 and y1 > y0 then
                local t = tex()
                t:SetTexture(fid)
                t:SetTexCoord(0, (x1 - x0) / L1.tileWidth, 0, (y1 - y0) / L1.tileHeight)
                rect(t, x0 / L1.layerWidth * U, y0 / L1.layerHeight * U,
                    x1 / L1.layerWidth * U, y1 / L1.layerHeight * U)
            end
        end
    elseif bg.kind == "img" then
        local room = bg.room
        local t = tex()
        t:SetTexture(room.file)
        t:SetTexCoord(0, room.width / room.texWidth, 0, room.height / room.texHeight)
        rect(t, 0, 0, U, U)
    else
        local t = tex()
        t:SetColorTexture(0.075, 0.085, 0.11, 1)
        rect(t, 0, 0, U, U)
        local logo = tex()
        logo:SetTexture(ns.MEDIA .. "TitanUpLogo")
        logo:SetDrawLayer("BACKGROUND", 2)     -- above the fill, under the grid lines' layer order
        logo:SetVertexColor(1, 1, 1, 0.06)
        local side = U * 0.62
        local aspect = bw / bh                 -- keep the logo square on screen
        rect(logo, U / 2 - side / 2 / aspect, U / 2 - side / 2, U / 2 + side / 2 / aspect, U / 2 + side / 2)
        for i = 1, 7 do
            for _, vertical in ipairs({ true, false }) do
                nl = nl + 1
                local l = bgLines[nl]
                if not l then
                    l = layer:CreateLine(nil, "BACKGROUND", nil, 1)
                    bgLines[nl] = l
                end
                l:SetColorTexture(0.15, 0.17, 0.22, 1)
                l:SetThickness(1)
                local v = i / 8 * U
                local x1, y1, x2, y2
                if vertical then
                    x1, y1 = toPx(v, 0); x2, y2 = toPx(v, U)
                else
                    x1, y1 = toPx(0, v); x2, y2 = toPx(U, v)
                end
                l:SetStartPoint("TOPLEFT", layer, x1, -y1)
                l:SetEndPoint("TOPLEFT", layer, x2, -y2)
                l:Show()
            end
        end
    end

    local ctx = Model.plan and Model.plan.ctx
    local pin = self.bossPin
    if ctx and ctx.bx and bg.kind == "map" then
        local x, y = toPx(ctx.bx * U, ctx.by * U)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
        pin:Show()
    else
        pin:Hide()
    end
end

function Board:RenderAll()
    if not self.frame then return end
    self:_layout()
    clampView()
    self:RenderBG()
    local plan = Model.plan
    if plan then
        Model:ReleaseAll()
        for _, op in ipairs(plan.pages[plan.page].ops) do self:RenderOp(op) end
    end
    self:RenderLasers()
    self:UpdateHeader()
    self:RefreshSlides()
    self:RefreshPlanUI()
    self:RefreshRoomUI()
    self:UpdateStatus()
end

function Board:ResetView()
    if not self.frame then return end
    self:_layout()
    view.zoom, view.cx, view.cy = 1, U / 2, U / 2
    clampView()
end

-- Opening an encounter or plan: show the whole room, and make that the
-- first slide's framing so viewers see the same thing.
function Board:_openZoomedOut()
    self:ResetView()
    local sl = Model:Page()
    if sl and ns.IsOwner() then sl.view = { z = view.zoom, cx = view.cx, cy = view.cy } end
end

-- Each slide remembers its camera. Without one: keep the current view.
function Board:ApplySlideView()
    if not self.frame then return end
    local sl = Model:Page()
    local v = sl and sl.view
    if v then
        self:_layout()
        view.zoom = math.max(1, math.min(8, v.z))
        view.cx, view.cy = v.cx, v.cy
        clampView()
    end
end

-- You moved the camera: remember it on this slide and show it to viewers.
function Board:_viewChanged()
    if not Model.plan or not ns.CanDraw() or self.mini then return end   -- mini view: your own camera only
    local sl = Model:Page()
    sl.view = { z = view.zoom, cx = view.cx, cy = view.cy }
    Model:Touch()
    ns.Sync:SendView()
end

-- ---------------------------------------------------------------------
-- Context (which encounter + slide)
-- ---------------------------------------------------------------------
function Board:SelectContext(ctx, page, remote)
    if Model.plan then
        if ns.IsOwner() then Model:Save() end
        Model:ReleaseAll()
    end
    Model:Load(ctx)
    Model.plan.page = math.max(1, math.min(page or 1, Model:SlideCount()))
    wipe(undo)
    if ctx.inst then self.expanded = ctx.inst end
    self:_openZoomedOut()
    self:RenderAll()
    self:RefreshList()
    if not remote then
        ns.Sync:SendAll()
    end
end

function Board:ApplyRemoteContext(inst, enc, map, page, fromSnapshot)
    inst = (inst and inst ~= 0) and inst or nil
    enc = (enc and enc ~= 0) and enc or nil
    map = (map and map ~= 0) and map or nil
    local ctx = ns.Content:MakeContext(inst, enc, map)
    if Model.plan and Model.plan.ctx.key == ctx.key then
        if fromSnapshot or Model.plan.page == page then return end
        if page > Model:SlideCount() then
            -- A slide we don't have yet: the snapshot is on its way, or ask.
            if GetTime() - (ns.Sync._lastRequest or 0) > 5 then ns.Sync:RequestSnapshot() end
            return
        end
        Model.plan.page = page
        self:ApplySlideView()
        self:RenderAll()
    else
        self:SelectContext(ctx, 1, true)
    end
end

function Board:SetPage(p)
    if not Model.plan or Model.plan.page == p or not Model:Page(p) then return end
    if IsInGroup() and not ns.CanDraw() then
        ns.Print("You're following the leader - they choose the slide.")
        return
    end
    Model.plan.page = p
    ns.Laser:Clear()
    local sl = Model:Page()
    if sl.view then
        self:ApplySlideView()
    else
        sl.view = { z = view.zoom, cx = view.cx, cy = view.cy }
    end
    self:RenderAll()
    ns.Sync:SendContext()
    ns.Sync:SendView()
    ns.Sync:AnnounceSum()
end

function Board:EnsurePlan()
    if Model.plan then return end
    self:SelectContext(ns.Content:CurrentContext() or ns.Content:MakeContext(), 1, true)
end

-- ---------------------------------------------------------------------
-- Drawing input
-- ---------------------------------------------------------------------
local function newOp(t)
    local s = settings()
    return { t = t, id = ns.me .. ":" .. ns.NextId(), author = ns.me, c = s.color, w = s.width, k = 0 }
end

local function pushUndo(entry)
    entry.key = Model.plan.ctx.key
    entry.page = Model.plan.page
    undo[#undo + 1] = entry
    if #undo > 50 then table.remove(undo, 1) end
end

local function distSeg(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = ((px - ax) * dx + (py - ay) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local qx, qy = ax + t * dx, ay + t * dy
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

function Board:HitTest(px, py, maxd)
    local pg = Model:Page()
    if not pg then return nil end
    local best, bestD = nil, maxd or 10
    for i = #pg.ops, 1, -1 do
        local op = pg.ops[i]
        if not op.live then
            local pts, d = op.pts, math.huge
            if op.t == "P" or op.t == "L" or op.t == "A" then
                local ax, ay = toPx(pts[1], pts[2])
                if #pts == 2 then d = math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2) end
                for j = 2, #pts / 2 do
                    local bx2, by2 = toPx(pts[2 * j - 1], pts[2 * j])
                    d = math.min(d, distSeg(px, py, ax, ay, bx2, by2))
                    ax, ay = bx2, by2
                end
            elseif op.t == "C" then
                local cx, cy, _, _, rad = ends(pts)
                d = math.abs(math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2) - rad)
            elseif op.t == "W" or op.t == "D" then
                -- Clicking anywhere inside the filled area counts as a hit.
                local cx, cy, ex, ey, rad = ends(pts)
                local dd = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
                if op.t == "D" then
                    local inner = rad * snap(op.k, DONUT_HOLES) / 100
                    if dd >= inner and dd <= rad then d = 0
                    else d = math.min(math.abs(dd - rad), math.abs(dd - inner)) end
                else
                    local half = math.rad(snap(op.k, PIE_ANGLES)) / 2
                    local dir = math.atan2(ey - cy, ex - cx)
                    local diff = math.abs(((math.atan2(py - cy, px - cx) - dir + math.pi) % (2 * math.pi)) - math.pi)
                    if diff <= half then
                        d = (dd <= rad) and 0 or (dd - rad)
                    else
                        local ax, ay = rim(cx, cy, rad, dir - half)
                        local bx2, by2 = rim(cx, cy, rad, dir + half)
                        d = math.min(distSeg(px, py, cx, cy, ax, ay), distSeg(px, py, cx, cy, bx2, by2))
                    end
                end
            elseif op.t == "T" then
                -- text: anywhere inside its box
                local x, y = toPx(pts[1], pts[2])
                local size = textPx(op)
                local fs = op._r and op._r.f[1]
                local halfW = (fs and fs.GetStringWidth and fs:GetStringWidth() or 0) / 2
                if halfW <= 0 then halfW = #(op.text or "") * size * 0.28 end
                d = math.max(0, math.abs(px - x) - halfW, math.abs(py - y) - size / 2)
            else
                -- stamps and soak zones: anywhere inside what's drawn
                local x, y = toPx(pts[1], pts[2])
                local radius = ((op.k == 20) and soakPx(op) or stampPx(op)) / 2
                d = math.max(0, math.sqrt((px - x) ^ 2 + (py - y) ^ 2) - radius)
            end
            if d <= bestD then best, bestD = op, d end
        end
    end
    return best
end

-- Ctrl + drag moves an item with any tool selected.

function Board:_startDrag(px, py, bx, by)
    local op = self:HitTest(px, py, 12)
    if op then
        self._drag = { op = op, bx = bx, by = by, before = Model.Serialize(op), lastSend = GetTime() }
    end
    return op
end

function Board:_down(btn)
    if not Model.plan then return end
    local px, py = cursor()
    if btn == "RightButton" or btn == "MiddleButton" then
        self._pan = { px = px, py = py, cx = view.cx, cy = view.cy, moved = false, btn = btn }
        return
    end
    if self.mini then return end   -- mini view: pan and zoom only
    if btn ~= "LeftButton" then return end
    local bx, by = fromPx(px, py)
    if IsControlKeyDown() and ns.CanDraw() then
        local op = self:_startDrag(px, py, bx, by)
        ns.Debug("Ctrl+click:", op and ("grabbed " .. op.t) or "nothing under the cursor")
        return
    end
    if tool.mode == "R" or IsAltKeyDown() or not ns.CanDraw() then
        self._laser = { px = px, py = py }
        ns.Laser:Move(math.max(0, math.min(U, bx)), math.max(0, math.min(U, by)))
        return
    end
    local mode = tool.mode
    if mode == "P" or mode == "L" or mode == "A" or mode == "C" or mode == "W" or mode == "D" then
        local op = newOp(mode)
        op.pts = (mode == "P") and { bx, by } or { bx, by, bx, by }
        if mode == "W" then op.k = settings().pieAngle end
        if mode == "D" then op.k = settings().donutInner end
        op.live = true
        Model:Apply(op)
        self._drawing = op
        self._gesture = { op.id }
        self._lastPx, self._lastPy = px, py
        self._lastLive = 0
        ns.Sync:SendLive(op)
    elseif mode == "T" then
        UI.Prompt({
            title = "Text label", help = "Up to 60 characters.", accept = "Place",
            onAccept = function(text)
                if not text or text == "" or not Model.plan then return end
                local op = newOp("T")
                op.pts, op.text = { bx, by }, text
                Model:Apply(op)
                ns.Sync:SendOp(op)
                pushUndo({ kind = "add", ids = { op.id } })
            end,
        })
    elseif mode == "M" then
        local function place(label)
            if not Model.plan then return end
            local op = newOp("M")
            op.k, op.pts = tool.stamp, { bx, by }
            if label and label ~= "" then op.text = label end
            Model:Apply(op)
            ns.Sync:SendOp(op)
            pushUndo({ kind = "add", ids = { op.id } })
        end
        if IsShiftKeyDown() then
            UI.Prompt({ title = "Stamp label", help = "A player name or short note shown under the stamp.", accept = "Place", onAccept = place })
        else
            place()
        end
    elseif mode == "V" then
        self:_startDrag(px, py, bx, by)
    elseif mode == "E" then
        self._erasing = { sers = {} }
        self:_eraseAt(px, py)
    end
end

function Board:_eraseAt(px, py)
    local op = self:HitTest(px, py, 10)
    if op then
        self._erasing.sers[#self._erasing.sers + 1] = Model.Serialize(op)
        Model:Remove(op.id)
        ns.Sync:SendDelete(op.id)
    end
end

function Board:_finishStroke(op)
    local s = 3 / (bw * view.zoom) * U    -- ~3 px tolerance
    if op.t == "P" then
        op.pts = Model.Simplify(op.pts, s)
    else
        local x1, y1 = toPx(op.pts[1], op.pts[2])
        local x2, y2 = toPx(op.pts[3], op.pts[4])
        if math.abs(x2 - x1) + math.abs(y2 - y1) < 4 then
            Model:Remove(op.id)
            ns.Sync:SendDelete(op.id)
            return false
        end
    end
    op.live = nil
    op._sent = nil
    Model:Apply(op)
    ns.Sync:SendOp(op)
    return true
end

function Board:_update()
    if next(ns.Laser.pointers) then
        ns.Laser:Animate()
        self:RenderLasers()
    end
    if not Model.plan then return end
    local laser = self._laser
    if laser then
        local px, py = cursor()
        if math.abs(px - laser.px) + math.abs(py - laser.py) >= 3 then
            laser.px, laser.py = px, py
            local bx, by = fromPx(px, py)
            ns.Laser:Move(math.max(0, math.min(U, bx)), math.max(0, math.min(U, by)))
        end
        return
    end
    local pan = self._pan
    if pan then
        local px, py = cursor()
        if not pan.moved and math.abs(px - pan.px) + math.abs(py - pan.py) > 4 then pan.moved = true end
        if pan.moved then
            view.cx = pan.cx - (px - pan.px) / (bw * view.zoom) * U
            view.cy = pan.cy - (py - pan.py) / (bh * view.zoom) * U
            self:RenderAll()
        end
        return
    end
    local op = self._drawing
    if op then
        local px, py = cursor()
        local bx, by = fromPx(px, py)
        bx = math.max(0, math.min(U, bx))
        by = math.max(0, math.min(U, by))
        if op.t == "P" then
            if math.abs(px - self._lastPx) + math.abs(py - self._lastPy) < 3 then return end
            self._lastPx, self._lastPy = px, py
            op.pts[#op.pts + 1] = bx
            op.pts[#op.pts + 1] = by
            -- Very long strokes are split so no single op gets huge.
            if #op.pts >= 600 then
                self:_finishStroke(op)
                local nxt = newOp("P")
                nxt.pts = { bx, by }
                nxt.live = true
                Model:Apply(nxt)
                self._gesture[#self._gesture + 1] = nxt.id
                self._drawing = nxt
                op = nxt
            end
        else
            op.pts[3], op.pts[4] = bx, by
        end
        self:RenderOp(op)
        if GetTime() - self._lastLive > 0.3 then
            self._lastLive = GetTime()
            ns.Sync:SendLive(op)
        end
        return
    end
    local drag = self._drag
    if drag then
        local bx, by = fromPx(cursor())
        local dx, dy = bx - drag.bx, by - drag.by
        if dx ~= 0 or dy ~= 0 then
            local pts = drag.op.pts
            for i = 1, #pts, 2 do
                pts[i] = math.max(0, math.min(U, pts[i] + dx))
                pts[i + 1] = math.max(0, math.min(U, pts[i + 1] + dy))
            end
            drag.bx, drag.by = bx, by
            self:RenderOp(drag.op)
            if GetTime() - drag.lastSend > 0.4 then
                drag.lastSend = GetTime()
                ns.Sync:SendOp(drag.op)
            end
        end
        return
    end
    if self._erasing then self:_eraseAt(cursor()) end
end

function Board:_up(btn)
    local pan = self._pan
    if pan and pan.btn == btn then
        self._pan = nil
        if pan.moved then self:_viewChanged() end
        if not pan.moved and btn == "RightButton" and Model.plan and ns.CanDraw() and not self.mini then
            local op = self:HitTest(pan.px, pan.py, 10)
            if op then
                pushUndo({ kind = "restore", sers = { Model.Serialize(op) } })
                Model:Remove(op.id)
                ns.Sync:SendDelete(op.id)
            end
        end
        return
    end
    if btn ~= "LeftButton" then return end
    if self._laser then
        self._laser = nil
        ns.Laser:Stop()
        return
    end
    if self._drawing then
        local op = self._drawing
        self._drawing = nil
        self:_finishStroke(op)
        local ids = {}
        for _, id in ipairs(self._gesture or {}) do
            if Model:Page().byId[id] then ids[#ids + 1] = id end
        end
        if #ids > 0 then pushUndo({ kind = "add", ids = ids }) end
        self._gesture = nil
    elseif self._drag then
        local drag = self._drag
        self._drag = nil
        local pts = drag.op.pts
        for i = 1, #pts do pts[i] = math.floor(pts[i] + 0.5) end
        if Model.Serialize(drag.op) ~= drag.before then
            Model:Apply(drag.op)
            ns.Sync:SendOp(drag.op)
            pushUndo({ kind = "restore", sers = { drag.before } })
        end
    elseif self._erasing then
        local sers = self._erasing.sers
        self._erasing = nil
        if #sers > 0 then pushUndo({ kind = "restore", sers = sers }) end
    end
end

function Board:_wheel(delta)
    if IsShiftKeyDown() and (tool.mode == "W" or tool.mode == "D") then
        self:CycleShapeOption(delta)
        return
    end
    if IsControlKeyDown() then
        local op = (not self.mini) and Model.plan and ns.CanDraw() and self:HitTest(cursor())
        if op then
            self:ResizeOp(op, delta)
        else
            self:SetWidth(settings().width + delta)
        end
        return
    end
    local px, py = cursor()
    local bx, by = fromPx(px, py)
    view.zoom = math.max(1, math.min(8, view.zoom * (delta > 0 and 1.2 or 1 / 1.2)))
    local ax, ay = fromPx(px, py)
    view.cx = view.cx + (bx - ax)
    view.cy = view.cy + (by - ay)
    self:RenderAll()
    self:_viewChanged()
end

-- Grow/shrink one item (Ctrl + mouse wheel while hovering it).
-- Stamps, text and soak zones change their size; shapes and strokes scale
-- around their center (a pie around its tip). A burst of wheel clicks on
-- the same item is one undo step.
local MAX_ITEM_W = 16
function Board:ResizeOp(op, delta)
    local now = GetTime()
    local r = self._resize
    if not (r and r.id == op.id and now - r.t < 1.5) then
        pushUndo({ kind = "restore", sers = { Model.Serialize(op) } })
        r = { id = op.id }
        self._resize = r
    end
    r.t = now
    if op.t == "T" or op.t == "M" then
        op.w = math.max(1, math.min(MAX_ITEM_W, (op.w or 3) + (delta > 0 and 1 or -1)))
    else
        local f = delta > 0 and 1.12 or 1 / 1.12
        local pts = op.pts
        local cx, cy
        if op.t == "C" or op.t == "W" or op.t == "D" then
            cx, cy = pts[1], pts[2]
        else
            local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
            for i = 1, #pts, 2 do
                x0, x1 = math.min(x0, pts[i]), math.max(x1, pts[i])
                y0, y1 = math.min(y0, pts[i + 1]), math.max(y1, pts[i + 1])
            end
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        end
        -- don't shrink below a few pixels or push points off the board
        local extent = 0
        for i = 1, #pts, 2 do extent = math.max(extent, math.abs(pts[i] - cx), math.abs(pts[i + 1] - cy)) end
        if f < 1 and extent * f * bw * view.zoom / U < 4 then return end
        local scaled = {}
        for i = 1, #pts, 2 do
            local x = cx + (pts[i] - cx) * f
            local y = cy + (pts[i + 1] - cy) * f
            if x < 0 or x > U or y < 0 or y > U then return end
            scaled[i], scaled[i + 1] = math.floor(x + 0.5), math.floor(y + 0.5)
        end
        op.pts = scaled
    end
    Model:Apply(op)
    ns.Sync:SendOp(op)
end

function Board:Undo()
    if not ns.CanDraw() then return end
    local e = table.remove(undo)
    if not e then return end
    local plan = Model.plan
    if not plan or e.key ~= plan.ctx.key then
        wipe(undo)
        return
    end
    if e.kind == "add" then
        for _, id in ipairs(e.ids) do
            Model:Remove(id, e.page)
            ns.Sync:SendDelete(id, e.page)
        end
    else
        for _, s in ipairs(e.sers) do
            local op = Model.Deserialize(s)
            if op then
                op = Model:Apply(op, e.page)
                ns.Sync:SendOp(op, e.page)
            end
        end
    end
end

function Board:ClearPage()
    if not Model.plan or not ns.CanDraw() then return end
    local b = self.clearBtn
    if not b.confirm then
        b.confirm = true
        b.label:SetText("Sure?")
        C_Timer.After(3, function()
            b.confirm = nil
            b.label:SetText("Clear")
        end)
        return
    end
    b.confirm = nil
    b.label:SetText("Clear")
    Model:Clear()
    ns.Sync:SendClear()
    wipe(undo)
end

-- ---------------------------------------------------------------------
-- Tool state
-- ---------------------------------------------------------------------
function Board:SetTool(mode)
    tool.mode = mode
    for m, b in pairs(self.toolBtns) do UI.SetActive(b, m == mode) end
    for k, b in pairs(self.stampBtns) do UI.SetActive(b, mode == "M" and k == tool.stamp) end
    self:UpdateShapeOption()
    if self.toolName then
        local name = "Stamp"
        for _, def in ipairs(TOOLS) do if def[1] == mode then name = def[2] end end
        self.toolName:SetText(name)
    end
end

-- Pie angle / donut hole: one button that shows the active tool's option.
function Board:UpdateShapeOption()
    local b = self.shapeOpt
    if not b then return end
    local s = settings()
    if tool.mode == "W" then
        b.label:SetText(("Angle %d\194\176"):format(snap(s.pieAngle, PIE_ANGLES)))
        b:Show()
    elseif tool.mode == "D" then
        b.label:SetText(("Hole %d%%"):format(snap(s.donutInner, DONUT_HOLES)))
        b:Show()
    else
        b:Hide()
    end
end

function Board:CycleShapeOption(delta)
    local s = settings()
    local list, key
    if tool.mode == "W" then
        list, key = PIE_ANGLES, "pieAngle"
    elseif tool.mode == "D" then
        list, key = DONUT_HOLES, "donutInner"
    else
        return
    end
    local cur = snap(s[key], list)
    local idx = 1
    for i, v in ipairs(list) do if v == cur then idx = i end end
    idx = idx + (delta > 0 and 1 or -1)
    if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
    s[key] = list[idx]
    self:UpdateShapeOption()
    -- Adjust the shape you're dragging out right now, too.
    local op = self._drawing
    if op and op.t == tool.mode then
        op.k = s[key]
        self:RenderOp(op)
        ns.Sync:SendLive(op)
    end
end

function Board:SetStamp(k)
    tool.stamp = k
    self:SetTool("M")
end

function Board:SetColor(i)
    settings().color = i
    for j, b in ipairs(self.colorBtns) do UI.SetActive(b, j == i) end
    self:UpdateSizePreview()
end

function Board:SetWidth(w)
    settings().width = math.max(1, math.min(8, w))
    self:UpdateSizePreview()
end

function Board:UpdateSizePreview()
    local s = settings()
    local col = self.COLORS[s.color] or self.COLORS[8]
    local size = 3 + s.width * 2.4
    self.sizeDot:SetSize(size, size)
    self.sizeDot:SetVertexColor(col[1], col[2], col[3], 1)
    self.sizeText:SetText(s.width)
end

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
    local f = self.frame
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
    self.miniPrev:SetShown(ns.CanDraw())
    self.miniNext:SetShown(ns.CanDraw())

    C_Timer.After(0, function() if Board:IsShown() then Board:RenderAll() end end)
end

function Board:TogglePanel(side)
    local s = settings()
    if side == "left" then s.leftCollapsed = not s.leftCollapsed else s.rightCollapsed = not s.rightCollapsed end
    self:ApplyLayout()
end

function Board:SetMini(on)
    if not self.frame or self.mini == on then return end
    self.mini = on
    if on then self._drawing, self._drag, self._erasing, self._pan = nil, nil, nil, nil end
    self:ApplyLayout()
    ns.Presence:Announce("P")
    C_Timer.After(0, function() Board:ResetView(); Board:RenderAll() end)
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

-- ---------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------
function Board:IsShown() return self.frame and self.frame:IsShown() or false end
function Board:Show() self:EnsureFrame():Show() end
function Board:Hide() if self.frame then self.frame:Hide() end end
function Board:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

function Board:_onShow()
    if not self.statusTicker then
        self.statusTicker = C_Timer.NewTicker(0.5, function() Board:UpdateStatus() end)
    end
    self:EnsurePlan()
    self:RefreshList(true)
    self:RenderAll()
    ns.Presence:Announce("P")
    if IsInGroup() and not ns.IsOwner() then ns.Sync:RequestSnapshot() end
end

function Board:_onHide()
    if self.statusTicker then self.statusTicker:Cancel(); self.statusTicker = nil end
    self._drawing, self._drag, self._erasing, self._pan = nil, nil, nil, nil
    if self.frame and not InCombatLockdown() then self.frame:SetPropagateKeyboardInput(true) end
    if self.fullscreen then self:SetFullscreen(false) end
    if Model.plan and ns.IsOwner() then Model:Save() end
    ns.Presence:Announce("P")
end

-- ---------------------------------------------------------------------
-- Build the window
-- ---------------------------------------------------------------------
-- The window is built the first time it's opened (nothing at login), so
-- people who never open the board don't pay for it. Everything that can
-- run while it's closed (sync, presence) checks self.frame first.
function Board:EnsureFrame()
    if not self.frame then self:Create() end
    return self.frame
end

function Board:Init()
    ns.On("PLAYER_REGEN_DISABLED", function()
        -- last chance before combat lockdown: never leave keys captured
        if Board.frame then pcall(Board.frame.SetPropagateKeyboardInput, Board.frame, true) end
        if Board:IsShown() and settings().autoMini and not Board.mini and not Board.fullscreen then
            Board._autoMini = true
            Board:SetMini(true)
        end
    end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if Board._autoMini then
            Board._autoMini = nil
            Board:SetMini(false)
        end
    end)
    ns.On("ZONE_CHANGED_NEW_AREA", function()
        if Board:IsShown() then Board:RefreshList(true) end
    end)
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
    local f, header = ns.Nav:Window(self, "TitanBoardFrame", "board", "TITANBOARD", FW, FH, { point = { "CENTER" }, mark = false,
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
        if IsInGroup() and not ns.CanDraw() then ns.Print("You're following the leader's board.") return end
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
            ns.Sync:SendAll()
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

    local function header(text, yy) UI.Text(strip, "GameFontNormalSmall", C.muted, text, "TOP", 0, yy) end
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

    header("TOOLS", -10)
    self.toolBtns = {}
    local y = -28
    for i, def in ipairs(TOOLS) do
        local mode = def[1]
        local b = UI.IconButton(strip, 26, ICONS .. def[4], nil, function() Board:SetTool(mode) end)
        b:SetPoint("TOPLEFT", gridPos(i, y))
        tip(b, def[2], def[3])
        self.toolBtns[mode] = b
    end
    y = y - math.ceil(#TOOLS / 2) * 28 - 4
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
    header("STAMPS", y)
    y = stampButtons(STAMPS, y - 18) - 8
    header("ZONES", y)
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
    canvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
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
    canvas:SetScript("OnSizeChanged", function() if Board:IsShown() then Board:RenderAll() end end)
    self.canvas = canvas

    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints()
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(layer:GetFrameLevel() + 10)

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

ns.RegisterModule({
    key = "board", name = "TitanBoard", icon = ns.MEDIA .. "icon", group = "tools", order = 1,
    desc = "Live raid strategy board - draw on boss rooms with the raid.",
    view = Board,
})
