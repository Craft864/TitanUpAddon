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
-- All decoding here is TitanBoard's own code.
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
-- Base64
-- ---------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, 64 do B64DEC[B64:byte(i)] = i - 1 end
B64DEC[("-"):byte()] = 62    -- URL-safe variants
B64DEC[("_"):byte()] = 63

local function decodeBase64(s)
    local out, bits, nbits = {}, 0, 0
    for i = 1, #s do
        local v = B64DEC[s:byte(i)]
        if v then
            bits = bits * 64 + v
            nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                local byte = math.floor(bits / 2 ^ nbits)
                out[#out + 1] = string.char(byte)
                bits = bits - byte * 2 ^ nbits
            end
        elseif s:sub(i, i) ~= "=" then
            return nil
        end
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------
-- JSON (WoW's built-in parser when available, otherwise a small one)
-- ---------------------------------------------------------------------
local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local function parseJSON(str)
    local pos = 1
    local function err(msg) error(("JSON %s at %d"):format(msg, pos), 0) end
    local function ws() pos = str:find("[^ \t\r\n]", pos) or #str + 1 end
    local value
    local function parseString()
        pos = pos + 1
        local parts = {}
        while true do
            local c = str:sub(pos, pos)
            if c == "" then err("unterminated string") end
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local e = str:sub(pos + 1, pos + 1)
                local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if e == "u" then
                    local cp = tonumber(str:sub(pos + 2, pos + 5), 16) or 63
                    parts[#parts + 1] = utf8char(cp)
                    pos = pos + 6
                else
                    parts[#parts + 1] = map[e] or e
                    pos = pos + 2
                end
            else
                local j = str:find('["\\]', pos) or #str + 1
                parts[#parts + 1] = str:sub(pos, j - 1)
                pos = j
            end
        end
        return table.concat(parts)
    end
    function value()
        ws()
        local c = str:sub(pos, pos)
        if c == "{" then
            local obj = {}
            pos = pos + 1
            ws()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                ws()
                if str:sub(pos, pos) ~= '"' then err("expected key") end
                local k = parseString()
                ws()
                if str:sub(pos, pos) ~= ":" then err("expected ':'") end
                pos = pos + 1
                obj[k] = value()
                ws()
                local d = str:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj end
                if d ~= "," then err("expected ',' or '}'") end
            end
        elseif c == "[" then
            local arr = {}
            pos = pos + 1
            ws()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = value()
                ws()
                local d = str:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr end
                if d ~= "," then err("expected ',' or ']'") end
            end
        elseif c == '"' then
            return parseString()
        elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then err("unexpected character") end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local result = value()
    return result
end

local function decodeJSON(s)
    if C_EncodingUtil and C_EncodingUtil.DeserializeJSON then
        local ok, res = pcall(C_EncodingUtil.DeserializeJSON, s)
        if ok and type(res) == "table" then return res end
    end
    local ok, res = pcall(parseJSON, s)
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
            return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255,
                #h >= 8 and tonumber(h:sub(7, 8), 16) / 255 or 1
        end
    end
    local r, g, b, a = s:match("^rgba?%(([%d%.]+),([%d%.]+),([%d%.]+),?([%d%.]*)%)$")
    if r then return tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255, tonumber(a) or 1 end
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
local CLASSES = { "warrior", "paladin", "hunter", "rogue", "priest", "deathknight", "shaman",
    "mage", "warlock", "monk", "druid", "demonhunter", "evoker" }
local CLASS_K = {}
for i, c in ipairs(CLASSES) do CLASS_K[c] = 30 + i end   -- stamp kinds 31-43

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

local PIE_ANGLES = { 30, 45, 60, 90, 120, 180, 270 }
local function snapAngle(deg)
    local best = PIE_ANGLES[1]
    for _, a in ipairs(PIE_ANGLES) do
        if math.abs(a - deg) < math.abs(best - deg) then best = a end
    end
    return best
end

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

local function resolveItem(anim, items)
    local idx = tonumber(anim.itemIndex)
    if idx and idx >= 0 and items[idx + 1] then return items[idx + 1] end
    if anim.objectId ~= nil then
        for _, it in ipairs(items) do
            if it.id ~= nil and tostring(it.id) == tostring(anim.objectId) then return it end
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
    local color = item and paletteIndex(item.fill, 3) or 3

    -- movement: arrow along the route (path points are the item's top-left)
    if type(anim.path) == "table" and #anim.path >= 2 then
        local w, h = 0, 0
        if item then w, h = num(item.w, 4), num(item.h, 4) end
        local pts = {}
        local flat = type(anim.path[1]) ~= "table"
        local n = flat and math.floor(#anim.path / 2) or #anim.path
        for i = 1, n do
            local px, py
            if flat then px, py = anim.path[2 * i - 1], anim.path[2 * i] else px, py = anim.path[i][1], anim.path[i][2] end
            px, py = num(px, 0), num(py, 0)
            if px <= 1.5 and py <= 1.5 then px, py = px * 100, py * 100 end
            pts[#pts + 1] = bx(px + w / 2)
            pts[#pts + 1] = by(py + h / 2)
        end
        local count = #pts / 2
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
        local parent = (tonumber(anim.parentItemIndex) and items[tonumber(anim.parentItemIndex) + 1]) or item
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
        local main = tonumber(anim.parentItemIndex) and items[tonumber(anim.parentItemIndex) + 1]
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

-- Returns data in the same shape ImportExport uses: { inst, enc, map, name,
-- slides = { { name, view, ops } } }, plus .notes for a summary.
function RS:Decode(text)
    local body = text:gsub("^%s+", ""):gsub("%s+$", "")
    body = body:sub(#PREFIX + 1):gsub("%s+", "")
    local raw = decodeBase64(body)
    if not raw or raw == "" then return nil, "The Raidstrats string isn't valid base64." end
    local json = raw
    if raw:byte(1) == 1 then
        local LD = LibStub and LibStub:GetLibrary("LibDeflate", true)
        json = LD and LD:DecompressDeflate(raw:sub(2))
        if not json then return nil, "Couldn't decompress the Raidstrats string - is it complete?" end
    end
    local plan, jerr = decodeJSON(json)
    if not plan then return nil, "Couldn't read the Raidstrats plan (" .. tostring(jerr) .. ")." end
    if type(plan.scenes) ~= "table" or #plan.scenes == 0 then return nil, "That Raidstrats plan has no scenes." end

    local notes = { scenes = #plan.scenes }
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
        for j, o in ipairs(ops) do o.id = "rs:" .. i .. ":" .. j end
        local name = (type(scene.name) == "string" and scene.name ~= "") and scene.name or ("Scene " .. i)
        data.slides[#data.slides + 1] = { name = ns.Model.CleanName(name), view = convertView(scene), ops = ops }
        if type(scene.bg or scene.background) == "string" then notes.bg = scene.bg or scene.background end
    end
    return data
end
