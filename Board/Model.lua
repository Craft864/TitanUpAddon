-- TitanBoard - Model.lua
-- The plan for one encounter: 4 phase pages, each a list of drawing ops.
--
-- An op is plain data:
--   { t = type, id = "Name-Realm:n", author, c = color 1-8, w = width 1-8,
--     k = stamp kind, pts = { x1, y1, x2, y2, ... }, text, live = bool }
-- Types: P pen, L line, A arrow, C circle (center, edge), T text, M stamp,
--        W pie slice (tip, edge; k = angle in degrees),
--        D donut (center, outer edge; k = hole size in % of the radius).
-- Coordinates are 0..4095, relative to the board's background image.
--
-- Wire/save format, comma separated (text last so it may contain commas):
--   t,id,c,w,k,points,text
-- Points are 4 characters each (two 12-bit base64 numbers), so a message
-- holds ~50 points.
local ADDON, ns = ...

local Model = {}
ns.Model = Model

local U = ns.U
local MOD = 2147483647

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local ch = B64:sub(i, i)
    ENC[i - 1] = ch
    DEC[ch] = i - 1
end

local VALID = { P = true, L = true, A = true, C = true, T = true, M = true, W = true, D = true }

local function clampU(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 elseif v > U then return U end
    return v
end

function Model.PackPoints(pts, first, last)
    first = first or 1
    last = last or (#pts / 2)
    local out = {}
    for p = first, last do
        local x, y = clampU(pts[2 * p - 1]), clampU(pts[2 * p])
        out[#out + 1] = ENC[math.floor(x / 64)] .. ENC[x % 64] .. ENC[math.floor(y / 64)] .. ENC[y % 64]
    end
    return table.concat(out)
end

function Model.UnpackPoints(s)
    if #s % 4 ~= 0 then return nil end
    local pts = {}
    for i = 1, #s, 4 do
        local a, b = DEC[s:sub(i, i)], DEC[s:sub(i + 1, i + 1)]
        local c, d = DEC[s:sub(i + 2, i + 2)], DEC[s:sub(i + 3, i + 3)]
        if not (a and b and c and d) then return nil end
        pts[#pts + 1] = a * 64 + b
        pts[#pts + 1] = c * 64 + d
    end
    return pts
end

-- Strip anything that would break the wire format or chat escapes.
function Model.CleanText(t)
    t = tostring(t or ""):gsub("[%c|~^]", "")
    return t:sub(1, 60)
end

function Model.Serialize(op, idOverride, packedPts)
    return table.concat({
        op.t, idOverride or op.id, op.c or 1, op.w or 3, op.k or 0,
        packedPts or Model.PackPoints(op.pts),
        op.text and Model.CleanText(op.text) or "",
    }, ",")
end

-- A short id ("12") comes from its sender; a full id ("Name-Realm:12")
-- is kept as-is (relayed or moved by someone else).
function Model.Deserialize(s, sender)
    local t, id, c, w, k, p, text = s:match("^(%a),([^,]+),(%d+),(%d+),(%d+),([^,]*),(.*)$")
    if not t or not VALID[t] then return nil end
    if not id:find(":", 1, true) then
        if not sender then return nil end
        id = sender .. ":" .. id
    end
    local pts = Model.UnpackPoints(p)
    if not pts or #pts < 2 then return nil end
    local op = {
        t = t, id = id, author = id:match("^(.*):"),
        c = math.min(8, math.max(1, tonumber(c))),
        w = math.min(16, math.max(1, tonumber(w))),   -- 1-8 when drawing; stamps/text can be resized up to 16
        k = tonumber(k), pts = pts,
    }
    if text ~= "" then op.text = text end
    return op
end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % MOD end
    return h
end

-- Douglas-Peucker: drop points that don't change the shape of a stroke.
function Model.Simplify(pts, eps)
    local n = #pts / 2
    if n <= 2 then return pts end
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    local eps2 = eps * eps
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local ax, ay, bx, by = pts[2 * a - 1], pts[2 * a], pts[2 * b - 1], pts[2 * b]
        local dx, dy = bx - ax, by - ay
        local len2 = dx * dx + dy * dy
        local best, bi = -1, nil
        for i = a + 1, b - 1 do
            local px, py = pts[2 * i - 1], pts[2 * i]
            local d
            if len2 == 0 then
                d = (px - ax) ^ 2 + (py - ay) ^ 2
            else
                local t = ((px - ax) * dx + (py - ay) * dy) / len2
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
                d = (px - (ax + t * dx)) ^ 2 + (py - (ay + t * dy)) ^ 2
            end
            if d > best then best, bi = d, i end
        end
        if bi and best > eps2 then
            keep[bi] = true
            stack[#stack + 1] = { a, bi }
            stack[#stack + 1] = { bi, b }
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = pts[2 * i - 1]
            out[#out + 1] = pts[2 * i]
        end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Plan state
--
-- A plan is a named, ordered list of slides for one encounter. Each slide
-- has its own drawings and remembers the camera (zoom/pan) it was shown
-- with, so switching slides shows everyone the same framing.
--
-- Saved as ns.db.plans[encounterKey] = {
--     active = "Default",
--     list = { [planName] = { slides = { { name, view = { z, cx, cy }, ops = { "..." } } }, saved } },
-- }
-- ---------------------------------------------------------------------
local MAX_SLIDES = 20
Model.MAX_SLIDES = MAX_SLIDES

function Model.CleanName(t, max)
    t = tostring(t or ""):gsub("[%c|~^:,]", "")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t:sub(1, max or 24)
end

-- bg: which room image the slide shows (see Rooms.lua); nil = default.
local function newSlide(name, view, bg)
    return { name = name, view = view, bg = bg, ops = {}, byId = {}, sum = 0 }
end

local function newPlan(ctx, name)
    return { ctx = ctx, name = name or "Default", page = 1, pages = { newSlide("Slide 1") } }
end

function Model:Init() end

function Model:Page(p)
    local plan = self.plan
    return plan and plan.pages[p or plan.page]
end

function Model:SlideCount()
    return self.plan and #self.plan.pages or 0
end

local function render(op, page)
    local plan = Model.plan
    if plan and page == plan.page and ns.Board then ns.Board:RenderOp(op) end
end

local function insertHashed(sl, op)
    if sl.byId[op.id] then return end
    op._h = hash(Model.Serialize(op))
    sl.sum = (sl.sum + op._h) % MOD
    sl.ops[#sl.ops + 1] = op
    sl.byId[op.id] = op
end

-- Add or replace an op (same id = update in place).
function Model:Apply(op, page)
    local plan = self.plan
    if not plan then return end
    page = page or plan.page
    local pg = plan.pages[page]
    if not pg then return end
    local old = pg.byId[op.id]
    if old and old ~= op then
        if old._h then pg.sum = (pg.sum - old._h) % MOD; old._h = nil end
        old.t, old.c, old.w, old.k, old.pts, old.text, old.live =
            op.t, op.c, op.w, op.k, op.pts, op.text, op.live
        op = old
    elseif old == op then
        if op._h then pg.sum = (pg.sum - op._h) % MOD; op._h = nil end
    else
        pg.ops[#pg.ops + 1] = op
        pg.byId[op.id] = op
    end
    if not op.live then
        op._h = hash(Model.Serialize(op))
        pg.sum = (pg.sum + op._h) % MOD
        self:Touch()
    end
    render(op, page)
    return op
end

-- In-progress stroke from someone else. mode "a" appends points,
-- "r" replaces them (shapes being dragged out).
function Model:ApplyLive(page, mode, op)
    local plan = self.plan
    if not plan or not plan.pages[page] then return end
    local pg = plan.pages[page]
    local old = pg.byId[op.id]
    if old then
        if not old.live then return end   -- already finalized
        if mode == "a" then
            for i = 1, #op.pts do old.pts[#old.pts + 1] = op.pts[i] end
        else
            old.pts = op.pts
        end
        old.c, old.w, old.k = op.c, op.w, op.k
        render(old, page)
    else
        op.live = true
        pg.ops[#pg.ops + 1] = op
        pg.byId[op.id] = op
        render(op, page)
    end
end

function Model:Remove(id, page)
    local plan = self.plan
    if not plan then return end
    page = page or plan.page
    local pg = plan.pages[page]
    local op = pg and pg.byId[id]
    if not op then return end
    pg.byId[id] = nil
    for i, o in ipairs(pg.ops) do
        if o == op then table.remove(pg.ops, i) break end
    end
    if op._h then pg.sum = (pg.sum - op._h) % MOD end
    if ns.Board then ns.Board:ReleaseOp(op) end
    self:Touch()
    return op
end

function Model:Clear(page, quiet)
    local plan = self.plan
    if not plan then return end
    page = page or plan.page
    local pg = plan.pages[page]
    if not pg then return end
    for _, op in ipairs(pg.ops) do
        if ns.Board then ns.Board:ReleaseOp(op) end
    end
    wipe(pg.ops)
    wipe(pg.byId)
    pg.sum = 0
    if not quiet then self:Touch() end
end

function Model:ReleaseAll()
    if not self.plan or not ns.Board then return end
    for _, sl in ipairs(self.plan.pages) do
        for _, op in ipairs(sl.ops) do ns.Board:ReleaseOp(op) end
    end
end

function Model:Checksum(page)
    local pg = self:Page(page)
    return pg and tostring(pg.sum) or "0"
end

function Model:CountOps(page)
    local pg = self:Page(page)
    return pg and #pg.ops or 0
end

function Model:SerializePage(p)
    local list = {}
    for _, op in ipairs(self.plan.pages[p].ops) do
        if not op.live then list[#list + 1] = Model.Serialize(op) end
    end
    return list
end

-- ---------------------------------------------------------------------
-- Slides: wire/export helpers. Slide meta is "name:zoom:cx:cy:room" per
-- slide, joined with "~"; ops for each slide travel in their own field.
-- ---------------------------------------------------------------------
function Model:SlideMeta()
    local out = {}
    for _, sl in ipairs(self.plan.pages) do
        local v = sl.view
        out[#out + 1] = table.concat({ Model.CleanName(sl.name) ,
            v and math.floor(v.z * 100 + 0.5) or 0, v and math.floor(v.cx + 0.5) or 0, v and math.floor(v.cy + 0.5) or 0,
            sl.bg or "" }, ":")
    end
    return table.concat(out, "~")
end

-- Returns { { name, view, ops = { op, ... } }, ... } or nil.
function Model.DecodeSlides(meta, opFields, sender)
    local slides = {}
    for i, m in ipairs(ns.Split(meta or "", "~")) do
        local name, z, cx, cy, bg = m:match("^([^:]*):(%d+):(%d+):(%d+):?(%w*)$")
        if not name then return nil end
        local sl = { name = (name ~= "" and name) or ("Slide " .. i), ops = {}, bg = (bg ~= "" and bg) or nil }
        z = tonumber(z)
        if z and z >= 100 then sl.view = { z = z / 100, cx = tonumber(cx), cy = tonumber(cy) } end
        local list = opFields[i]
        if list and list ~= "" then
            for _, s in ipairs(ns.Split(list, "~")) do
                local op = Model.Deserialize(s, sender)
                if op then sl.ops[#sl.ops + 1] = op end
            end
        end
        slides[i] = sl
    end
    if #slides == 0 or #slides > MAX_SLIDES then return nil end
    return slides
end

-- Replace the whole current plan's slides (snapshot from the leader, or
-- an import). reid = give every op a fresh id owned by you.
function Model:SetSlides(name, slides, reid)
    local plan = self.plan
    if not plan then return end
    self:ReleaseAll()
    plan.name = name or plan.name
    plan.pages = {}
    for i, sd in ipairs(slides) do
        local sl = newSlide(sd.name, sd.view, sd.bg)
        for _, op in ipairs(sd.ops) do
            if reid then
                op.id = ns.me .. ":" .. ns.NextId()
                op.author = ns.me
            end
            insertHashed(sl, op)
        end
        plan.pages[i] = sl
    end
    if #plan.pages == 0 then plan.pages[1] = newSlide("Slide 1") end
    plan.page = math.max(1, math.min(plan.page or 1, #plan.pages))
end

local function uniqueSlideName(plan, base)
    local taken = {}
    for _, sl in ipairs(plan.pages) do taken[sl.name] = true end
    if not taken[base] then return base end
    local n = 2
    while taken[base .. " " .. n] do n = n + 1 end
    return base .. " " .. n
end

-- New empty slide after the current one; starts with the given view and
-- the current slide's room.
function Model:AddSlide(view)
    local plan = self.plan
    if not plan or #plan.pages >= MAX_SLIDES then return nil end
    local i = plan.page + 1
    local bg = plan.pages[plan.page] and plan.pages[plan.page].bg
    table.insert(plan.pages, i, newSlide(uniqueSlideName(plan, "Slide " .. (#plan.pages + 1)), view, bg))
    plan.keep = true
    self:Touch()
    return i
end

function Model:DuplicateSlide(p)
    local plan = self.plan
    local src = plan and plan.pages[p]
    if not src or #plan.pages >= MAX_SLIDES then return nil end
    local copy = newSlide(uniqueSlideName(plan, Model.CleanName(src.name, 18) .. " copy"),
        src.view and { z = src.view.z, cx = src.view.cx, cy = src.view.cy }, src.bg)
    for _, op in ipairs(src.ops) do
        if not op.live then
            local dup = Model.Deserialize(Model.Serialize(op))
            dup.id = ns.me .. ":" .. ns.NextId()
            dup.author = ns.me
            insertHashed(copy, dup)
        end
    end
    table.insert(plan.pages, p + 1, copy)
    plan.keep = true
    self:Touch()
    return p + 1
end

function Model:DeleteSlide(p)
    local plan = self.plan
    if not plan or #plan.pages <= 1 or not plan.pages[p] then return false end
    for _, op in ipairs(plan.pages[p].ops) do
        if ns.Board then ns.Board:ReleaseOp(op) end
    end
    table.remove(plan.pages, p)
    plan.page = math.max(1, math.min(plan.page, #plan.pages))
    self:Touch()
    return true
end

function Model:RenameSlide(p, name)
    local sl = self:Page(p)
    name = Model.CleanName(name)
    if not sl or name == "" then return false end
    sl.name = name
    self.plan.keep = true
    self:Touch()
    return true
end

function Model:MoveSlide(p, delta)
    local plan = self.plan
    local q = p + delta
    if not plan or not plan.pages[p] or not plan.pages[q] then return nil end
    plan.pages[p], plan.pages[q] = plan.pages[q], plan.pages[p]
    if plan.page == p then plan.page = q elseif plan.page == q then plan.page = p end
    self:Touch()
    return q
end

-- ---------------------------------------------------------------------
-- Saved plans. Only the owner (leader, or you solo) saves: a raider
-- watching the leader's plan must not overwrite their own plans.
-- ---------------------------------------------------------------------
function Model:Entry(key, create)
    local plans = ns.db.plans
    local e = plans[key]
    if e and e.pages and not e.list then
        -- Saved by v0.1-0.3: four fixed phases -> slides "Phase 1..n".
        local last = 0
        for p = 1, 4 do
            if e.pages[p] and #e.pages[p] > 0 then last = p end
        end
        local slides = {}
        for p = 1, math.max(1, last) do
            slides[p] = { name = "Phase " .. p, ops = e.pages[p] or {} }
        end
        e = { active = "Default", list = { Default = { slides = slides, saved = e.saved } } }
        plans[key] = e
    end
    if not e and create then
        e = { active = "Default", list = {} }
        plans[key] = e
    end
    return e
end

function Model:Load(ctx, planName)
    local entry = ns.IsOwner() and self:Entry(ctx.key)
    planName = planName or (entry and entry.active) or "Default"
    local plan = newPlan(ctx, planName)
    self.plan = plan
    local saved = entry and entry.list[planName]
    if not saved then return end
    plan.keep = true
    plan.pages = {}
    for i, sd in ipairs(saved.slides or {}) do
        local sl = newSlide(sd.name or ("Slide " .. i), sd.view, sd.bg)
        for _, s in ipairs(sd.ops or {}) do
            local op = Model.Deserialize(s)
            if op then insertHashed(sl, op) end
        end
        plan.pages[i] = sl
    end
    if #plan.pages == 0 then plan.pages[1] = newSlide("Slide 1") end
end

local function isBlank(plan)
    if #plan.pages > 1 then return false end
    local sl = plan.pages[1]
    return #sl.ops == 0 and sl.name == "Slide 1"
end

function Model:Save()
    local plan = self.plan
    if not plan or not ns.IsOwner() then return end
    if isBlank(plan) and not plan.keep then return end
    local entry = self:Entry(plan.ctx.key, true)
    local slides = {}
    for i, sl in ipairs(plan.pages) do
        slides[i] = { name = sl.name, view = sl.view, bg = sl.bg, ops = self:SerializePage(i) }
    end
    entry.list[plan.name] = { slides = slides, saved = time(), boss = plan.ctx.name, instName = plan.ctx.instName }
    entry.active = plan.name
end

function Model:Touch()
    if not self._saveTimer then
        self._saveTimer = true
        C_Timer.After(1.5, function()
            self._saveTimer = nil
            self:Save()
        end)
    end
    if ns.Sync then ns.Sync:AnnounceSum() end
end

function Model:PlanNames()
    local out, seen = {}, {}
    local e = self.plan and self:Entry(self.plan.ctx.key)
    if e then
        for n in pairs(e.list) do out[#out + 1] = n; seen[n] = true end
    end
    if self.plan and not seen[self.plan.name] then out[#out + 1] = self.plan.name end
    table.sort(out)
    return out
end

function Model:UniquePlanName(base)
    base = Model.CleanName(base)
    if base == "" then base = "Plan" end
    local taken = {}
    for _, n in ipairs(self:PlanNames()) do taken[n] = true end
    if not taken[base] then return base end
    local n = 2
    while taken[base .. " " .. n] do n = n + 1 end
    return base .. " " .. n
end

function Model:SwitchPlan(name)
    if not self.plan or name == self.plan.name then return end
    self:Save()
    self:ReleaseAll()
    self:Load(self.plan.ctx, name)
end

function Model:NewPlan(name)
    self:Save()
    self:ReleaseAll()
    local ctx = self.plan.ctx
    self.plan = newPlan(ctx, self:UniquePlanName(name))
    self.plan.keep = true
    self:Save()
end

-- Keep working under a new name; the old plan stays as it was last saved.
function Model:SaveAs(name)
    self:Save()
    self.plan.name = self:UniquePlanName(name)
    self.plan.keep = true
    self:Save()
end

function Model:DeletePlan(name)
    local plan = self.plan
    if not plan then return end
    local e = self:Entry(plan.ctx.key)
    if e then e.list[name] = nil end
    if name ~= plan.name then return end
    self:ReleaseAll()
    local remaining = {}
    if e then for n in pairs(e.list) do remaining[#remaining + 1] = n end end
    table.sort(remaining)
    if remaining[1] then
        e.active = remaining[1]
        self:Load(plan.ctx, remaining[1])
    else
        ns.db.plans[plan.ctx.key] = nil
        self.plan = newPlan(plan.ctx, "Default")
    end
end
