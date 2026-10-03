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
-- Raid instances (quiet mode): the only ledger traffic is the record of a
-- death roll that just finished, sent once to the raid by each player.
-- Summaries, the guild refresh, answering requests and payment updates
-- wait until you leave the instance. Incoming records are still accepted
-- (cheap). Nothing here touches protected functions, so combat can't cause
-- errors; sends are skipped during encounter lockdown.
--
-- Messages (prefix TitanUpDR):
--   H count hash                 digest of the sender's own games
--   Z name                       "name, please send your games"
--   E id w l g t r paid          one game record (sender must be w or l)
local ADDON, ns = ...

local L = {}
ns.DRLedger = L

local SEP = "^"
local SEND_RATE = 0.25      -- seconds between queued record messages
local MAX_SHARE = 150       -- most recent games each player shares
local KEEP_OTHERS = 1000    -- games between other players kept (all of yours are kept)

local queue = {}
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
L._dirty = dirty

function L:Quiet()
    local inInstance, kind = IsInInstance()
    return inInstance and kind == "raid"
end

function L:Init()
    ns.udb.deathroll.games = ns.udb.deathroll.games or {}
    self:Migrate()
    for _, rec in pairs(games()) do self:CheckLock(rec) end
    self:InitTrades()
    ns.On("GROUP_ROSTER_UPDATE", function()
        -- raids change roster constantly: share with the group at most once a minute
        if IsInGroup() and GetTime() - (L._groupDigestAt or -60) >= 60 then
            L._groupDigestAt = GetTime()
            L:ScheduleDigest(4, "group")
        end
    end)
    local function zoneCheck()
        if not L:Quiet() then L:FlushDeferred() end
    end
    ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, zoneCheck) end)
    ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, zoneCheck) end)
    C_Timer.After(6, function() L:ScheduleDigest(0) end)
    self:Trim()
    -- refresh the guild every 10 minutes (only differences cause any traffic)
    C_Timer.NewTicker(600, function() L:ScheduleDigest(0, "guild") end)
end

-- Records from 0.9.x's simple ledger become your own (one-sided) games.
function L:Migrate()
    local old = ns.udb.deathroll.ledger
    if not old or #old == 0 then return end
    for i, e in ipairs(old) do
        local id = "legacy-" .. ns.Short(ns.me) .. "-" .. (e.t or 0) .. "-" .. i
        if not games()[id] and e.opp then
            games()[id] = {
                id = id, w = e.won and ns.me or e.opp, l = e.won and e.opp or ns.me,
                g = e.wager or 0, t = e.t or 0, r = e.rolls or 0,
                paid = e.paid and (e.wager or 0) or 0, src = { [ns.me] = true },
            }
        end
    end
    ns.udb.deathroll.ledger = {}
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
    if self:Quiet() then
        -- raid instance: just this game, once, to the raid
        C_Timer.After(1, function() L:ShareGame(rec) end)
    else
        self:ScheduleDigest(1)
    end
    return rec
end

