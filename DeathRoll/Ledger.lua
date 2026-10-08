-- Titan Up - DeathRoll/Ledger.lua
-- Every finished death roll is saved as a game record, by BOTH players:
--   { id, w = winner, l = loser, g = wager (gold), t = server time,
--     r = number of rolls, paid = gold paid so far, src = { [name] = true } }
-- `src` is who has reported a MATCHING copy of the game. Confirmed = both
-- players' copies match. A confirmed game is LOCKED on your client: later
-- copies that disagree are ignored (counted as rejected edits), so nobody
-- can change or dispute it afterwards by editing their own saved data.
-- Senders can't be faked (WoW stamps every addon message with the real
-- sender), and players can only send games they played in. Only confirmed
-- games count in the standings.
--
-- Payments: only the WINNER's addon can confirm money was received (trade
-- detection on their side, or their Mark paid). The loser's side records
-- what it sent and waits for the winner's confirmation.
--
-- Sharing: each player is the source of truth for the games they played.
-- Everyone announces a small digest of their own games, to their group and
-- to the guild's (hidden) addon channel; if your copy of someone's games
-- differs, you ask on the same channel and they send their records. So the
-- standings fill in from any online guildmate with Titan Up, grouped or not. Nobody can send games between two
-- other people, and if two reports of one game disagree on who won or the
-- amount, the game is marked disputed and left out of the standings.
--
-- Payments: completed trades are watched. Gold given from the loser to the
-- winner is credited to their unpaid games (oldest first, partial payments
-- count). "Mark paid" works for gold sent any other way. Paid amounts only
-- ever go up.
--
-- Quiet mode (in combat or an encounter): nothing is sent and incoming
-- records are set aside until the fight ends, so the ledger never adds work
-- mid-fight. A finished game and a confirmed payment are sent straight away
-- (one record each) so the other player sees them within a second or two.
--
-- Messages (prefix TitanUpDR):
--   H count hash from            digest of the sender's own games with t >= from
--                                (their newest MAX_SHARE in the window; `from`
--                                is 0.31.2 - without it, the old window is meant)
--   Z name                       "name, please send your games"
--   E id w l g t r paid          one game record (sender must be w or l, and the
--                                id starts with w's or l's name)
--   C id                         "is this debt paid?" - the winner's addon answers
--                                with its record (the winner is the source of truth)
local ADDON, ns = ...

local L = {}
ns.DRLedger = L

local SEP = "^"
-- Sharing a long history never holds up a game's own messages: the ledger
-- keeps its own count of the prefix's send allowance (WoW's burst of 10,
-- then one more a second - the game's messages counted too), never uses
-- the last RESERVE of it, and pauses YIELD seconds whenever a game sends
-- something. It checks every PUMP_EVERY seconds.
local BURST, REFILL, RESERVE = 10, 1, 2
local PUMP_EVERY, YIELD = 0.5, 2
local MAX_SHARE = 150       -- most recent games each player shares
local KEEP_OTHERS = 1000    -- games between other players kept (all of yours are kept)
local ARCHIVE_DAYS = 90     -- settled games older than this are folded into per-player totals
local PENDING_DAYS = 7      -- a game only one player ever reported is dropped after this
local DAY = 86400

local queue = {}
local sendNow              -- defined below (declared here so everything above can use it)
local requested = {}        -- [name] = time we last asked them

local function games() return ns.udb.deathroll.games end
local now = ns.Now
local int = ns.DeathRoll.Int
-- a number from a message, cut to lo..hi (nil for nan or none)
local function clamp(v, lo, hi)
    v = tonumber(v)
    if v and v == v then return math.max(lo, math.min(hi, math.floor(v))) end
end
local function isMine(rec) return (rec.w == ns.me or rec.l == ns.me) and rec.src and rec.src[ns.me] end
-- one game record as an E message
local function recMsg(rec)
    return table.concat({ "E", rec.id, rec.w, rec.l, rec.g, rec.t, rec.r or 0, rec.paid or 0 }, SEP)
end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- Redraw an open Death Roll window at most twice a second (records can
-- arrive in bursts while someone shares their history).
local refreshPending = false
local function refresh()
    if refreshPending then return end
    if not (ns.DeathRollUI and ns.DeathRollUI.IsShown and ns.DeathRollUI:IsShown()) then return end
    refreshPending = true
    C_Timer.After(0.5, function()
        refreshPending = false
        if ns.DeathRollUI:IsShown() then ns.DeathRollUI:Refresh() end
    end)
