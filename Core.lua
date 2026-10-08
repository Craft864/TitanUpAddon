-- Titan Up - Core.lua
-- The Titan Up guild toolkit. Modules: TitanBoard (raid strategy board),
-- Death Roll (fun). Event dispatch, saved variables, player/group helpers,
-- permissions and slash commands; every module hangs off the shared `ns`.
local ADDON, ns = ...

ns.VERSION = "0.30.1"
ns.PREFIX = "TitanBoard"     -- board sync channel (unchanged, so it stays compatible)
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.U = 4095            -- board coordinates run 0..4095 on both axes
ns.acl = {}            -- [fullName] = true : players the leader allowed to draw

-- ---------------------------------------------------------------------
-- Event dispatch: ns.On(event, fn) - several modules can share an event.
-- ---------------------------------------------------------------------
local Core = CreateFrame("Frame")
ns.Core = Core
local handlers = {}

-- Event registration can't break startup: an event the game no longer
-- has is skipped (noted for /tu debug) instead of throwing.
ns.skippedEvents = {}
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(Core.RegisterEvent, Core, event)
        if not ok then ns.skippedEvents[#ns.skippedEvents + 1] = event end
    end
    table.insert(handlers[event], fn)
end

Core:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- ---------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------
function ns.Print(...)
    print("|cff4fc3f7Titan Up|r", ...)
end

function ns.Debug(...)
    if ns.db and ns.db.debug then print("|cff7f8c9a[TB]|r", ...) end
end

-- ---------------------------------------------------------------------
-- Names. Midnight can hand addons "secret" values (e.g. names in some
-- restricted contexts); using one as a table key throws, so every name
-- goes through these helpers first.
-- ---------------------------------------------------------------------
function ns.IsSecret(v)
    local f = issecretvalue
    if f then return f(v) and true or false end
    return false
end

-- ---------------------------------------------------------------------
-- Safe reads: Midnight can hide ("secret") values mid-fight; comparing or
-- doing maths on one is an error. These hand back the value only when it's
-- readable and of the right type, else nil - so a newly hidden value shows
-- as "unknown" instead of breaking a feature.
-- ---------------------------------------------------------------------
ns.Safe = {}
function ns.Safe.Num(v) if type(v) == "number" and not ns.IsSecret(v) then return v end end
function ns.Safe.Text(v) if type(v) == "string" and not ns.IsSecret(v) then return v end end
function ns.Safe.Bool(v) if type(v) == "boolean" and not ns.IsSecret(v) then return v end end
-- call a game function and return its first result, safely (nil on error / hidden)
function ns.Safe.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or ns.IsSecret(v) then return nil end
    return v
end
-- a unit's class token ("MAGE"), or nil
function ns.Safe.Class(unit)
    if not UnitClass then return nil end
    local ok, _, class = pcall(UnitClass, unit)
    return ok and ns.Safe.Text(class) or nil
end

function ns.FullName(unit)
    local name, realm = UnitFullName(unit)
    if not name or ns.IsSecret(name) then return nil end
    if not realm or ns.IsSecret(realm) or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- CHAT_MSG_ADDON senders on your own realm can arrive without "-Realm".
function ns.NormalizeSender(sender)
    if not sender or ns.IsSecret(sender) or sender == "" then return nil end
    if not sender:find("-", 1, true) then
        local realm = GetNormalizedRealmName()
        if realm and realm ~= "" then sender = sender .. "-" .. realm end
    end
    return sender
end

function ns.Short(full)
    if not full then return "?" end
    return full:match("^([^%-]+)") or full
end

-- ---------------------------------------------------------------------
-- Group helpers
-- ---------------------------------------------------------------------
local HOME = LE_PARTY_CATEGORY_HOME
local INSTANCE = LE_PARTY_CATEGORY_INSTANCE

function ns.GroupChannel()
    if HOME and IsInRaid(HOME) then return "RAID" end
    if HOME and IsInGroup(HOME) then return "PARTY" end
    if INSTANCE and IsInGroup(INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- ---------------------------------------------------------------------
-- Your guild
-- ---------------------------------------------------------------------
-- Titan Up works for anyone. All of its addon data goes over the hidden
-- GUILD addon channel, which the game delivers only to members of YOUR
-- guild (and guarantees the sender is one). So each guild's Titan Up data
-- stays inside that guild: other guilds - and pugs in your raid - never
-- receive it and can't send you any. Group features (board, games, Raid
-- Check) also ignore guildmates who aren't in your current group.
-- Without a guild, everything local still works; nothing is sent or received.
ns.guildOK = false        -- in a guild (and its info has loaded)
ns.guildName = nil

-- true + name: in a guild; false: no guild; nil: still loading
function ns.CheckGuild()
    if not (IsInGuild and IsInGuild()) then return false end
    local name = GetGuildInfo("player")
    if not name then return nil end
    return true, name
end

-- ---------------------------------------------------------------------
-- Codec: compression for TitanBoard import/export strings.
-- Uses the game's built-in Deflate (C_EncodingUtil - fast, no Lua library to
-- load), plus a printable text encoding identical to LibDeflate's
-- EncodeForPrint, so strings made by earlier versions (and by them) still
-- import. If the game API were ever missing, a LibDeflate loaded by another
-- addon is used instead.
-- ---------------------------------------------------------------------
local Codec = {}
ns.Codec = Codec
local ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
local TO_CHAR, TO_SIX = {}, {}
for i = 1, 64 do
    local c = ALPHA:sub(i, i)
    TO_CHAR[i - 1], TO_SIX[c:byte()] = c, i - 1
