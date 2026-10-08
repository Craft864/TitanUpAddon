-- TitanBoard - RaidstratsImport.lua
-- Reads plan strings exported by the Raidstrats.gg website
-- ("!raidstrats-addon-..."), converts them into TitanBoard slides.
--
-- The string is base64 of either JSON or (first byte 0x01) raw-deflated
-- JSON. The plan has planName / boss / raid and a list of scenes; each
-- scene has items positioned in PERCENT (0-100) of a 16:9 canvas whose
-- background fills the whole canvas, plus optional animations.
--
-- Raidstrats scenes are animated; TitanBoard slides are still images, so
-- the conversion keeps where things start and draws movement as arrows:
--   icon (role / class / raid marker) -> stamp with the player's name
--   line / arrow                       -> line / arrow
--   circle (filled)                    -> soak zone (outline circle if huge)
--   donut / cone / triangle            -> donut / pie slice
--   rectangle                          -> closed outline
--   text                               -> text
--   path animation                     -> arrow along the route
--   frontal sweep                      -> pie covering the sweep (or a beam)
--   tether                             -> line between the two
--   pulse / fade / bounce ...          -> dropped (cosmetic)
local ADDON, ns = ...

local RS = {}
ns.RaidstratsImport = RS

local U = ns.U
local PREFIX = "!raidstrats-addon-"
local CW, CH = 1115, 627          -- their canvas aspect; only the ratio matters
local OUR_W, OUR_H = 700, 394     -- typical on-screen board size at zoom 1

