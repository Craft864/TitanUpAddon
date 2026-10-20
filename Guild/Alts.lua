-- Titan Up - Guild/Alts.lua
-- Alt linking (0.37.0, on by default; "Link my characters" in Settings):
-- the game standings show one row per player, under their main, and Death
-- Roll records and debts are combined across a player's characters.
--
-- Titan Up's saved data is per account, so every character you log into
-- with Titan Up is known here (chars). Each one tells the guild, once per
-- login, "my main is M and my characters are A, B, C" (prefix TitanUpAL).
-- Two characters only count as linked when BOTH say so - each from its own
-- login, and WoW stamps every addon message with its real sender - so
-- nobody can claim someone else's character as their alt (or put their
-- Death Roll debts on someone else). Characters outside your guild are
-- never listed. Turning it off tells the guild to forget your links.
-- Without a guild (0.48.0) the list goes to your friends running Titan Up
-- instead, and names all your characters on this account.
--
--   A main part n names       names: comma list; your own realm left off
local ADDON, ns = ...

local AL = {}
ns.Alts = AL

local PREFIX = "TitanUpAL"
local KEEP_DAYS = 180
local DAY = 86400

local function db() return ns.udb.alts end
function AL:Enabled() return db().share and true or false end

-- ---------------------------------------------------------------------
-- Your own characters
-- ---------------------------------------------------------------------
function AL:Init()
    ns.Listen(PREFIX, "guild", function(msg, sender) AL:OnMessage(msg, sender) end)
    self.inbox = {}
    local cut = ns.Now() - KEEP_DAYS * DAY
    for name, l in pairs(db().links) do
        if type(l) ~= "table" or (l.t or 0) < cut then db().links[name] = nil end
    end
    self:Seen()
    -- once the guild is known: remember which guild this character is in, then tell it
    local tries = 0
    local function go()
        tries = tries + 1
        -- (no guild after a minute: tell friends instead)
        if (ns.guildName or tries > 4) and ns.DataChannel() then
            self:Seen()
            C_Timer.After(8 + math.random() * 20, function() AL:Announce() end)
        elseif tries < 20 then
            C_Timer.After(15, go)
        end
    end
    C_Timer.After(4, go)
    if ns.Friends then ns.Friends:OnNewFriend(function() ns.Debounce("alts:friends", 10, function() AL:Announce() end) end) end
end

