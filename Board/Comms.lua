-- TitanBoard - Comms.lua
-- Everything that touches the addon message channel.
--
--  * A token-bucket send queue (burst + refill rate, see settings) that
--    backs off when the client reports throttling.
--  * Encounter lockdown: while C_ChatInfo.InChatMessagingLockdown() is true
--    nothing is sent; the queue holds and flushes after the pull.
--  * Coalescing: queued messages can carry a key so a newer version of the
--    same thing (an op being dragged, presence state) replaces the old one.
--  * Messages over 250 bytes are split into numbered parts and reassembled.
--    Parts wait behind ordinary messages, so a big snapshot never holds up
--    live drawing, the camera or presence.
--  * Solo, or without a guild to send through ("local" mode), nothing is sent.
--
-- Wire format: "<kind>^<payload>"; parts are "#^<msgid>,<i>,<n>^<chunk>".
local ADDON, ns = ...

local Comms = {}
ns.Comms = Comms

local SEP = "^"
local MAXLEN = 250
local CHUNK = 230
local MAX_PARTS = 400       -- receivers (every version) drop anything longer

local queue = {}
local parts = {}            -- { m = part, id = msgid, key }, sent when queue is empty
local tokens, lastRefill = 0, 0
local ticker
local handlers = {}
local partial = {}
-- a random start, so ids after a /reload don't collide with parts of a
-- message from before it that receivers may still be holding
local msgCounter = math.random(0, 4094)

Comms.stats = { sent = 0, recv = 0, throttled = 0 }

function Comms:On(kind, fn) handlers[kind] = fn end

function Comms:Mode() return (IsInGroup() and ns.DataChannel()) and "group" or "local" end

function Comms:QueueSize() return #queue + #parts end
function Comms:SendingParts() return #parts > 0 end

function Comms:Init()
    tokens = ns.db.settings.burst
    lastRefill = GetTime()
    ns.Listen(ns.PREFIX, "group", function(text, sender) Comms:Receive(text, sender) end)   -- guildmates in your group only
end

-- ---------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------
function Comms:Send(kind, payload, key)
    if self:Mode() == "local" then return end
    local msg = kind .. SEP .. (payload or "")
    if key then
        for _, e in ipairs(queue) do
            if e.key == key and not e.gen then
                e.msg = msg
                return
            end
        end
    end
    queue[#queue + 1] = { msg = msg, key = key }
    self:Pump()
end

-- A generator builds its payload at send time, so a stroke being drawn
-- always sends its newest points. gen() returns kind, payload, more.
function Comms:SendGen(key, gen)
    if self:Mode() == "local" then return end
    for _, e in ipairs(queue) do
        if e.key == key then return end
    end
    queue[#queue + 1] = { gen = gen, key = key }
    self:Pump()
end

function Comms:Purge(key)
    for i = #queue, 1, -1 do
        if queue[i].key == key then table.remove(queue, i) end
    end
end

function Comms:Pump()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, function() Comms:_tick() end)
end

-- A newer message with the same key (a newer snapshot) replaces the
-- unsent parts of the older one.
function Comms:_split(msg, key)
    local chunks = ns.Chunks(msg, CHUNK)
    if #chunks > MAX_PARTS then
        ns.Print(("This plan is too big to share live (%d KB). Share it with Export instead."):format(math.floor(#msg / 1024)))
        return
    end
    if key then
        for i = #parts, 1, -1 do if parts[i].key == key then table.remove(parts, i) end end
    end
    msgCounter = (msgCounter % 4095) + 1
    local id = ("%x"):format(msgCounter)
    for i, c in ipairs(chunks) do
        parts[#parts + 1] = { m = "#" .. SEP .. id .. "," .. i .. "," .. #chunks .. SEP .. c, id = id, key = key }
    end
end

-- the next message to send: ordinary ones first, then parts
local function nextMessage()
    local e = queue[1]
    if not e then
        local p = table.remove(parts, 1)
        return p and p.m, p
    end
    if e.gen then
        local kind, payload, more = e.gen()
        if not kind or not more then table.remove(queue, 1) end
        return kind and (kind .. SEP .. payload), nil, e.key
    end
    table.remove(queue, 1)
    return e.msg, nil, e.key
end

function Comms:_tick()
    local s = ns.db.settings
    local now = GetTime()
    tokens = math.min(s.burst, tokens + (now - lastRefill) * s.rate)
    lastRefill = now
    if #queue == 0 and #parts == 0 then
        ticker:Cancel()
        ticker = nil
        return
    end
    if ns.InLockdown() then return end
    if self:Mode() == "local" then wipe(queue); wipe(parts) return end

    while tokens >= 1 and (#queue > 0 or #parts > 0) do
        local msg, part, key = nextMessage()
        if msg and #msg > MAXLEN then
            self:_split(msg, key)
        elseif msg then
            local res = self.TrySend(ns.PREFIX, msg)
            if res == "throttle" then
                table.insert(part and parts or queue, 1, part or { msg = msg })
                tokens = 0
                break
            elseif res then
                tokens = tokens - 1
            elseif part then
                -- a part that can't go out: the rest of its message is useless
                for i = #parts, 1, -1 do if parts[i].id == part.id then table.remove(parts, i) end end
            end
        end
    end
end

-- One addon message straight out: true when sent, "throttle" when the
-- server asked to slow down, false when it failed (or there's no guild).
-- The laser uses it too, so its throttles show in the same stats.
function Comms.TrySend(prefix, msg)
    local channel = ns.DataChannel()
    if not channel then return false end
    local res = ns.TrySend(prefix, msg, channel)
    if res == true then Comms.stats.sent = Comms.stats.sent + 1
    elseif res == "throttle" then Comms.stats.throttled = Comms.stats.throttled + 1
    else ns.Debug("send failed:", prefix) end
    return res
end

-- ---------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------
function Comms:Receive(text, sender)
    local kind, rest = text:match("^([^%^]+)%^(.*)$")
    if not kind then return end
    if kind == "#" then
        local id, i, n, chunk = rest:match("^(%x+),(%d+),(%d+)%^(.*)$")
        if not id then return end
        local whole = ns.Reassemble(partial, sender .. "/" .. id, i, n, chunk, MAX_PARTS)
        if whole then return self:Receive(whole, sender) end
        return
    end
    self.stats.recv = self.stats.recv + 1
    local fn = handlers[kind]
    if fn then ns.Try(fn, rest, sender) end
end

-- Is a long message from this sender still arriving?
function Comms:Receiving(sender)
    local now, prefix = GetTime(), sender .. "/"
    for key, box in pairs(partial) do
        if key:sub(1, #prefix) == prefix and now - box.at < 60 then return true end
    end
    return false
end
