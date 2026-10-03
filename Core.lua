-- Titan Up - Core.lua
-- The Titan Up guild toolkit. Modules: TitanBoard (raid strategy board),
-- Death Roll (fun). Event dispatch, saved variables, player/group helpers,
-- permissions and slash commands; every module hangs off the shared `ns`.
local ADDON, ns = ...

ns.VERSION = "0.13.0"
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

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        Core:RegisterEvent(event)
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
        if ns.Sim and ns.Sim.active then
            for _, m in ipairs(ns.Sim.members) do out[#out + 1] = { name = m.name, group = m.group or 1, online = true } end
        end
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
    if ns.Sim and ns.Sim.active then
        for _, m in ipairs(ns.Sim.members) do
            if m.name == full then return m.class end
        end
    end
    local unit = (full == ns.me) and "player" or ns.UnitForName(full)
    if unit then
        local _, class = UnitClass(unit)
        if class and not ns.IsSecret(class) then return class end
    end
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
    if not IsInGroup() then
        if name == ns.me then return true end
        return (ns.Sim and ns.Sim.active and ns.acl[name]) and true or false
    end
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
    deathroll = { announce = true, delayChat = true, ledger = {}, games = {} },
    loot = { drops = {}, minQuality = 4 },
    raidcheck = { approved = { flask = {}, food = {} }, potMin = 10, durMin = 20, pullCheck = true },
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

ns.On("PLAYER_LOGIN", function()
    ns.me = ns.FullName("player") or UnitName("player")
    for _, name in ipairs({ "Content", "Model", "Comms", "Sync", "Presence",
                            "Board", "Laser", "Invite", "ImportExport", "Sim",
                            "Hub", "DeathRoll", "DRLedger", "DeathRollUI", "Wheel", "WheelUI", "Loot", "LootUI",
                            "RaidCheck", "RaidCheckUI" }) do
        local m = ns[name]
        if m and m.Init then m:Init() end
    end
    ns.Print("v" .. ns.VERSION .. " loaded. /tu opens Titan Up, /tb the board, /tu roll Death Roll.")
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TitanBoard")
    if ADDON ~= "TitanBoard" and loaded then
        ns.Print("|cffff5a5aThe old standalone TitanBoard addon is also enabled.|r It's now part of Titan Up - please disable or delete the TitanBoard folder and /reload.")
    end
end)

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
local HELP = {
    "/tb - open or close the board",
    "/tb sim - start/stop a fake raid to test solo (results print after ~30s)",
    "/tb sim lockdown - pretend an encounter lockdown is active (tests queueing)",
    "/tb loop - send your drawing through the real addon channel to yourself and verify it",
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
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    if cmd == "" then
        ns.Hub:Toggle()
    elseif cmd == "board" or cmd == "tb" then
        SlashCmdList.TITANBOARD(arg)
    elseif cmd == "roll" or cmd == "dr" or cmd == "deathroll" then
        if arg == "sim" then ns.DeathRoll:StartSim() else ns.DeathRollUI:Toggle() end
    elseif ns.Nav.sectionByKey[cmd] then
        ns.Hub:ShowSection(cmd)
    elseif ns.Nav.byKey[cmd] then
        local m = ns.Nav.byKey[cmd]
        if arg == "sim" and m.sim then m.sim() else m.show() end
    elseif cmd == "mem" or cmd == "memory" then
        local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
        local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
        if update and get then
            update()
            ns.Print(("Titan Up is using %.0f KB of memory."):format(get(ADDON) or 0))
        else
            ns.Print("This client doesn't report addon memory.")
        end
    elseif cmd == "minimap" then
        ns.udb.minimap.hidden = not ns.udb.minimap.hidden
        ns.Hub:UpdateMinimapButton()
        ns.Print("Minimap button " .. (ns.udb.minimap.hidden and "hidden" or "shown") .. ".")
    else
        ns.Print("/tu - Titan Up hub")
        ns.Print("/tb - TitanBoard (/tb help for its commands)")
        ns.Print("/tu raidcheck - raid readiness (also runs on ready check and /pull)")
        ns.Print("/tu loot - loot tracker")
        ns.Print("/tu games - all the games")
        ns.Print("/tu roll - Death Roll   |   /tu roll sim - practice against a fake opponent")
        ns.Print("/tu wheel - Wheel of Fortune   |   /tu wheel sim - practice with bots")
        ns.Print("/tu minimap - show/hide the minimap button")
        ns.Print("/tu mem - how much memory Titan Up is using")
    end
end

SLASH_TITANBOARD1 = "/tb"
SLASH_TITANBOARD2 = "/titanboard"
SlashCmdList.TITANBOARD = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    if cmd == "" then
        ns.Board:Toggle()
    elseif cmd == "help" then
        for _, line in ipairs(HELP) do ns.Print(line) end
    elseif cmd == "sim" then
        if arg == "lockdown" then
            ns.fakeLockdown = not ns.fakeLockdown
            ns.Print("Fake encounter lockdown " .. (ns.fakeLockdown and "|cffff9f40ON|r - your changes now queue." or "OFF - queue flushes."))
        elseif ns.Sim.active then
            ns.Sim:Stop()
        else
            ns.Sim:Start()
        end
    elseif cmd == "loop" then
        ns.Comms:ToggleLoopback()
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
