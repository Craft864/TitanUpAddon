-- Titan Up - Guild/Shared.lua
-- Shared lists: one list per guildmate (their crafting recipes, their loot
-- wishlist), kept by everyone running Titan Up so it shows even when its
-- owner is offline. Used by the Crafters directory and the Loot wishlist.
--
-- Everything here travels on the background lane (ns.BulkSend: one
-- message every couple of seconds in all, paused in combat, boss fights,
-- raids and Mythic+), and only when something is new:
--   * login: one short "my list is version X" line (H);
--   * a change of your own: your whole list, once, ~30 s after the last edit (D);
--   * someone's hello shows a version you don't have: one guildmate asks (Q),
--     the owner answers (or, if they've gone, someone holding a copy does);
--   * first time you open the window: one "what lists exist?" (W), one
--     guildmate answers with a list of versions (L), and you ask only for
--     the ones you're missing.
-- Asks and answers are spread over a few random seconds, and anyone who
-- hears someone else ask or answer first stays quiet.
--
-- Messages (prefix per feature, fields joined with ^):
--   H hash t                        my list's version (sent by its owner)
--   Q owner,owner,...               please send these owners' lists
--   D owner t hash part n chunk     a list, in parts
--   W nonce                         "which lists exist?" (a catch-up)
--   L nonce part n chunk            answer: owner:hash:t;owner:hash:t;...
-- A list is plain text with no ^ or |; an empty one means "removed".
local ADDON, ns = ...

local Shared = {}
ns.Shared = Shared
Shared.__index = Shared

local CHUNK = 170
local PUSH_DELAY = 30           -- your edits go out this long after the last one
local KEEP_DAYS = 120           -- a list nobody has refreshed in this long is dropped
local DAY = 86400

function Shared.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return ("%x"):format(h)
end

-- def: { prefix, name, store = fn() -> { [owner] = { t, h, p } }, mine = fn() -> payload,
--        changed = fn(owner) (a list arrived or changed), max = longest payload in bytes }
function Shared.New(def)
    local o = setmetatable({ def = def, prefix = def.prefix, inbox = {}, seenQ = {}, seenD = {},
                             asked = {}, pushedAt = -1e9, nonce = nil }, Shared)
    return o
end

function Shared:Store() return self.def.store() end

local function now() return ns.Now() end
local function key(self, kind, x) return self.prefix .. ":" .. kind .. ":" .. (x or "") end

-- ---------------------------------------------------------------------
-- Start-up
-- ---------------------------------------------------------------------
function Shared:Init()
    ns.Listen(self.prefix, "guild", function(msg, sender) self:OnMessage(msg, sender) end)
    self:Prune()
    self:Refresh(true)
    -- say hello once the guild channel is up (it can take a while after login)
    local tries = 0
    local function hello()
        tries = tries + 1
        if ns.DataChannel() then
            C_Timer.After(10 + math.random() * 30, function() self:Hello() end)
        elseif tries < 20 then
            C_Timer.After(15, hello)
        end
    end
    C_Timer.After(5, hello)
end

function Shared:Prune()
    local cut = now() - KEEP_DAYS * DAY
    for owner, e in pairs(self:Store()) do
        if type(e) ~= "table" or (owner ~= ns.me and (e.t or 0) < cut) then self:Store()[owner] = nil end
    end
end

-- ---------------------------------------------------------------------
-- Your own list
-- ---------------------------------------------------------------------
-- Rebuild your entry from def.mine(). A change goes out (once) PUSH_DELAY
-- seconds after the last one. quiet: only update, never send (start-up).
function Shared:Refresh(quiet)
    local p = self.def.mine() or ""
    if self.def.max and #p > self.def.max then p = p:sub(1, self.def.max):gsub("[^,;]*$", "") end
    local store, h = self:Store(), Shared.Hash(p)
    local cur = store[ns.me]
    if cur and cur.h == h then return false end
    if p == "" and not cur then return false end
    store[ns.me] = { t = now(), h = h, p = p }
    if self.def.changed then self.def.changed(ns.me) end
    if not quiet then
        ns.Debounce(key(self, "push"), PUSH_DELAY, function() self:Push(true) end)
    end
    return true
end

function Shared:Hello()
    local e = self:Store()[ns.me]
    if not e or e.p == "" then return end
    ns.BulkDrop(key(self, "hello"))
    ns.BulkSend(self.prefix, ns.Join("H", e.h, e.t), key(self, "hello"))
end

-- queue owner's list (yours, or a copy you hold) as D parts
function Shared:Send(owner)
    local e = self:Store()[owner]
    if not e then return false end
    local k = key(self, "D", owner)
    ns.BulkDrop(k)                                -- a newer copy replaces one still waiting
    local parts = ns.Chunks(e.p or "", CHUNK)
    for i, chunk in ipairs(parts) do
        ns.BulkSend(self.prefix, ns.Join("D", owner, e.t, e.h, i, #parts, chunk), k)
    end
    return true
end

-- your list to the guild (at most once a minute unless it changed)
function Shared:Push(changed)
    if not changed and GetTime() - self.pushedAt < 60 then return end
    self.pushedAt = GetTime()
    self:Send(ns.me)
end

-- ---------------------------------------------------------------------
-- Catch-up (the first time a window opens, then at most twice an hour)
-- ---------------------------------------------------------------------
function Shared:CatchUp()
    if not ns.DataChannel() then return false end
    if self.caughtAt and GetTime() - self.caughtAt < 1800 then return false end
    self.caughtAt = GetTime()
    self.nonce = ("%s%d"):format(ns.Short(ns.me or "x"):sub(1, 6), math.random(100000, 999999))
    ns.BulkSend(self.prefix, ns.Join("W", self.nonce), key(self, "W"))
    return true
end

-- every list you hold, as owner:hash:t;...
function Shared:Digest()
    local out = {}
    for owner, e in pairs(self:Store()) do
        if e.p and e.p ~= "" then out[#out + 1] = owner .. ":" .. e.h .. ":" .. (e.t or 0) end
    end
    table.sort(out)
    return table.concat(out, ";")
end

-- owners whose lists you're missing or have an older copy of, asked for
-- in as few Q messages as fit
function Shared:Ask(owners)
    local store, list, len = self:Store(), {}, 0
    local function flush()
        if #list == 0 then return end
        ns.BulkSend(self.prefix, ns.Join("Q", table.concat(list, ",")), key(self, "Q"))
        list, len = {}, 0
    end
    for _, owner in ipairs(owners) do
        if owner ~= ns.me and not (store[owner] and self.asked[owner] and GetTime() - self.asked[owner] < 300) then
            self.asked[owner] = GetTime()
            if len + #owner > 200 then flush() end
            list[#list + 1] = owner
            len = len + #owner + 1
        end
    end
    flush()
end

-- ---------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------
local function int(v, lo, hi)
    local n = tonumber(v)
    if n and n == n and n % 1 == 0 and n >= lo and n <= hi then return n end
end

local function validOwner(s) return type(s) == "string" and s:match("^[^%-,;:%s|]+%-[^,;:%s|]+$") ~= nil and #s <= 60 end

function Shared:OnMessage(msg, sender)
    local f = ns.Split(msg, "^")
    local kind = f[1]
    local store = self:Store()
    if kind == "H" then
        local h, t = f[2], int(f[3], 0, now() + DAY)
        if not h or h == "" or not t then return end
        local e = store[sender]
        -- (a copy someone else gave us doesn't outrank the owner's own word)
        if e and (e.h == h or ((e.t or 0) >= t and not e.via)) then return end
        -- someone else will probably ask: wait a moment, then ask only if nobody has
        local heard = GetTime()
        C_Timer.After(1 + math.random() * 5, function()
            if (self.seenQ[sender] or 0) >= heard or (self.seenD[sender] or 0) >= heard then return end
            local cur = store[sender]
            if cur and cur.h == h then return end
            self:Ask({ sender })
        end)
    elseif kind == "Q" then
        local heard = GetTime()
        for _, owner in ipairs(ns.Split(f[2] or "", ",")) do
            if validOwner(owner) then
                self.seenQ[owner] = heard
                if owner == ns.me then
                    self:Push(false)
                elseif store[owner] and store[owner].p ~= "" then
                    -- a copy: only if the owner hasn't answered and nobody else has
                    C_Timer.After(5 + math.random() * 8, function()
                        if (self.seenD[owner] or 0) >= heard then return end
                        if ns.BulkQueued(key(self, "D", owner)) > 0 then return end
                        self.seenD[owner] = GetTime()
                        self:Send(owner)
                    end)
                end
            end
        end
    elseif kind == "D" then
        local owner, t, h = f[2], int(f[3], 0, now() + DAY), f[4]
        if not (validOwner(owner) and t and h and h ~= "") then return end
        if owner == ns.me then return end                 -- your own list is yours
        if sender ~= owner and t > now() + 300 then return end   -- a copy dated in the future would stick
        self.seenD[owner] = GetTime()
        -- someone else is already sending this list: drop our copy
        if sender ~= ns.me and ns.BulkQueued(key(self, "D", owner)) > 0 then ns.BulkDrop(key(self, "D", owner)) end
        local whole = ns.Reassemble(self.inbox, owner .. ":" .. h, f[5], f[6], f[7] or "", 60)
        if not whole then return end
        if Shared.Hash(whole) ~= h then return end
        local e = store[owner]
        -- the owner's own word always counts; a copy only if it's newer
        if e and sender ~= owner and (e.t or 0) >= t then return end
        if e and e.h == h then e.t = math.max(e.t or 0, t) return end
        if whole == "" then store[owner] = nil
        else store[owner] = { t = t, h = h, p = whole, via = sender ~= owner and sender or nil } end
        if self.def.changed then self.def.changed(owner) end
    elseif kind == "W" then
        local nonce = f[2]
        if not nonce or nonce == "" or not next(store) then return end
        self.seenL = self.seenL or {}
        C_Timer.After(2 + math.random() * 8, function()
            -- (paused: it would go out long after they stopped listening)
            if self.seenL[nonce] or ns.BulkPaused() then return end
            self.seenL[nonce] = true
            local parts = ns.Chunks(self:Digest(), CHUNK + 20)
            self.lParts = self.lParts or {}
            self.lParts[nonce] = #parts
            for i, chunk in ipairs(parts) do ns.BulkSend(self.prefix, ns.Join("L", nonce, i, #parts, chunk), key(self, "L", nonce)) end
        end)
    elseif kind == "L" then
        local nonce = f[2]
        if not nonce then return end
        self.seenL = self.seenL or {}
        self.seenL[nonce] = true
        -- someone else is answering: drop ours if none of it has gone out yet
        local mine = self.lParts and self.lParts[nonce]
        if mine and ns.BulkQueued(key(self, "L", nonce)) >= mine then ns.BulkDrop(key(self, "L", nonce)) end
        if nonce ~= self.nonce then return end
        local whole = ns.Reassemble(self.inbox, "L:" .. nonce .. ":" .. sender, f[3], f[4], f[5] or "", 60)
        if not whole then return end
        self.nonce = nil
        local want = {}
        for _, item in ipairs(ns.Split(whole, ";")) do
            local owner, h, t = item:match("^(.-):(%x+):(%d+)$")
            t = tonumber(t)
            if owner and validOwner(owner) and owner ~= ns.me then
                local e = store[owner]
                if not e or (e.h ~= h and (e.t or 0) < t) then want[#want + 1] = owner end
            end
        end
        self:Ask(want)
    end
end

-- ---------------------------------------------------------------------
-- Compact numbers for lists: base 36, sorted IDs as gaps ("1a,3,b")
-- ---------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function Shared.B36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

function Shared.FromB36(s) return tonumber(s, 36) end

function Shared.PackIds(ids)
    table.sort(ids)
    local out, last = {}, 0
    for _, id in ipairs(ids) do
        if id > last then out[#out + 1] = Shared.B36(id - last); last = id end
    end
    return table.concat(out, ",")
end

function Shared.UnpackIds(s)
    local out, last = {}, 0
    for part in (s or ""):gmatch("[^,]+") do
        local d = tonumber(part, 36)
        if not d then break end
        last = last + d
        out[#out + 1] = last
    end
    return out
end

-- ---------------------------------------------------------------------
-- Shift-clicking an item into one of our boxes: the game hands the link to
-- the chat box; when one of ours has the focus, it gets the link instead
-- (only watched, Blizzard's function isn't changed).
-- ---------------------------------------------------------------------
local linkBoxes = {}
local hooked = false
function ns.AcceptLinks(box, onLink)
    linkBoxes[#linkBoxes + 1] = { box = box, fn = onLink }
    if hooked or not hooksecurefunc then return end
    hooked = true
    local function got(link)
        if type(link) ~= "string" then return end
        for _, b in ipairs(linkBoxes) do
            if b.box:HasFocus() then
                if b.fn then b.fn(link) else b.box:SetText(link) end
                return
            end
        end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", got) end
    if ChatEdit_InsertLink then pcall(hooksecurefunc, "ChatEdit_InsertLink", got) end
end
