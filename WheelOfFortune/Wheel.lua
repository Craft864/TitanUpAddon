-- Titan Up - WheelOfFortune/Wheel.lua
-- Wheel of Fortune. One host runs the game (sets the puzzles, doesn't
-- play); up to three players take seats.
--
-- Rules (like the show):
--   * On your turn: SPIN, BUY A VOWEL ($250 from your round money), or SOLVE.
--   * Spin lands on $ -> call a consonant; you earn $ x each time it appears
--     and keep your turn. Not in the puzzle (or already called) -> next player.
--   * BANKRUPT -> lose your round money and your turn. LOSE A TURN -> next player.
--   * A vowel that's not in the puzzle passes the turn; a wrong solve too.
--   * Solving banks your round money (at least $1,000) into your total.
--   * Most money after the last round wins.
--   * Bonus round (optional, ticked in the lobby): the winner gets R S T L N E
--     free, picks 3 more consonants and a vowel, then has BONUS_SOLVE seconds
--     to solve (as many guesses as they like) for a hidden bonus prize.
--
-- The host's client is the referee: it holds the phrase, spins, checks
-- letters and solves, and only ever sends the board with unrevealed letters
-- hidden - so players can't read the answer from addon traffic.
--
-- Messages ("TitanUpWF", fields joined by ^):
--   N id rounds auto prize bonus     host opened a game (the id starts with the host's name; bonus 0.36.0)
--   P id name,name,name              seats
--   S id ...state... cat mask left auto prize   game state (mask: "_" = hidden letter;
--                                    the prize is left off when it won't fit)
--   X id                             host closed the game
--   J id / L id                      take / leave a seat (to host)
--   A id action arg                  spin | letter X | vowel X | solve text (to host)
--   Q id                             ask the host for the current state
-- Bonus round (0.36.0): the S state is "bonus" with phase "pick" (arg = the
-- letters picked so far) then "solve". Older clients just watch it; the
-- wire format is unchanged apart from the extra N field.
local ADDON, ns = ...

local WF = {}
ns.Wheel = WF

local PREFIX = "TitanUpWF"
local SEP = "^"

-- wedge i sits (i-1)*15 degrees clockwise from the top of Media/Wheel
WF.WEDGES = { 2500, 600, 700, 600, 650, 500, 700, "B", 600, 550, 500, 600,
              800, 650, "L", 700, 900, 500, 650, 300, "B", 350, 600, 450 }
WF.VOWELS = "AEIOU"
WF.CONSONANTS = "BCDFGHJKLMNPQRSTVWXYZ"
WF.VOWEL_COST = 250
WF.MIN_WIN = 1000
WF.SEATS = 3
WF.MAX_ROUNDS = 5
WF.SPIN_TIME = 2.5          -- seconds from SPIN to the result (3.4 before 0.36.0)
WF.ROWS, WF.COLS = 4, 14
WF.BONUS_FREE = "RSTLNE"
WF.BONUS_PICKS, WF.BONUS_VOWELS = 3, 1
WF.BONUS_SOLVE = 20         -- seconds to solve the bonus puzzle (10 on the show; typing takes longer)
WF.BONUS_PRIZES = { 25000, 30000, 35000, 40000, 50000, 75000, 100000 }

WF.games = {}
WF.current = nil   -- id of the game you're hosting / playing / watching

-- Ready-made puzzles: { category, phrase, theme }. Every one fits the
-- board (4 rows of 14, words not split). Hosts can type their own too.
WF.BANK = {
    -- World of Warcraft
    { "PHRASE", "DON'T STAND IN THE FIRE", "wow" },
    { "PHRASE", "STAND IN THE GOOD STUFF", "wow" },
    { "PHRASE", "ONE MORE PULL", "wow" },
    { "PHRASE", "WHO PULLED THAT", "wow" },
    { "PHRASE", "TITAN UP", "wow" },
    { "PHRASE", "NEED BEFORE GREED", "wow" },
    { "PHRASE", "TANK AND SPANK", "wow" },
    { "PHRASE", "RELEASE AND RUN BACK", "wow" },
    { "PHRASE", "HEALER IS OUT OF MANA", "wow" },
    { "PHRASE", "CLICK THE PORTAL", "wow" },
    { "PHRASE", "INTERRUPT THE CAST", "wow" },
    { "PHRASE", "FOR THE HORDE", "wow" },
    { "PHRASE", "FOR THE ALLIANCE", "wow" },
    { "PHRASE", "YOU ARE NOT PREPARED", "wow" },
    { "PHRASE", "TIME IS MONEY FRIEND", "wow" },
    { "PHRASE", "JOB'S DONE", "wow" },
    { "PHRASE", "ZUG ZUG", "wow" },
    { "PHRASE", "LOK'TAR OGAR", "wow" },
    { "PHRASE", "ALL OF THE LOOT", "wow" },
    { "PHRASE", "BOP IT TWIST IT PULL IT", "wow" },
    { "PHRASE", "LOOT COUNCIL DRAMA", "wow" },
    { "PHRASE", "WIPE IT UP", "wow" },
    { "PHRASE", "SAVE THE BLOODLUST", "wow" },
    { "PLACE", "STORMWIND CITY", "wow" },
    { "PLACE", "ORGRIMMAR", "wow" },
    { "PLACE", "THE MOLTEN CORE", "wow" },
    { "PLACE", "BLACKROCK MOUNTAIN", "wow" },
    { "PLACE", "GOLDSHIRE INN", "wow" },
    { "PLACE", "THE BARRENS", "wow" },
    { "PLACE", "ICECROWN CITADEL", "wow" },
    { "PLACE", "SILVERMOON CITY", "wow" },
    { "PLACE", "SHATTRATH CITY", "wow" },
    { "PLACE", "THE DARK PORTAL", "wow" },
    { "PLACE", "UNDERCITY", "wow" },
    { "PLACE", "THOUSAND NEEDLES", "wow" },
    { "PLACE", "THE AUCTION HOUSE", "wow" },
    { "PLACE", "THE GREAT VAULT", "wow" },
    { "PLACE", "IRONFORGE", "wow" },
    { "PLACE", "THE EMERALD DREAM", "wow" },
    { "CHARACTER", "LEEROY JENKINS", "wow" },
    { "CHARACTER", "ARTHAS MENETHIL", "wow" },
    { "CHARACTER", "SYLVANAS WINDRUNNER", "wow" },
    { "CHARACTER", "JAINA PROUDMOORE", "wow" },
    { "CHARACTER", "ILLIDAN STORMRAGE", "wow" },
    { "CHARACTER", "THE LICH KING", "wow" },
    { "CHARACTER", "DEATHWING", "wow" },
    { "CHARACTER", "HOGGER", "wow" },
    { "CHARACTER", "MANKRIK'S WIFE", "wow" },
    { "CHARACTER", "GROMMASH HELLSCREAM", "wow" },
    { "CHARACTER", "ANDUIN WRYNN", "wow" },
    { "CHARACTER", "KHADGAR", "wow" },
    { "CHARACTER", "CHROMIE", "wow" },
    { "THING", "HEARTHSTONE", "wow" },
    { "THING", "A STACK OF HEALTHSTONES", "wow" },
    { "THING", "DUNGEON FINDER", "wow" },
    { "THING", "REPAIR BOT", "wow" },
    { "THING", "A LEGENDARY CLOAK", "wow" },
    { "THING", "THE CORRUPTED ASHBRINGER", "wow" },
    { "THING", "AN EMPTY QUIVER", "wow" },
    { "THINGS", "PETS AND MOUNTS", "wow" },
    { "THINGS", "MURLOCS", "wow" },
    { "THINGS", "CLOTH SCRAPS", "wow" },
    { "WHAT ARE YOU DOING?", "WIPING ON TRASH", "wow" },
    { "WHAT ARE YOU DOING?", "STANDING IN FIRE", "wow" },
    { "WHAT ARE YOU DOING?", "RUNNING BACK FROM THE GRAVEYARD", "wow" },
    { "WHAT ARE YOU DOING?", "QUEUEING FOR DUNGEONS", "wow" },
    { "WHAT ARE YOU DOING?", "FARMING GOLD", "wow" },
    { "WHAT ARE YOU DOING?", "FISHING IN DALARAN", "wow" },
    { "WHAT ARE YOU DOING?", "WAITING ON THE TANK", "wow" },
    { "WHAT ARE YOU DOING?", "DANCING ON A MAILBOX", "wow" },
    { "FOOD & DRINK", "CONJURED MANA BUNS", "wow" },
    { "FOOD & DRINK", "MOONBERRY JUICE", "wow" },
    { "FOOD & DRINK", "A HEARTY FEAST", "wow" },
    { "EVENT", "GUILD RAID NIGHT", "wow" },
    { "EVENT", "BREWFEST", "wow" },
    { "EVENT", "HALLOW'S END", "wow" },
    { "EVENT", "THE DARKMOON FAIRE", "wow" },
    { "EVENT", "FEAST OF WINTER VEIL", "wow" },
    { "BEFORE & AFTER", "HEARTHSTONE COLD", "wow" },
    { "BEFORE & AFTER", "MURLOC AND KEY", "wow" },
    { "BEFORE & AFTER", "LEEROY JENKINS WAS HERE", "wow" },
    { "RHYME TIME", "GNOME SWEET GNOME", "wow" },
    { "RHYME TIME", "TROLL TOLL", "wow" },
    { "RHYME TIME", "MAGE RAGE", "wow" },
    { "RHYME TIME", "LOOT ROUTE", "wow" },
    -- Pop culture
    { "MOVIE TITLE", "THE LORD OF THE RINGS", "pop" },
    { "MOVIE TITLE", "JURASSIC PARK", "pop" },
    { "MOVIE TITLE", "BACK TO THE FUTURE", "pop" },
    { "MOVIE TITLE", "THE PRINCESS BRIDE", "pop" },
    { "MOVIE TITLE", "STAR WARS", "pop" },
    { "MOVIE TITLE", "THE LION KING", "pop" },
    { "MOVIE TITLE", "GHOSTBUSTERS", "pop" },
    { "MOVIE TITLE", "TOP GUN", "pop" },
    { "MOVIE TITLE", "FINDING NEMO", "pop" },
    { "MOVIE TITLE", "THE MATRIX", "pop" },
    { "MOVIE TITLE", "HOME ALONE", "pop" },
    { "MOVIE TITLE", "JAWS", "pop" },
    { "MOVIE TITLE", "TOY STORY", "pop" },
    { "MOVIE TITLE", "THE GOONIES", "pop" },
    { "TV SHOW", "THE OFFICE", "pop" },
    { "TV SHOW", "GAME OF THRONES", "pop" },
    { "TV SHOW", "STRANGER THINGS", "pop" },
    { "TV SHOW", "BREAKING BAD", "pop" },
    { "TV SHOW", "FRIENDS", "pop" },
    { "TV SHOW", "THE SIMPSONS", "pop" },
    { "TV SHOW", "SCOOBY-DOO", "pop" },
    { "TV SHOW", "THE MANDALORIAN", "pop" },
    { "CHARACTER", "DARTH VADER", "pop" },
    { "CHARACTER", "HARRY POTTER", "pop" },
    { "CHARACTER", "MARIO AND LUIGI", "pop" },
    { "CHARACTER", "SPONGEBOB SQUAREPANTS", "pop" },
    { "CHARACTER", "PIKACHU", "pop" },
    { "CHARACTER", "SHERLOCK HOLMES", "pop" },
    { "CHARACTER", "INDIANA JONES", "pop" },
    { "CHARACTER", "GANDALF THE GREY", "pop" },
    { "CHARACTER", "SUPER MARIO", "pop" },
    { "CHARACTER", "BATMAN AND ROBIN", "pop" },
    { "PHRASE", "MAY THE FORCE BE WITH YOU", "pop" },
    { "PHRASE", "WINTER IS COMING", "pop" },
    { "PHRASE", "I'LL BE BACK", "pop" },
    { "PHRASE", "TO INFINITY AND BEYOND", "pop" },
    { "PHRASE", "HOUSTON WE HAVE A PROBLEM", "pop" },
    { "PHRASE", "GAME OVER", "pop" },
    { "PHRASE", "LEVEL UP", "pop" },
    { "PHRASE", "ONE DOES NOT SIMPLY", "pop" },
    { "PHRASE", "IT'S DANGEROUS TO GO ALONE", "pop" },
    { "PHRASE", "PRESS START TO PLAY", "pop" },
    { "PHRASE", "ARE WE THERE YET", "pop" },
    { "PLACE", "HOGWARTS", "pop" },
    { "PLACE", "THE DEATH STAR", "pop" },
    { "PLACE", "JURASSIC PARK", "pop" },
    { "PLACE", "THE SHIRE", "pop" },
    { "PLACE", "BIKINI BOTTOM", "pop" },
    { "THING", "A LIGHTSABER", "pop" },
    { "THING", "THE ONE RING", "pop" },
    { "THING", "A DELOREAN", "pop" },
    { "THING", "THE MASTER SWORD", "pop" },
    { "FOOD & DRINK", "PIZZA AND WINGS", "pop" },
    { "FOOD & DRINK", "MOUNTAIN OF NACHOS", "pop" },
    { "BEFORE & AFTER", "STAR WARS OF THE ROSES", "pop" },
    { "BEFORE & AFTER", "HARRY POTTER AND THE CHAMBER OF COMMERCE", "pop" },
}
WF.THEMES = { { key = nil, label = "All" }, { key = "wow", label = "WoW" }, { key = "pop", label = "Pop culture" } }

-- A random puzzle from a theme (nil = all), avoiding phrases in `taken`.
function WF.RandomPuzzle(theme, taken)
    local pool = {}
    for _, p in ipairs(WF.BANK) do
        if (not theme or p[3] == theme) and not (taken and taken[p[2]]) then pool[#pool + 1] = p end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

-- True when R S T L N E leave something to guess.
function WF.BonusOK(phrase) return WF.Mask(phrase, WF.BONUS_FREE):find("_") ~= nil end

-- A random bonus puzzle (one R S T L N E doesn't give away).
function WF.RandomBonus(theme, taken)
    local skip = {}
    for k in pairs(taken or {}) do skip[k] = true end
    for _ = 1, #WF.BANK do
        local pz = WF.RandomPuzzle(theme, skip)
        if not pz or WF.BonusOK(pz[2]) then return pz end
        skip[pz[2]] = true
    end
end
-- ---------------------------------------------------------------------
-- Puzzle text
-- ---------------------------------------------------------------------
function WF.Clean(text, max, asTyped)
    if asTyped then
        -- free text (the prize): keep case and digits, drop anything that could
        -- break a message (separators, escape codes, line breaks)
        text = tostring(text or ""):gsub("[^%w '&%-%?!%.,:+/]", "")
        text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        return text:sub(1, max or 60)
    end
    text = tostring(text or ""):upper():gsub("[^A-Z '&%-%?!%.,]", "")
    text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return text:sub(1, max or 60)
end

-- Lay a phrase (or its mask) out on the 4 x 14 board, words kept whole.
-- Returns { "ROW ONE", "ROW TWO", ... } or nil if it doesn't fit.
function WF.Layout(text)
    local rows, line = {}, ""
    for word in text:gmatch("%S+") do
        if #word > WF.COLS then return nil end
        local candidate = (line == "") and word or (line .. " " .. word)
        if #candidate <= WF.COLS then
            line = candidate
        else
            rows[#rows + 1] = line
            line = word
        end
    end
    if line ~= "" then rows[#rows + 1] = line end
    if #rows == 0 or #rows > WF.ROWS then return nil end
    return rows
end

local function isLetter(ch) return ch:match("^[A-Z]$") ~= nil end
local function isVowel(ch) return WF.VOWELS:find(ch, 1, true) ~= nil end

function WF.Mask(phrase, used)
    return (phrase:gsub("[A-Z]", function(ch) return used:find(ch, 1, true) and ch or "_" end))
end

local function count(phrase, letter)
    local n = 0
    for ch in phrase:gmatch(".") do if ch == letter then n = n + 1 end end
    return n
end

-- Letters still hidden: consonants, vowels
local function remaining(phrase, used)
    local c, v = 0, 0
    local seen = {}
    for ch in phrase:gmatch("[A-Z]") do
        if not seen[ch] and not used:find(ch, 1, true) then
            seen[ch] = true
            if isVowel(ch) then v = v + 1 else c = c + 1 end
        end
    end
    return c, v
end

function WF.SeatOf(g, name)
    for i, n in ipairs(g.seats) do if n == name then return i end end
end

-- ---------------------------------------------------------------------
-- Messaging
-- ---------------------------------------------------------------------
-- (during an encounter the send queue holds them until it ends)
function WF:Send(...)
    if not self.sim and IsInGroup() then ns.SendFields(PREFIX, ...) end
end

-- a whole number from a message within lo..hi, else nil (nan / inf too)
local function int(v, lo, hi)
    local n = tonumber(v)
    if n and n == n and n % 1 == 0 and n >= lo and n <= hi then return n end
end

-- a game id starts with its host's name ("Ryan-1790000000")
local function hostsId(id, name) return id:sub(1, #ns.Short(name) + 1) == ns.Short(name) .. "-" end

local function ui(what, g, extra)
    if ns.WheelUI then ns.WheelUI:OnChange(what, g, extra) end
end

function WF:Init()
    ns.Listen(PREFIX, "group", function(text, sender) WF:OnMessage(text, sender) end)
    ns.On("GROUP_ROSTER_UPDATE", function() WF:CheckRoster() end)
end

function WF:IsHost(g) return g and (g.host == ns.me or g.engine) end

-- Everyone's copy of the state (the host also keeps g.phrase / g.puzzles).
-- The prize (also in the N) is left off when the message would pass the
-- 255-byte limit; receivers then keep the prize they have.
function WF:StateMessage(g)
    local left = g.turnEnds and math.max(0, math.ceil(g.turnEnds - GetTime())) or -1
    local text = ns.Join("S", g.id, g.state, g.round, g.rounds, g.turn, g.phase, g.spin, g.sq, g.value,
        table.concat(g.bank, ","), table.concat(g.total, ","), g.used, g.msg, g.arg, g.cat, g.mask,
        left, g.auto and 1 or 0)
    local full = text .. "^" .. (g.prize or "")
    return #full <= 255 and full or text
end

-- ---------------------------------------------------------------------
-- Turn timer: the referee gives each player 25 seconds to act (spin / buy /
-- solve, or pick a consonant). Any progress restarts the clock; running out
-- passes the turn. A light check runs only while a game it referees is in play.
-- ---------------------------------------------------------------------
WF.TURN_SECONDS = 25

local function waiting(g)
    if g.state == "bonus" then return g.phase == "pick" or g.phase == "solve" end
    return g.state == "playing" and (g.phase == "turn" or g.phase == "letter")
end
-- a game that's being played (a round or the bonus round)
local function live(g) return g.state == "playing" or g.state == "bonus" end

function WF:ArmTimer(g)
    if waiting(g) then
        local key = table.concat({ g.state, g.round, g.turn, g.phase, g.used, g.sq, g.value, g.picks or "" }, ":")
        if key ~= g.timerKey then
            g.timerKey, g.turnEnds = key, GetTime() + (g.phase == "solve" and WF.BONUS_SOLVE or WF.TURN_SECONDS)
        end
        if not self.timerTicker then self.timerTicker = C_Timer.NewTicker(0.5, function() WF:CheckTimers() end) end
    else
        g.turnEnds, g.timerKey = nil, nil
    end
end

function WF:CheckTimers()
    local any = false
    for _, g in pairs(self.games) do
        if self:IsHost(g) and waiting(g) and g.turnEnds then
            any = true
            if GetTime() >= g.turnEnds then
                g.timerKey = nil
                if g.state == "bonus" then
                    self:BonusTimeout(g)
                else
                    local seat = g.turn
                    self:NextTurn(g)
                    g.msg, g.arg = "timeout", tostring(seat)
                    self:Broadcast(g)
                end
            end
        end
    end
    if not any and self.timerTicker then self.timerTicker:Cancel(); self.timerTicker = nil end
end

-- Prize: a number shows as gold, anything else as written.
function WF.PrizeText(prize)
    if not prize or prize == "" then return nil end
    local n = tonumber((prize:gsub("[,%s]", ""):gsub("[gG]$", "")))
    if n and n > 0 then
        return ((BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(n))) or tostring(math.floor(n))) .. "g |TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"
    end
    return prize
end

WF.SOLO_NEXT_ROUND = 5      -- seconds the bot host waits before the next round

function WF:Broadcast(g)
    if g.phrase then g.mask = WF.Mask(g.phrase, g.used) end
    if self:IsHost(g) then self:ArmTimer(g) end
    self:Send(self:StateMessage(g))
    ui("state", g)
    self:BotTurn(g)
    -- solo and Play-together games move on to the next round by themselves
    if ((g.engine and self.sim) or g.auto) and g.state == "roundover" and g.autoNext ~= g.round then
        g.autoNext = g.round
        local round = g.round
        C_Timer.After(WF.SOLO_NEXT_ROUND, function()
            if (WF.sim or g.auto) and g.state == "roundover" and g.round == round then WF:NextRound(g) end
        end)
    end
end

function WF:BroadcastSeats(g)
    self:Send("P", g.id, table.concat(g.seats, ","))
    ui("seats", g)
end

function WF:OnMessage(text, sender)
    local f = ns.Split(text, SEP)
    local kind, id = f[1], f[2]
    if not id or id == "" then return end
    local g = self.games[id]
    if kind == "N" then
        -- a new game: never one that already exists, and only under the sender's own name
        local rounds = int(f[3], 1, WF.MAX_ROUNDS)
        if g or not rounds or not hostsId(id, sender) then return end
        g = self:NewGame(id, sender, rounds)
        g.auto, g.prize, g.bonus = f[4] == "1", WF.Clean(f[5] or "", 48, true), f[6] == "1"
        ui("new", g)
        return
    end
    if not g then
        -- a game we never saw opened (we /reloaded, or joined the group late):
        -- picked up from its host's own seat list or state
        if (kind ~= "S" and kind ~= "P") or not hostsId(id, sender) then return end
        g = self:NewGame(id, sender, int(f[5], 1, WF.MAX_ROUNDS) or 1)
    end
    if g.host == ns.me then
        -- we're the referee
        if kind == "J" then self:HostJoin(g, sender)
        elseif kind == "L" then self:HostLeave(g, sender)
        elseif kind == "A" then self:HostAct(g, sender, f[3], f[4])
        elseif kind == "Q" then self:BroadcastSeats(g); self:Send(self:StateMessage(g)) end
        return
    end
    if sender ~= g.host then return end
    if kind == "P" then
        g.seats = {}
        for n in (f[3] or ""):gmatch("[^,]+") do g.seats[#g.seats + 1] = n end
        ui("seats", g)
    elseif kind == "S" then
        local prevSq = g.sq
        g.state, g.round, g.rounds, g.turn = f[3], int(f[4], 0, WF.MAX_ROUNDS) or 0, int(f[5], 1, WF.MAX_ROUNDS) or 1, int(f[6], 0, WF.SEATS) or 0
        g.phase, g.spin, g.sq, g.value = f[7] or "", int(f[8], 0, #WF.WEDGES) or 0, int(f[9], 0, 1e9) or 0, int(f[10], 0, 1e6) or 0
        local function nums(s) local t = {} for n in (s or ""):gmatch("[^,]+") do t[#t + 1] = int(n, -1e9, 1e9) or 0 end return t end
        g.bank, g.total = nums(f[11]), nums(f[12])
        g.used, g.msg, g.arg, g.cat, g.mask = f[13] or "", f[14] or "", f[15] or "", f[16] or "", f[17] or ""
        local left = int(f[18], -1, 600)
        g.turnEnds = (left and left >= 0) and (GetTime() + left) or nil
        g.auto = f[19] == "1"
        if f[20] then g.prize = WF.Clean(f[20], 48, true) end
        if g.state == "bonus" then g.bonus = true end
        self:HeardHost(g)
        ui("state", g, { spun = g.sq ~= prevSq and g.phase == "spinning" })
    elseif kind == "X" then
        g.state = "cancelled"
        g.msg = "ended"
        ui("state", g)
    end
end

-- Players' side: a game whose host has gone quiet while it's being played
-- (they /reloaded or went offline - offline players stay in the group) is
-- ended after a full turn plus half a minute. The host's referee sends an
-- update at least every turn, so silence that long means it's gone.
WF.HOST_SILENCE = WF.TURN_SECONDS + 30

function WF:HeardHost(g)
    g.heardAt = GetTime()
    if live(g) and not self.hostTicker then
        self.hostTicker = C_Timer.NewTicker(5, function() WF:CheckHosts() end)
    end
end

function WF:CheckHosts()
    local any = false
    for _, g in pairs(self.games) do
        if not self:IsHost(g) and live(g) and g.heardAt then
            if ns.InLockdown() then
                g.heardAt = GetTime()             -- an encounter holds every message: not the host's fault
            elseif GetTime() - g.heardAt > WF.HOST_SILENCE then
                g.state, g.msg = "cancelled", "lost"
                ui("state", g)
            end
            any = any or live(g)
        end
    end
    if not any and self.hostTicker then self.hostTicker:Cancel(); self.hostTicker = nil end
end

-- Finished/closed games are dropped after 30 minutes.
function WF:Cleanup()
    local now = GetTime()
    for id, g in pairs(self.games) do
        if (g.state == "over" or g.state == "cancelled") and now - g.created > 1800 and id ~= self.current then
            self.games[id] = nil
        end
    end
end

function WF:NewGame(id, host, rounds)
    self:Cleanup()
    local g = {
        id = id, host = host, seats = {}, state = "lobby", round = 0, rounds = rounds,
        turn = 0, phase = "", spin = 0, sq = 0, value = 0,
        bank = { 0, 0, 0 }, total = { 0, 0, 0 }, used = "", msg = "", arg = "", cat = "", mask = "",
        created = GetTime(), gone = {},
    }
    self.games[id] = g
    return g
end

-- ---------------------------------------------------------------------
-- Your actions (players send them to the host; the host applies them)
-- ---------------------------------------------------------------------
function WF:CanPlay()
    if self.sim then return true end
    if not IsInGroup() then return false, "Wheel of Fortune is played with your party or raid - join a group first." end
    if not ns.DataChannel() then return false, ns.NEEDS_GUILD end
    if ns.InLockdown() then return false, "Can't play during an encounter." end
    return true
end

-- puzzles = { { category, phrase }, ... }; bonus = { category, phrase } or nil
function WF:Host(puzzles, prize, bonus)
    local ok, why = self:CanPlay()
    if not ok then ns.Print(why) return nil end
    local list = {}
    for i, p in ipairs(puzzles) do
        local cat, phrase = WF.Clean(p[1], 24), WF.Clean(p[2], 56)
        if phrase ~= "" then
            if not phrase:find("[A-Z]") then ns.Print(("Round %d's puzzle needs some letters."):format(i)) return nil end
            if not WF.Layout(phrase) then
                ns.Print(("Round %d's puzzle doesn't fit the board (4 rows of 14, words can't be split)."):format(i))
                return nil
            end
            list[#list + 1] = { cat ~= "" and cat or "PHRASE", phrase }
        end
    end
    if #list == 0 then ns.Print("Add at least one puzzle (category + phrase).") return nil end
    if #list > WF.MAX_ROUNDS then ns.Print("Up to " .. WF.MAX_ROUNDS .. " rounds per game.") return nil end
    local bonusPz
    if bonus then
        local cat, phrase = WF.Clean(bonus[1], 24), WF.Clean(bonus[2], 56)
        if phrase == "" or not phrase:find("[A-Z]") then ns.Print("Add a bonus puzzle, or untick Bonus round.") return nil end
        if not WF.Layout(phrase) then
            ns.Print("The bonus puzzle doesn't fit the board (4 rows of 14, words can't be split).")
            return nil
        end
        if not WF.BonusOK(phrase) then ns.Print("R S T L N E would give the bonus puzzle away - pick another.") return nil end
        bonusPz = { cat ~= "" and cat or "PHRASE", phrase }
    end
    return self:Launch(list, WF.Clean(prize or "", 48, true), false, bonusPz,
        "%s is hosting Wheel of Fortune (%d round%s) - open Titan Up (/tu wheel) to grab a seat!")
end

-- Start a game (hosted, or auto = everyone plays): tell the group, and post
-- a chat invite when everyone in the group is in the guild.
function WF:Launch(list, prize, auto, bonusPz, invite)
    self._idSeq = ((self._idSeq or 0) % 9) + 1
    local id = ns.Short(ns.me) .. "-" .. ((GetServerTime and GetServerTime()) or time()) .. self._idSeq
    local g = self:NewGame(id, ns.me, #list)
    g.puzzles, g.prize = list, prize
    g.bonusPz, g.bonus = bonusPz, bonusPz ~= nil
    if auto then g.auto, g.seats = true, { ns.me } end
    self.current = id
    self:Send("N", id, #list, auto and 1 or 0, prize or "", bonusPz and 1 or 0)
    self:BroadcastSeats(g)
    if not self.sim and IsInGroup() and ns.GroupIsAllGuild() then
        ns.SayGroup(invite:format(ns.Short(ns.me), #list, #list == 1 and "" or "s"))
    end
    ui("new", g)
    return g
end

-- Play together: no host. Random built-in puzzles; whoever starts it takes
-- seat 1 (their addon referees, but their screen never shows the answer);
-- rounds move on by themselves.
function WF:Play(rounds, theme, bonus)
    local ok, why = self:CanPlay()
    if not ok then ns.Print(why) return nil end
    rounds = math.max(1, math.min(WF.MAX_ROUNDS, tonumber(rounds) or 3))
    local list, taken = {}, {}
    for _ = 1, rounds do
        local pz = WF.RandomPuzzle(theme, taken)
        if not pz then break end
        taken[pz[2]] = true
        list[#list + 1] = { pz[1], pz[2] }
    end
    if #list == 0 then ns.Print("No puzzles for that theme.") return nil end
    local bonusPz = bonus and WF.RandomBonus(theme, taken)
    return self:Launch(list, nil, true, bonusPz and { bonusPz[1], bonusPz[2] } or nil,
        "%s started Wheel of Fortune (%d round%s, everyone plays) - open Titan Up (/tu wheel) to grab a seat!")
end

function WF:Join(id)
    local g = self.games[id]
    if not g or g.state ~= "lobby" then return end
    local ok, why = self:CanPlay()
    if not ok then ns.Print(why) return end
    self.current = id
    if self:IsHost(g) then self:HostJoin(g, ns.me) else self:Send("J", id) end
end

function WF:Leave(id)
    local g = self.games[id]
    if not g then return end
    if self:IsHost(g) then self:HostLeave(g, ns.me) else self:Send("L", id) end
end

function WF:Watch(id)
    self.current = id
    self:Send("Q", id)
end

function WF:Act(action, arg)
    local g = self.games[self.current or ""]
    if not g then return end
    if self:IsHost(g) then self:HostAct(g, ns.me, action, arg) else self:Send("A", g.id, action, arg or "") end
end

-- ---------------------------------------------------------------------
-- Referee (host)
-- ---------------------------------------------------------------------
function WF:HostJoin(g, name)
    if g.state ~= "lobby" or WF.SeatOf(g, name) or #g.seats >= WF.SEATS then return end
    if name == g.host and not g.engine and not g.auto then return end   -- a host knows the answers (Play together has none)
    g.seats[#g.seats + 1] = name
    self:BroadcastSeats(g)
end

function WF:HostLeave(g, name)
    local seat = WF.SeatOf(g, name)
    if not seat then return end
    if g.state == "lobby" then
        table.remove(g.seats, seat)
        self:BroadcastSeats(g)
    else
        g.gone[name] = true
        if g.turn == seat and g.state == "bonus" then return self:BonusEnd(g, false) end
        if g.turn == seat and g.state == "playing" then self:NextTurn(g) end
        self:Broadcast(g)
    end
end

function WF:Start()
    local g = self.games[self.current or ""]
    if not g or not self:IsHost(g) or g.state ~= "lobby" then return end
    if #g.seats == 0 then ns.Print("Nobody has taken a seat yet.") return end
    self:NextRound(g)
end

function WF:NextRound(g)
    if g.round >= g.rounds then return self:StartBonus(g) end
    g.round = g.round + 1
    local p = g.puzzles[g.round]
    g.cat, g.phrase = p[1], p[2]
    g.used = ""
    for i = 1, WF.SEATS do g.bank[i] = 0 end
    g.state = "playing"
    g.turn = ((g.round - 1) % #g.seats) + 1
    if g.gone[g.seats[g.turn]] then self:NextTurn(g) end
    g.phase, g.value, g.msg, g.arg = "turn", 0, "round", tostring(g.round)
    self:Broadcast(g)
end

function WF:NextTurn(g)
    local n = #g.seats
    for _ = 1, n do
        g.turn = (g.turn % n) + 1
        if not g.gone[g.seats[g.turn]] then break end
    end
    g.phase, g.value = "turn", 0
end

function WF:RoundWon(g, seat)
    local win = math.max(g.bank[seat] or 0, WF.MIN_WIN)
    g.total[seat] = (g.total[seat] or 0) + win
    for ch in g.phrase:gmatch("[A-Z]") do
        if not g.used:find(ch, 1, true) then g.used = g.used .. ch end
    end
    g.msg, g.arg, g.phase = "solved", seat .. ":" .. win, ""
    g.state = (g.round >= g.rounds and not g.bonusPz) and "over" or "roundover"
end

function WF:HostAct(g, name, action, arg)
    if g.state == "bonus" then return self:BonusAct(g, name, action, arg) end
    if g.state ~= "playing" then return end
    local seat = WF.SeatOf(g, name)
    if not seat or seat ~= g.turn then return end
    local cLeft = remaining(g.phrase, g.used)
    if action == "spin" then
        if g.phase ~= "turn" then return end
        if cLeft == 0 then g.msg, g.arg = "noconsonants", ""; return self:Broadcast(g) end
        g.phase, g.spin, g.sq = "spinning", math.random(1, #WF.WEDGES), g.sq + 1
        g.msg, g.arg = "spinning", ""
        self:Broadcast(g)
        local sq = g.sq
        C_Timer.After(WF.SPIN_TIME, function() WF:ResolveSpin(g, sq) end)
    elseif action == "letter" then
        local L = WF.Clean(arg, 1)
        if g.phase ~= "letter" or not isLetter(L) or isVowel(L) then return end
        if g.used:find(L, 1, true) then
            g.msg, g.arg = "already", L
            self:NextTurn(g)
            return self:Broadcast(g)
        end
        g.used = g.used .. L
        local n = count(g.phrase, L)
        if n > 0 then
            g.bank[seat] = g.bank[seat] + n * g.value
            g.msg, g.arg, g.phase = "found", L .. n .. ":" .. (n * g.value), "turn"
            if not WF.Mask(g.phrase, g.used):find("_") then self:RoundWon(g, seat) end
        else
            g.msg, g.arg = "none", L
            self:NextTurn(g)
        end
        self:Broadcast(g)
    elseif action == "vowel" then
        local V = WF.Clean(arg, 1)
        if g.phase ~= "turn" or not isVowel(V) or g.used:find(V, 1, true) then return end
        if g.bank[seat] < WF.VOWEL_COST then return end
        g.bank[seat] = g.bank[seat] - WF.VOWEL_COST
        g.used = g.used .. V
        local n = count(g.phrase, V)
        if n > 0 then
            g.msg, g.arg = "foundvowel", V .. n
            if not WF.Mask(g.phrase, g.used):find("_") then self:RoundWon(g, seat) end
        else
            g.msg, g.arg = "none", V
            self:NextTurn(g)
        end
        self:Broadcast(g)
    elseif action == "solve" then
        if g.phase ~= "turn" then return end
        local guess = WF.Clean(arg, 60):gsub("[^A-Z]", "")
        if guess == g.phrase:gsub("[^A-Z]", "") then
            self:RoundWon(g, seat)
        else
            g.msg, g.arg = "wrong", ""
            self:NextTurn(g)
        end
        self:Broadcast(g)
    end
end

function WF:ResolveSpin(g, sq)
    if g.sq ~= sq or g.phase ~= "spinning" or g.state ~= "playing" then return end
    local w = WF.WEDGES[g.spin]
    if w == "B" then
        g.bank[g.turn] = 0
        g.msg, g.arg = "bankrupt", ""
        self:NextTurn(g)
    elseif w == "L" then
        g.msg, g.arg = "loseturn", ""
        self:NextTurn(g)
    else
        g.value, g.phase, g.msg, g.arg = w, "letter", "spun", tostring(w)
    end
    self:Broadcast(g)
end

-- ---------------------------------------------------------------------
-- Bonus round (referee)
-- ---------------------------------------------------------------------
-- The game's leader (first seat on a tie); nil if everyone has left.
function WF.Leader(g)
    local best, bi = -1, nil
    for i, name in ipairs(g.seats) do
        if not g.gone[name] and (g.total[i] or 0) > best then best, bi = g.total[i] or 0, i end
    end
    return bi
end

function WF:StartBonus(g)
    local seat = g.bonusPz and WF.Leader(g)
    if not seat then
        g.state, g.phase, g.msg, g.arg = "over", "", "nobonus", ""
        return self:Broadcast(g)
    end
    g.cat, g.phrase = g.bonusPz[1], g.bonusPz[2]
    g.bonusPrize = WF.BONUS_PRIZES[math.random(1, #WF.BONUS_PRIZES)]
    g.used, g.picks = WF.BONUS_FREE, ""
    for i = 1, WF.SEATS do g.bank[i] = 0 end
    g.state, g.turn, g.phase, g.value = "bonus", seat, "pick", 0
    g.msg, g.arg = "bonus", ""
    self:Broadcast(g)
end

local function pickCounts(picks)
    local c, v = 0, 0
    for ch in picks:gmatch(".") do if isVowel(ch) then v = v + 1 else c = c + 1 end end
    return c, v
end

-- Reveal the picked letters and start the solve clock.
function WF:BonusReveal(g)
    g.used = g.used .. g.picks
    g.phase, g.msg, g.arg = "solve", "bonussolve", g.picks
    if not WF.Mask(g.phrase, g.used):find("_") then return self:BonusEnd(g, true) end
    self:Broadcast(g)
end

function WF:BonusEnd(g, won)
    local seat = g.turn
    if won then g.total[seat] = (g.total[seat] or 0) + g.bonusPrize end
    for ch in g.phrase:gmatch("[A-Z]") do
        if not g.used:find(ch, 1, true) then g.used = g.used .. ch end
    end
    g.state, g.phase = "over", ""
    g.msg, g.arg = won and "bonuswon" or "bonuslost", seat .. ":" .. g.bonusPrize
    self:Broadcast(g)
end

function WF:BonusTimeout(g)
    if g.phase == "pick" then return self:BonusReveal(g) end    -- out of time picking: play with what they chose
    self:BonusEnd(g, false)
end

function WF:BonusAct(g, name, action, arg)
    if WF.SeatOf(g, name) ~= g.turn then return end
    if action == "letter" or action == "vowel" then
        local L = WF.Clean(arg, 1)
        if g.phase ~= "pick" or not isLetter(L) or g.used:find(L, 1, true) or g.picks:find(L, 1, true) then return end
        local c, v = pickCounts(g.picks)
        if isVowel(L) then
            if v >= WF.BONUS_VOWELS then return end
        elseif c >= WF.BONUS_PICKS then return end
        g.picks = g.picks .. L
        g.msg, g.arg = "picking", g.picks
        c, v = pickCounts(g.picks)
        if c >= WF.BONUS_PICKS and v >= WF.BONUS_VOWELS then return self:BonusReveal(g) end
        self:Broadcast(g)
    elseif action == "solve" then
        if g.phase ~= "solve" then return end
        local guess = WF.Clean(arg, 60):gsub("[^A-Z]", "")
        if guess == g.phrase:gsub("[^A-Z]", "") then return self:BonusEnd(g, true) end
        g.msg = "bonuswrong"                      -- keep guessing until the clock runs out
        self:Broadcast(g)
    end
end

-- Host buttons
function WF:HostNextRound()
    local g = self.games[self.current or ""]
    if g and self:IsHost(g) and g.state == "roundover" then self:NextRound(g) end
end

function WF:HostSkip()
    local g = self.games[self.current or ""]
    if not g or not self:IsHost(g) or g.state ~= "playing" or g.phase == "spinning" then return end
    g.msg, g.arg = "skipped", ""
    self:NextTurn(g)
    self:Broadcast(g)
end

function WF:HostEnd()
    local g = self.games[self.current or ""]
    if not g or not self:IsHost(g) then return end
    g.state, g.msg = "cancelled", "ended"
    self:Send("X", g.id)
    ui("state", g)
    if self.sim then self.sim = nil end
end

function WF:CheckRoster()
    if self.sim or not next(self.games) then return end
    self:Cleanup()
    local members = {}
    for _, n in ipairs(ns.GroupNames()) do members[n] = true end
    for _, g in pairs(self.games) do
        if g.state ~= "over" and g.state ~= "cancelled" then
            if not IsInGroup() or not members[g.host] then
                g.state, g.msg = "cancelled", "ended"
                ui("state", g)
            elseif g.host == ns.me then
                for _, n in ipairs(g.seats) do
                    if not members[n] and not g.gone[n] then self:HostLeave(g, n) end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Practice (/tu wheel sim): a fake host and two bot players, you take
-- the first seat. The referee runs on your client.
-- ---------------------------------------------------------------------
local BOTS = { "Selune", "Vexa" }
local FREQ = "RSTLNDHCMGPBFYWKVXZJQ"

function WF:StartSim(bonus)
    if IsInGroup() then ns.Print("Practice mode is for solo testing - leave your group first.") return end
    local realm = GetNormalizedRealmName() or "Medivh"
    self.sim = { bots = {} }
    for _, b in ipairs(BOTS) do self.sim.bots[b .. "-" .. realm] = true end
    -- three random puzzles from the bank
    local pool, picks = {}, {}
    for i = 1, #WF.BANK do pool[i] = WF.BANK[i] end
    for _ = 1, 3 do picks[#picks + 1] = table.remove(pool, math.random(1, #pool)) end
    local taken = {}
    for _, p in ipairs(picks) do taken[p[2]] = true end
    local bonusPz = bonus and WF.RandomBonus(nil, taken)
    local g = self:Host(picks, nil, bonusPz)
    if not g then self.sim = nil return end
    g.engine = true
    g.host = "Brakk-" .. realm
    g.seats = { ns.me, BOTS[1] .. "-" .. realm, BOTS[2] .. "-" .. realm }
    ns.Print("Practice Wheel of Fortune: Brakk hosts, you play against Selune and Vexa.")
    self:BroadcastSeats(g)
    C_Timer.After(1, function() if WF.sim then WF:NextRound(g) end end)
    return g
end

function WF:BotTurn(g)
    if not (self.sim and g.engine) then return end
    if g.state == "bonus" then return self:BotBonus(g) end
    if g.state ~= "playing" then return end
    local name = g.seats[g.turn]
    if not self.sim.bots[name] then return end
    if g.phase ~= "turn" and g.phase ~= "letter" then return end
    local stamp = g.sq .. ":" .. g.turn .. ":" .. g.phase .. ":" .. g.used
    C_Timer.After(1.4 + math.random() * 0.8, function()
        if g.sq .. ":" .. g.turn .. ":" .. g.phase .. ":" .. g.used ~= stamp then return end
        local cLeft, vLeft = remaining(g.phrase, g.used)
        if g.phase == "letter" then
            for ch in FREQ:gmatch(".") do
                if not g.used:find(ch, 1, true) and math.random() < 0.6 then return WF:HostAct(g, name, "letter", ch) end
            end
            for ch in FREQ:gmatch(".") do
                if not g.used:find(ch, 1, true) then return WF:HostAct(g, name, "letter", ch) end
            end
            return
        end
        local hidden = select(2, WF.Mask(g.phrase, g.used):gsub("_", ""))
        local letters = #g.phrase:gsub("[^A-Z]", "")
        if hidden / math.max(1, letters) < 0.35 and math.random() < 0.6 then
            return WF:HostAct(g, name, "solve", math.random() < 0.75 and g.phrase or "NOT SURE")
        end
        if vLeft > 0 and g.bank[g.turn] >= WF.VOWEL_COST and (cLeft == 0 or math.random() < 0.25) then
            for ch in ("EAOIU"):gmatch(".") do
                if not g.used:find(ch, 1, true) then return WF:HostAct(g, name, "vowel", ch) end
            end
        end
        if cLeft > 0 then return WF:HostAct(g, name, "spin") end
        return WF:HostAct(g, name, "solve", g.phrase)
    end)
end

-- A bot in the bonus round: picks common letters, then has a go at solving.
function WF:BotBonus(g)
    local name = g.seats[g.turn]
    if not self.sim.bots[name] or (g.phase ~= "pick" and g.phase ~= "solve") then return end
    local stamp = g.phase .. ":" .. (g.picks or "")
    C_Timer.After(1.2 + math.random() * 0.8, function()
        if g.state ~= "bonus" or g.phase .. ":" .. (g.picks or "") ~= stamp then return end
        if g.phase == "solve" then
            local hidden = select(2, WF.Mask(g.phrase, g.used):gsub("_", ""))
            local letters = #g.phrase:gsub("[^A-Z]", "")
            if math.random() < 1 - hidden / math.max(1, letters) then WF:BonusAct(g, name, "solve", g.phrase) end
            return
        end
        local c, v = pickCounts(g.picks)
        for ch in ((c < WF.BONUS_PICKS and "CDMGHPBFYW" or "") .. (v < WF.BONUS_VOWELS and "AEIOU" or "")):gmatch(".") do
            if not g.used:find(ch, 1, true) and not g.picks:find(ch, 1, true) then return WF:BonusAct(g, name, "letter", ch) end
        end
    end)
end
