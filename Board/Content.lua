-- TitanBoard - Content.lua
-- Which raids, dungeons and bosses exist - read live from the game so a new
-- season works without an addon update:
--   * Mythic+ pool: C_ChallengeMode.GetMapTable() (the active keystone
--     dungeons, including ones returning from older expansions)
--   * Raids: the newest Encounter Journal tier
--   * Bosses + where they stand: Encounter Journal + the map pins the
--     journal uses for its skull icons
local ADDON, ns = ...

local Content = {}
ns.Content = Content

-- If a keystone dungeon's name doesn't match its journal entry, map it
-- here: [normalized name] = journalInstanceID. (/tb debug prints misses.)
Content.NAME_OVERRIDES = {}

local function norm(s)
    return (tostring(s or ""):lower():gsub("[^%w]", ""))
end

-- EJ_SelectTier changes what the Encounter Journal window shows, so put
-- the player's tier back afterwards.
local function withTiers(fn)
    local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local ok, err = pcall(fn)
    if not ok then ns.Debug("journal read failed:", err) end
    if prev then pcall(EJ_SelectTier, prev) end
end

function Content:Init()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        pcall(C_MythicPlus.RequestMapInfo)
    end
    ns.On("CHALLENGE_MODE_MAPS_UPDATE", function()
        Content._dungeons = nil
        if ns.Board and ns.Board.frame then ns.Board:RefreshList(true) end
    end)
end

-- name -> journal instance ID across every tier (dungeons and raids)
function Content:JournalIndex()
    if self._index then return self._index end
    local idx = {}
    withTiers(function()
        for tier = 1, EJ_GetNumTiers() do
            EJ_SelectTier(tier)
            for _, isRaid in ipairs({ false, true }) do
                local i = 1
                while true do
                    local id, name = EJ_GetInstanceByIndex(i, isRaid)
                    if not id then break end
                    idx[norm(name)] = id
                    i = i + 1
                end
            end
        end
    end)
    self._index = idx
    return idx
end

-- The journal lists the expansion's world bosses as a "raid". Spot it by
-- its name matching the tier ("Midnight") or by not showing difficulties.
function Content:Raids()
    if self._raids then return self._raids end
    local out, world = {}, {}
    withTiers(function()
        local tier = EJ_GetNumTiers()
        EJ_SelectTier(tier)
        local tierName = EJ_GetTierInfo and EJ_GetTierInfo(tier)
        local i = 1
        while true do
            local id, name = EJ_GetInstanceByIndex(i, true)
            if not id then break end
            local isWorld = tierName ~= nil and name == tierName
            if not isWorld then
                local showDifficulty = select(9, EJ_GetInstanceInfo(id))
                isWorld = showDifficulty == false
            end
            local list = isWorld and world or out
            list[#list + 1] = { id = id, name = name }
            i = i + 1
        end
    end)
    self._raids, self._world = out, world
    return out
end

function Content:WorldBosses()
    self:Raids()
    return self._world or {}
end

function Content:Dungeons()
    if self._dungeons then return self._dungeons end
    local out = {}
    local maps = (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()) or {}
    if #maps == 0 then return out end   -- not loaded yet; don't cache
    local idx = self:JournalIndex()
    for _, cmID in ipairs(maps) do
        local name = C_ChallengeMode.GetMapUIInfo(cmID)
        if name then
            local key = norm(name)
            local jid = self.NAME_OVERRIDES[key] or idx[key]
            if not jid then ns.Debug("No journal match for keystone dungeon:", name) end
            out[#out + 1] = { id = jid, name = name, missing = not jid }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    self._dungeons = out
    return out
end

-- All floor maps that belong to an instance's main map.
local function floorsOf(mapID)
    local list, seen = {}, {}
    local function add(m)
        if m and m > 0 and not seen[m] then
            seen[m] = true
            list[#list + 1] = m
        end
    end
    add(mapID)
    local gid = C_Map.GetMapGroupID and C_Map.GetMapGroupID(mapID)
    if gid then
        for _, info in ipairs(C_Map.GetMapGroupMembersInfo(gid) or {}) do add(info.mapID) end
    end
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do add(child.mapID) end
    return list
end

-- Bosses of an instance: { id = journalEncounterID, dungeonEncounterID,
-- name, map = floor uiMapID, x, y = position on that floor (0-1) }
function Content:Encounters(instID)
    self._enc = self._enc or {}
    if not instID then return {} end
    if self._enc[instID] then return self._enc[instID] end
    local list = {}
    local ok, err = pcall(function()
        local function read()
            local j = 1
            while true do
                local name, _, jEnc, _, _, _, dEnc = EJ_GetEncounterInfoByIndex(j, instID)
                if not name then break end
                list[#list + 1] = { id = jEnc, dungeonEncounterID = dEnc, name = name }
                j = j + 1
            end
        end
        read()
        if #list == 0 then
            EJ_SelectInstance(instID)
            read()
        end
        local mainMap = select(7, EJ_GetInstanceInfo(instID))
        if not mainMap or mainMap == 0 then return end
        local pinned = {}
        for _, mapID in ipairs(floorsOf(mainMap)) do
            local pins = C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap
                and C_EncounterJournal.GetEncountersOnMap(mapID)
            for _, pin in ipairs(pins or {}) do
                if not pinned[pin.encounterID] then
                    pinned[pin.encounterID] = { map = mapID, x = pin.mapX, y = pin.mapY }
                end
            end
        end
        for _, e in ipairs(list) do
            local p = pinned[e.id]
            if p then
                e.map, e.x, e.y = p.map, p.x, p.y
            else
                e.map = mainMap
            end
        end
    end)
    if not ok then ns.Debug("encounter read failed:", err) end
    self._enc[instID] = list
    return list
end

function Content:InstanceName(instID)
    if not instID then return nil end
    local ok, name = pcall(EJ_GetInstanceInfo, instID)
    return ok and name or nil
end

-- A "context" is what the board is showing: instance, boss, floor map.
-- ctx.key identifies the saved plan.
function Content:MakeContext(inst, enc, map)
    local ctx = { inst = inst, enc = enc, map = map }
    if inst then
        ctx.instName = self:InstanceName(inst)
        if enc then
            for _, e in ipairs(self:Encounters(inst)) do
                if e.id == enc then
                    ctx.name = e.name
                    ctx.map = ctx.map or e.map
                    ctx.bx, ctx.by = e.x, e.y
                end
            end
        end
        if not ctx.map then
            local m = select(7, EJ_GetInstanceInfo(inst))
            if m and m > 0 then ctx.map = m end
        end
    end
    if enc then
        ctx.key = "e" .. enc
    elseif ctx.map then
        ctx.key = "m" .. ctx.map
    else
        ctx.key = "free"
    end
    return ctx
end

-- Where the player is standing right now (nil outside instances).
function Content:CurrentContext()
    if not IsInInstance() then return nil end
    local uiMap = C_Map.GetBestMapForUnit("player")
    if not uiMap then return nil end
    local ok, inst = pcall(EJ_GetInstanceForMap, uiMap)
    inst = (ok and inst and inst > 0) and inst or nil
    local ctx = self:MakeContext(inst, nil, uiMap)
    ctx.here = true
    return ctx
end