function RS.IsRaidstrats(text)
    return type(text) == "string" and text:gsub("^%s+", ""):sub(1, #PREFIX) == PREFIX
end

-- ---------------------------------------------------------------------
-- Base64 and JSON: the game's own decoders (C_EncodingUtil, since 11.1)
-- ---------------------------------------------------------------------
local function decodeBase64(s)
    local E = C_EncodingUtil
    if not (E and E.DecodeBase64) then return nil end
    s = s:gsub("%-", "+"):gsub("_", "/")              -- URL-safe variant
    local ok, out = pcall(E.DecodeBase64, s)
    return ok and type(out) == "string" and out or nil
end

local function decodeJSON(s)
    local E = C_EncodingUtil
    if not (E and E.DeserializeJSON) then return nil, "this game version can't read JSON" end
    local ok, res = pcall(E.DeserializeJSON, s)
    if ok and type(res) == "table" then return res end
    return nil, res
end

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
local function num(v, default)
    v = tonumber(v)
    return v or default
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- percent of their canvas -> board units (both axes run 0..4095)
local function bx(p) return clamp(p / 100 * U, 0, U) end
local function by(p) return clamp(p / 100 * U, 0, U) end

local function parseColor(c)
    if type(c) ~= "string" then return nil end
    local s = c:lower():gsub("%s+", "")
    if s:sub(1, 1) == "#" then
        local h = s:sub(2)
        if #h == 3 then h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2) end
        if #h >= 6 then
            local r, g, b = tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
            if not (r and g and b) then return nil end
            return r / 255, g / 255, b / 255, #h >= 8 and (tonumber(h:sub(7, 8), 16) or 255) / 255 or 1
        end
    end
    local r, g, b, a = s:match("^rgba?%(([%d%.]+),([%d%.]+),([%d%.]+),?([%d%.]*)%)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r and g and b then return r / 255, g / 255, b / 255, tonumber(a) or 1 end
    return nil
end

-- nearest TitanBoard palette color (1-8)
local function paletteIndex(c, default)
    local r, g, b, a = parseColor(c)
    if not r or (a and a <= 0.01) then return default end
    local best, bestD = default, math.huge
    for i, col in ipairs(ns.Board.COLORS) do
        local d = (col[1] - r) ^ 2 + (col[2] - g) ^ 2 + (col[3] - b) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best
end

local function isFilled(item)
    local _, _, _, a = parseColor(item.fill)
    return a and a > 0.05
end

local RAID_ICONS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8 }
local ROLES = { tank = 1, healer = 2, heal = 2, rdps = 3, mdps = 3, dps = 3, damager = 3 }
local CLASS_K = {}
for i, c in ipairs(ns.Board.CLASS_ICONS) do CLASS_K[c:lower()] = 30 + i end   -- stamp kinds 31-43

local function stampKind(icon)
    local key = tostring(icon or ""):lower():gsub("^.*/", ""):gsub("%.%a+$", ""):gsub("[%s_%-]", "")
    if RAID_ICONS[key] then return 10 + RAID_ICONS[key] end
    if ROLES[key] then return ROLES[key] end
    if CLASS_K[key] then return CLASS_K[key] end
    return 30   -- generic colored marker
end

-- Item center/size in percent and in their pixels.
local function rect(item)
    local x, y = num(item.x, 0), num(item.y, 0)
    local w, h = num(item.w, 4), num(item.h, 4)
    return x, y, w, h, x + w / 2, y + h / 2
end

-- Their sizes are percent of their canvas; ours are 1-16 steps.
local function stampW(wPct)
    return clamp(math.floor(((wPct / 100 * OUR_W) - 16) / 3 + 0.5), 1, 16)
end
local function lineW(strokePct)
    return clamp(math.floor((OUR_H * (strokePct or 0.6) / 100) / 1.4 + 0.5), 1, 8)
end
local function textW(fontPct)
    return clamp(math.floor(((OUR_H * (fontPct or 4) / 100) - 10) / 2 + 0.5), 1, 15)
end

local function snapAngle(deg) return ns.Board.Snap(deg, ns.Board.PIE_ANGLES) end

-- ---------------------------------------------------------------------
-- Conversion
-- ---------------------------------------------------------------------
local function op(t, c, w, k, pts, text)
    return { t = t, c = c, w = w, k = k or 0, pts = pts, text = text }
end

local function convertItem(item, ops, notes)
    local kind = tostring(item.kind or ""):lower()
    local shape = tostring(item.shape or ""):lower()
    local label = (type(item.label) == "string" and item.label ~= "") and ns.Model.CleanText(item.label) or nil
    if item.isFrontalBeam == true or item.isFrontalBeam == 1 then return end   -- drawn from its animation

    if kind == "line" then
        local pts = { bx(num(item.x1, 0)), by(num(item.y1, 0)), bx(num(item.x2, 0)), by(num(item.y2, 0)) }
        ops[#ops + 1] = op(shape == "arrow" and "A" or "L", paletteIndex(item.stroke or item.fill, 3), lineW(num(item.strokeWidth)), 0, pts)
        return
    end

    local x, y, w, h, cx, cy = rect(item)
    if kind == "text" then
        if label then ops[#ops + 1] = op("T", paletteIndex(item.textColor or item.fill, 8), textW(num(item.fontSize)), 0, { bx(cx), by(cy) }, label) end
        return
    end

    if kind == "icon" then
        local k = stampKind(item.icon)
        local o = op("M", paletteIndex(item.fill, 5), stampW(w), k, { bx(cx), by(cy) }, label)
        ops[#ops + 1] = o
        return
    end

    if kind == "shape" then
        local color = paletteIndex(item.stroke, nil) or paletteIndex(item.fill, 1)
        local fillColor = paletteIndex(item.fill, color)
        local rx = w / 2                      -- radius in percent of width
        if shape == "circle" or shape == "ellipse" then
            -- soak zones max out at ~26% of the board width; bigger -> outline circle
            if isFilled(item) and w <= 26 then
                ops[#ops + 1] = op("M", fillColor, clamp(math.floor((w / 100 * 700 - 24) / 10 + 0.5), 1, 16), 20, { bx(cx), by(cy) }, label)
            else
                ops[#ops + 1] = op("C", color, lineW(num(item.strokeWidth)), 0, { bx(cx), by(cy), bx(cx + rx), by(cy) })
                if label then ops[#ops + 1] = op("T", 8, 3, 0, { bx(cx), by(cy) }, label) end
            end
        elseif shape == "donut" then
            -- snap to the hole sizes the board offers (30-80% in steps of 10)
            local hole = clamp(math.floor(num(item.innerRatio, 0.5) * 10 + 0.5) * 10, 30, 80)
            ops[#ops + 1] = op("D", fillColor, lineW(num(item.strokeWidth)), hole, { bx(cx), by(cy), bx(cx + rx), by(cy) })
        elseif shape == "triangle" or shape == "cone" then
            -- apex at the top, opening downward
            local wpx, hpx = w / 100 * CW, h / 100 * CH
            local spread = snapAngle(math.deg(2 * math.atan((wpx / 2) / math.max(1, hpx))))
            ops[#ops + 1] = op("W", fillColor, lineW(num(item.strokeWidth)), spread, { bx(cx), by(y), bx(cx), by(y + h) })
        elseif shape == "rect" or shape == "rectangle" or shape == "square" or shape == "polygon" then
            ops[#ops + 1] = op("P", color, lineW(num(item.strokeWidth)), 0,
                { bx(x), by(y), bx(x + w), by(y), bx(x + w), by(y + h), bx(x), by(y + h), bx(x), by(y) })
            if label then ops[#ops + 1] = op("T", 8, 3, 0, { bx(cx), by(cy) }, label) end
        else
            notes.skipped = (notes.skipped or 0) + 1
        end
        return
    end
    notes.skipped = (notes.skipped or 0) + 1
end

-- items[index + 1] when it's a real item (indexes in their file start at 0)
local function itemAt(items, index)
    local it = tonumber(index) and items[tonumber(index) + 1]
    return type(it) == "table" and it or nil
end

local function resolveItem(anim, items)
    local it = itemAt(items, anim.itemIndex)
    if it then return it end
    if anim.objectId ~= nil then
        for _, o in ipairs(items) do
            if type(o) == "table" and o.id ~= nil and tostring(o.id) == tostring(anim.objectId) then return o end
        end
    end
    return nil
end

local function itemCenter(item)
    local _, _, _, _, cx, cy = rect(item)
    return cx, cy
end

local function convertAnimation(anim, items, ops, notes)
    local item = resolveItem(anim, items)

    -- movement: arrow along the route (path points are the item's top-left)
    if type(anim.path) == "table" and #anim.path >= 2 then
        local w, h = 0, 0
        if item then w, h = num(item.w, 4), num(item.h, 4) end
        local pts = {}
        local flat = type(anim.path[1]) ~= "table"
        local n = flat and math.floor(#anim.path / 2) or #anim.path
        for i = 1, n do
            local px, py
            if flat then
                px, py = anim.path[2 * i - 1], anim.path[2 * i]
            elseif type(anim.path[i]) == "table" then
                px, py = anim.path[i][1], anim.path[i][2]
            end
            if px ~= nil then
                px, py = num(px, 0), num(py, 0)
                if px <= 1.5 and py <= 1.5 then px, py = px * 100, py * 100 end
                pts[#pts + 1] = bx(px + w / 2)
                pts[#pts + 1] = by(py + h / 2)
            end
        end
        local count = #pts / 2
        if count < 2 then return end              -- not a route
        if count >= 3 then
            local body = {}
            for i = 1, #pts - 2 do body[i] = pts[i] end
            ops[#ops + 1] = op("P", 3, 3, 0, body)
        end
        ops[#ops + 1] = op("A", 3, 3, 0, { pts[#pts - 3], pts[#pts - 2], pts[#pts - 1], pts[#pts] })
        notes.moves = (notes.moves or 0) + 1
        return
    end

    -- frontal: from the parent item (usually the boss) outward
    if anim.isFrontalSweepAnimation == true or anim.isFrontalSweepAnimation == 1 then
        local parent = itemAt(items, anim.parentItemIndex) or item
        local cx, cy = 50, 50
        if parent then cx, cy = itemCenter(parent) end
        local a0 = num(anim.startAngle, 0)
        local a1 = num(anim.endAngle, a0)
        local mid = math.rad((a0 + a1) / 2)            -- 0 = up, clockwise
        local reachPx = CH * num(anim.frontalH, 18) / 100
        local ex = cx + math.sin(mid) * reachPx / CW * 100
        local ey = cy - math.cos(mid) * reachPx / CH * 100
        local sweep = math.abs(a1 - a0)
        local beamDeg = math.deg(2 * math.atan((CW * num(anim.frontalW, 5) / 100 / 2) / math.max(1, reachPx)))
        if sweep + beamDeg >= 22 then
            ops[#ops + 1] = op("W", 1, 2, snapAngle(sweep + beamDeg), { bx(cx), by(cy), bx(ex), by(ey) })
        else
            ops[#ops + 1] = op("L", 1, 8, 0, { bx(cx), by(cy), bx(ex), by(ey) })
        end
        notes.frontals = (notes.frontals or 0) + 1
        return
    end

    -- tether: a line between follower and the item it's tied to
    if anim.isTetherAnimation == true or anim.isTetherAnimation == 1 then
        local main = itemAt(items, anim.parentItemIndex)
        if item and main then
            local x1, y1 = itemCenter(item)
            local x2, y2 = itemCenter(main)
            ops[#ops + 1] = op("L", 7, 2, 0, { bx(x1), by(y1), bx(x2), by(y2) })
            notes.tethers = (notes.tethers or 0) + 1
        end
        return
    end
    -- pulse / fade / bounce / rotate ...: cosmetic, nothing to draw
end

-- Their viewport (zoom, normalized pan) -> our slide camera.
local function convertView(scene)
    local vs = scene.viewportState or scene.view
    if type(vs) ~= "table" then return nil end
    local zoom = clamp(num(vs.zoom, 1), 1, 8)
    if zoom <= 1.001 then return nil end
    local panX, panY = num(vs.panX, 0), num(vs.panY, 0)
    local u = -panX / zoom + 0.5 / zoom
    local v = -panY / zoom + 0.5 / zoom
    return { z = zoom, cx = clamp(u, 0, 1) * U, cy = clamp(v, 0, 1) * U }
end

-- Find a boss by name in the encounter journal lists TitanBoard knows.
local function findEncounter(bossName)
    if type(bossName) ~= "string" or bossName == "" then return nil end
    local function norm(s) return tostring(s):lower():gsub("[^%w]", "") end
    local want = norm(bossName)
    local lists = { ns.Content:Raids(), ns.Content:WorldBosses(), ns.Content:Dungeons() }
    for _, list in ipairs(lists) do
        for _, inst in ipairs(list) do
            if inst.id then
                for _, e in ipairs(ns.Content:Encounters(inst.id)) do
                    if norm(e.name) == want then return inst.id, e.id end
                end
            end
        end
    end
    return nil
end

-- An op that would survive the board's own save format (a broken one,
-- e.g. a point missing, is dropped instead of breaking the board).
local function valid(o)
    local ok, ser = pcall(ns.Model.Serialize, o, "rs:1")
    return ok and ns.Model.Deserialize(ser) ~= nil
end

local function convert(plan)
    local notes = {}
    local data = { name = ns.Model.CleanName((type(plan.planName) == "string" and plan.planName ~= "") and plan.planName or "Raidstrats import"), slides = {}, notes = notes }
    data.boss = plan.boss
    data.inst, data.enc = findEncounter(plan.boss)

    for i, scene in ipairs(plan.scenes) do
        if i > ns.Model.MAX_SLIDES then
            notes.truncated = #plan.scenes - ns.Model.MAX_SLIDES
            break
        end
        local ops = {}
        local items = type(scene.items) == "table" and scene.items or {}
        for _, item in ipairs(items) do
            if type(item) == "table" then convertItem(item, ops, notes) end
        end
        for _, anim in ipairs(type(scene.animations) == "table" and scene.animations or {}) do
            if type(anim) == "table" then convertAnimation(anim, items, ops, notes) end
        end
        local good = {}
        for j, o in ipairs(ops) do
            o.id = "rs:" .. i .. ":" .. j
            if valid(o) then good[#good + 1] = o else notes.skipped = (notes.skipped or 0) + 1 end
        end
        local name = (type(scene.name) == "string" and scene.name ~= "") and scene.name or ("Scene " .. i)
        data.slides[#data.slides + 1] = { name = ns.Model.CleanName(name), view = convertView(scene), ops = good }
    end
    return data
end

-- Returns data in the same shape ImportExport uses: { inst, enc, map, name,
-- slides = { { name, view, ops } } }, plus .notes for a summary.
function RS:Decode(text)
    local body = text:gsub("^%s+", ""):gsub("%s+$", "")
    body = body:sub(#PREFIX + 1):gsub("%s+", "")
    local raw = decodeBase64(body)
    if not raw or raw == "" then return nil, "The Raidstrats string isn't valid base64." end
    local json = raw
    if raw:byte(1) == 1 then
        json = ns.Codec.Decompress(raw:sub(2))
        if not json then return nil, "Couldn't decompress the Raidstrats string - is it complete?" end
        if #json > ns.ImportExport.MAX_PAYLOAD then return nil, "That Raidstrats plan is too big to import." end
    end
    local plan, jerr = decodeJSON(json)
    if not plan then return nil, "Couldn't read the Raidstrats plan (" .. tostring(jerr) .. ")." end
    if type(plan.scenes) ~= "table" or #plan.scenes == 0 then return nil, "That Raidstrats plan has no scenes." end

    local ok, data = pcall(convert, plan)
    if not ok or not data then
        ns.Debug("Raidstrats conversion failed:", data)
        return nil, "That Raidstrats plan couldn't be read."
    end
    return data
end