function L:ShareGame(rec)
    queue[#queue + 1] = { msg = table.concat({ "E", rec.id, rec.w, rec.l, rec.g, rec.t, rec.r or 0, rec.paid or 0 }, SEP), ch = "PARTY" }
    self:StartPump()
end

-- Work held back while in a raid instance, sent when you leave.
function L:FlushDeferred()
    if self._deferDigest then
        self._deferDigest = nil
        self:ScheduleDigest(2)
    end
    if self._deferShare then
        local chans = self._deferShare
        self._deferShare = nil
        for ch in pairs(chans) do self:ShareMine(ch ~= "GROUP" and ch or nil) end
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
    self:ScheduleDigest(1)
    refresh()
    return true
end

-- The loser's side: what you've sent, until the winner's addon confirms it.
function L:NoteSent(rec, amount)
    rec.sent = math.min(rec.g, math.max(rec.sent or 0, math.floor(amount)))
    refresh()
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
local trade

function L:InitTrades()
    local function amounts()
        if not trade then return end
        local mine = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
        local theirs = GetTargetTradeMoney and GetTargetTradeMoney() or 0
        if not ns.IsSecret(mine) then trade.gave = math.floor((mine or 0) / 10000) end
        if not ns.IsSecret(theirs) then trade.got = math.floor((theirs or 0) / 10000) end
    end
    ns.On("TRADE_SHOW", function()
        trade = { partner = ns.FullName("NPC"), gave = 0, got = 0 }
    end)
    ns.On("TRADE_MONEY_CHANGED", amounts)
    ns.On("TRADE_ACCEPT_UPDATE", amounts)
    ns.On("UI_INFO_MESSAGE", function(_, msg)
        if trade and msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
            local t = trade
            trade = nil
            L:OnTradeComplete(t.partner, t.gave or 0, t.got or 0)
        end
    end)
    ns.On("TRADE_CLOSED", function()
        local t = trade
        -- the "trade complete" message can arrive just after the window closes
        C_Timer.After(1, function() if trade == t then trade = nil end end)
    end)
end

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
function L:Digest(player)
    local c = digestCache[player]
    if c then return c[1], c[2] end
    local count, sum = 0, 0
    for id, rec in pairs(games()) do
        if (rec.w == player or rec.l == player) and rec.src and rec.src[player] then
            count = count + 1
            sum = (sum + hash(id .. ":" .. (rec.paid or 0))) % 2147483647
        end
    end
    digestCache[player] = { count, tostring(sum) }
    return count, tostring(sum)
end

-- channel: "GUILD", or nil/anything else = your party/raid.
local function canUse(channel)
    if ns.DeathRoll.sim or ns.InLockdown() then return nil end
    if channel == "GUILD" then return IsInGuild and IsInGuild() and "GUILD" or nil end
    return IsInGroup() and ns.GroupChannel() or nil
end

local function sendNow(msg, channel)
    local ch = canUse(channel)
    if not ch then return false end
    pcall(C_ChatInfo.SendAddonMessage, "TitanUpDR", msg, ch)
    return true
end

-- The send timer only runs while records are queued.
function L:Pump()
    if #queue == 0 then
        if self.pumpTicker then self.pumpTicker:Cancel(); self.pumpTicker = nil end
        return
    end
    if ns.InLockdown() then return end
    local item = table.remove(queue, 1)
    sendNow(item.msg, item.ch)
end

function L:StartPump()
    if not self.pumpTicker and #queue > 0 then self.pumpTicker = C_Timer.NewTicker(SEND_RATE, function() L:Pump() end) end
end

-- Keep every game you played; of everyone else's, keep the newest KEEP_OTHERS.
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

-- where: "group", "guild" or nil (both)
function L:ScheduleDigest(delay, where)
    if self:Quiet() then
        self._deferDigest = true          -- sent when you leave the raid instance
        return
    end
    if self._digestTimer then
        -- already scheduled: if the destinations differ, send to both
        if self._digestWhere ~= where then self._digestWhere = nil end
        return
    end
    self._digestWhere = where
    self._digestTimer = true
    C_Timer.After(delay or 0, function()
        L._digestTimer = nil
        local w = L._digestWhere
        local count, h = L:Digest(ns.me)
        if count == 0 then return end
        local msg = table.concat({ "H", count, h }, SEP)
        if w ~= "guild" then sendNow(msg, "PARTY") end
        if w ~= "group" then sendNow(msg, "GUILD") end
    end)
end

function L:ShareMine(channel)
    self._sharing = self._sharing or {}
    local key = channel == "GUILD" and "GUILD" or "GROUP"
    if self._sharing[key] and GetTime() - self._sharing[key] < 20 then return end
    self._sharing[key] = GetTime()
    local mine = {}
    for _, rec in pairs(games()) do
        if (rec.w == ns.me or rec.l == ns.me) and rec.src and rec.src[ns.me] then mine[#mine + 1] = rec end
    end
    table.sort(mine, function(a, b) return a.t > b.t end)
    for i = 1, math.min(#mine, MAX_SHARE) do
        local r = mine[i]
        queue[#queue + 1] = { msg = table.concat({ "E", r.id, r.w, r.l, r.g, r.t, r.r or 0, r.paid or 0 }, SEP), ch = channel }
    end
    self:StartPump()
end

function L:Merge(f, sender)
    local id, w, l = f[2], f[3], f[4]
    local g, t, r, paid = tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8])
    if not id or id == "" or not w or not l or not g or not t then return end
    if sender ~= w and sender ~= l then return end          -- only your own games
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
    refresh()
end

function L:OnMessage(f, sender, channel)
    local kind = f[1]
    if kind == "H" then
        if self:Quiet() then return end           -- raid instance: compare notes later
        local count, h = tonumber(f[2]), f[3]
        local myCount, myHash = self:Digest(sender)
        if count and (count ~= myCount or h ~= myHash) then
            if requested[sender] and GetTime() - requested[sender] < 30 then return end
            requested[sender] = GetTime()
            C_Timer.After(0.5 + math.random() * 1.5, function() sendNow("Z" .. SEP .. sender, channel) end)
        end
    elseif kind == "Z" then
        if f[2] ~= ns.me then return end
        if self:Quiet() then
            self._deferShare = self._deferShare or {}
            self._deferShare[channel == "GUILD" and "GUILD" or "GROUP"] = true
            return
        end
        self:ShareMine(channel)
    elseif kind == "E" then
        self:Merge(f, sender)
    end
end
