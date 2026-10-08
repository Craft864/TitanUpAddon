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
--   H count hash                 digest of the sender's own games
--   Z name                       "name, please send your games"
--   E id w l g t r paid          one game record (sender must be w or l)
--   C id                         "is this debt paid?" - the winner's addon answers
--                                with its record (the winner is the source of truth)
local ADDON, ns = ...

local L = {}
ns.DRLedger = L

local SEP = "^"
-- seconds between queued record messages: slower than the send queue's
-- ~2 a second, so sharing a long history never holds up a game's own messages
local SEND_RATE = 0.6
local MAX_SHARE = 150       -- most recent games each player shares
local KEEP_OTHERS = 1000    -- games between other players kept (all of yours are kept)
local ARCHIVE_DAYS = 90     -- settled games older than this are folded into per-player totals

local queue = {}
local sendNow              -- defined below (declared here so everything above can use it)
local requested = {}        -- [name] = time we last asked them

local function games() return ns.udb.deathroll.games end
local function now() return (GetServerTime and GetServerTime()) or time() end

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

-- Per-player digest cache, cleared whenever one of their games changes.
local digestCache = {}
local function dirty(rec)
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
    ns.On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1, function() if not L:Quiet() then L:FlushDeferred() end end) end)
    ns.On("ENCOUNTER_END", function() C_Timer.After(2, function() if not L:Quiet() then L:FlushDeferred() end end) end)
    local function zoneCheck()
        if not L:Quiet() then L:FlushDeferred() end
    end
    ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, zoneCheck) end)
    ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, zoneCheck) end)
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
    if games()[id] then return games()[id] end
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
    queue[#queue + 1] = table.concat({ "E", rec.id, rec.w, rec.l, rec.g, rec.t, rec.r or 0, rec.paid or 0 }, SEP)
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
        local now = checks[id]
        if not now then return end
        if (rec.paid or 0) >= rec.g then
            ns.Print(("%s confirmed your payment - debt cleared."):format(who))
        elseif now.replied then
            local part = (rec.paid or 0) > 0 and (" (" .. ns.DeathRoll.Fmt(rec.paid) .. " of " .. ns.DeathRoll.Fmt(rec.g) .. " confirmed so far)") or ""
            ns.Print(("%s's addon hasn't confirmed payment yet%s. Trade them the gold, or ask them to click Mark paid."):format(who, part))
        else
            ns.Print(("No answer from %s yet - they may be offline or in combat. You'll be told if they answer."):format(who))
            -- keep listening: a winner in combat answers once their fight ends
            now.waiting = true
            C_Timer.After(600, function() if checks[id] == now then checks[id] = nil end end)
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

-- Your games that still have gold outstanding, oldest first.
function L:MyUnpaid()
    local out = {}
    for _, rec in pairs(games()) do
        if (rec.w == ns.me or rec.l == ns.me) and not rec.conflict and self:Owed(rec) > 0 then out[#out + 1] = rec end
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

function L:Recent(limit)
    local list = {}
    for _, rec in pairs(games()) do list[#list + 1] = rec end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    if limit then while #list > limit do table.remove(list) end end
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
            if match and not rec.conflict and self:Owed(rec) > 0 then list[#list + 1] = rec end
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
-- the same recent window on every client (from the start of the day), so
-- archived games never make two digests differ
function L.DigestWindow() return math.floor(now() / 86400) * 86400 - ARCHIVE_DAYS * 86400 end

function L:Digest(player)
    local from = L.DigestWindow()
    if self.digestFrom ~= from then wipe(digestCache); self.digestFrom = from end
    local c = digestCache[player]
    if c then return c[1], c[2] end
    local count, sum = 0, 0
    for id, rec in pairs(games()) do
        if (rec.w == player or rec.l == player) and rec.src and rec.src[player] and (rec.t or 0) >= from then
            count = count + 1
            sum = (sum + hash(id .. ":" .. (rec.paid or 0))) % 2147483647
        end
    end
    digestCache[player] = { count, tostring(sum) }
    return count, tostring(sum)
end

-- Everything goes over the guild channel (guild members only).
sendNow = function(msg)
    return not (ns.DeathRoll.sim or ns.InLockdown()) and ns.SendFields("TitanUpDR", msg)
end

-- The send timer only runs while records are queued.
function L:Pump()
    if #queue == 0 then
        if self.pumpTicker then self.pumpTicker:Cancel(); self.pumpTicker = nil end
        return
    end
    if self:Quiet() then return end                 -- hold until the fight is over
    sendNow(table.remove(queue, 1))
end

function L:StartPump()
    if not self.pumpTicker and #queue > 0 then self.pumpTicker = C_Timer.NewTicker(SEND_RATE, function() L:Pump() end) end
end

-- Keep every game you played; of everyone else's, keep the newest KEEP_OTHERS.
-- Settled games older than 3 months are folded into per-player totals
-- (wins / losses / net / games) and their records dropped, so the ledger
-- stays small. Unpaid games are never archived. Old unconfirmed games never
-- counted, so they're just dropped. Games from before the cut-off that a
-- guildmate re-sends are ignored (they're already in the totals).
function L:Archive()
    local cutoff = now() - ARCHIVE_DAYS * 86400
    local d = ns.udb.deathroll
    d.archive = d.archive or { totals = {}, before = 0 }
    local a = d.archive
    local changed = 0
    for id, rec in pairs(games()) do
        if (rec.t or 0) < cutoff then
            if not self:Confirmed(rec) or rec.conflict then
                games()[id] = nil
                changed = changed + 1
            elseif self:Owed(rec) <= 0 and rec.w and rec.l then
                local function t(name) a.totals[name] = a.totals[name] or { wins = 0, losses = 0, net = 0, games = 0 } return a.totals[name] end
                local w, l = t(rec.w), t(rec.l)
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
    for id, rec in pairs(games()) do
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
        local count, h = L:Digest(ns.me)
        if count > 0 then sendNow(table.concat({ "H", count, h }, SEP)) end
    end)
end

function L:ShareMine()
    if self._sharedAt and GetTime() - self._sharedAt < 20 then return end
    self._sharedAt = GetTime()
    local mine = {}
    for _, rec in pairs(games()) do
        if (rec.w == ns.me or rec.l == ns.me) and rec.src and rec.src[ns.me] then mine[#mine + 1] = rec end
    end
    table.sort(mine, function(a, b) return a.t > b.t end)
    for i = 1, math.min(#mine, MAX_SHARE) do
        local r = mine[i]
        queue[#queue + 1] = table.concat({ "E", r.id, r.w, r.l, r.g, r.t, r.r or 0, r.paid or 0 }, SEP)
    end
    self:StartPump()
end

function L:Merge(f, sender)
    local id, w, l = f[2], f[3], f[4]
    local g, t, r, paid = tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8])
    if not id or id == "" or not w or not l or not g or not t then return end
    if sender ~= w and sender ~= l then return end          -- only your own games
    local arch = ns.udb.deathroll.archive
    if arch and arch.before and t < arch.before and not games()[id] then return end   -- already in the archived totals
    local rec = games()[id]
    if not rec then
        rec = {
            id = id, w = w, l = l, g = g, t = t, r = r or 0, src = { [sender] = true },
            paid = (sender == w) and math.min(g, paid or 0) or 0,      -- only the winner vouches for payment
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
            if sender == rec.w and paid and paid > (rec.paid or 0) then
                rec.paid = math.min(rec.g, paid)
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
        local myCount, myHash = self:Digest(sender)
        if count and (count ~= myCount or h ~= myHash) then
            if requested[sender] and GetTime() - requested[sender] < 30 then return end
            requested[sender] = GetTime()
            C_Timer.After(0.5 + math.random() * 1.5, function() sendNow("Z" .. SEP .. sender) end)
        end
    elseif kind == "Z" then
        if f[2] ~= ns.me then return end
        if self:Quiet() then self._deferShare = true return end
        self:ShareMine()
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
