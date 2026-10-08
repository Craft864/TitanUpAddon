-- Titan Up - DeathRoll/DeathRoll.lua
-- Death roll: two players take turns /rolling. The first roll is 1-N (N =
-- the starting roll, usually the wager); every next roll is 1 up to the
-- previous result. Whoever rolls a 1 loses the wager.
--
-- Honesty: rolls are never sent between addons. Every client reads them
-- from the game's own system message ("Ryan rolls 2756 (1-100000)"), the
-- same text everyone in the group sees, and only accepts a roll from the
-- player whose turn it is with exactly the range they owe. Addon messages
-- are only used to set up the room (create, join, accept, cancel).
--
-- Messages ("TitanUpDR", fields joined by ^):
--   N id wager start target   new room (sender = host; target "" = anyone)
--   J id                      ask to take the open seat
--   S id opponent             host seats an opponent
--   Y id                      accept (ready)
--   G id first                host starts the game
--   X id                      cancel / leave
--   W id 1|0                  "I'm watching / stopped watching" (to the challenger)
--   V id total name,name,...  the spectator list (from the challenger)
--   D id                      the challenged/seated player declines (game stays open)
--   O id                      the challenger opens a reserved challenge to anyone
--   K id n roll max           echo of the sender's OWN roll #n (a fallback if
--                             someone's client couldn't read it from chat)
--   Q id                      "send me this room" (spectators, after combat, after /reload)
--   F id host wager start target opp state rolls   room state reply (from a player of the room)
--
-- Robustness: rolls can't be read during an encounter (chat text is hidden
-- from addons), so the Roll button pauses in combat/encounters; a roll that
-- couldn't be read simply doesn't count and is rolled again; after combat
-- (and after a /reload) the two players compare roll lists and keep the
-- longest one that follows the rules.
local ADDON, ns = ...

local DR = {}
ns.DeathRoll = DR

local PREFIX = "TitanUpDR"
local SEP = "^"
DR.MAX_ROLL = 1000000            -- WoW's /roll limit
DR.OPEN_TIMEOUT = 300            -- unanswered challenges expire after 5 minutes
DR.rooms = {}                    -- [id] = room
DR.mine = nil                    -- id of the room you're playing in

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
function DR.Fmt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local rollPattern
local function buildPattern()
    -- built from the client's own (localized) roll message
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
end

-- Strip player links / color codes from a name in a system message:
-- "|Hplayer:Metasham-Medivh|h[Metasham]|h" -> "Metasham-Medivh".
local function cleanName(name)
    local linked = name:match("|Hplayer:([^:|]+)")
    if linked then return linked end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    name = name:gsub("^%[", ""):gsub("%]$", "")
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