end

function Codec.EncodeForPrint(str)
    local out, n, i, len = {}, 0, 1, #str
    while i <= len - 2 do
        local a, b, c = str:byte(i, i + 2)
        local v = a + b * 256 + c * 65536
        n = n + 1
        out[n] = TO_CHAR[v % 64] .. TO_CHAR[math.floor(v / 64) % 64] .. TO_CHAR[math.floor(v / 4096) % 64] .. TO_CHAR[math.floor(v / 262144)]
        i = i + 3
    end
    local cache, bits = 0, 0
    while i <= len do cache = cache + str:byte(i) * 2 ^ bits; bits = bits + 8; i = i + 1 end
    while bits > 0 do
        n = n + 1
        out[n] = TO_CHAR[cache % 64]
        cache = math.floor(cache / 64)
        bits = bits - 6
    end
    return table.concat(out)
end

function Codec.DecodeForPrint(str)
    str = str:gsub("^[%c ]+", ""):gsub("[%c ]+$", "")
    local len = #str
    if len == 1 then return nil end
    local out, n, i = {}, 0, 1
    while i <= len - 3 do
        local a, b, c, d = str:byte(i, i + 3)
        a, b, c, d = TO_SIX[a], TO_SIX[b], TO_SIX[c], TO_SIX[d]
        if not (a and b and c and d) then return nil end
        local v = a + b * 64 + c * 4096 + d * 262144
        n = n + 1
        out[n] = string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536))
        i = i + 4
    end
    local cache, bits = 0, 0
    while i <= len do
        local x = TO_SIX[str:byte(i)]
        if not x then return nil end
        cache = cache + x * 2 ^ bits
        bits = bits + 6
        i = i + 1
    end
    while bits >= 8 do
        n = n + 1
        out[n] = string.char(cache % 256)
        cache = math.floor(cache / 256)
        bits = bits - 8
    end
    return table.concat(out)
end

local function otherLibDeflate() return LibStub and LibStub:GetLibrary("LibDeflate", true) end

function Codec.Compress(str)
    local E = C_EncodingUtil
    if E and E.CompressString and Enum and Enum.CompressionMethod then
        local level = Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize
        local ok, out = pcall(E.CompressString, str, Enum.CompressionMethod.Deflate, level)
        if ok and type(out) == "string" then return out end
    end
    local LD = otherLibDeflate()
    return LD and LD:CompressDeflate(str, { level = 9 })
end

