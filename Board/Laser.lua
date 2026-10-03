-- TitanBoard - Laser.lua
-- Laser pointer: anyone in the group can point at the board while holding
-- the left mouse button (viewers always; drawers with the Laser tool or by
-- holding Alt). Everyone sees a dot in the pointer's class color with
-- their name and a short fading trail.
--
-- Pointer traffic uses its own addon prefix and its own small send budget
-- so it never delays drawing messages, and only the NEWEST position is
-- ever sent - a pointer that's a second late is useless, so nothing queues.
-- Like everything else it's silent during an encounter lockdown.
local ADDON, ns = ...

local Laser = {}
ns.Laser = Laser

local PREFIX = "TitanBoardL"
local INTERVAL = 0.15   -- seconds between position updates from one person
local BURST, RATE = 10, 4
local FADE, GONE = 1.0, 2.0  -- start fading / disappear after this long without updates

local tokens, lastRefill, lastSend = BURST, 0, 0
local pending
Laser.pointers = {}     -- [name] = { x, y, dx, dy, t, trail = { x, y, ... }, ended }
Laser.sent = 0

local function curPage() return ns.Model.plan and ns.Model.plan.page or 1 end

function Laser:Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    lastRefill = GetTime()
    ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
        if prefix ~= PREFIX then return end
        if ns.IsSecret(text) or ns.IsSecret(sender) then return end
        sender = ns.NormalizeSender(sender)
        if not sender or sender == ns.me then return end
        Laser:OnMessage(text, sender)
    end)
end

-- The send timer only runs while a position is waiting to go out.
function Laser:_kick()
    if not self.ticker then self.ticker = C_Timer.NewTicker(0.05, function() Laser:_flush() end) end
end

-- ---------------------------------------------------------------------
-- Sending (your pointer)
-- ---------------------------------------------------------------------
function Laser:Move(x, y)
    self:_track(ns.me, x, y)
    pending = curPage() .. ";" .. ns.Model.PackPoints({ x, y })
    self:_flush()
    if pending then self:_kick() end
end

function Laser:Stop()
    local p = self.pointers[ns.me]
    if p then p.ended = GetTime() end
    pending = curPage() .. ";x"
    self:_flush()
    if pending then self:_kick() end
end

function Laser:_flush()
    if not pending then
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        return
    end
    local mode = ns.Comms:Mode()
    if mode == "local" or ns.InLockdown() then
        pending = nil
        return
    end
    local now = GetTime()
    tokens = math.min(BURST, tokens + (now - lastRefill) * RATE)
    lastRefill = now
    if tokens < 1 or now - lastSend < INTERVAL then return end
    local msg = pending
    if mode == "sim" then
        if ns.Sim then ns.Sim:OnOutgoing(msg) end
    else
        local channel, target = ns.GroupChannel(), nil
        if mode == "loopback" then channel, target = "WHISPER", UnitName("player") end
        if not channel then pending = nil return end
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
        local E = Enum and Enum.SendAddonMessageResult
        if ok and E and res == E.AddonMessageThrottle then
            tokens = 0      -- keep the newest position, try again shortly
            return
        end
    end
    pending = nil
    tokens = tokens - 1
    lastSend = now
    self.sent = self.sent + 1
end

-- ---------------------------------------------------------------------
-- Receiving (other people's pointers)
-- ---------------------------------------------------------------------
function Laser:_track(name, x, y)
    local p = self.pointers[name]
    if not p then
        p = { x = x, y = y, dx = x, dy = y, trail = {} }
        self.pointers[name] = p
    end
    p.x, p.y, p.t, p.ended = x, y, GetTime(), nil
    if ns.Board then ns.Board:RenderLasers() end
    return p
end

function Laser:OnMessage(text, sender)
    local page, data = text:match("^(%d+);(.+)$")
    if not page then return end
    -- Only group members (or the simulator's fake raiders) can point.
    local member = false
    for _, n in ipairs(ns.GroupNames()) do
        if n == sender then member = true break end
    end
    if not member then return end
    if tonumber(page) ~= curPage() then
        self.pointers[sender] = nil
        if ns.Board then ns.Board:RenderLasers() end
        return
    end
    if data == "x" then
        local p = self.pointers[sender]
        if p then p.ended = GetTime() end
        return
    end
    local pts = ns.Model.UnpackPoints(data)
    if pts and #pts == 2 then self:_track(sender, pts[1], pts[2]) end
end

-- Called every frame by the board: glide toward the newest position,
-- keep a short trail, fade out stale pointers. Returns true while any
-- pointer is visible.
function Laser:Animate()
    local now = GetTime()
    local any = false
    for name, p in pairs(self.pointers) do
        local age = now - (p.ended or p.t or now)
        if age > (p.ended and 0.4 or GONE) then
            self.pointers[name] = nil
        else
            any = true
            local k = (name == ns.me) and 1 or 0.35
            p.dx = p.dx + (p.x - p.dx) * k
            p.dy = p.dy + (p.y - p.dy) * k
            local tr = p.trail
            local lx, ly = tr[#tr - 1], tr[#tr]
            if not lx or math.abs(lx - p.dx) + math.abs(ly - p.dy) > 12 then
                tr[#tr + 1] = p.dx
                tr[#tr + 1] = p.dy
                if #tr > 16 then table.remove(tr, 1); table.remove(tr, 1) end
            end
            p.alpha = (p.ended and math.max(0, 1 - age / 0.4)) or (age > FADE and math.max(0, 1 - (age - FADE) / (GONE - FADE))) or 1
        end
    end
    return any
end

function Laser:Clear()
    wipe(self.pointers)
    pending = nil
    if ns.Board then ns.Board:RenderLasers() end
end
