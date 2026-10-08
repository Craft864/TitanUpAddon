-- TitanBoard - Sync.lua
-- The board protocol on top of Comms. Every drawing message is checked on
-- the RECEIVING side: a client only applies it if the sender may draw
-- (leader, assistant, or on the leader's grant list).
--
--   O  page;op           finished op (same id = update/move)
--   S  page;a|r op       live stroke in progress (a = append points, r = replace)
--   D  page;id           delete
--   X  page              clear a slide
--   C  inst,enc,map,page board context (which boss / slide is shown)
--   V  page,zoom,cx,cy   the camera for a slide (viewers follow it)
--   B  page,room         which room image a slide shows
--   R                    "send me the board" (the owner answers)
--   F  ctx\31plan\31slide meta\31ops slide 1\31ops slide 2 ...
--                        full snapshot, ops joined with ~
--   K  page,sum          owner's checksum; viewers that differ resync
--   A  name,name,...     draw permissions (leader only)
--   I  what              invite to open the board
--   H / P                presence (see Presence.lua)
local ADDON, ns = ...

local Sync = {}
ns.Sync = Sync

local Model, Comms

local function live() return Comms:Mode() ~= "local" end
local function curPage() return Model.plan and Model.plan.page or 1 end

local function wireId(op)
    if op.author == ns.me then return op.id:match(":(%d+)$") or op.id end
    return op.id
end

local function resolveId(id, sender)
    if id:find(":", 1, true) then return id end
    return sender .. ":" .. id
end

local function allowed(sender)
    if ns.CanDraw(sender) then return true end
    ns.Debug("ignored drawing message from", sender, "(no permission)")
    return false
end

-- ---------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------
function Sync:SendOp(op, page)
    if not live() then return end
    Comms:Purge("live:" .. op.id)
    Comms:Send("O", (page or curPage()) .. ";" .. Model.Serialize(op, wireId(op)), "op:" .. op.id)
end

function Sync:SendLive(op)
    if not live() then return end
    local page = curPage()
    Comms:SendGen("live:" .. op.id, function()
        if not op.live then return nil end
        if op.t == "P" then
            local n = #op.pts / 2
            local from = (op._sent or 0) + 1
            if from > n then return nil end
            local to = math.min(n, from + 44)
            op._sent = to
            return "S", page .. ";a" .. Model.Serialize(op, wireId(op), Model.PackPoints(op.pts, from, to)), to < n
        end
        return "S", page .. ";r" .. Model.Serialize(op, wireId(op)), false
    end)
end

function Sync:SendDelete(id, page)
    if not live() then return end
    Comms:Purge("live:" .. id)
    Comms:Purge("op:" .. id)
    local short = (id:match("^(.*):") == ns.me) and id:match(":(%d+)$") or id
    Comms:Send("D", (page or curPage()) .. ";" .. short)
end

function Sync:SendClear(page)
    if not live() then return end
    Comms:Send("X", tostring(page or curPage()))
end

function Sync:SendAll() self:SendContext(); self:SendSnapshot() end

function Sync:SendContext()
    if not live() or not ns.CanDraw() or not Model.plan then return end
    local ctx = Model.plan.ctx
    Comms:Send("C", table.concat({ ctx.inst or 0, ctx.enc or 0, ctx.map or 0, curPage() }, ","), "ctx")
end

function Sync:RequestSnapshot()
    if not live() then return end
    self._lastRequest = GetTime()
    Comms:Send("R", "", "req")
end

function Sync:SendSnapshot()
    if not live() or not ns.IsOwner() or self._snapTimer then return end
    self._snapTimer = true
    C_Timer.After(0.5, function()
        self._snapTimer = nil
        local plan = Model.plan
        if not plan then return end
        local ctx = plan.ctx
        local parts = {
            table.concat({ ctx.inst or 0, ctx.enc or 0, ctx.map or 0, plan.page }, ","),
            Model.CleanName(plan.name),
            Model:SlideMeta(),
        }
        Model:AddPageFields(parts)
        Comms:Send("F", table.concat(parts, "\031"), "snapshot")
        self:SendACL()
        self:AnnounceSum()
    end)
end

function Sync:SendView()
    if not live() or not ns.CanDraw() or not Model.plan then return end
    if self._viewTimer then return end
    self._viewTimer = true
    C_Timer.After(0.4, function()
        self._viewTimer = nil
        local sl = Model:Page()
        local v = sl and sl.view
        if not v then return end
        Comms:Send("V", table.concat({ curPage(), math.floor(v.z * 100 + 0.5), math.floor(v.cx + 0.5), math.floor(v.cy + 0.5) }, ","), "view")
    end)
end

function Sync:SendRoom(page)
    if not live() or not ns.CanDraw() or not Model.plan then return end
    page = page or curPage()
    local sl = Model:Page(page)
    if not sl then return end
    Comms:Send("B", page .. "," .. (sl.bg or ""), "room:" .. page)
end

function Sync:SendACL()
    if not live() or not ns.IsOwner() then return end
    local names = {}
    for n in pairs(ns.acl) do names[#names + 1] = n end
    Comms:Send("A", table.concat(names, ","), "acl")
end

function Sync:AnnounceSum()
    if not live() or not ns.IsOwner() or self._sumTimer then return end
    self._sumTimer = true
    C_Timer.After(2, function()
        self._sumTimer = nil
        if Model.plan then
            Comms:Send("K", curPage() .. "," .. Model:Checksum(), "sum")
        end
    end)
end

-- ---------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------
local function applySnapshot(payload, sender)
    local fields = ns.Split(payload, "\031")
    local inst, enc, map, page = (fields[1] or ""):match("^(%d+),(%d+),(%d+),(%d+)$")
    if not inst then return end
    local slides = Model.DecodeSlides(fields[3], fields, sender, 4)
    if not slides then return end
    ns.Board:ApplyRemoteContext(tonumber(inst), tonumber(enc), tonumber(map), 1, true)
    Model.plan.page = tonumber(page)
    Model:SetSlides(fields[2] ~= "" and fields[2] or nil, slides, false)
    ns.Board:ApplySlideView()
    ns.Board:RenderAll()
    ns.Debug("snapshot from", sender)
end

function Sync:Init()
    Model, Comms = ns.Model, ns.Comms

    Comms:On("O", function(p, sender)
        if not allowed(sender) then return end
        local page, s = p:match("^(%d+);(.*)$")
        local op = page and Model.Deserialize(s, sender)
        if op then Model:Apply(op, tonumber(page)) end
    end)

    Comms:On("S", function(p, sender)
        if not allowed(sender) then return end
        local page, mode, s = p:match("^(%d+);([ar])(.*)$")
        local op = page and Model.Deserialize(s, sender)
        if op then Model:ApplyLive(tonumber(page), mode, op) end
    end)

    Comms:On("D", function(p, sender)
        if not allowed(sender) then return end
        local page, id = p:match("^(%d+);(.+)$")
        if page then Model:Remove(resolveId(id, sender), tonumber(page)) end
    end)

    Comms:On("X", function(p, sender)
        if not allowed(sender) then return end
        local page = tonumber(p)
        if page then Model:Clear(page) end
        ns.Print(ns.Short(sender) .. " cleared slide " .. (page or "?") .. ".")
    end)

    Comms:On("C", function(p, sender)
        if not allowed(sender) then return end
        local inst, enc, map, page = p:match("^(%d+),(%d+),(%d+),(%d+)$")
        if not inst then return end
        ns.Board:ApplyRemoteContext(tonumber(inst), tonumber(enc), tonumber(map), tonumber(page))
        -- An assistant switched bosses: the leader's client sends its saved plan.
        if ns.IsOwner() then Sync:SendSnapshot() end
    end)

    Comms:On("V", function(p, sender)
        if not allowed(sender) then return end
        local page, z, cx, cy = p:match("^(%d+),(%d+),(%d+),(%d+)$")
        local sl = page and Model:Page(tonumber(page))
        if not sl or tonumber(z) < 100 then return end
        sl.view = { z = tonumber(z) / 100, cx = tonumber(cx), cy = tonumber(cy) }
        if tonumber(page) == curPage() then ns.Board:ApplySlideView(); ns.Board:RenderAll() end
    end)

    Comms:On("B", function(p, sender)
        if not allowed(sender) then return end
        local page, bg = p:match("^(%d+),(%w*)$")
        local sl = page and Model:Page(tonumber(page))
        if not sl then return end
        sl.bg = (bg ~= "" and bg) or nil
        if tonumber(page) == curPage() then
            ns.Board:ResetView()
            ns.Board:RenderAll()
        end
    end)

    Comms:On("R", function()
        if ns.IsOwner() then
            Sync:SendAll()
        end
    end)

    Comms:On("F", function(p, sender)
        if not allowed(sender) then return end
        applySnapshot(p, sender)
    end)

    Comms:On("K", function(p, sender)
        if ns.IsOwner() or sender ~= ns.LeaderName() then return end
        local page, sum = p:match("^(%d+),(%d+)$")
        if not page then return end
        Sync._leaderSum = { page = tonumber(page), sum = sum }
        if tonumber(page) ~= curPage() or sum == Model:Checksum() or Sync._healTimer then return end
        -- Give in-flight messages a moment, then resync if still different.
        Sync._healTimer = true
        C_Timer.After(3, function()
            Sync._healTimer = nil
            local ls = Sync._leaderSum
            if ls and ls.page == curPage() and ls.sum ~= Model:Checksum()
                and GetTime() - (Sync._lastRequest or 0) > 10 then
                ns.Debug("board differs from leader's - resyncing")
                Sync:RequestSnapshot()
            end
        end)
    end)

    Comms:On("A", function(p, sender)
        if sender ~= ns.LeaderName() then return end
        wipe(ns.acl)
        for n in p:gmatch("[^,]+") do ns.acl[n] = true end
        ns.Board:UpdateViewers()
    end)

    Comms:On("I", function(p, sender)
        if not allowed(sender) then return end
        ns.Invite:OnInvite(sender, p)
    end)
end

-- Is my board the same as the leader's last announced checksum?
function Sync:InSync()
    if ns.IsOwner() or not self._leaderSum then return nil end
    return self._leaderSum.page == curPage() and self._leaderSum.sum == Model:Checksum()
end