-- this character, as seen now (and which guild it's in)
function AL:Seen()
    if not ns.me then return end
    local c = db().chars[ns.me] or { first = ns.Now() }
    c.seen = ns.Now()
    if ns.guildName then c.guild = ns.guildName end
    local class = UnitClass and select(2, UnitClass("player"))
    if type(class) == "string" and not ns.IsSecret(class) then c.class = class end
    db().chars[ns.me] = c
    -- the main picked from the guild roster (0.41.0) logs in: it's yours now
    if db().pendingMain == ns.me then
        db().pendingMain = nil
        db().main = ns.me
        self:Changed()
        ns.Print(("%s is now your main - your other characters are listed under it."):format(ns.Short(ns.me)))
    end
end

function AL:IsMine(name)
    if not name then return false end
    return name == ns.me or db().chars[name] ~= nil
end

-- your characters in your current guild (all of them without a guild), oldest first
function AL:MyChars()
    local out = {}
    for name, c in pairs(db().chars) do
        if name == ns.me or not ns.guildName or c.guild == ns.guildName then out[#out + 1] = name end
    end
    table.sort(out, function(a, b)
        local x, y = db().chars[a].first or 0, db().chars[b].first or 0
        if x ~= y then return x < y end
        return a < b
    end)
    return out
end

-- your main: the one you picked, else your first character in this guild
function AL:MyMain()
    local chars = self:MyChars()
    local picked = db().main
    for _, n in ipairs(chars) do if n == picked then return picked end end
    return chars[1] or ns.me
end

function AL:SetMain(name)
    db().main = name
    db().pendingMain = nil
    db().confirmed = true
    self:Changed()
    self:Announce()
end

-- "Pick your main" (0.41.0): asked until answered, once per account. Someone
-- who already picked a main in Settings (with linking on) has answered.
function AL:NeedsMain()
    local d = db()
    if d.confirmed then return false end
    return not (d.main and self:Enabled())
end

-- picked in the pop-up: one of your characters (linking turns on)
function AL:PickMain(name)
    db().share = true
    self:SetMain(name)
end

-- picked from the guild roster: a character this account hasn't logged into
-- with Titan Up yet. It becomes your main when it logs in (Seen); until then
-- your characters stay under the oldest one. Nothing is claimed for it
-- before then, so a wrong pick can't merge you with someone else.
function AL:PickPending(name)
    local d = db()
    d.share = true
    d.pendingMain = name
    d.confirmed = true
    self:Changed()
    self:Announce()
end
function AL:PendingMain() return db().pendingMain end

function AL:SetEnabled(on)
    db().share = on and true or false
    self:Changed()
    self:Announce()
end

-- ---------------------------------------------------------------------
-- Telling the guild
-- ---------------------------------------------------------------------
local function shortName(full)
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local name, r = full:match("^(.-)%-(.+)$")
    if name and r == realm then return name end
    return full
end

function AL:Announce()
    if not ns.DataChannel() then return false end
    local main, list = "", {}
    if self:Enabled() then
        main = shortName(self:MyMain())
        for _, n in ipairs(self:MyChars()) do list[#list + 1] = shortName(n) end
    end
    local parts = ns.Chunks(table.concat(list, ","), 180)
    ns.BulkDrop("alts")
    for i, chunk in ipairs(parts) do ns.BulkSend(PREFIX, ns.Join("A", main, i, #parts, chunk), "alts") end
    return true
end

local function full(name, sender)
    if name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. (sender:match("%-(.+)$") or "")
end

function AL:OnMessage(msg, sender)
    local f = ns.Split(msg, "^")
    if f[1] ~= "A" then return end
    local whole = ns.Reassemble(self.inbox, sender, f[3], f[4], f[5] or "", 20)
    if not whole then return end
    local main = full(f[2] or "", sender)
    local set, n = {}, 0
    for name in whole:gmatch("[^,]+") do
        local fn = full(name, sender)
        if fn and n < 60 then set[fn] = true; n = n + 1 end
    end
    if not main or not set[sender] then
        db().links[sender] = nil                        -- turned off (or nothing valid): forget
    else
        set[main] = true
        db().links[sender] = { m = main, a = set, t = ns.Now() }
    end
    self:Changed()
end

-- ---------------------------------------------------------------------
-- Who's whose
-- ---------------------------------------------------------------------
-- Two characters are linked when each lists the other.
function AL:Linked(a, b)
    if a == b then return true end
    if self:IsMine(a) and self:IsMine(b) then return self:Enabled() end
    local la, lb = db().links[a], db().links[b]
    return (la and lb and la.a[b] and lb.a[a]) and true or false
end

local cache = {}
function AL:Changed()
    wipe(cache)
    ns.Debounce("alts-redraw", 0.5, function()
        for _, name in ipairs({ "WowdleUI", "DeathRollUI" }) do
            local v = ns[name]
            if v and v.frame and v.frame:IsShown() and v.Refresh then pcall(v.Refresh, v) end
        end
    end)
end

-- The name a character is listed under: their main, when the link holds
-- both ways (yours: your main, unless linking is off).
function AL:Main(name)
    if not name then return name end
    local c = cache[name]
    if c then return c end
    local main = name
    if self:IsMine(name) then
        if self:Enabled() then main = self:MyMain() end
    else
        local l = db().links[name]
        if l and l.m and l.m ~= name and self:Linked(name, l.m) then
            local ml = db().links[l.m]
            if ml and ml.m == l.m then main = l.m end      -- the main agrees it's the main
        end
    end
    cache[name] = main
    return main
end

-- Same player? (the same main)
function AL:Same(a, b)
    if not (a and b) then return false end
    return a == b or self:Main(a) == self:Main(b)
end

-- a main's characters you know of (for tooltips), main first
function AL:CharsOf(main)
    local out = { main }
    local seen = { [main] = true }
    if self:IsMine(main) then
        for _, n in ipairs(self:MyChars()) do if not seen[n] then seen[n] = true; out[#out + 1] = n end end
    else
        local l = db().links[main]
        for n in pairs(l and l.a or {}) do
            if not seen[n] and self:Main(n) == main then seen[n] = true; out[#out + 1] = n end
        end
        table.sort(out, function(a, b) if a == main then return true elseif b == main then return false end return a < b end)
    end
    return out
end
