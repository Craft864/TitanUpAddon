-- Titan Up - Chess/Chess.lua
-- Chess between two guildmates, saved until the game ends.
--
--   * Each game is saved on your character (TitanUpDB.chess.games) until
--     it's won, drawn or resigned - through /reload, logout and patches.
--     You can have several games going, each against a different guildmate
--     or the same one.
--   * Both online: moves go straight over the guild's addon channel.
--   * Not online together: guild couriers. Everything goes over the guild
--     channel, so every guildmate running Titan Up quietly keeps a copy of
--     other people's games (TitanUpDB.chess.carry, a few hundred bytes
--     each). When a player logs in, they say which games they have and how
--     far along (H); whoever holds a newer copy - the opponent, or any
--     courier - sends it (S). Couriers wait a moment first so the opponent
--     (or one courier) answers and the rest stay quiet.
--   * Honesty: every client checks every move against the full rules
--     (Rules.lua), so an illegal move is never accepted. Moves are only ever
--     added. A courier could in theory hand over a made-up (legal) move;
--     your own moves always win over anyone else's copy, and your
--     opponent's moves are only replaced by your opponent, so when the two
--     of you next meet (or one's game reaches the other), a made-up move
--     is rolled back and the courier who delivered it is named.
--   * Timers (0.35.0, chosen with the challenge, none by default):
--     days per move - your opponent can claim the win once your time for a
--     move has run out (moves carry the time they were made, so this works
--     through couriers); live clock - minutes each, ticking only while both
--     players are online (it pauses when either logs off). Your own client
--     ends the game when your own clock runs out; a mover's reported clock
--     is never believed above what the opponent measured (plus 5 s).
--
-- Messages ("TitanUpCH", fields joined by ^; ids start with the challenger's
-- name, like Death Roll rooms):
--   C id white black timer    challenge (sender = the challenger, one of the two)
--                             timer (0.35.0): "" none, d1/d3/d7 days per move, l5/l10/l30 live minutes each
--   A id at                   accept (from the challenged player; at = server time, 0.35.0)
--   D id                      decline (challenged) / cancel (challenger) an open challenge
--   M id n move at clock      move number n (1 = White's first), UCI ("e2e4", "e7e8q");
--                             at = server time of the move, clock = the mover's seconds left (live clock) (0.35.0)
--   E id kind n               kind: R resign, O offer a draw, Y accept the draw, T claim a win on time,
--                             F out of time (the sender lost) (n = moves so far)
--   H entries                 "here are my games": id:n:hash:state,... (state i/a/o)
--   S id white black by state result reason moves timer times start clocks
--                             a whole game (moves comma-separated; 0.35.0 adds the timer, each move's
--                             time, when the game started and the live clocks "white:black")
--   U key part n chunk        an S too long for one message, in parts
local ADDON, ns = ...

local CH = {}
ns.Chess = CH

local R = ns.ChessRules         -- (Rules.lua loads first)
local PREFIX = "TitanUpCH"
CH.PREFIX = PREFIX
CH.MAX_GAMES = 20               -- games in progress (yours)
CH.KEEP_OVER = 20               -- finished games kept in your list
CH.CARRY_MAX = 60               -- other people's games a courier holds
CH.OVER_DAYS = 3                -- couriers deliver a finished game's result this long
local DAY = 86400

local RANK = { invited = 1, active = 2, over = 3 }
local STATE_CODE = { invited = "i", active = "a", over = "o" }
local CODE_STATE = { i = "invited", a = "active", o = "over" }
local RULE_END = { mate = true, stalemate = true, repetition = true, fifty = true, material = true }
local OTHER_END = { resign = true, agreed = true, declined = true, cancelled = true, time = true }

-- Timers offered with a challenge (code, label). "" = none (the default).
CH.TIMERS = {
    { "", "No timer" },
    { "d1", "1 day per move" }, { "d3", "3 days per move" }, { "d7", "7 days per move" },
    { "l5", "Live clock: 5 min each" }, { "l10", "Live clock: 10 min each" }, { "l30", "Live clock: 30 min each" },
}
local TIMER_OK = {}
for _, t in ipairs(CH.TIMERS) do TIMER_OK[t[1]] = t[2] end
CH.TIMER_LABEL = TIMER_OK
CH.CLAIM_GRACE = 3600           -- days per move: a claim is accepted up to an hour early (clock differences)
CH.KNOWN_DAYS = 30              -- guildmates with Chess are remembered this long

CH.live = {}                    -- id -> the rules game (positions), built when needed
CH.pending = {}                 -- id -> a courier's queued delivery
CH.lastS = {}                   -- id -> { at, n } the last full game we sent
CH.lastHello = {}               -- sender -> when we last answered their hello with ours
CH.inbox = {}                   -- S messages arriving in parts

local function db() return ns.udb.chess end

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- djb2 over the move text: lets two clients compare games in a few bytes
function CH.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return ("%x"):format(h)
end

local function split(moves)
    local t = {}
    if moves and moves ~= "" then
        for m in moves:gmatch("[^,]+") do t[#t + 1] = m end
    end
    return t
end
CH.SplitMoves = split

local function count(moves) return #split(moves) end

local function prefixText(list, n) return table.concat(list, ",", 1, n) end

local function validName(n) return type(n) == "string" and #n <= 64 and n:match("^[^%-%^,:|]+%-[^%^,:|]+$") ~= nil end

-- An id is "<challenger>-<number>".
local function validId(id, by)
    if type(id) ~= "string" or #id > 80 or id:find("[%^,:|]") then return false end
    if not id:match("%-%d+$") then return false end
    return by == nil or id:sub(1, #ns.Short(by) + 1) == ns.Short(by) .. "-"
end

function CH:IsPlayer(g, name) name = name or ns.me return g.w == name or g.b == name end
function CH:Opponent(g) return g.w == ns.me and g.b or g.w end
function CH:ColorOf(g, name) name = name or ns.me return g.w == name and "w" or (g.b == name and "b" or nil) end

-- Who moves next: White when an even number of moves have been made.
function CH:ToMove(g)
    local n = count(g.moves)
    return (n % 2 == 0) and "w" or "b", (n % 2 == 0) and g.w or g.b
end

-- The mover of move number i.
local function moverOf(g, i) return (i % 2 == 1) and g.w or g.b end

-- Waiting on you: your move, or a challenge to answer.
function CH:NeedsMe(g)
    if g.status == "active" then return select(2, self:ToMove(g)) == ns.me end
    return g.status == "invited" and g.by ~= ns.me
end

-- The rules game for a saved game (replayed once, then kept up to date).
function CH:Live(g)
    local lg = self.live[g.id]
    if lg and lg.text == g.moves then return lg.game end
    local game = R.Play(split(g.moves))
    if not game then game = R.Begin() end        -- (a saved game is always legal; never seen)
    self.live[g.id] = { text = g.moves, game = game }
    return game
end

-- Your games, the ones waiting on you first, finished ones last.
function CH:Games()
    local out = {}
    for _, g in pairs(db().games) do
        if self:IsPlayer(g) then out[#out + 1] = g end
    end
    local function key(g)
        if self:NeedsMe(g) then return 1 end
        if g.status ~= "over" then return 2 end
        return 3
    end
    table.sort(out, function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then return ka < kb end
        if (a.updated or 0) ~= (b.updated or 0) then return (a.updated or 0) > (b.updated or 0) end
        return a.id < b.id
    end)
    return out
end

function CH:WaitingCount()
    local n = 0
    for _, g in pairs(db().games) do if self:IsPlayer(g) and self:NeedsMe(g) then n = n + 1 end end
    return n
end

function CH:Get(id) return db().games[id] end

-- ---------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------
-- "days", n | "live", minutes | nil
function CH:Timer(g)
    local kind, n = (g.tc or ""):match("^([dl])(%d+)$")
    if not kind then return nil end
    return kind == "d" and "days" or "live", tonumber(n)
end

local function clampTime(v, lo)
    v = tonumber(v)
    local now = ns.Now()
    if not v or v ~= v or v > now + 60 then v = now end
    if lo and v < lo then v = lo end
    return math.floor(v)
end

-- When the side to move's time started: the last move, or the start of the game.
function CH:TurnStart(g)
    local n = count(g.moves)
    return (n > 0 and g.at and g.at[n]) or g.startAt or g.updated or ns.Now()
end

-- Days per move: seconds the side to move has left (negative = out of time).
function CH:DaysLeft(g)
    local kind, days = self:Timer(g)
    if kind ~= "days" then return nil end
    return self:TurnStart(g) + days * DAY - ns.Now()
end

-- Live clock: seconds `color` has left.
function CH:ClockLeft(g, color)
    local kind, mins = self:Timer(g)
    if kind ~= "live" then return nil end
    g.clk = g.clk or { w = mins * 60, b = mins * 60 }
    local left = g.clk[color] or mins * 60
    if g.status == "active" and self:ToMove(g) == color then left = left - (g.run or 0) end
    return left
end

-- The opponent is out of time and you can claim the win.
function CH:CanClaimTime(g)
    if g.status ~= "active" or self:NeedsMe(g) then return false end
    local kind = self:Timer(g)
    if kind == "days" then return self:DaysLeft(g) < 0 end
    if kind == "live" then return self:ClockLeft(g, self:ToMove(g)) <= -10 end
    return false
end

-- Guildmates heard running Titan Up 0.34.0+ (any chess message), newest first.
function CH:KnownPlayers()
    local out = {}
    local r = self:Roster()
    for name, at in pairs(db().known or {}) do
        if name ~= ns.me and (not r.loaded or r.inGuild[name]) then
            out[#out + 1] = { name = name, at = at, online = self:IsOnline(name) == true, class = r.class[name] }
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.at ~= b.at then return a.at > b.at end
        return a.name < b.name
    end)
    return out
end

-- ---------------------------------------------------------------------
-- Guild roster: names and who's online
-- ---------------------------------------------------------------------
function CH:Roster()
    local now = GetTime()
    if self.roster and now - self.roster.at < 10 then return self.roster end
    local r = { at = now, online = {}, list = {}, class = {}, inGuild = {} }
    if GetNumGuildMembers and GetGuildRosterInfo then
        local ok, total = pcall(GetNumGuildMembers)
        if ok and type(total) == "number" and not ns.IsSecret(total) then
            for i = 1, total do
                local ok2, name, _, _, _, _, _, _, _, online, _, class = pcall(GetGuildRosterInfo, i)
                if ok2 and type(name) == "string" and not ns.IsSecret(name) then
                    name = ns.NormalizeSender(name)
                    if name then
                        r.list[#r.list + 1] = name
                        r.inGuild[name] = true
                        if type(class) == "string" and not ns.IsSecret(class) then r.class[name] = class end
                        if online and not ns.IsSecret(online) then r.online[name] = true end
                    end
                end
            end
        end
    end
    r.loaded = #r.list > 0
    self.roster = r
    return r
end

-- true / false, or nil when the roster isn't known
function CH:IsOnline(name)
    if self.heard and self.heard[name] and GetTime() - self.heard[name] < 120 then return true end
    local r = self:Roster()
    if not r.loaded then return nil end
    return r.online[name] == true
end

-- What a player typed -> a guildmate's full name, or nil + why not.
function CH:ResolveName(text)
    text = tostring(text or ""):gsub("[%s%^,:|]", "")
    if text == "" then return nil, "Type a guildmate's name." end
    local r = self:Roster()
    if r.loaded then
        local want = text:lower()
        local exact, matches = nil, {}
        for _, n in ipairs(r.list) do
            if n:lower() == want then exact = n end
            if ns.Short(n):lower() == want then matches[#matches + 1] = n end
        end
        if exact then return exact end
        if #matches == 1 then return matches[1] end
        if #matches > 1 then return nil, "More than one guildmate is called that - add their realm (Name-Realm)." end
        return nil, text .. " isn't in your guild."
    end
    local full = ns.NormalizeSender(text)
    if not full then return nil, "Type a guildmate's name." end
    -- first letter capitalised, like the game's own names
    full = full:gsub("^(%l)", string.upper)
    return full
end

-- ---------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------
local function touch(g) g.updated = ns.Now() end

local function finish(g, result, reason)
    g.status, g.result, g.reason = "over", result, reason
    g.offer = nil
    touch(g)
end

-- The rules ended the game (mate, stalemate, draws)?
local function checkEnd(g)
    if g.status ~= "active" then return end
    local game = CH:Live(g)
    if game.over then finish(g, game.winner or "d", game.over) end
end

-- Old finished games drop off the list; so do old courier copies.
function CH:Prune()
    local now = ns.Now()
    local over = {}
    for id, g in pairs(db().games) do
        if g.status == "over" then over[#over + 1] = g end
        -- a challenge nobody answered for 30 days
        if g.status == "invited" and now - (g.updated or 0) > 30 * DAY then db().games[id] = nil end
    end
    table.sort(over, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    for i = self.KEEP_OVER + 1, #over do db().games[over[i].id] = nil end
    db().known = db().known or {}
    for name, at in pairs(db().known) do
        if now - (tonumber(at) or 0) > self.KNOWN_DAYS * DAY then db().known[name] = nil end
    end
    local carry, list = db().carry, {}
    for id, c in pairs(carry) do
        local age = now - (c.updated or 0)
        if (c.status == "over" and age > self.OVER_DAYS * DAY) or age > 60 * DAY then carry[id] = nil
        else list[#list + 1] = c end
    end
    if #list > self.CARRY_MAX then
        table.sort(list, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
        for i = self.CARRY_MAX + 1, #list do carry[list[i].id] = nil end
    end
end

local function changed(g, what)
    CH:Prune()
    if ns.ChessUI then ns.ChessUI:OnChange(g, what) end
    if ns.Nav and ns.Nav.RefreshChrome then ns.Nav:RefreshChrome() end
end

-- ---------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------
function CH:Send(...) return ns.SendFields(PREFIX, ...) end

-- The timer fields of an S: timer, move times, start, clocks.
function CH:TimerFields(g)
    if not self:Timer(g) then return "" end
    local times = {}
    for i = 1, count(g.moves) do times[i] = tostring((g.at and g.at[i]) or 0) end
    local clk = ""
    if g.clk then clk = ("%d:%d"):format(math.floor(g.clk.w or 0), math.floor(g.clk.b or 0)) end
    return g.tc, table.concat(times, ","), tostring(g.startAt or 0), clk
end

-- A whole game: one message, or parts when it's long.
function CH:SendState(g, force)
    local n = count(g.moves)
    local last = self.lastS[g.id]
    if not force and last and last.n == n and last.status == g.status and GetTime() - last.at < 10 then return end
    self.lastS[g.id] = { at = GetTime(), n = n, status = g.status }
    local msg = ns.Join("S", g.id, g.w, g.b, g.by, STATE_CODE[g.status] or "a", g.result or "", g.reason or "", g.moves or "",
        self:TimerFields(g))
    if #msg <= 250 then
        ns.Send(PREFIX, msg, ns.DataChannel())
        return
    end
    local key = math.random(1, 999999)
    local parts = ns.Chunks(msg, 200)
    for i, chunk in ipairs(parts) do self:Send("U", key, i, #parts, chunk) end
end

-- "Here are my games": sent at login, when the window opens, and in reply
-- to a player whose games are behind or ahead of ours.
function CH:Hello(force)
    if not ns.DataChannel() then return end
    local now = GetTime()
    if not force and self.helloAt and now - self.helloAt < 30 then return end
    self.helloAt = now
    local entries = {}
    for _, g in pairs(db().games) do
        if self:IsPlayer(g) and (g.status ~= "over" or ns.Now() - (g.updated or 0) < self.OVER_DAYS * DAY) then
            local list = split(g.moves)
            entries[#entries + 1] = ("%s:%d:%s:%s"):format(g.id, #list, CH.Hash(g.moves or ""), STATE_CODE[g.status] or "a")
        end
    end
    -- a few games per message (one empty hello when there are none)
    local i = 1
    repeat
        local batch = {}
        local len = 0
        while entries[i] and (#batch == 0 or len + #entries[i] < 220) do
            batch[#batch + 1] = entries[i]
            len = len + #entries[i] + 1
            i = i + 1
        end
        self:Send("H", table.concat(batch, ","))
    until not entries[i]
end

-- ---------------------------------------------------------------------
-- What you do
-- ---------------------------------------------------------------------
function CH:Challenge(text, tc)
    if not ns.DataChannel() then return false, ns.NEEDS_GUILD end
    local name, err = self:ResolveName(text)
    if not name then return false, err end
    if name == ns.me then return false, "You can't challenge yourself." end
    local active = 0
    for _, g in pairs(db().games) do if self:IsPlayer(g) and g.status ~= "over" then active = active + 1 end end
    if active >= self.MAX_GAMES then return false, ("You already have %d games going - finish one first."):format(active) end
    local id = ("%s-%d%02d"):format(ns.Short(ns.me), ns.Now(), math.random(0, 99))
    local white = math.random(2) == 1
    tc = TIMER_OK[tc or ""] and tc or ""
    local g = { id = id, w = white and ns.me or name, b = white and name or ns.me, by = ns.me,
                status = "invited", moves = "", created = ns.Now(), via = {} }
    if tc ~= "" then g.tc, g.at = tc, {} end
    touch(g)
    db().games[id] = g
    if tc ~= "" then self:Send("C", id, g.w, g.b, tc) else self:Send("C", id, g.w, g.b) end
    changed(g, "new")
    return true, g
end

function CH:Accept(id)
    local g = self:Get(id)
    if not g or g.status ~= "invited" or g.by == ns.me then return false end
    g.status = "active"
    g.startAt = ns.Now()
    touch(g)
    if g.tc then self:Send("A", id, g.startAt) else self:Send("A", id) end
    changed(g, "state")
    return true
end

-- Decline a challenge to you, or take back your own.
function CH:Decline(id)
    local g = self:Get(id)
    if not g or g.status ~= "invited" then return false end
    finish(g, nil, g.by == ns.me and "cancelled" or "declined")
    self:Send("D", id)
    changed(g, "state")
    return true
end

function CH:Move(id, uci)
    local g = self:Get(id)
    if not g or g.status ~= "active" then return false, "This game isn't in progress." end
    local _, who = self:ToMove(g)
    if who ~= ns.me then return false, "It's not your move." end
    local game = self:Live(g)
    if not R.Step(game, uci) then return false, "That move isn't legal." end
    local list = split(g.moves)
    list[#list + 1] = uci
    g.moves = table.concat(list, ",")
    self.live[g.id].text = g.moves
    g.offer = nil
    touch(g)
    -- timers: when it was made, and our clock
    local clock
    if self:Timer(g) then
        g.at = g.at or {}
        g.at[#list] = ns.Now()
        local kind = self:Timer(g)
        if kind == "live" then
            local mine = self:ColorOf(g)
            -- (ToMove has already moved on: take our time from before the move)
            self:ClockLeft(g, mine)
            g.clk[mine] = math.max(0, (g.clk[mine] or 0) - (g.run or 0))
            g.run = 0
            self:PauseForSlide(g)
            clock = math.floor(g.clk[mine])
        end
    end
    if g.tc then self:Send("M", id, #list, uci, g.at[#list], clock)
    else self:Send("M", id, #list, uci) end
    checkEnd(g)
    changed(g, "move")
    return true
end

-- Your opponent ran out of time: claim the win.
function CH:ClaimTime(id)
    local g = self:Get(id)
    if not g or not self:CanClaimTime(g) then return false end
    finish(g, self:ColorOf(g), "time")
    self:Send("E", id, "T", count(g.moves))
    changed(g, "state")
    return true
end

function CH:Resign(id)
    local g = self:Get(id)
    if not g or g.status ~= "active" then return false end
    local mine = self:ColorOf(g)
    finish(g, mine == "w" and "b" or "w", "resign")
    self:Send("E", id, "R", count(g.moves))
    changed(g, "state")
    return true
end

function CH:OfferDraw(id)
    local g = self:Get(id)
    if not g or g.status ~= "active" then return false end
    local n = count(g.moves)
    g.offer = { by = ns.me, n = n }
    self:Send("E", id, "O", n)
    changed(g, "offer")
    return true
end

function CH:AcceptDraw(id)
    local g = self:Get(id)
    local n = g and count(g.moves)
    if not g or g.status ~= "active" or not g.offer or g.offer.by == ns.me or g.offer.n ~= n then return false end
    finish(g, "d", "agreed")
    self:Send("E", id, "Y", n)
    changed(g, "state")
    return true
end

-- Take a finished game off your list.
function CH:Remove(id)
    local g = self:Get(id)
    if not g or g.status ~= "over" then return false end
    db().games[id] = nil
    self.live[id] = nil
    changed(nil, "removed")
    return true
end

-- ---------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------
local function notify(text, g)
    ns.Print("|cff4fc2f7Chess:|r " .. text)
    local UIv = ns.ChessUI
    if UIv and not UIv:IsShown() and ns.Dock and ns.Dock.Notice then
        ns.Dock:Notice(text, "Open", function() UIv:Open(g and g.id) end)
    end
end

-- A courier's copy of someone else's game.
local function carryCopy(id) return db().carry[id] end

local function storeCarry(t)
    local c = db().carry[t.id] or {}
    for _, k in ipairs({ "id", "w", "b", "by", "status", "result", "reason", "moves", "offer", "tc", "at", "startAt", "clk", "created" }) do c[k] = t[k] end
    c.updated = ns.Now()
    db().carry[t.id] = c
    -- something newer went past: a queued delivery of an older copy isn't needed
    local p = CH.pending[t.id]
    if p and count(t.moves) >= p.n and (RANK[t.status] or 0) >= p.rank then CH.pending[t.id] = nil end
end

function CH:OnMessage(msg, sender)
    self.heard = self.heard or {}
    self.heard[sender] = GetTime()
    db().known = db().known or {}
    db().known[sender] = ns.Now()                    -- has Chess: offered in the challenge list
    local f = ns.Split(msg, "^")
    local kind = f[1]
    if kind == "C" then self:OnChallenge(f[2], f[3], f[4], sender, f[5])
    elseif kind == "A" or kind == "D" then self:OnAnswer(kind, f[2], sender, f[3])
    elseif kind == "M" then self:OnMove(f[2], tonumber(f[3]), f[4], sender, f[5], f[6])
    elseif kind == "E" then self:OnEnd(f[2], f[3], tonumber(f[4]), sender)
    elseif kind == "H" then self:OnHello(f[2] or "", sender)
    elseif kind == "S" then self:OnState(f, sender)
    elseif kind == "U" then
        -- (the chunk itself holds ^ separators: take everything after the 4th)
        local key, part, n, chunk = msg:match("^U%^([^%^]*)%^([^%^]*)%^([^%^]*)%^(.*)$")
        if not key then return end
        local whole = ns.Reassemble(self.inbox, sender .. "|" .. key, part, n, chunk, 40)
        if whole then
            local s = ns.Split(whole, "^")
            if s[1] == "S" then self:OnState(s, sender) end
        end
    end
end

function CH:OnChallenge(id, w, b, sender, tc)
    if not (validName(w) and validName(b)) or w == b then return end
    if sender ~= w and sender ~= b then return end
    if not validId(id, sender) then return end
    local t = { id = id, w = w, b = b, by = sender, status = "invited", moves = "" }
    if tc and tc ~= "" and TIMER_OK[tc] then t.tc, t.at = tc, {} end
    local target = (sender == w) and b or w
    if target == ns.me then
        if db().games[id] then return end
        t.created, t.via = ns.Now(), {}
        touch(t)
        db().games[id] = t
        notify(("%s challenged you to a game of chess%s."):format(ns.Short(sender), t.tc and (" (" .. TIMER_OK[t.tc] .. ")") or ""), t)
        changed(t, "new")
    elseif not db().games[id] and not carryCopy(id) then
        storeCarry(t)
    end
end

function CH:OnAnswer(kind, id, sender, at)
    local g = self:Get(id)
    local mine = g and self:IsPlayer(g)
    local t = mine and g or carryCopy(id)
    if not t or t.status ~= "invited" or not self:IsPlayer(t, sender) then return end
    if kind == "A" then
        if sender == t.by then return end                -- only the challenged player accepts
        t.status = "active"
        t.startAt = clampTime(at, t.created)
        touch(t)
        if mine then notify(("%s accepted your challenge. %s"):format(ns.Short(sender),
            self:ColorOf(g) == "w" and "You play White - your move." or "You play Black."), g) end
    else
        finish(t, nil, sender == t.by and "cancelled" or "declined")
        if mine then notify(sender == t.by and ("%s took back their challenge."):format(ns.Short(sender))
            or ("%s declined your challenge."):format(ns.Short(sender)), g) end
    end
    if mine then changed(g, "state") else storeCarry(t) end
end

-- The timers of a move that arrived: when it was made, and the mover's clock
-- (never more than we measured for them, plus 5 seconds for the message).
function CH:TimeMove(g, n, at, clock)
    if not self:Timer(g) then return end
    g.at = g.at or {}
    g.at[n] = clampTime(at, (n > 1 and g.at[n - 1]) or g.startAt)
    if self:Timer(g) == "live" then
        local color = (n % 2 == 1) and "w" or "b"
        self:ClockLeft(g, color)                      -- (sets the clocks up if needed)
        local measured = math.max(0, g.clk[color] - (g.run or 0))
        local claimed = tonumber(clock)
        if not claimed or claimed ~= claimed then claimed = measured end
        g.clk = g.clk or {}
        g.clk[color] = math.max(0, math.min(claimed, measured + 5))
        g.run = 0
        self:PauseForSlide(g)
    end
end

function CH:OnMove(id, n, uci, sender, at, clock)
    if not n or type(uci) ~= "string" or #uci < 4 or #uci > 5 then return end
    local g = self:Get(id)
    if g and self:IsPlayer(g) then
        if g.status ~= "active" or self:Opponent(g) ~= sender then return end
        local list = split(g.moves)
        if n == #list and list[n] == uci then return end             -- already have it
        if n > #list + 1 then self:AnswerHello(sender, true) return end  -- we missed some: ask
        if n ~= #list + 1 or moverOf(g, n) ~= sender then return end
        local game = self:Live(g)
        if not R.Step(game, uci) then return end
        list[n] = uci
        g.moves = table.concat(list, ",")
        self.live[g.id].text = g.moves
        if g.via then g.via[n] = nil end
        g.offer = nil
        self:TimeMove(g, n, at, clock)
        touch(g)
        checkEnd(g)
        if g.status == "over" then
            notify(self:EndText(g), g)
        elseif ns.ChessUI and not ns.ChessUI:IsShown() then
            ns.Print(("|cff4fc2f7Chess:|r %s played %s - your move."):format(ns.Short(sender), game.san[n] or uci))
            ns.ChessUI:FlashRail()
        end
        changed(g, "move")
        return
    end
    -- courier: keep the copy current
    local c = carryCopy(id)
    if not c or c.status ~= "active" or not self:IsPlayer(c, sender) then return end
    local list = split(c.moves)
    if n ~= #list + 1 or moverOf(c, n) ~= sender then return end
    local game = self:Live(c)
    if not R.Step(game, uci) then return end
    list[n] = uci
    c.moves = table.concat(list, ",")
    self.live[c.id].text = c.moves
    c.offer = nil
    self:TimeMove(c, n, at, clock)
    if game.over then finish(c, game.winner or "d", game.over) end
    storeCarry(c)
end

function CH:OnEnd(id, kind, n, sender)
    local g = self:Get(id)
    local mine = g and self:IsPlayer(g)
    local t = mine and g or carryCopy(id)
    if not t or t.status ~= "active" or not self:IsPlayer(t, sender) or not n then return end
    if mine and sender ~= self:Opponent(g) then return end
    local moves = count(t.moves)
    if kind == "R" then
        finish(t, self:ColorOf(t, sender) == "w" and "b" or "w", "resign")
        if mine then notify(("%s resigned. You win!"):format(ns.Short(sender)), g) end
    elseif kind == "O" then
        if n ~= moves then return end
        t.offer = { by = sender, n = n }
        if mine then notify(("%s offers a draw."):format(ns.Short(sender)), g) end
    elseif kind == "Y" then
        if not (t.offer and t.offer.n == n and n == moves and t.offer.by ~= sender) then return end
        finish(t, "d", "agreed")
        if mine then notify(("%s accepted your draw offer."):format(ns.Short(sender)), g) end
    elseif kind == "T" or kind == "F" then
        -- T: the sender claims the win on time; F: the sender's own clock ran out
        local tk = self:Timer(t)
        if not tk or n ~= moves then return end
        local senderColor = self:ColorOf(t, sender)
        local loser = (kind == "F") and senderColor or (senderColor == "w" and "b" or "w")
        if kind == "T" then
            if self:ToMove(t) ~= loser then return end
            -- only when the loser really is out of time, as far as we can tell
            if tk == "days" and self:DaysLeft(t) > self.CLAIM_GRACE then return end
            if tk == "live" and mine and self:ClockLeft(t, loser) > 15 then return end
        end
        finish(t, loser == "w" and "b" or "w", "time")
        if mine then notify(self:EndText(g), g) end
    else
        return
    end
    if mine then touch(g); changed(g, "state") else storeCarry(t) end
end

-- Send them our own hello (at most every 20 seconds each).
function CH:AnswerHello(sender, now)
    local last = self.lastHello[sender]
    if not now and last and GetTime() - last < 20 then return end
    if last and GetTime() - last < 5 then return end
    self.lastHello[sender] = GetTime()
    self:Hello(true)
end

function CH:OnHello(text, sender)
    local reported = {}
    for entry in text:gmatch("[^,]+") do
        local id, n, hash, s = entry:match("^(.+):(%d+):(%x+):([iao])$")
        if id then reported[id] = { n = tonumber(n), hash = hash, rank = RANK[CODE_STATE[s]] } end
    end
    local now = ns.Now()
    local behind = false
    -- our own games with them
    for _, g in pairs(db().games) do
        if self:IsPlayer(g) and self:Opponent(g) == sender then
            local r = reported[g.id]
            local list = split(g.moves)
            local recent = g.status ~= "over" or now - (g.updated or 0) < self.OVER_DAYS * DAY
            if not r then
                -- they don't have it: a challenge they never got, or a game they lost track of
                if recent and not (g.status == "over" and g.by ~= ns.me and g.reason == "declined") then self:SendState(g) end
            else
                if r.n <= #list and r.hash == CH.Hash(prefixText(list, r.n)) then
                    -- their copy matches ours up to their last move: confirmed
                    if g.via then for i = 1, r.n do g.via[i] = nil end end
                    if #list > r.n or (RANK[g.status] or 0) > (r.rank or 0) then self:SendState(g) end
                    if (r.rank or 0) > (RANK[g.status] or 0) then behind = true end
                else
                    -- ahead of us, or a different game: both send theirs, and
                    -- each player's own moves win
                    behind = true
                    if r.n <= #list then self:SendState(g, true) end
                end
            end
        end
    end
    if behind then self:AnswerHello(sender) end
    -- couriers: deliver what they're missing
    for id, c in pairs(db().carry) do
        if self:IsPlayer(c, sender) and not (db().games[id] and self:IsPlayer(db().games[id])) then
            local r = reported[id]
            local n = count(c.moves)
            local rank = RANK[c.status] or 0
            local recent = c.status ~= "over" or now - (c.updated or 0) < self.OVER_DAYS * DAY
            local need
            if not r then need = recent and c.status ~= "over"
            else need = n > r.n or (n == r.n and rank > (r.rank or 0)) end
            -- (an unanswered challenge goes only to the player it's for)
            if need and c.status == "invited" and sender == c.by then need = false end
            if need then self:Deliver(c, n, rank) end
        end
    end
end

-- A courier hands over its copy after a short random wait, unless the
-- opponent or another courier does it first.
function CH:Deliver(c, n, rank)
    local token = {}
    self.pending[c.id] = { n = n, rank = rank, token = token }
    C_Timer.After(1.5 + math.random() * 3.5, function()
        local p = CH.pending[c.id]
        if not p or p.token ~= token then return end
        CH.pending[c.id] = nil
        local cur = carryCopy(c.id)
        if cur then CH:SendState(cur) end
    end)
end

function CH:OnState(f, sender)
    local id, w, b, by, code, result, reason, moves = f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9] or ""
    local tc, times, startAt, clocks = f[10] or "", f[11] or "", f[12], f[13] or ""
    if not TIMER_OK[tc] then tc = "" end
    local status = CODE_STATE[code or ""]
    if not status or not (validName(w) and validName(b)) or w == b then return end
    if by ~= w and by ~= b then return end
    if not validId(id, by) then return end
    if #moves > 4000 or moves:find("[^a-h1-8qrbn,]") then return end
    local theirs = split(moves)
    if status == "invited" and #theirs > 0 then return end
    local tg = R.Play(theirs)
    if not tg then return end                        -- an illegal move anywhere: ignore it all
    if result ~= "w" and result ~= "b" and result ~= "d" then result = nil end
    if tg.over then
        status, result, reason = "over", tg.winner or "d", tg.over
    elseif status == "over" and (RULE_END[reason] or not OTHER_END[reason]) then
        return                                       -- says it's over by the rules, but it isn't
    end
    local t = { id = id, w = w, b = b, by = by, status = status, result = result, reason = reason, moves = table.concat(theirs, ",") }
    if tc ~= "" then
        t.tc, t.at = tc, {}
        local list = split(times)
        for i = 1, #theirs do t.at[i] = clampTime(list[i] and tonumber(list[i]) ~= 0 and list[i] or nil, t.at[i - 1]) end
        t.startAt = clampTime(tonumber(startAt) ~= 0 and startAt or nil)
        local cw, cb = clocks:match("^(%d+):(%d+)$")
        if cw then t.clk = { w = tonumber(cw), b = tonumber(cb) } end
    end

    if w == ns.me or b == ns.me then
        self:MergeMine(t, theirs, sender)
        return
    end
    -- courier copy: take it when it's newer (a player's own copy wins a disagreement)
    local c = carryCopy(id)
    if c then
        if c.w ~= w or c.b ~= b or c.by ~= by then return end
        local mine = split(c.moves)
        local extends = #theirs >= #mine and prefixText(theirs, #mine) == c.moves
        local newer = #theirs > #mine or (RANK[status] or 0) > (RANK[c.status] or 0)
        if (extends and newer) or (self:IsPlayer(c, sender) and c.moves ~= t.moves) then storeCarry(t) end
        local p = self.pending[id]
        if p and #theirs >= p.n and (RANK[status] or 0) >= p.rank then self.pending[id] = nil end
    else
        storeCarry(t)
    end
end

-- A whole game for one of OUR games arrived.
function CH:MergeMine(t, theirs, sender)
    local opp = (t.w == ns.me) and t.b or t.w
    local fromOpp = sender == opp
    local g = self:Get(t.id)
    if not g then
        -- a challenge (or a game) we never heard about, delivered by a courier
        if t.status == "over" or t.by == ns.me then return end
        g = { id = t.id, w = t.w, b = t.b, by = t.by, status = t.status, moves = t.moves, created = ns.Now(), via = {},
              tc = t.tc, at = t.at, startAt = t.startAt, clk = t.clk }
        if not fromOpp then for i = 1, #theirs do g.via[i] = sender end end
        touch(g)
        db().games[g.id] = g
        if g.status == "invited" then
            notify(("%s challenged you to a game of chess%s%s."):format(ns.Short(t.by), g.tc and (" (" .. TIMER_OK[g.tc] .. ")") or "",
                fromOpp and "" or (" (delivered by " .. ns.Short(sender) .. ")")), g)
        end
        checkEnd(g)
        changed(g, "new")
        return
    end
    if g.w ~= t.w or g.b ~= t.b or g.by ~= t.by then return end
    g.via = g.via or {}
    local mine = split(g.moves)
    local d
    for i = 1, math.min(#mine, #theirs) do
        if mine[i] ~= theirs[i] then d = i break end
    end
    -- nobody else can make OUR moves: their copy counts only up to the
    -- first move of ours we don't already have
    local base = d and d - 1 or #mine
    for i = base + 1, #theirs do
        if moverOf(g, i) == ns.me then
            for j = #theirs, i, -1 do theirs[j] = nil end
            t.moves = table.concat(theirs, ",")
            break
        end
    end
    local before = g.moves
    local beforeStatus = g.status
    local adoptFrom                                -- first ply taken from their copy
    if d then
        if moverOf(g, d) == ns.me then
            -- our own move: ours stands; tell them
            if fromOpp then self:SendState(g, true) end
            return
        end
        if not fromOpp then return end              -- only our opponent can replace our opponent's moves
        local courier = g.via[d]
        for i = d, #mine do g.via[i] = nil end
        g.moves = t.moves
        adoptFrom = d
        if g.status == "over" and t.status ~= "over" then g.status, g.result, g.reason = "active", nil, nil end
        if courier then
            notify(("%s's move %d was wrong in the copy %s delivered - it's been put back to %s's real move."):format(
                ns.Short(opp), math.floor((d + 1) / 2), ns.Short(courier), ns.Short(opp)), g)
        end
    elseif #theirs > #mine then
        if g.status == "over" then
            if fromOpp then self:SendState(g, true) end
            return
        end
        for i = #mine + 1, #theirs do g.via[i] = (not fromOpp) and sender or nil end
        g.moves = t.moves
        adoptFrom = #mine + 1
    elseif fromOpp then
        for i = 1, #theirs do g.via[i] = nil end     -- they've confirmed these
    end
    -- timers of the moves we took from their copy
    if adoptFrom and g.tc and t.tc == g.tc then
        g.at = g.at or {}
        for i = adoptFrom, #split(g.moves) do g.at[i] = t.at and t.at[i] or ns.Now() end
        for i = #split(g.moves) + 1, #mine do g.at[i] = nil end
        if self:Timer(g) == "live" and t.clk then
            -- their clocks, never more time than we already had down
            g.clk = g.clk or {}
            for _, c in ipairs({ "w", "b" }) do
                g.clk[c] = math.min(t.clk[c] or 0, g.clk[c] or t.clk[c] or 0)
            end
            g.run = 0
        end
    end
    if t.startAt and not g.startAt then g.startAt = t.startAt end
    -- the game's state
    local ours = split(g.moves)
    if #ours == #theirs and (RANK[t.status] or 0) > (RANK[g.status] or 0) then
        if t.status == "active" and g.status == "invited" then
            g.status = "active"
        elseif t.status == "over" then
            -- a resignation or agreed draw, from our opponent or carried by a courier
            g.status, g.result, g.reason = "over", t.result, t.reason
        end
    end
    checkEnd(g)
    if g.moves ~= before or g.status ~= beforeStatus then
        touch(g)
        g.offer = nil
        if g.status == "over" and beforeStatus ~= "over" then notify(self:EndText(g), g)
        elseif beforeStatus == "invited" and g.status == "active" and g.moves == before then
            notify(("%s accepted your challenge. %s"):format(ns.Short(opp),
                self:ColorOf(g) == "w" and "You play White - your move." or "You play Black."), g)
        elseif self:NeedsMe(g) and g.moves ~= before then
            notify(("Your move against %s%s."):format(ns.Short(opp), fromOpp and "" or (" (delivered by " .. ns.Short(sender) .. ")")), g)
        end
        changed(g, "state")
    end
    -- they're behind us: catch them up
    if fromOpp and (#ours > #theirs or (RANK[g.status] or 0) > (RANK[t.status] or 0)) then self:SendState(g) end
end

-- ---------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------
local REASONS = {
    mate = "checkmate", stalemate = "stalemate", repetition = "threefold repetition",
    fifty = "the 50-move rule", material = "not enough pieces to mate", agreed = "agreement",
    resign = "resignation", time = "time",
}

function CH:EndText(g)
    if g.reason == "declined" then return (g.by == ns.me and ns.Short(self:Opponent(g)) or "You") .. " declined the challenge." end
    if g.reason == "cancelled" then return "The challenge was taken back." end
    if g.result == "d" then return "Draw by " .. (REASONS[g.reason] or "agreement") .. "." end
    local me = self:ColorOf(g)
    local won = g.result == me
    local opp = ns.Short(self:Opponent(g))
    if g.reason == "resign" then return won and (opp .. " resigned. You win!") or "You resigned." end
    if g.reason == "time" then return won and (opp .. " ran out of time. You win!") or "You ran out of time." end
    return (won and "You beat " .. opp or opp .. " won") .. " by " .. (REASONS[g.reason] or "checkmate") .. "."
end

-- ---------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------
-- A move's slide (ChessUI) takes this long; the next clock starts after it,
-- on both players' computers, whether or not the window is open (Ryan).
CH.SLIDE = 0.3
function CH:PauseForSlide(g)
    self.slidePause = self.slidePause or {}
    self.slidePause[g.id] = GetTime() + self.SLIDE
end

-- Once a second: live clocks tick while both players are online, your own
-- clock running out ends the game, and the window's clocks update.
function CH:Tick()
    local now = GetTime()
    local dt = math.min(5, now - (self.lastTick or now))
    self.lastTick = now
    local liveGames = false
    for _, g in pairs(db().games) do
        if g.status == "active" and self:IsPlayer(g) and self:Timer(g) == "live" then
            liveGames = true
            local opp = self:Opponent(g)
            local from = math.max(now - dt, self.slidePause and self.slidePause[g.id] or 0)
            if self:IsOnline(opp) == true and now > from then
                g.run = (g.run or 0) + (now - from)
                if self:NeedsMe(g) and self:ClockLeft(g, self:ColorOf(g)) <= 0 then
                    local mine = self:ColorOf(g)
                    g.clk[mine], g.run = 0, 0
                    finish(g, mine == "w" and "b" or "w", "time")
                    self:Send("E", g.id, "F", count(g.moves))
                    notify(self:EndText(g), g)
                    changed(g, "state")
                end
            end
        end
    end
    -- keep the guild roster (who's online) fresh while a live clock is running
    if liveGames and now - (self.rosterAsked or 0) > 15 then
        self.rosterAsked = now
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        self.roster = nil
    end
    if ns.ChessUI and ns.ChessUI.Tick then ns.ChessUI:Tick() end
end

function CH:Init()
    self:Prune()
    self.lastTick = GetTime()
    C_Timer.NewTicker(1, function() CH:Tick() end)
    ns.Listen(PREFIX, "guild", function(msg, sender) CH:OnMessage(msg, sender) end)
    -- say which games we have once the guild has loaded, then mention any waiting on you
    C_Timer.After(15, function()
        CH:Hello(true)
        local n = CH:WaitingCount()
        if n > 0 then
            ns.Print(("|cff4fc2f7Chess:|r %d game%s waiting on you. |cff8a8f9c/tu chess|r"):format(n, n == 1 and " is" or "s are"))
        end
    end)
end
