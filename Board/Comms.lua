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
--  * Solo ("local" mode) nothing is sent.
--
-- Wire format: "<kind>^<payload>"; parts are "#^<msgid>,<i>,<n>^<chunk>".
local ADDON, ns = ...

local Comms = {}
ns.Comms = Comms

local SEP = "^"
local MAXLEN = 250
local CHUNK = 230

local queue = {}
local tokens, lastRefill = 0, 0
local ticker
local handlers = {}
local partial = {}
local msgCounter = 0

Comms.stats = { sent = 0, recv = 0, throttled = 0 }

function Comms:On(kind, fn) handlers[kind] = fn end

function Comms:Mode() return IsInGroup() and "group" or "local" end

function Comms:QueueSize() return #queue end

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

function Comms:_split(msg)
    msgCounter = (msgCounter % 4095) + 1
    local id = ("%x"):format(msgCounter)
    local n = math.ceil(#msg / CHUNK)
    local parts = {}
    for i = 1, n do
        parts[i] = "#" .. SEP .. id .. "," .. i .. "," .. n .. SEP .. msg:sub((i - 1) * CHUNK + 1, i * CHUNK)
    end
    return parts
end

function Comms:_tick()
    local s = ns.db.settings
    local now = GetTime()
    tokens = math.min(s.burst, tokens + (now - lastRefill) * s.rate)
    lastRefill = now
    if #queue == 0 then
        ticker:Cancel()
        ticker = nil
        return
    end
    if ns.InLockdown() then return end
    if self:Mode() == "local" then wipe(queue) return end

    while #queue > 0 and tokens >= 1 do
        local e = queue[1]
        local msg
        if e.gen then
            local kind, payload, more = e.gen()
            if kind then msg = kind .. SEP .. payload end
            if not kind or not more then table.remove(queue, 1) end
        else
            msg = e.msg
            table.remove(queue, 1)
        end
        if msg then
            if #msg > MAXLEN then
                local parts = self:_split(msg)
                for i = #parts, 1, -1 do table.insert(queue, 1, { msg = parts[i] }) end
            else
                local res = self:_rawSend(msg)
                if res == "throttle" then
                    table.insert(queue, 1, { msg = msg })
                    tokens = 0
                    break
                elseif res then
                    tokens = tokens - 1
                end
            end
        end
    end
end

function Comms:_rawSend(msg)
    local channel = ns.DataChannel()
    if not channel then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, channel)
    if not ok then
        ns.Debug("send error:", res)
        return false
    end
    local E = Enum and Enum.SendAddonMessageResult
    if res == nil or res == true or (E and res == E.Success) then
        self.stats.sent = self.stats.sent + 1
        return true
    end
    if E and res == E.AddonMessageThrottle then
        self.stats.throttled = self.stats.throttled + 1
        return "throttle"
    end
    ns.Debug("send result:", tostring(res))
    return false
end

-- ---------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------
function Comms:Receive(text, sender)
    local kind, rest = text:match("^([^%^]+)%^(.*)$")
    if not kind then return end
    if kind == "#" then
        local hdr, chunk = rest:match("^([^%^]+)%^(.*)$")
        if not hdr then return end
        local id, i, n = hdr:match("^(%x+),(%d+),(%d+)$")
        i, n = tonumber(i), tonumber(n)
        if not id or not n or n > 400 or i < 1 or i > n then return end
        local now = GetTime()
        for k, p in pairs(partial) do
            if now - p.t > 30 then partial[k] = nil end
        end
        local key = sender .. "/" .. id
        local p = partial[key]
        if not p or p.n ~= n then
            p = { n = n, got = 0, parts = {}, t = now }
            partial[key] = p
        end
        if not p.parts[i] then
            p.parts[i] = chunk
            p.got = p.got + 1
        end
        if p.got == n then
            partial[key] = nil
            return self:Receive(table.concat(p.parts), sender)
        end
        return
    end
    self.stats.recv = self.stats.recv + 1
    local fn = handlers[kind]
    if fn then
        local ok, err = pcall(fn, rest, sender)
        if not ok then geterrorhandler()(err) end
    end
end