function DR:ParseRoll(msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return nil end
    if not rollPattern then buildPattern() end
    local name, roll, lo, hi = msg:match(rollPattern)
    if not name then return nil end
    name = cleanName(name)
    local noRealm = not name:find("-", 1, true)       -- WoW left the realm off (e.g. connected realms)
    return ns.NormalizeSender(name), tonumber(roll), tonumber(lo), tonumber(hi), noRealm
end

-- Same player? Exact match, or the same character name when one side
-- came through without a realm.
function DR.SameName(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ra, rb = a:find("-", 1, true), b:find("-", 1, true)
    local function strip(r) return (r or ""):gsub("[%s']", ""):lower() end
    local sa, sb = ns.Short(a), ns.Short(b)
    if sa ~= sb then return false end
    -- same name; realms equal once spaces/apostrophes are ignored
    return strip(a:sub((ra or #a) + 1)) == strip(b:sub((rb or #b) + 1))
end

-- Diagnostics for /tu roll debug: roll lines we couldn't use, and when the
-- echo fallback had to fill in.
DR.debugLog = {}
function DR:Log(text)
    table.insert(self.debugLog, 1, date("%H:%M:%S") .. "  " .. text)
    while #self.debugLog > 15 do table.remove(self.debugLog) end
end

function DR:Other(room, name)
    if name == room.host then return room.opponent end
    return room.host
end

function DR:IsPlayer(room, name)
    name = name or ns.me
    return name == room.host or (room.opponent ~= nil and name == room.opponent)
end

function DR:MyRoom()
    return self.mine and self.rooms[self.mine]
end

local function changed(room, what, extra)
    DR:SaveActive()
    DR:UpdateFilter()
    if ns.DeathRollUI then ns.DeathRollUI:OnChange(room, what, extra) end
end

local function cancel(room, by)
    room.state, room.cancelledBy = "cancelled", by
    if DR.mine == room.id then DR.mine = nil end
    changed(room, "cancelled")
end

-- Paused while rolls can't be read reliably (combat / encounter lockdown).
function DR:Paused() return ns.Busy() end

-- ---------------------------------------------------------------------
-- Messaging
-- ---------------------------------------------------------------------
-- (practice mode: nothing leaves your client)
function DR:Send(kind, ...)
    if not self.sim and IsInGroup() and not ns.InLockdown() then ns.SendFields(PREFIX, kind, ...) end
end

local function sayInGroup(text)
    if not DR.sim and IsInGroup() and not ns.InLockdown() then ns.SayGroup(text) end
end

function DR:Init()
    -- ledger sync is guild-wide; games are for guildmates in your group
    ns.Listen(PREFIX, function(text)
        local kind = text:sub(1, 1)
        return (kind == "H" or kind == "Z" or kind == "E" or kind == "C") and "guild" or "group"
    end, function(text, sender) DR:OnMessage(text, sender) end)
    ns.On("CHAT_MSG_SYSTEM", function(msg) DR:OnSystem(msg) end)
    ns.On("GROUP_ROSTER_UPDATE", function() DR:CheckRoster() end)
    for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END" }) do
        ns.On(ev, function() DR:OnCombatChange() end)
    end
    C_Timer.NewTicker(10, function()
        if not next(DR.rooms) and not DR.filterOn then return end   -- nothing going on
        DR:PruneSpectators()
        DR:Expire()
        DR:UpdateFilter()      -- safety net: the chat filter never outlives a game
    end)
    C_Timer.After(3, function() DR:RestoreActive() end)
end

function DR:OnMessage(text, sender)
    local f = ns.Split(text, SEP)
    if f[1] == "H" or f[1] == "Z" or f[1] == "E" or f[1] == "C" then return ns.DRLedger:OnMessage(f, sender) end
    local kind, id = f[1], f[2]
    if not id or id == "" then return end
    local room = self.rooms[id]

    if kind == "N" then
        local wager, start = tonumber(f[3]), tonumber(f[4])
        if not wager or not start or start < 2 or start > self.MAX_ROLL then return end
        room = {
            id = id, host = sender, wager = wager, start = start,
            target = (f[5] and f[5] ~= "") and f[5] or nil,
            ready = { [sender] = true }, state = "open", rolls = {}, created = GetTime(),
        }
        self.rooms[id] = room
        changed(room, "new")
    elseif not room then
        if kind == "F" then self:ApplyState(f, sender) end
        return
    elseif kind == "J" then
        -- only the host's client hands out the seat (first come, or the challenged player)
        if room.host == ns.me and room.state == "open" and (not room.target or room.target == sender) then
            room.opponent = sender
            room.state = "seated"
            self:Send("S", id, sender)
            if room.spectators and room.spectators[sender] then
                room.spectators[sender] = nil          -- they took the seat
                self:BroadcastSpectators(room)
            end
            changed(room, "seated")
        end
    elseif kind == "S" then
        if sender ~= room.host then return end
        room.opponent = f[3]
        room.state = "seated"
        if room.opponent == ns.me then self.mine = id end
        changed(room, "seated")
    elseif kind == "Y" then
        if not self:IsPlayer(room, sender) or room.state ~= "seated" then return end
        room.ready[sender] = true
        changed(room, "ready")
        self:MaybeStart(room)
    elseif kind == "G" then
        if sender ~= room.host or room.state ~= "seated" then return end
        self:BeginRolling(room, f[3])
    elseif kind == "X" then
        if not self:IsPlayer(room, sender) or room.state == "done" then return end
        cancel(room, sender)
    elseif kind == "D" then
        -- the challenged (or seated) player said no: the game stays open
        local reserved = room.target == sender and room.state == "open"
        local seated = room.opponent == sender and room.state == "seated"
        if not reserved and not seated then return end
        self:ApplyDecline(room, sender)
    elseif kind == "O" then
        if sender ~= room.host or room.state ~= "open" then return end
        room.target, room.declinedBy = nil, nil
        changed(room, "opened")
    elseif kind == "K" then
        -- a player's echo of their own roll: use it if chat didn't deliver it
        local n, roll, max = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
        if not n or not roll or not max then return end
        if not self:IsPlayer(room, sender) then return end
        C_Timer.After(1.5, function()
            if room.state ~= "rolling" or not DR.SameName(room.turn, sender) then return end   -- already applied from chat
            if #room.rolls + 1 ~= n or max ~= room.max or roll < 1 or roll > max then return end
            DR:Log(("used %s's roll report (%s, 1-%s) - their roll line never arrived in a readable form"):format(ns.Short(sender), DR.Fmt(roll), DR.Fmt(max)))
            DR:ApplyRoll(room, sender, roll, true)
        end)
    elseif kind == "W" then
        -- the challenger keeps the official spectator list
        if room.host ~= ns.me or self:IsPlayer(room, sender) then return end
        room.spectators = room.spectators or {}
        local was = room.spectators[sender] ~= nil
        if f[3] == "1" then room.spectators[sender] = GetTime() else room.spectators[sender] = nil end
        if was ~= (room.spectators[sender] ~= nil) then self:BroadcastSpectators(room) end
    elseif kind == "V" then
        if sender ~= room.host then return end
        room.specTotal = tonumber(f[3]) or 0
        room.specList = {}
        for n in (f[4] or ""):gmatch("[^,]+") do room.specList[#room.specList + 1] = n end
        changed(room, "spectators")
    elseif kind == "Q" then
        if self:IsPlayer(room, ns.me) then self:SendState(room) end
        -- a new watcher also needs the current spectator list
        if room.host == ns.me and room.spectators and next(room.spectators) then self:BroadcastSpectators(room) end
    elseif kind == "F" then
        self:ApplyState(f, sender)
    end
end

-- Full room state: for spectators who open the window late, and so the two
-- players can compare notes after combat or a /reload.
function DR:SendState(room)
    local rolls = {}
    for _, r in ipairs(room.rolls) do rolls[#rolls + 1] = r.who .. ":" .. r.roll .. ":" .. r.max end
    self:Send("F", room.id, room.host, room.wager, room.start, room.target or "", room.opponent or "",
        room.state, table.concat(rolls, ","))
end

-- A roll list is valid if it starts at the first roll, every roll stays in
-- the range set by the previous one, and the players alternate (host first).
function DR:ValidChain(room, rolls)
    local max, who = room.start, room.host
    for i, r in ipairs(rolls) do
        if r.max ~= max or r.roll < 1 or r.roll > max or r.who ~= who then return false end
        if r.roll == 1 and i ~= #rolls then return false end
        max = r.roll
        who = (who == room.host) and room.opponent or room.host
    end
    return true
end

-- Turn, range and result always follow from the roll list itself.
function DR:Derive(room)
    local last = room.rolls[#room.rolls]
    if last and last.roll == 1 then
        room.state, room.loser, room.winner, room.turn = "done", last.who, self:Other(room, last.who), nil
    elseif room.state == "rolling" or #room.rolls > 0 then
        room.state = "rolling"
        room.max = last and last.roll or room.start
        room.turn = last and self:Other(room, last.who) or room.host
    end
end

function DR:ApplyState(f, sender)
    local id = f[2]
    local host = f[3]
    local incoming = {
        host = host, wager = tonumber(f[4]) or 0, start = tonumber(f[5]) or 0,
        target = (f[6] ~= "" and f[6]) or nil, opponent = (f[7] ~= "" and f[7]) or nil,
        state = f[8] or "open", rolls = {},
    }
    for entry in (f[9] or ""):gmatch("[^,]+") do
        local who, roll, max = entry:match("^(.+):(%d+):(%d+)$")
        if who then incoming.rolls[#incoming.rolls + 1] = { who = who, roll = tonumber(roll), max = tonumber(max) } end
    end
    -- only the room's players speak for it
    if sender ~= incoming.host and sender ~= incoming.opponent then return end
    local room = self.rooms[id]
    if not room then
        room = { id = id, host = host, ready = {}, created = GetTime(), rolls = {}, state = "open" }
        for k, v in pairs(incoming) do if k ~= "rolls" then room[k] = v end end
        self.rooms[id] = room
    elseif room.host ~= host then
        return
    end
    if incoming.state == "cancelled" and room.state ~= "done" then
        room.state, room.cancelledBy = "cancelled", sender
    elseif incoming.state ~= "open" or room.state == "open" then
        room.opponent = room.opponent or incoming.opponent
        if room.state == "open" or room.state == "seated" then room.state = incoming.state end
        -- keep the longest roll list that follows the rules
        if #incoming.rolls > #room.rolls and self:ValidChain(room, incoming.rolls) then
            local before = #room.rolls
            room.rolls = incoming.rolls
            if self:IsPlayer(room) and before > 0 then
                room.warning = ("Caught up on %d roll(s) you missed."):format(#incoming.rolls - before)
            end
        end
        local wasDone = room.state == "done"
        self:Derive(room)
        if room.state == "done" and not wasDone then self:Finish(room) end
    end
    if room.opponent == ns.me or room.host == ns.me then self.mine = id end
    changed(room, "state")
end

-- ---------------------------------------------------------------------
-- Your actions
-- ---------------------------------------------------------------------
function DR:CanPlay()
    if self.sim then return true end
    if not IsInGroup() then return false, "You need to be in a party or raid - roll results only reach your group." end
    if not ns.DataChannel() then return false, ns.NEEDS_GUILD end
    if ns.InLockdown() then return false, "Can't start a death roll during an encounter." end
    return true
end

-- The first roll is always 1 to the wager (capped at WoW's /roll maximum).
function DR:Create(wager, target)
    local ok, why = self:CanPlay()
    if not ok then ns.Print(why) return nil end
    if self:MyRoom() and (self:MyRoom().state == "rolling" or self:MyRoom().state == "seated") then
        ns.Print("Finish or cancel your current death roll first.")
        return nil
    end
    wager = math.floor(tonumber(wager) or 0)
    if wager < 1 then ns.Print("Enter a wager of at least 1 gold.") return nil end
    local start = wager
    if start > self.MAX_ROLL then
        start = self.MAX_ROLL
        ns.Print("WoW's /roll tops out at " .. self.Fmt(self.MAX_ROLL) .. ", so the first roll is 1-" .. self.Fmt(start) .. ".")
    end
    if start < 2 then ns.Print("The starting roll has to be at least 2.") return nil end
    -- Server time makes the id unique and identical for both players, so
    -- both ledgers file the game under the same id.
    self._idSeq = ((self._idSeq or 0) % 9) + 1
    local id = ns.Short(ns.me) .. "-" .. ((GetServerTime and GetServerTime()) or time()) .. self._idSeq
    local room = {
        id = id, host = ns.me, wager = wager, start = start, target = target,
        ready = { [ns.me] = true }, state = "open", rolls = {}, created = GetTime(), sim = self.sim and true or nil,
    }
    self.rooms[id] = room
    self.mine = id
    self:Send("N", id, wager, start, target or "")
    if ns.udb.deathroll.announce then
        if target then
            sayInGroup(("%s challenges %s to a death roll for %sg! Open Titan Up (/tu roll) to accept."):format(
                ns.Short(ns.me), ns.Short(target), self.Fmt(wager)))
        else
            sayInGroup(("%s started a death roll for %sg - first roll 1-%s. Open Titan Up (/tu roll) to join!"):format(
                ns.Short(ns.me), self.Fmt(wager), self.Fmt(start)))
        end
    end
    changed(room, "new")
    return room
end

function DR:Join(id)
    local room = self.rooms[id]
    if not room or room.state ~= "open" then return end
    local ok, why = self:CanPlay()
    if not ok then ns.Print(why) return end
    if room.target and room.target ~= ns.me then
        ns.Print("That challenge is for " .. ns.Short(room.target) .. ".")
        return
    end
    room.joinRequested = true
    self:Send("J", id)
    changed(room, "joining")
end

function DR:Accept(id)
    local room = self.rooms[id]
    if not room or room.state ~= "seated" or not self:IsPlayer(room) then return end
    room.ready[ns.me] = true
    self:Send("Y", id)
    changed(room, "ready")
    self:MaybeStart(room)
end

function DR:MaybeStart(room)
    if room.host ~= ns.me or room.state ~= "seated" then return end
    if room.ready[room.host] and room.opponent and room.ready[room.opponent] then
        self:Send("G", room.id, room.host)
        self:BeginRolling(room, room.host)    -- the challenger rolls first
    end
end

function DR:BeginRolling(room, first)
    room.state = "rolling"
    room.turn = first
    room.max = room.start
    room.rolls = {}
    changed(room, "started")
    self:OnTurn(room)
end

function DR:Roll()
    local room = self:MyRoom()
    if not room or room.state ~= "rolling" or room.turn ~= ns.me then return end
    if room.pendingRoll and GetTime() - room.pendingRoll < 4 then return end   -- no double clicks
    if self:Paused() then
        ns.Print("Death roll is paused until combat ends.")
        return
    end
    local stamp = GetTime()
    room.pendingRoll = stamp
    if RandomRoll then
        RandomRoll(1, room.max)
    else
        ns.Print("Couldn't roll - type /roll " .. room.max .. " instead.")
    end
    -- If the result never shows up (combat, lag), the turn stays yours.
    C_Timer.After(4, function()
        if room.pendingRoll == stamp and room.state == "rolling" and room.turn == ns.me then
            room.pendingRoll = nil
            room.warning = "Couldn't read that roll - it doesn't count. Roll again."
            changed(room, "warning")
        end
    end)
end

function DR:Cancel(id)
    local room = self.rooms[id or self.mine or ""]
    if not room or room.state == "done" or room.state == "cancelled" then return end
    if not self:IsPlayer(room) then return end
    self:Send("X", room.id)
    cancel(room, ns.me)
    if self.sim then self.sim = nil end
end

-- Decline a challenge meant for you (or one you'd joined but not accepted).
-- The game isn't cancelled: the challenger can open it to anyone.
function DR:Decline(id)
    local room = self.rooms[id or ""]
    if not room or room.host == ns.me then return end
    local reserved = room.target == ns.me and room.state == "open"
    local seated = room.opponent == ns.me and room.state == "seated"
    if not reserved and not seated then return end
    self:Send("D", room.id)
    self:ApplyDecline(room, ns.me)
end

function DR:ApplyDecline(room, who)
    room.declinedBy = who
    if room.opponent == who then
        room.opponent = nil
        room.state = "open"
        room.ready = { [room.host] = true }
        room.joinRequested = nil
    end
    if self.mine == room.id and room.host ~= ns.me then self.mine = nil end
    changed(room, "declined")
end

-- Challenger: open a reserved (or declined) challenge to anyone in the group.
function DR:OpenToAnyone(id)
    local room = self.rooms[id or ""]
    if not room or room.host ~= ns.me or room.state ~= "open" then return end
    room.target, room.declinedBy = nil, nil
    self:Send("O", room.id)
    if ns.udb.deathroll.announce then
        sayInGroup(("%s's death roll for %sg is now open to anyone! Open Titan Up (/tu roll) to join."):format(
            ns.Short(ns.me), self.Fmt(room.wager)))
    end
    changed(room, "opened")
end

function DR:Watch(id)
    local room = self.rooms[id]
    if room then self:Send("Q", id) end
end

function DR:Rematch(id)
    local room = self.rooms[id]
    if not room or room.state ~= "done" then return end
    local opp = self:Other(room, ns.me)
    if room.sim then return self:StartSim(room.wager) end   -- practice stays practice
    return self:Create(room.wager, opp)
end

-- ---------------------------------------------------------------------
-- Rolls (from the game's system messages)
-- ---------------------------------------------------------------------
function DR:AnyRolling()
    for _, room in pairs(self.rooms) do if room.state == "rolling" then return true end end
    return false
end

function DR:OnSystem(msg)
    if not self:AnyRolling() then return end      -- most system messages: no game running
    if ns.IsSecret(msg) then
        self:Log("a system message arrived hidden (secret) - couldn't read it")
        return
    end
    local name, roll, lo, hi, noRealm = self:ParseRoll(msg)
    if not name then
        if type(msg) == "string" and msg:find("%d+%s*%(%d+%-%d+%)") then self:Log("couldn't read roll line: " .. msg:gsub("|", "||")) end
        return
    end
    local used = false
    for _, room in pairs(self.rooms) do
        if room.state == "rolling" and (self.SameName(room.turn, name)
            or (noRealm and ns.Short(room.turn or "") == ns.Short(name))) then
            used = true
            name = room.turn
            if lo == 1 and hi == room.max then
                self.matched[msg] = GetTime()
                self:ApplyRoll(room, name, roll)
            elseif self:IsPlayer(room) or room.watching then
                room.warning = ("%s rolled %s-%s - needs 1-%s. Ignored."):format(ns.Short(name), self.Fmt(lo), self.Fmt(hi), self.Fmt(room.max))
                changed(room, "warning")
            end
        end
    end
    if not used then
        for _, room in pairs(self.rooms) do
            if room.state == "rolling" and ns.Short(room.turn or "") == ns.Short(name) then
                self:Log(("roll line name '%s' didn't match '%s'"):format(name, room.turn))
            end
        end
    end
end

function DR:ApplyRoll(room, name, roll, fromEcho)
    local entry = { who = name, roll = roll, max = room.max }
    -- my own roll: echo it to the group so nobody's stuck if their client
    -- couldn't read it from chat
    if name == ns.me and not room.sim and not fromEcho then
        self:Send("K", room.id, #room.rolls + 1, roll, room.max)
    end
    room.rolls[#room.rolls + 1] = entry
    room.warning = nil
    room.pendingRoll = nil
    if roll == 1 then
        room.state = "done"
        room.loser = name
        room.winner = self:Other(room, name)
        room.turn = nil
        self:Finish(room)
    else
        room.max = roll
        room.turn = self:Other(room, name)
    end
    changed(room, "roll", entry)
    if room.state == "rolling" then self:OnTurn(room) end
end

function DR:Finish(room)
    if room.finished then return end
    room.finished = true
    if self:IsPlayer(room) and not room.sim then ns.DRLedger:RecordGame(room) end
    if room.host == ns.me and ns.udb.deathroll.announce then
        -- wait until the final roll has landed on screen, so chat can't spoil it
        local reveal = (ns.DeathRollUI and ns.DeathRollUI.SPIN or 1.2) + 0.4
        local text = ("%s won %sg from %s in a death roll (%d rolls)!"):format(
            ns.Short(room.winner), self.Fmt(room.wager), ns.Short(room.loser), #room.rolls)
        if room.sim then sayInGroup(text) else C_Timer.After(reveal, function() sayInGroup(text) end) end
    end
    if self.mine == room.id and self.sim then self.sim = nil end
end

-- ---------------------------------------------------------------------
-- Spectators
-- ---------------------------------------------------------------------
-- Watchers tell the challenger when they open/close a game and repeat it
-- every 30s while watching; the challenger keeps the list (dropping anyone
-- silent for 75s or no longer in the group) and shares it.
local WATCH_EVERY, WATCH_TIMEOUT = 30, 75

function DR:SpectatorNames(room)
    if room.host == ns.me then
        local list = {}
        for n in pairs(room.spectators or {}) do
            if not self:IsPlayer(room, n) then list[#list + 1] = n end      -- someone who took the seat isn't watching
        end
        table.sort(list)
        return list, #list
    end
    local list = {}
    for _, n in ipairs(room.specList or {}) do
        if not self:IsPlayer(room, n) then list[#list + 1] = n end
    end
    local dropped = #(room.specList or {}) - #list
    return list, math.max(#list, (room.specTotal or 0) - dropped)
end

function DR:BroadcastSpectators(room)
    local list, total = self:SpectatorNames(room)
    -- keep the message under the addon message size limit
    local names, len = {}, 0
    for _, n in ipairs(list) do
        if len + #n + 1 > 200 then break end
        names[#names + 1] = n
        len = len + #n + 1
    end
    self:Send("V", room.id, total, table.concat(names, ","))
    changed(room, "spectators")
end

function DR:PruneSpectators()
    local now = GetTime()
    for _, room in pairs(self.rooms) do
        if room.host == ns.me and room.spectators and next(room.spectators) then
            local dropped = false
            for n, seen in pairs(room.spectators) do
                if now - seen > WATCH_TIMEOUT or not ns.InMyGroup(n) then
                    room.spectators[n] = nil
                    dropped = true
                end
            end
            if dropped then self:BroadcastSpectators(room) end
        end
    end
end

-- Called by the window whenever the game you're looking at changes
-- (nil = you're not looking at any game).
function DR:SetWatching(id)
    local room = id and self.rooms[id]
    if room and (room.sim or self:IsPlayer(room, ns.me)) then room, id = nil, nil end
    if self.watching == id then return end
    if self.watching then self:Send("W", self.watching, "0") end
    self.watching = id
    if self.watchTicker then self.watchTicker:Cancel(); self.watchTicker = nil end
    if id then
        self:Send("W", id, "1")
        self.watchTicker = C_Timer.NewTicker(WATCH_EVERY, function()
            local r = DR.rooms[DR.watching or ""]
            if r and r.state ~= "cancelled" and r.state ~= "done" then DR:Send("W", r.id, "1") end
        end)
    end
end

function DR:CheckRoster()
    if self.sim or not next(self.rooms) then return end
    local members = {}
    for _, n in ipairs(ns.GroupNames()) do members[n] = true end
    for _, room in pairs(self.rooms) do
        if room.state == "open" or room.state == "seated" or room.state == "rolling" then
            local gone = (not members[room.host]) or (room.opponent and not members[room.opponent])
            if gone or not IsInGroup() then cancel(room, "left") end
        end
    end
end

function DR:Expire()
    local now = GetTime()
    for id, room in pairs(self.rooms) do
        if room.state == "open" and now - room.created > self.OPEN_TIMEOUT then cancel(room, "expired") end
        if (room.state == "cancelled" or room.state == "done") and id ~= self.mine and now - room.created > 3600 then
            self.rooms[id] = nil
        end
    end
end

-- ---------------------------------------------------------------------
-- Combat: pause, then compare notes
-- ---------------------------------------------------------------------
function DR:OnCombatChange()
    local room = self:MyRoom()
    if room then changed(room, "pause") end
    if self.Paused(self) or not room or room.sim then return end
    if room.state ~= "rolling" and room.state ~= "seated" then return end
    -- Back out of combat: ask the other player for their roll list.
    if self._resyncTimer then return end
    self._resyncTimer = true
    C_Timer.After(1.5, function()
        DR._resyncTimer = nil
        if not DR:Paused() and DR:MyRoom() == room then
            DR:Send("Q", room.id)
            DR:SendState(room)
        end
    end)
end

-- ---------------------------------------------------------------------
-- /reload safety: your active game is saved and picked back up.
-- ---------------------------------------------------------------------
function DR:SaveActive()
    if not ns.udb then return end
    local room = self:MyRoom()
    if room and not room.sim and (room.state == "seated" or room.state == "rolling") then
        local copy = { savedAt = time() }
        for _, k in ipairs({ "id", "host", "wager", "start", "target", "opponent", "state" }) do copy[k] = room[k] end
        copy.rolls = {}
        for i, r in ipairs(room.rolls) do copy.rolls[i] = { who = r.who, roll = r.roll, max = r.max } end
        copy.ready = {}
        for k, v in pairs(room.ready or {}) do copy.ready[k] = v end
        ns.udb.deathroll.active = copy
    else
        ns.udb.deathroll.active = nil
    end
end

function DR:RestoreActive()
    local saved = ns.udb and ns.udb.deathroll.active
    if not saved or self.rooms[saved.id] then return end
    local members = {}
    for _, n in ipairs(ns.GroupNames()) do members[n] = true end
    local other = (saved.host == ns.me) and saved.opponent or saved.host
    if time() - (saved.savedAt or 0) > 1800 or not IsInGroup() or not members[other] then
        ns.udb.deathroll.active = nil
        return
    end
    local room = { created = GetTime() }
    for k, v in pairs(saved) do room[k] = v end
    room.savedAt = nil
    self.rooms[room.id] = room
    self.mine = room.id
    self:Derive(room)
    ns.Print(("Picked your death roll against %s back up."):format(ns.Short(other)))
    self:Send("Q", room.id)
    self:SendState(room)
    changed(room, "state")
end

-- ---------------------------------------------------------------------
-- Chat filter: while a game is rolling, its roll lines are held back and
-- posted once the on-screen roll lands, so chat can't spoil the result.
-- Only that game's rolls are touched; the filter is removed as soon as no
-- game is rolling (checked on every change and every 10 seconds).
-- ---------------------------------------------------------------------
DR.matched = {}       -- [message] = time it was matched to a game
local held = {}       -- [message] = { frames = {...}, at = time }
local DELAY = 1.4

local function systemColor()
    local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
    if info then return info.r, info.g, info.b end
    return 1, 1, 0
end

function DR:IsGameRoll(msg)
    local t = self.matched[msg]
    if t and GetTime() - t < 5 then return true end
    local name, _, lo, hi = self:ParseRoll(msg)
    if not name then return false end
    for _, room in pairs(self.rooms) do
        if room.state == "rolling" and room.turn == name and lo == 1 and hi == room.max then return true end
    end
    return false
end

local function rollFilter(frame, _, msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return false end
    if not DR:IsGameRoll(msg) then return false end
    local h = held[msg]
    if not h or GetTime() - h.at > 5 then
        h = { frames = {}, at = GetTime() }
        held[msg] = h
        C_Timer.After(DELAY, function()
            held[msg] = nil
            local r, g, b = systemColor()
            for f in pairs(h.frames) do
                if f.AddMessage then f:AddMessage(msg, r, g, b) end
            end
        end)
    end
    if frame then h.frames[frame] = true end
    return true
end

function DR:UpdateFilter()
    local want = false                  -- chat never spoils a roll (normal /rolls untouched)
    for _, room in pairs(self.rooms) do
        if room.state == "rolling" then want = true break end
    end
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    local remove = ChatFrame_RemoveMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter)
    if want and not self.filterOn and add then
        add("CHAT_MSG_SYSTEM", rollFilter)
        self.filterOn = true
    elseif not want and self.filterOn and remove then
        remove("CHAT_MSG_SYSTEM", rollFilter)
        self.filterOn = false
    end
    for m, t in pairs(self.matched) do
        if GetTime() - t > 10 then self.matched[m] = nil end
    end
end

-- (records, payments and standings live in DeathRoll/Ledger.lua)

-- ---------------------------------------------------------------------
-- Practice mode (/tu roll sim): a fake opponent joins, accepts and rolls.
-- Your own rolls are real /rolls (they work solo); Brakk's are simulated.
-- ---------------------------------------------------------------------
local SIM_OPP = "Brakk"

function DR:StartSim(wager)
    if IsInGroup() then
        ns.Print("Practice mode is for solo testing - leave your group first.")
        return
    end
    local opp = SIM_OPP .. "-" .. (GetNormalizedRealmName() or "Medivh")
    self.sim = { opp = opp }
    local room = self:Create(wager or 10000, nil)
    if not room then self.sim = nil return end
    room.sim = true
    ns.Print("Practice death roll: " .. SIM_OPP .. " will join, accept and roll against you.")
    local id = room.id
    C_Timer.After(1.0, function() if DR.sim then DR:OnMessage("J" .. SEP .. id, opp) end end)
    C_Timer.After(2.2, function() if DR.sim then DR:OnMessage("Y" .. SEP .. id, opp) end end)
    if ns.DeathRollUI then ns.DeathRollUI:ShowRoom(id) end
end

function DR:OnTurn(room)
    if not (self.sim and room.sim and room.turn == self.sim.opp) then return end
    local max, opp = room.max, self.sim.opp
    C_Timer.After(1.6, function()
        if room.state ~= "rolling" or room.turn ~= opp or room.max ~= max then return end
        local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
        DR:OnSystem(fmt:format(SIM_OPP, math.random(1, max), 1, max))
    end)
end