-- Raw Deflate first (what LibDeflate writes); zlib-wrapped as a fallback.
function Codec.Decompress(str)
    local E = C_EncodingUtil
    if E and E.DecompressString and Enum and Enum.CompressionMethod then
        for _, method in ipairs({ Enum.CompressionMethod.Deflate, Enum.CompressionMethod.Zlib }) do
            if method then
                local ok, out = pcall(E.DecompressString, str, method)
                if ok and type(out) == "string" and out ~= "" then return out end
            end
        end
    end
    local LD = otherLibDeflate()
    return LD and LD:DecompressDeflate(str)
end

function Codec.Available()
    return (C_EncodingUtil and C_EncodingUtil.CompressString and true) or (otherLibDeflate() ~= nil)
end

-- ---------------------------------------------------------------------
-- Sending: one small queue per message prefix (each feature has its own
-- prefix, and WoW limits each prefix separately). A burst goes straight
-- out; beyond that, messages wait their turn (~2 a second). If WoW says a
-- message was throttled, it's put back and retried after a short pause
-- instead of being lost. A timer runs only while something is waiting.
-- ---------------------------------------------------------------------
local SEND_BURST, SEND_RATE = 10, 2
local sendQ = {}
local sendTicker

local function throttled(r)
    local R = Enum and Enum.SendAddonMessageResult
    return r == false or (R and type(r) == "number" and (r == R.AddonMessageThrottle or r == R.ChannelThrottle))
end

local function queueFor(prefix)
    local q = sendQ[prefix]
    if not q then q = { tokens = SEND_BURST, last = GetTime(), items = {} } sendQ[prefix] = q end
    local now = GetTime()
    q.tokens = math.min(SEND_BURST, q.tokens + (now - q.last) * SEND_RATE)
    q.last = now
    return q
end

local function attempt(prefix, item)
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, prefix, item[1], item[2], item[3])
    if not ok then return true end                       -- a bad message: drop it rather than loop
    return not throttled(r)
end

local function pump()
    local waiting = false
    for prefix, q in pairs(sendQ) do
        queueFor(prefix)
        while #q.items > 0 and q.tokens >= 1 and GetTime() >= (q.pauseUntil or 0) do
            if attempt(prefix, q.items[1]) then
                table.remove(q.items, 1)
                q.tokens = q.tokens - 1
            else
                q.tokens, q.pauseUntil = 0, GetTime() + 1           -- throttled: back off, retry
                break
            end
        end
        if #q.items > 0 then waiting = true end
    end
    if not waiting and sendTicker then sendTicker:Cancel(); sendTicker = nil end
end