end

-- Per-player digest cache, cleared whenever one of their games changes
-- (and the newest-first list, cleared on any change).
local digestCache = {}
local recent
local function dirty(rec)
    recent = nil
    if rec then
        if rec.w then digestCache[rec.w] = nil end
        if rec.l then digestCache[rec.l] = nil end
    else
        wipe(digestCache)
    end
end

-- Quiet = in combat or an encounter: nothing is sent, and incoming
-- records wait until the fight is over (no work while you're fighting).
function L:Quiet() return ns.Busy() end

function L:Init()
    for _, rec in pairs(games()) do self:CheckLock(rec) end
    -- trades: gold that went from a loser to their winner
    ns.WatchTrades(function(t)
        local mine = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
        local theirs = GetTargetTradeMoney and GetTargetTradeMoney() or 0
        if not ns.IsSecret(mine) then t.gave = math.floor((mine or 0) / 10000) end
        if not ns.IsSecret(theirs) then t.got = math.floor((theirs or 0) / 10000) end
    end, function(t) L:OnTradeComplete(t.partner, t.gave or 0, t.got or 0) end)
    ns.On("GROUP_ROSTER_UPDATE", function()
        -- raids change roster constantly: share with the group at most once a minute
        if IsInGroup() and GetTime() - (L._groupDigestAt or -60) >= 60 then
            L._groupDigestAt = GetTime()
            L:ScheduleDigest(4)
        end
    end)
    -- after a fight (or a loading screen): send what was held back
    for ev, delay in pairs({ PLAYER_REGEN_ENABLED = 1, ENCOUNTER_END = 2, PLAYER_ENTERING_WORLD = 3, ZONE_CHANGED_NEW_AREA = 3 }) do
        ns.On(ev, function() C_Timer.After(delay, function() if not L:Quiet() then L:FlushDeferred() end end) end)
    end
    C_Timer.After(6, function() L:ScheduleDigest(0) end)
    C_Timer.After(20, function() if not L:Quiet() then L:Archive() end end)     -- fold settled games older than 3 months
    self:Trim()
    -- refresh the guild every 10 minutes (only differences cause any traffic)
    C_Timer.NewTicker(600, function() L:ScheduleDigest(0) end)
end

-- ---------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------
function L:RecordGame(room)
    if room.sim then return nil end          -- practice games are never recorded
    local id = room.id
    local old = games()[id]
    -- the same game already in: keep it. A record under this id between
    -- other players (or for another amount) is someone squatting the id:
    -- the game you just played replaces it.
    if old and old.w == room.winner and old.l == room.loser and old.g == room.wager then return old end
    local rec = {
        id = id, w = room.winner, l = room.loser, g = room.wager, t = now(),
        r = #room.rolls, paid = 0, src = { [ns.me] = true },
    }
    games()[id] = rec
    dirty(rec)
    -- send this game straight away so the other player's copy confirms it,
    -- then the usual summary for everyone else
    C_Timer.After(1, function() L:ShareGame(rec) end)
    self:ScheduleDigest(1)
    return rec
end

function L:ShareGame(rec)
    queue[#queue + 1] = recMsg(rec)
    self:StartPump()
end

-- Work held back while in a raid instance, sent when you leave.
function L:FlushDeferred()
    if self._pendingChecks then
        local pending = self._pendingChecks
        self._pendingChecks = nil
        for id in pairs(pending) do
            local rec = games()[id]
            if rec and rec.w == ns.me then self:ShareGame(rec) end
        end
    end
    if self._inbox and #self._inbox > 0 then
        local inbox = self._inbox
        self._inbox = nil
        for _, item in ipairs(inbox) do self:Merge(item[1], item[2]) end
    end
    self:StartPump()
    if self._deferDigest then
        self._deferDigest = nil
        self:ScheduleDigest(2)
    end
    if self._deferShare then
        self._deferShare = nil
        self:ShareMine()
    end
end

function L:Confirmed(rec) return (rec.src and rec.src[rec.w] and rec.src[rec.l]) and true or false end
function L:Owed(rec) return math.max(0, (rec.g or 0) - (rec.paid or 0)) end

-- Both players' copies match -> lock it for good (on this client).
function L:CheckLock(rec)
    if not rec.locked and not rec.conflict and self:Confirmed(rec) then rec.locked = true end
end

-- Only the winner can confirm payment received.
function L:SetPaid(rec, amount)
    if rec.w ~= ns.me then return false end
    amount = math.min(rec.g, math.floor(amount))
    if amount <= (rec.paid or 0) then return false end
    rec.paid = amount
    rec.paidT = now()
    dirty(rec)
    -- send the confirmation straight to the loser (and everyone) right away
    self:ShareGame(rec)
    refresh()
    return true
end

-- The loser's side: what you've sent, until the winner's addon confirms it.
function L:NoteSent(rec, amount)
    rec.sent = math.min(rec.g, math.max(rec.sent or 0, math.floor(amount)))
    refresh()
end

-- Loser: ask the winner's addon whether it has confirmed this payment.
local checks = {}           -- [id] = { at = time asked, replied = bool }
function L:CheckDebt(id)
    local rec = games()[id]
    if not rec or rec.l ~= ns.me then return end
    local who = ns.Short(rec.w)
    if self:Quiet() then ns.Print("Can't check during combat - try again after the fight.") return end
    local c = checks[id]
    if c and GetTime() - c.at < 5 then return end
    checks[id] = { at = GetTime(), replied = false }
    if not sendNow("C" .. SEP .. id) then
        ns.Print("Couldn't send the check (not in the guild channel?).")
        return
    end
    ns.Print(("Asking %s's addon about your %sg debt..."):format(who, ns.DeathRoll.Fmt(rec.g)))
    C_Timer.After(4, function()
        local st = checks[id]
        if not st then return end
        if (rec.paid or 0) >= rec.g then
            ns.Print(("%s confirmed your payment - debt cleared."):format(who))
        elseif st.replied then
            local part = (rec.paid or 0) > 0 and (" (" .. ns.DeathRoll.Fmt(rec.paid) .. " of " .. ns.DeathRoll.Fmt(rec.g) .. " confirmed so far)") or ""
            ns.Print(("%s's addon hasn't confirmed payment yet%s. Trade them the gold, or ask them to click Mark paid."):format(who, part))
        else
            ns.Print(("No answer from %s yet - they may be offline or in combat. You'll be told if they answer."):format(who))
            -- keep listening: a winner in combat answers once their fight ends
            st.waiting = true
            C_Timer.After(600, function() if checks[id] == st then checks[id] = nil end end)
            return
        end
        checks[id] = nil
        refresh()
    end)
end

-- A late answer to a Check (the winner was in combat): report it.
function L:CheckAnswered(rec)
    local c = checks[rec.id]
    if not (c and c.waiting) then return end
    checks[rec.id] = nil
    local who = ns.Short(rec.w)
    if (rec.paid or 0) >= rec.g then
        ns.Print(("%s confirmed your payment - debt cleared."):format(who))
    else
        ns.Print(("%s's addon answered: payment not confirmed yet. Trade them the gold, or ask them to click Mark paid."):format(who))
    end
end

function L:MarkPaid(id)
    local rec = games()[id]
    if rec and rec.w == ns.me then self:SetPaid(rec, rec.g) end
end

-- Your confirmed games that still have gold outstanding, oldest first (a
-- game only one player reported isn't a debt yet).
function L:MyUnpaid()
    local out = {}
    for _, rec in pairs(games()) do
        if (rec.w == ns.me or rec.l == ns.me) and not rec.conflict and self:Confirmed(rec) and self:Owed(rec) > 0 then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- ---------------------------------------------------------------------
-- Standings (every game you know about, disputed ones excluded)
-- ---------------------------------------------------------------------
function L:Stats()
    local by = {}
    local function s(name)
        by[name] = by[name] or { name = name, wins = 0, losses = 0, net = 0, owes = 0, owed = 0, games = 0 }
        return by[name]
    end
    -- archived (older, settled) games count through their totals
    local arch = ns.udb.deathroll.archive
    for name, a in pairs(arch and arch.totals or {}) do
        local x = s(name)
        x.wins, x.losses, x.net, x.games = x.wins + a.wins, x.losses + a.losses, x.net + a.net, x.games + a.games
    end
    for _, rec in pairs(games()) do
        if not rec.conflict and rec.w and rec.l and self:Confirmed(rec) then
            local w, l, owed = s(rec.w), s(rec.l), self:Owed(rec)
            w.wins, w.net, w.games, w.owed = w.wins + 1, w.net + rec.g, w.games + 1, w.owed + owed
            l.losses, l.net, l.games, l.owes = l.losses + 1, l.net - rec.g, l.games + 1, l.owes + owed
        end
    end
    local list = {}
    for _, v in pairs(by) do list[#list + 1] = v end
    table.sort(list, function(a, b)
        if a.net ~= b.net then return a.net > b.net end
        return a.name < b.name
    end)
    return list, by
end

-- Every game, newest first (kept until a record changes).
function L:Recent()
    if recent then return recent end
    local list = {}
    for _, rec in pairs(games()) do list[#list + 1] = rec end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    recent = list
    return list
end

-- ---------------------------------------------------------------------
-- Trades: credit gold that went from a loser to their winner
-- ---------------------------------------------------------------------
function L:OnTradeComplete(partner, gave, got)
    if not partner then return end
    local function apply(amount, iAmWinner)
        if amount <= 0 then return end
        local list = {}
        for _, rec in pairs(games()) do
            local match
            if iAmWinner then
                match = rec.w == ns.me and rec.l == partner      -- they're paying you
            else
                match = rec.l == ns.me and rec.w == partner      -- you're paying them
                    and math.max(rec.paid or 0, rec.sent or 0) < rec.g
            end
            if match and not rec.conflict and self:Confirmed(rec) and self:Owed(rec) > 0 then list[#list + 1] = rec end
        end
        table.sort(list, function(a, b) return a.t < b.t end)
        local total = 0
        for _, rec in ipairs(list) do
            if amount <= 0 then break end
            if iAmWinner then
                local pay = math.min(amount, self:Owed(rec))
                self:SetPaid(rec, (rec.paid or 0) + pay)
                amount, total = amount - pay, total + pay
            else
                local covered = math.max(rec.paid or 0, rec.sent or 0)
                local pay = math.min(amount, math.max(0, rec.g - covered))
                if pay > 0 then
                    self:NoteSent(rec, covered + pay)
                    amount, total = amount - pay, total + pay
                end
            end
        end
        if total > 0 then
            local DR = ns.DeathRoll
            if iAmWinner then
                ns.Print(("Received %sg from %s - credited to their death roll debt."):format(DR.Fmt(total), ns.Short(partner)))
            else
                ns.Print(("Paid %sg to %s - it clears once their Titan Up confirms it."):format(DR.Fmt(total), ns.Short(partner)))
            end
        end
    end
    apply(got, true)
    apply(gave, false)
end

-- ---------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------
-- The digest window starts at the beginning of a day 89 days back - always
-- after every client's archive cut-off (now - 90 days, whatever time of day
-- it ran), so games a guildmate has already archived never make two
-- digests differ.
function L.DigestWindow() return math.floor(now() / DAY) * DAY - (ARCHIVE_DAYS - 1) * DAY end
-- (what versions before 0.31.2 count: a day earlier, and every game)
local function oldWindow() return math.floor(now() / DAY) * DAY - ARCHIVE_DAYS * DAY end

-- count and hash of `player`'s own games with t >= from
function L:Digest(player, from)
    from = from or L.DigestWindow()
    local c = digestCache[player]
    if c and c.from == from then return c.count, c.sum end
    local count, sum = 0, 0
    for id, rec in pairs(games()) do
        if (rec.w == player or rec.l == player) and rec.src and rec.src[player] and (rec.t or 0) >= from then
            count = count + 1
            sum = (sum + hash(id .. ":" .. (rec.paid or 0))) % 2147483647
        end
    end
    digestCache[player] = { from = from, count = count, sum = tostring(sum) }
    return count, tostring(sum)
end

-- Your digest (and ShareMine) covers your newest MAX_SHARE games in the
-- window: where that set starts.
function L:MineFrom()
    local from, ts = L.DigestWindow(), {}
    for _, rec in pairs(games()) do
        if isMine(rec) and (rec.t or 0) >= from then ts[#ts + 1] = rec.t end
    end
    if #ts > MAX_SHARE then
        table.sort(ts, function(a, b) return a > b end)
        from = ts[MAX_SHARE]
    end
    return from
end

-- what's left of the send allowance after spending n
local allowance, allowanceAt = BURST, 0
local function spend(n)
    local t = GetTime()
    allowance = math.min(BURST, allowance + (t - allowanceAt) * REFILL) - n
    allowanceAt = t
    return allowance
end

-- Everything goes over the guild channel (guild members only).
sendNow = function(msg)
    if ns.DeathRoll.sim or not ns.SendFields("TitanUpDR", msg) then return false end
    spend(1)
    return true
end

-- A game's own message just went out: the ledger waits a moment.
function L:Yield()
    spend(1)
    self.yieldUntil = GetTime() + YIELD
end

-- The send timer only runs while records are queued.
function L:Pump()
    if #queue == 0 then
        if self.pumpTicker then self.pumpTicker:Cancel(); self.pumpTicker = nil end
        return
    end
    if self:Quiet() then return end                                 -- hold until the fight is over
    if GetTime() < (self.yieldUntil or 0) or spend(0) < 1 + RESERVE then return end
    sendNow(table.remove(queue, 1))
end

function L:StartPump()
    if not self.pumpTicker and #queue > 0 then self.pumpTicker = C_Timer.NewTicker(PUMP_EVERY, function() L:Pump() end) end
end

-- Keep every game you played; of everyone else's, keep the newest KEEP_OTHERS.
-- Settled games older than 3 months are folded into per-player totals
-- (wins / losses / net / games) and their records dropped, so the ledger
-- stays small. Unpaid games are never archived. Old unconfirmed games never
-- counted, so they're just dropped (a game only one player reported after
-- a week; one dated in the future at once). Games from before the cut-off
-- that a guildmate re-sends are ignored (they're already in the totals).
function L:Archive()
    local t0 = now()
    local cutoff = t0 - ARCHIVE_DAYS * DAY
    local d = ns.udb.deathroll
    d.archive = d.archive or { totals = {}, before = 0 }
    local a = d.archive
    local changed = 0
    for id, rec in pairs(games()) do
        local t = rec.t or 0
        local confirmed = self:Confirmed(rec)
        if t > t0 + DAY or (not confirmed and not rec.conflict and t < t0 - PENDING_DAYS * DAY) then
            games()[id] = nil
            changed = changed + 1
        elseif t < cutoff then
            if not confirmed or rec.conflict then
                games()[id] = nil
                changed = changed + 1
            elseif self:Owed(rec) <= 0 and rec.w and rec.l then
                local function tot(name) a.totals[name] = a.totals[name] or { wins = 0, losses = 0, net = 0, games = 0 } return a.totals[name] end
                local w, l = tot(rec.w), tot(rec.l)
                w.wins, w.net, w.games = w.wins + 1, w.net + (rec.g or 0), w.games + 1
                l.losses, l.net, l.games = l.losses + 1, l.net - (rec.g or 0), l.games + 1
                games()[id] = nil
                changed = changed + 1
            end
        end
    end
    if changed > 0 then a.before = math.max(a.before or 0, cutoff) dirty() end
    return changed
end

function L:Trim()
    local others = {}
    for _, rec in pairs(games()) do
        if rec.w ~= ns.me and rec.l ~= ns.me then others[#others + 1] = rec end
    end
    if #others <= KEEP_OTHERS then return end
    table.sort(others, function(a, b) return (a.t or 0) > (b.t or 0) end)
    for i = KEEP_OTHERS + 1, #others do games()[others[i].id] = nil end
    dirty()
end

function L:ScheduleDigest(delay)
    if self:Quiet() then self._deferDigest = true return end          -- sent when the fight is over
    if self._digestTimer then return end
    self._digestTimer = true
    C_Timer.After(delay or 0, function()
        L._digestTimer = nil
        local from = L:MineFrom()
        local count, h = L:Digest(ns.me, from)
        if count > 0 then sendNow(table.concat({ "H", count, h, from }, SEP)) end
    end)
end

-- Send your games (the set your digest covers). One guildmate asking again
-- while your games haven't changed gets nothing new from a second round, so
-- that's skipped for half an hour (others asking still get it).
local sharedTo = {}         -- [name] = { at, digest }
function L:ShareMine(asker)
    local from = self:MineFrom()
    local _, h = self:Digest(ns.me, from)
    local last = asker and sharedTo[asker]
    if last and last.h == h and GetTime() - last.at < 1800 then return end
    if self._sharedAt and GetTime() - self._sharedAt < 20 then return end
    self._sharedAt = GetTime()
    if asker then sharedTo[asker] = { at = GetTime(), h = h } end
    local mine = {}
    for _, rec in pairs(games()) do
        if isMine(rec) and (rec.t or 0) >= from then mine[#mine + 1] = rec end
    end
    table.sort(mine, function(a, b) return a.t > b.t end)
    for _, r in ipairs(mine) do queue[#queue + 1] = recMsg(r) end
    self:StartPump()
end

-- A record from the guild. Only a game's own two players speak for it: for
-- a new record the sender must be its winner or loser and the id must
-- start with one of their names; for one you have, the sender must be one
-- of ITS players (whatever the message says). Numbers are checked: whole
-- gold 1..9,999,999, dated within the last 90 days (and not tomorrow).
function L:Merge(f, sender)
    local id, w, l = f[2], f[3], f[4]
    local t0 = now()
    local g, t = int(f[5], 1, ns.DeathRoll.MAX_WAGER), int(f[6], 0, t0 + DAY)
    local r, paid = clamp(f[7], 0, 1000) or 0, tonumber(f[8])
    if not id or id == "" or not w or not l or w == l or not g or not t then return end
    if sender ~= w and sender ~= l then return end          -- only your own games
    local rec = games()[id]
    if rec and sender ~= rec.w and sender ~= rec.l then
        -- not one of this game's players: ignored (and noted)
        rec.rejected = (rec.rejected or 0) + 1
        rec.rejectedBy = sender
        refresh()
        return
    end
    if not rec then
        local idName = id:match("^(.-)%-%d+$")
        if idName ~= ns.Short(w) and idName ~= ns.Short(l) then return end
        if t < t0 - ARCHIVE_DAYS * DAY then return end
    end
    local arch = ns.udb.deathroll.archive
    if arch and arch.before and t < arch.before and not rec then return end   -- already in the archived totals
    if not rec then
        rec = {
            id = id, w = w, l = l, g = g, t = t, r = r, src = { [sender] = true },
            paid = (sender == w) and clamp(paid, 0, g) or 0,      -- only the winner vouches for payment
        }
        games()[id] = rec
        self._added = (self._added or 0) + 1
        if self._added % 50 == 0 then self:Trim() end
    else
        if sender == rec.w and checks[id] then checks[id].replied = true end
        rec.src = rec.src or {}
        local same = rec.w == w and rec.l == l and rec.g == g
        if not same then
            if rec.locked then
                -- confirmed by both players earlier: this is an edit, ignore it
                rec.rejected = (rec.rejected or 0) + 1
                rec.rejectedBy = sender
                refresh()
                return
            end
            rec.conflict = true
        else
            rec.src[sender] = true
            paid = clamp(paid, 0, rec.g)
            if sender == rec.w and paid and paid > (rec.paid or 0) then
                rec.paid = paid
                rec.paidT = now()
            end
        end
    end
    self:CheckLock(rec)
    dirty(rec)
    if sender == rec.w and rec.l == ns.me then self:CheckAnswered(rec) end
    refresh()
end

function L:OnMessage(f, sender)
    local kind = f[1]
    if kind == "H" then
        if self:Quiet() then return end           -- in combat: compare notes later
        local count, h = tonumber(f[2]), f[3]
        -- 0.31.2+ say where their digest starts; older versions mean the old window
        local from = (f[4] == nil or f[4] == "") and oldWindow() or int(f[4], now() - ARCHIVE_DAYS * DAY, now() + DAY)
        if not count or not from then return end
        local myCount, myHash = self:Digest(sender, from)
        if count ~= myCount or h ~= myHash then
            -- asking again about the same digest won't help: at most every half hour
            local q = requested[sender]
            if q and GetTime() - q.at < (q.h == h and 1800 or 30) then return end
            requested[sender] = { at = GetTime(), h = h }
            C_Timer.After(0.5 + math.random() * 1.5, function() sendNow("Z" .. SEP .. sender) end)
        end
    elseif kind == "Z" then
        if f[2] ~= ns.me then return end
        if self:Quiet() then self._deferShare = true return end
        self:ShareMine(sender)
    elseif kind == "C" then
        -- someone asks whether their debt to us is paid: answer with our record
        local rec = games()[f[2] or ""]
        if not (rec and rec.w == ns.me and rec.l == sender) then return end
        if self:Quiet() then
            -- in combat: answer as soon as the fight is over
            self._pendingChecks = self._pendingChecks or {}
            self._pendingChecks[rec.id] = true
            return
        end
        self:ShareGame(rec)
    elseif kind == "E" then
        if self:Quiet() then
            -- in combat: keep it for after the fight
            self._inbox = self._inbox or {}
            if #self._inbox < 300 then self._inbox[#self._inbox + 1] = { f, sender } end
            return
        end
        self:Merge(f, sender)
    end
end
