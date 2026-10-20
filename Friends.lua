local ADDON, ns = ...

-- ---------------------------------------------------------------------
-- Friends (0.48.0): Titan Up also talks to your friends who run it, so
-- Chess, Wowdle, Death Roll standings, Crafters and wishlists work without
-- a shared guild.
--   * Battle.net friends playing retail WoW in your region: through
--     Battle.net (any realm).
--   * Character friends (the in-game friends list): by hidden whisper,
--     which only reaches your own and connected realms.
-- Each friend gets one small hello per session (TitanUpFR "H"); one that
-- runs Titan Up answers "A", and from then on gets the guild-wide traffic
-- (ns.Routes). Friends who are in your guild get it over the guild instead.
-- There's no relaying: you only reach your own friends.
-- ---------------------------------------------------------------------
local FR = { known = {}, greeted = {}, onNew = {} }
ns.Friends = FR

local PREFIX = "TitanUpFR"
local CACHE = 10

function FR:Enabled()
    local u = ns.udb
    return not (u and u.friends and u.friends.share == false)
end

function FR:SetEnabled(on)
    if ns.udb and ns.udb.friends then ns.udb.friends.share = on and true or false end
    if on then self:Greet() end
end

local function str(v) return type(v) == "string" and not ns.IsSecret(v) and v ~= "" and v or nil end

-- "Name-Realm" for a Battle.net game account (nil if it isn't retail WoW)
local function bnName(a)
    if type(a) ~= "table" then return nil end
    if a.clientProgram and a.clientProgram ~= (BNET_CLIENT_WOW or "WoW") then return nil end
    if WOW_PROJECT_ID and a.wowProjectID and a.wowProjectID ~= WOW_PROJECT_ID then return nil end
    if a.isInCurrentRegion == false then return nil end
    local name = str(a.characterName)
    if not name then return nil end
    local realm = str(a.realmName)
    realm = realm and realm:gsub("[%s%-]", "")
    if realm and realm ~= "" then return name .. "-" .. realm end
    return ns.NormalizeSender(name)
end

-- Your online friends in WoW: { names = { ... }, byName = { [name] = { name, bn = gameAccountID } } }
function FR:Online()
    local now = GetTime()
    if self.list and now - self.list.at < CACHE then return self.list end
    local L = { at = now, names = {}, byName = {} }
    local function add(name, bnID)
        if not name or name == ns.me then return end
        local e = L.byName[name]
        if not e then
            e = { name = name }
            L.byName[name] = e
            L.names[#L.names + 1] = name
        end
        if bnID then e.bn = bnID end
    end
    local BN = C_BattleNet
    if BNGetNumFriends and BN and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo then
        local ok, n = pcall(BNGetNumFriends)
        n = ok and not ns.IsSecret(n) and tonumber(n) or 0
        for i = 1, n do
            local ok2, accts = pcall(BN.GetFriendNumGameAccounts, i)
            accts = ok2 and not ns.IsSecret(accts) and tonumber(accts) or 0
            for j = 1, accts do
                local ok3, a = pcall(BN.GetFriendGameAccountInfo, i, j)
                if ok3 and type(a) == "table" and a.isOnline ~= false and a.gameAccountID then add(bnName(a), a.gameAccountID) end
            end
        end
    end
    local CF = C_FriendList
    if CF and CF.GetNumFriends and CF.GetFriendInfoByIndex then
        local ok, n = pcall(CF.GetNumFriends)
        n = ok and not ns.IsSecret(n) and tonumber(n) or 0
        for i = 1, n do
            local ok2, f = pcall(CF.GetFriendInfoByIndex, i)
            if ok2 and type(f) == "table" and f.connected and str(f.name) then add(ns.NormalizeSender(f.name)) end
        end
    end
    self.list = L
    return L
end

function FR:Refresh() self.list = nil end

-- Is this character an online friend of yours (Battle.net or character)?
function FR:IsFriend(name)
    name = ns.NormalizeSender(name)
    return name ~= nil and self:Online().byName[name] ~= nil
end

-- Does this friend run Titan Up (heard from them this session)?
function FR:Known(name) return self.known[name] == true end

-- A Battle.net game account id -> that friend's character name
function FR:NameForBN(id)
    if not id or ns.IsSecret(id) then return nil end
    local f = C_BattleNet and C_BattleNet.GetGameAccountInfoByID
    if f then
        local ok, a = pcall(f, id)
        local name = ok and bnName(a)
        if name then return name end
    end
    for _, e in pairs(self:Online().byName) do if e.bn == id then return e.name end end
    return nil
end

-- Who gets guild-wide traffic: friends running Titan Up who aren't in
-- your guild. { { channel = "BN"|"WHISPER", target, name }, ... }
function FR:Targets()
    local out = {}
    if not self:Enabled() then return out end
    local L = self:Online()
    for _, name in ipairs(L.names) do
        if self.known[name] and not ns.IsGuildmate(name) then
            local e = L.byName[name]
            if e.bn then out[#out + 1] = { channel = "BN", target = e.bn, name = name }
            else out[#out + 1] = { channel = "WHISPER", target = name, name = name } end
        end
    end
    return out
end

function FR:Any() return #self:Targets() > 0 end

-- run fn(name) when a friend running Titan Up is first heard (modules say hello)
function FR:OnNewFriend(fn) self.onNew[#self.onNew + 1] = fn end

-- A Titan Up message from a friend: they run it.
function FR:Heard(name)
    if not name or self.known[name] then return end
    self.known[name] = true
    -- a few seconds' wait, so several friends at login share one round of hellos
    ns.Debounce("friends:new", 5, function()
        for _, fn in ipairs(self.onNew) do ns.Try(fn) end
    end)
end

local function send(e, msg)
    if e.bn then ns.Send(PREFIX, msg, "BN", e.bn) else ns.Send(PREFIX, msg, "WHISPER", e.name) end
end

-- Say hello to each online friend we haven't greeted this session.
function FR:Greet()
    if not self:Enabled() or not ns.me then return end
    local L = self:Online()
    for _, name in ipairs(L.names) do
        if not self.greeted[name] then
            self.greeted[name] = true
            send(L.byName[name], "H^" .. ns.VERSION)
        end
    end
    -- friends who went offline are greeted again when they're back
    for name in pairs(self.greeted) do
        if not L.byName[name] then self.greeted[name], self.known[name] = nil, nil end
    end
end

function FR:OnHello(msg, name, bnID)
    if not self:Enabled() then return end
    local kind = msg:match("^(%a)")
    if kind ~= "H" and kind ~= "A" then return end
    if kind == "H" then
        self.greeted[name] = true
        send({ name = name, bn = bnID }, "A^" .. ns.VERSION)
    end
    self:Heard(name)
end

function FR:Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    ns.On("CHAT_MSG_ADDON", function(p, msg, channel, sender)
        if p ~= PREFIX or channel ~= "WHISPER" or ns.IsSecret(msg) then return end
        local name = ns.NormalizeSender(sender)
        if name and name ~= ns.me and self:IsFriend(name) then self:OnHello(msg, name) end
    end)
    ns.On("BN_CHAT_MSG_ADDON", function(p, msg, _, senderID)
        if p ~= PREFIX or ns.IsSecret(msg) then return end
        local name = self:NameForBN(senderID)
        if name and name ~= ns.me then self:OnHello(msg, name, senderID) end
    end)
    local function changed()
        self:Refresh()
        ns.Debounce("friends:greet", 5, function() self:Greet() end)
    end
    for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED" }) do
        ns.On(ev, changed)
    end
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
    C_Timer.After(8, function() self:Greet() end)
end