function ns.Send(prefix, msg, channel, target)
    if not (prefix and msg and channel) then return false end
    local q = queueFor(prefix)
    local item = { msg, channel, target }
    if #q.items == 0 and q.tokens >= 1 and GetTime() >= (q.pauseUntil or 0) then
        if attempt(prefix, item) then q.tokens = q.tokens - 1 return true end
        q.tokens, q.pauseUntil = 0, GetTime() + 1
    end
    q.items[#q.items + 1] = item
    if not sendTicker then sendTicker = C_Timer.NewTicker(0.25, pump) end
    return true
end

-- fields joined with "^", to your guild's channel (nothing without a guild)
function ns.SendFields(prefix, ...)
    local ch = ns.DataChannel()
    if ch then ns.Send(prefix, table.concat({ ... }, "^"), ch) end
    return ch ~= nil
end

-- ns.Listen(prefix, scope, fn): fn(msg, sender, channel) for each readable
-- message on prefix from a guildmate - in your group if scope is "group"
-- (scope can also be a function of the message) - never your own.
function ns.Listen(prefix, scope, fn)
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    ns.On("CHAT_MSG_ADDON", function(p, msg, channel, sender)
        if p ~= prefix or ns.IsSecret(msg) then return end
        sender = ns.NormalizeSender(sender)
        if not sender or sender == ns.me then return end
        if not ns.AcceptAddon(channel, sender, type(scope) == "function" and scope(msg) or scope) then return end
        fn(msg, sender, channel)
    end)
end

-- A "[Titan Up] ..." line in party / raid chat.
function ns.SayGroup(text)
    local channel = ns.GroupChannel()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if channel and send then pcall(send, "[Titan Up] " .. text, channel) end
end

-- Encounter lockdown: the game blocks addon messages during boss fights.
function ns.InLockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if f then
        local ok, v = pcall(f)
        if ok and v then return true end
    end
    return false
end

-- ns.WatchTrades(update, done): while a trade window is open, update(t) runs
-- when it opens and on every change (t.partner = who you're trading with);
-- done(t) once the trade completes. Each watcher gets its own t.
function ns.WatchTrades(update, done)
    local trade
    local function changed() if trade then update(trade) end end
    ns.On("TRADE_SHOW", function() trade = { partner = ns.FullName("NPC") }; changed() end)
    for _, ev in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
        ns.On(ev, changed)
    end
    ns.On("UI_INFO_MESSAGE", function(_, msg)
        if trade and msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
            local t = trade
            trade = nil
            done(t)
        end
    end)
    ns.On("TRADE_CLOSED", function()
        local t = trade
        -- the "trade complete" message can arrive just after the window closes
        C_Timer.After(1, function() if trade == t then trade = nil end end)
    end)
end

-- in combat or a boss fight: a time to stay quiet
function ns.Busy() return (InCombatLockdown and InCombatLockdown()) or ns.InLockdown() end

function ns.InRaidInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and kind == "raid"
end

-- ---------------------------------------------------------------------
-- /tu mem: where Titan Up's memory goes. The total is what WoW counts for
-- the addon (after a cleanup pass, so stale garbage doesn't inflate it);
-- saved data is estimated per area by walking its tables; windows are
-- listed because once opened they stay built until /reload.
-- ---------------------------------------------------------------------
local AREA_NAMES = {
    pullReport = "Pull Report (tonight's pulls)", raidHistory = "Raid Scorecard history", loot = "Loot history",
    deathroll = "Death Roll ledger", wowdle = "Wowdle", timer = "Combat Timer", deathAlerts = "Death Alerts",
    keys = "Keystone Roulette", splitter = "Stack Splitter", brez = "Battle rez tracker", raidcheck = "Raid Check",
    tweaks = "UI Tweaks", wheel = "Wheel of Fortune", minimap = "Minimap button",
}

-- rough size of a value in KB (strings, numbers and table entries)
function ns.EstimateKB(v)
    local seen, bytes = {}, 0
    local function walk(x)
        local t = type(x)
        if t == "string" then bytes = bytes + 24 + #x
        elseif t == "number" or t == "boolean" then bytes = bytes + 16
        elseif t == "table" then
            if seen[x] then return end
            seen[x] = true
            bytes = bytes + 40
            for k, val in pairs(x) do bytes = bytes + 32; walk(k); walk(val) end
        end
    end
    walk(v)
    return bytes / 1024
end

function ns.MemoryBreakdown()
    local out = { areas = {}, windows = {} }
    for key, val in pairs(ns.udb or {}) do
        if type(val) == "table" then
            out.areas[#out.areas + 1] = { name = AREA_NAMES[key] or key, kb = ns.EstimateKB(val) }
        end
    end
    if ns.db then out.areas[#out.areas + 1] = { name = "TitanBoard plans & settings", kb = ns.EstimateKB(ns.db) } end
    table.sort(out.areas, function(a, b) return a.kb > b.kb end)
    out.saved = 0
    for _, a in ipairs(out.areas) do out.saved = out.saved + a.kb end
    for key, m in pairs(ns.Nav and ns.Nav.byKey or {}) do
        local f = m.frame and m.frame()
        if f then out.windows[#out.windows + 1] = m.name or key end
    end
    if ns.Hub and ns.Hub.frame then out.windows[#out.windows + 1] = "Hub" end
    table.sort(out.windows)
    return out
end

function ns.MemoryReport()
    collectgarbage("collect")
    local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    local total
    if update and get then update(); total = get(ADDON) end
    local b = ns.MemoryBreakdown()
    if total then ns.Print(("Titan Up is using |cffffffff%.0f KB|r of memory (after a cleanup pass)."):format(total))
    else ns.Print("This client doesn't report addon memory; here's what can be measured.") end
    ns.Print(("  Saved data: about %.0f KB"):format(b.saved))
    for i, a in ipairs(b.areas) do
        if i > 8 or a.kb < 1 then break end
        ns.Print(("    %s  |cff8a8f9c~%.0f KB|r"):format(a.name, a.kb))
    end
    ns.Print(("  Windows opened this session (%d, stay built until /reload): %s"):format(#b.windows, #b.windows > 0 and table.concat(b.windows, ", ") or "none"))
    if total then ns.Print(("  Code, windows and everything else: about %.0f KB"):format(math.max(0, total - b.saved))) end
end

-- Where Titan Up addon data goes: your guild's channel, or nowhere.
function ns.DataChannel()
    if ns.guildOK and IsInGuild() then return "GUILD" end
    return nil
end

-- Fast "is this person in my party/raid" (rebuilt on roster changes, and
-- at most once a second on a miss in case an update is still pending).
local groupSet, groupBuilt, groupCount = {}, -10, -1
local function rebuildGroup()
    wipe(groupSet)
    for _, n in ipairs(ns.GroupNames()) do groupSet[n] = true end
    groupBuilt = GetTime()
    groupCount = GetNumGroupMembers()
end
ns.On("GROUP_ROSTER_UPDATE", function() groupBuilt = -10 end)
function ns.InMyGroup(name)
    if not name then return false end
    if groupSet[name] and GetTime() - groupBuilt < 30 then return true end
    -- miss: rebuild if the group changed size, or at most once a second
    if GetTime() - groupBuilt >= 1 or GetNumGroupMembers() ~= groupCount then rebuildGroup() end
    return groupSet[name] == true
end

-- Every Titan Up message handler checks this first.
--   scope "group": only from guildmates in your current group
--   scope "guild": from any guildmate
function ns.AcceptAddon(channel, sender, scope)
    if not ns.guildOK or channel ~= "GUILD" then return false end
    -- same-realm senders can arrive without "-Realm": add it before the group lookup
    if scope == "group" then return ns.InMyGroup(ns.NormalizeSender(sender)) end
    return true
end

-- Public chat lines (invites/announcements) only when the whole group is
-- in YOUR guild.
function ns.GroupIsAllGuild()
    if not ns.guildName then return false end
    if not IsInGroup() then return true end
    for _, unit in ipairs(ns.GroupUnits()) do
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local g = GetGuildInfo(unit)
            if g ~= ns.guildName then return false end
        end
    end
    return true
end

function ns.GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
        end
    end
    return units
end

-- The roster: { { name = fullName, group = raid group 1-8, online }, ... }.
-- Solo with the simulator running, the fake raiders count as members so
-- the UI behaves like a raid.
function ns.GroupRoster()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local n = ns.FullName(unit)
                local _, _, subgroup, _, _, _, _, online = GetRaidRosterInfo(i)
                if n then out[#out + 1] = { name = n, group = subgroup or 1, online = online ~= false } end
            end
        end
    elseif IsInGroup() then
        for _, unit in ipairs(ns.GroupUnits()) do
            if UnitExists(unit) then
                local n = ns.FullName(unit)
                if n then out[#out + 1] = { name = n, group = 1, online = UnitIsConnected(unit) ~= false } end
            end
        end
    else
        out[1] = { name = ns.me, group = 1, online = true }
    end
    return out
end

function ns.GroupNames()
    local out = {}
    for _, m in ipairs(ns.GroupRoster()) do out[#out + 1] = m.name end
    return out
end

function ns.UnitForName(full)
    for _, unit in ipairs(ns.GroupUnits()) do
        if UnitExists(unit) and ns.FullName(unit) == full then return unit end
    end
end

function ns.ClassOf(full)
    local unit = (full == ns.me) and "player" or ns.UnitForName(full)
    if unit then return ns.Safe.Class(unit) end
end

function ns.LeaderName()
    if not IsInGroup() then return ns.me end
    for _, unit in ipairs(ns.GroupUnits()) do
        if UnitExists(unit) and UnitIsGroupLeader(unit) then return ns.FullName(unit) end
    end
end

-- The "owner" answers snapshot requests and is the authority on the
-- plan: the group leader, or you when solo.
function ns.IsOwner()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") and true or false
end

-- Who may draw: the leader, raid assistants, and anyone on the leader's
-- grant list. Solo, only you (plus fake raiders you granted in /tb sim).
function ns.CanDraw(name)
    name = name or ns.me
    if not IsInGroup() then return name == ns.me end
    if name == ns.LeaderName() then return true end
    if IsInRaid() then
        local unit = ns.UnitForName(name)
        if unit and UnitIsGroupAssistant(unit) then return true end
    end
    return ns.acl[name] == true
end

function ns.NextId()
    ns.db.seq = (ns.db.seq or 0) + 1
    return ns.db.seq
end

function ns.Split(s, sep)
    local out, start = {}, 1
    while true do
        local i = s:find(sep, start, true)
        if not i then
            out[#out + 1] = s:sub(start)
            return out
        end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + #sep
    end
end

-- ---------------------------------------------------------------------
-- Saved variables + module start-up
-- ---------------------------------------------------------------------
local DEFAULTS = {
    plans = {},
    seq = 0,
    debug = false,
    settings = {
        color = 1,
        width = 3,
        autoMini = true,
        rate = 1.0,    -- messages per second the send queue refills
        burst = 10,    -- messages that can go out back to back
        pieAngle = 90, -- pie slice angle in degrees
        donutInner = 50, -- donut hole, % of the outer radius
        leftCollapsed = false,
        rightCollapsed = false,
    },
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Suite-wide settings (TitanBoardDB above keeps the board's plans).
local SUITE_DEFAULTS = {
    minimap = { angle = 200, hidden = false },
    nav = { railMin = false },              -- the Titan Up window: pos (top-left, once dragged), rail narrowed to icons
    dock = {},                              -- the alert stack: pos once dragged
    deathroll = { announce = true, games = {} },
    loot = { drops = {}, minQuality = 4, rollWindow = false },
    raidcheck = { potMin = 5, hpotMin = 5, durMin = 20, pullCheck = true },
    raidHistory = { weeks = {} },
    tweaks = { releaseGuard = false, bonusGuard = false },
    deathAlerts = { enabled = false, where = "instances", tankHealOnly = false, collapse = true, chat = false, size = "medium",
                    duration = 4, channel = "Master", roleSounds = true, selfSoundOn = true, sound = "WoW: Raid Warning",
                    tankSound = "WoW: Alarm Clock", healerSound = "WoW: Boss Emote", selfSound = "WoW: Quest Failed",
                    pos = { "TOP", "TOP", 0, -220 } },
    splitter = { enabled = false, mode = "take", presets = { 1, 5, 10, 20 }, remember = true },
    brez = { enabled = false, size = "medium", pos = { "CENTER", "CENTER", -260, 120 } },
    timer = { enabled = true, chatSummary = true, chatWhere = { raid = true, mplus = false, dungeon = false, world = false }, chatMin = 30,
              instanceOnly = false, font = "friz", size = 30, color = 1, outline = true,
              tenths = false, linger = -1, pos = { "TOP", "TOP", 0, -140 } },
    pullReport = { popup = "never", personal = false },      -- pop-ups off until someone turns them on
    keys = { min = 0, max = 0, excluded = {}, weight = "equal", history = {} },
    wowdle = { guesses = {}, standings = {}, stats = { played = 0, wins = 0, streak = 0, best = 0, sum = 0, dist = { 0, 0, 0, 0, 0, 0 } } },
}

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    TitanBoardDB = TitanBoardDB or {}
    applyDefaults(TitanBoardDB, DEFAULTS)
    ns.db = TitanBoardDB
    TitanUpDB = TitanUpDB or {}
    applyDefaults(TitanUpDB, SUITE_DEFAULTS)
    ns.udb = TitanUpDB
end)

-- Modules start at login for everyone; the guild only decides syncing.
local started = false
local function startModules()
    if started then return end
    started = true
    for _, name in ipairs({ "Updates", "Content", "Model", "Comms", "Sync", "Presence",
                            "Board", "Laser", "Invite", "ImportExport",
                            "Hub", "DeathRoll", "DRLedger", "DeathRollUI", "Wheel", "WheelUI", "Loot", "LootUI", "LootRolls",
                            "RaidCheck", "RaidCheckUI", "PullReport", "PullReportUI", "RaidScorecard", "RaidScorecardUI", "MacroShare", "MacroShareUI", "Timer", "TimerUI", "Tweaks", "TweaksUI", "DeathAlerts", "StackSplitter", "BattleRez", "BonusRollGuard", "Keys", "KeysUI", "Wowdle", "WowdleUI" }) do
        -- each module starts on its own: one failing can't stop the rest
        local m = ns[name]
        if m and m.Init then
            local ok, err = pcall(m.Init, m)
            if not ok then
                ns.Print(("|cffff5a5a%s didn't start properly:|r %s"):format(name, tostring(err)))
                if geterrorhandler then pcall(geterrorhandler(), err) end
            end
        end
    end
    ns.Print("v" .. ns.VERSION .. " loaded. /tu opens Titan Up, /tb the board, /tu roll Death Roll.")
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TitanBoard")
    if ADDON ~= "TitanBoard" and loaded then
        ns.Print("|cffff5a5aThe old standalone TitanBoard addon is also enabled.|r It's now part of Titan Up - please disable or delete the TitanBoard folder and /reload.")
    end
end
ns.Started = function() return started end

ns.NEEDS_GUILD = "Playing with others needs a guild - Titan Up syncs over your guild's private addon channel. Solo and practice modes still work."
local NO_GUILD = "You're not in a guild: Titan Up works on your own, but nothing syncs with other players until you join one."
local toldNoGuild = false
local function guildCheck(final)
    local ok, name = ns.CheckGuild()
    if ok then
        local before = ns.guildName
        ns.guildOK, ns.guildName = true, name
        if before and before ~= name then
            ns.Print(("Now syncing with <%s>."):format(name))
        elseif ns._noGuildSince then
            ns._noGuildSince = nil
            ns.Print(("Joined <%s> - Titan Up now syncs with your guild."):format(name))
        end
        toldNoGuild = false
        return true
    end
    if ok == nil and not final then return false end       -- guild info still loading
    if ns.guildOK then
        -- left the guild mid-session: keep working, stop syncing
        ns.guildOK, ns.guildName = false, nil
        ns._noGuildSince = GetTime()
        ns.Print(NO_GUILD)
        toldNoGuild = true
    elseif not toldNoGuild and final then
        -- only after a minute of checking, so a slow guild load never
        -- shows this to someone who IS in a guild
        toldNoGuild = true
        ns._noGuildSince = GetTime()
        ns.Print(NO_GUILD)
    end
    return false
end

ns.On("PLAYER_LOGIN", function()
    ns.me = ns.FullName("player") or UnitName("player")
    startModules()
    if guildCheck(false) then return end
    -- guild info can arrive a little after login: keep asking for a minute
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(2, function()
        tries = tries + 1
        if guildCheck(tries >= 30) or tries >= 30 then ticker:Cancel() end
    end)
end)
ns.On("PLAYER_GUILD_UPDATE", function() if ns.me then guildCheck(false) end end)
ns.On("GUILD_ROSTER_UPDATE", function() if ns.me and not ns.guildOK then guildCheck(false) end end)

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
local HELP = {
    "/tb - open or close the board",
    "/tb mini - toggle combat mini view",
    "/tb ids - print the instance/encounter IDs of the current board (for custom room images)",
    "/tb ids all - list every boss in the current instance with its encounter ID",
    "/tb testroom - toggle the sample custom room image on the current board",
    "/tb rate <n> - messages per second the send queue refills (default 1)",
    "/tb debug - toggle debug output",
}

SLASH_TITANUP1 = "/tu"
SLASH_TITANUP2 = "/titanup"
SlashCmdList.TITANUP = function(msg)
    if not ns.Started() then return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    if cmd == "" then
        ns.Hub:Toggle()
    elseif cmd == "board" or cmd == "tb" then
        SlashCmdList.TITANBOARD(arg)
    elseif cmd == "roll" or cmd == "dr" or cmd == "deathroll" then
        if arg == "sim" then ns.DeathRoll:StartSim()
        elseif arg == "debug" then
            local log = ns.DeathRoll.debugLog
            if #log == 0 then
                ns.Print("Death Roll debug: nothing unusual recorded (every roll was read from chat normally).")
            else
                ns.Print("Death Roll debug (newest first):")
                for _, line in ipairs(log) do ns.Print("  " .. line) end
            end
        else ns.DeathRollUI:Toggle() end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then
        ns.Settings:Toggle()
    elseif cmd == "new" or cmd == "whatsnew" then
        ns.Updates:ShowWhatsNew()
    elseif cmd == "versions" or cmd == "version" then
        ns.Updates:Check()
    elseif cmd == "timer" and arg == "test" then
        ns.Timer:Test()
    elseif cmd == "timer" and arg == "debug" then
        ns.Timer.debug = not ns.Timer.debug
        ns.Print("Combat Timer debug " .. (ns.Timer.debug and "ON - each combat / boss event and what the timer did will be printed." or "OFF."))
    elseif ns.Nav.sectionByKey[cmd] then
        ns.Hub:ShowSection(cmd)
    elseif ns.Nav.byKey[cmd] then
        local m = ns.Nav.byKey[cmd]
        if arg == "sim" and m.sim then m.sim() else m.show() end
    elseif cmd == "rolls" then
        if ns.LootRolls:Enabled() then ns.LootRolls.V:Open()
        else ns.Print("The loot roll window is off - turn it on in Loot settings (/tu settings).") end
    elseif cmd == "mem" or cmd == "memory" then
        ns.MemoryReport()
    elseif cmd == "minimap" then
        ns.udb.minimap.hidden = not ns.udb.minimap.hidden
        ns.Hub:UpdateMinimapButton()
        ns.Print("Minimap button " .. (ns.udb.minimap.hidden and "hidden" or "shown") .. ".")
    else
        ns.Print("/tu - open / close Titan Up (Home and every module on the left-hand rail)")
        ns.Print("/tb - TitanBoard (/tb help for its commands)")
        ns.Print("/tu raidcheck - raid readiness (also runs on ready check and /pull)")
        ns.Print("/tu timer - Combat Timer   |   /tu timer test - run it 10 seconds   |   /tu timer debug - explain what it's doing")
        ns.Print("/tu loot - loot tracker   |   /tu rolls - the loot roll window (if turned on in Loot settings)")
        ns.Print("/tu games - Home (the games are on the rail)")
        ns.Print("/tu roll - Death Roll   |   /tu roll sim - practice   |   /tu roll debug - roll-reading problems")
        ns.Print("/tu wheel - Wheel of Fortune   |   /tu wheel sim - practice with bots")
        ns.Print("/tu minimap - show/hide the minimap button")
        ns.Print("/tu settings - every module's options on one page")
        ns.Print("/tu versions - which Titan Up version everyone in your group runs")
        ns.Print("/tu new - what's new in this version")
        ns.Print("/tu mem - how much memory Titan Up is using, broken down by saved data and open windows")
    end
end

SLASH_TITANBOARD1 = "/tb"
SLASH_TITANBOARD2 = "/titanboard"
SlashCmdList.TITANBOARD = function(msg)
    if not ns.Started() then return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    if cmd == "" then
        ns.Board:Toggle()
    elseif cmd == "help" then
        for _, line in ipairs(HELP) do ns.Print(line) end
    elseif cmd == "mini" then
        if not ns.Board:IsShown() then ns.Board:Show() end
        ns.Board:SetMini(not ns.Board.mini)
    elseif cmd == "ids" then
        ns.Board:PrintIds(arg == "all")
    elseif cmd == "testroom" then
        ns.testRoom = not ns.testRoom
        ns.Print("Sample room image " .. (ns.testRoom and "ON" or "OFF") .. ". Coordinates are relative to the image, so existing drawings will shift.")
        ns.Board:ResetView()
        ns.Board:RenderAll()
    elseif cmd == "rate" then
        local n = tonumber(arg)
        if n and n > 0 then
            ns.db.settings.rate = n
            ns.Print("Send rate set to " .. n .. " msg/s.")
        else
            ns.Print("Send rate is " .. ns.db.settings.rate .. " msg/s.")
        end
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("Debug " .. (ns.db.debug and "ON" or "OFF"))
    else
        ns.Print("Unknown command. /tb help")
    end
end
