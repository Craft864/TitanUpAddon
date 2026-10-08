-- Titan Up - Keys/Keys.lua
-- Keystone Roulette (UI Tweaks section): spin a wheel of your group's
-- Mythic+ keys, or hold a quick vote, and announce the winner.
--   * Keys: yours from the game; Titan Up guildmates' over the guild
--     channel; everyone else's read locally from BigWigs' LibKeystone and
--     Details' LibOpenRaid if they're installed (Titan Up sends nothing to
--     non-guildmates itself).
--   * Filters: a level range, dungeons to leave out, and equal chances or
--     favoring higher keys.
--   * Vote: Titan Up users click a button; anyone can type the number or
--     short name in party chat. Ties are settled by a spin.
--   * Result: posted to party chat, and Titan Up users get a popup with the
--     dungeon and a Teleport button (set up after combat if needed).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local KR = {}
ns.Keys = KR

local PREFIX = "TitanUpKR"
local VOTE_SECONDS = 20
local SPIN_SECONDS = 3.6

local function db() return ns.udb.keys end

KR.JOKES = {
    "the wheel has spoken - no appeals!",
    "pack your potions, it's happening.",
    "may your interrupts land and your healer stay awake.",
    "chosen by an extremely scientific spin.",
    "time to find out if the route was ever planned.",
    "the timer is already nervous.",
    "please clap for whoever owns this key.",
    "no rerolls. Okay, maybe one reroll.",
    "you asked for chaos, you got chaos.",
    "the tank has been notified. The tank has not consented.",
    "bring snacks, this one has trash packs.",
    "the dungeon gods demand tribute (repair bills).",
    "this is fine. Everything is fine.",
    "fortune favors the bold. And the overgeared.",
    "victory or a very educational wipe.",
    "the keystone glows with anticipation. Or fear.",
    "a fine choice, if we do say so ourselves.",
    "deplete it or complete it - no in between.",
}

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
function KR:Init()
    self.fromGuild, self.fromLib = {}, {}
    ns.Listen(PREFIX, "group", function(msg, sender) KR:OnMessage(msg, sender) end)
    for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
        ns.On(ev, function(text, sender) KR:OnChatVote(text, sender) end)
    end
    ns.On("PLAYER_REGEN_ENABLED", function()
        if KR.popupPending then C_Timer.After(0.5, function() KR:SetupTeleport() end) end
        if ns.KeysUI and ns.KeysUI:IsShown() then C_Timer.After(0.5, function() ns.KeysUI:SetupIconTeleports() end) end
    end)
    -- spell buttons must be hidden before combat locks them
    ns.On("PLAYER_REGEN_DISABLED", function() if ns.KeysUI then ns.KeysUI:HideIconTeleports(true) end end)
    -- other addons' keystone libraries (read locally)
    local LKS = LibStub and LibStub("LibKeystone", true)
    if LKS and LKS.Register then
        pcall(LKS.Register, KR, function(level, mapID, _, name)
            if type(level) == "number" and level > 0 and type(mapID) == "number" and name then
                KR.fromLib[ns.NormalizeSender(name) or name] = { mapID = mapID, level = level, source = "BigWigs" }
                if ns.KeysUI then ns.KeysUI:Refresh() end
            end
        end)
    end
end

-- ---------------------------------------------------------------------
-- Collecting keys
-- ---------------------------------------------------------------------
local short = ns.UI.Short

function KR.MapInfo(mapID)
    local name, _, _, texture, background = C_ChallengeMode.GetMapUIInfo(mapID)
    return name or ("Dungeon " .. tostring(mapID)), texture, background
end

-- Short name from the dungeon's words: "Magisters' Terrace" -> "MT",
-- "Pit of Saron" -> "PS"; one-word names use their first four letters.
function KR.Abbrev(mapID)
    local name = KR.MapInfo(mapID)
    local letters, words = {}, 0
    for w in name:gmatch("[%a']+") do
        local lw = w:lower()
        if lw ~= "of" and lw ~= "the" and lw ~= "and" then letters[#letters + 1] = w:sub(1, 1):upper(); words = words + 1 end
    end
    if words <= 1 then return (name:gsub("[^%a]", ""):sub(1, 4):upper()) end
    return table.concat(letters)
end

-- Party members as { full, short, class, unit }.
function KR.Party()
    local out = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local full = ns.FullName(unit)
        if not full then return end
        out[#out + 1] = { full = full, short = short(full), class = ns.Safe.Class(unit), unit = unit }
    end
    add("player")
    if not IsInRaid() then for i = 1, 4 do add("party" .. i) end end
    return out
end

local function libOpenRaidKeys()
    local LOR = LibStub and LibStub("LibOpenRaid-1.0", true)
    if not (LOR and LOR.GetAllKeystonesInfo) then return {} end
    local ok, all = pcall(LOR.GetAllKeystonesInfo)
    return ok and type(all) == "table" and all or {}
end

-- Everyone's key, plus who we know nothing about.
function KR:Collect()
    local keys, missing = {}, {}
    local lor = libOpenRaidKeys()
    for _, m in ipairs(KR.Party()) do
        local k
        if m.unit == "player" then
            local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
            local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
            if mapID and level and level > 0 then k = { mapID = mapID, level = level, source = "You" } end
        end
        k = k or self.fromGuild[m.full] or self.fromLib[m.full]
        if not k then
            local o = lor[m.full] or lor[m.short]
            if o and (o.level or 0) > 0 and (o.challengeMapID or o.mythicPlusMapID) then
                k = { mapID = o.challengeMapID or o.mythicPlusMapID, level = o.level, source = "Details" }
            end
        end
        if k then
            keys[#keys + 1] = { owner = m.full, short = m.short, class = m.class, mapID = k.mapID, level = k.level, source = k.source }
        else
            missing[#missing + 1] = m
        end
    end
    table.sort(keys, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.owner < b.owner end)
    return keys, missing
end

-- Ask for fresh keys: guildmates over the guild channel, everyone else
-- through BigWigs / Details if they're installed.
function KR:RequestKeys()
    if self.lastRequest and GetTime() - self.lastRequest < 5 then return end
    self.lastRequest = GetTime()
    local ch = ns.DataChannel()
    if ch and IsInGroup() then ns.Send(PREFIX, "Q", ch) end
    local LKS = LibStub and LibStub("LibKeystone", true)
    if LKS and LKS.Request and IsInGroup() then pcall(LKS.Request, "PARTY") end
    local LOR = LibStub and LibStub("LibOpenRaid-1.0", true)
    if LOR and LOR.RequestKeystoneDataFromParty and IsInGroup() then pcall(LOR.RequestKeystoneDataFromParty) end
end

function KR:Eligible(keys)
    local d, out = db(), {}
    for _, k in ipairs(keys) do
        if (d.min == 0 or k.level >= d.min) and (d.max == 0 or k.level <= d.max) and not d.excluded[k.mapID] then out[#out + 1] = k end
    end
    return out
end

-- Weighted random pick (equal chances, or by key level).
function KR:Pick(list)
    if #list == 0 then return nil end
    local total = 0
    for _, k in ipairs(list) do total = total + (db().weight == "higher" and k.level or 1) end
    local r = math.random() * total
    for i, k in ipairs(list) do
        r = r - (db().weight == "higher" and k.level or 1)
        if r <= 0 then return i end
    end
    return #list
end

-- ---------------------------------------------------------------------
-- Messages (guild channel, group members only)
-- ---------------------------------------------------------------------
--   Q                   send me your key
--   K map level         my key
--   V id secs list      a vote started (list: map:level:owner,...)
--   B id index          my vote
--   W map level owner   the winner
function KR:Send(msg) ns.SendFields(PREFIX, msg) end

function KR:OnMessage(msg, sender)
    local f = ns.Split(msg, "^")
    if f[1] == "Q" then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        if mapID and level and level > 0 then
            C_Timer.After(math.random() * 1.5, function() KR:Send(("K^%d^%d"):format(mapID, level)) end)
        end
    elseif f[1] == "K" then
        local mapID, level = tonumber(f[2]), tonumber(f[3])
        if mapID and level and level > 0 and level < 40 then
            self.fromGuild[sender] = { mapID = mapID, level = level, source = "Titan Up" }
            if ns.KeysUI then ns.KeysUI:Refresh() end
        end
    elseif f[1] == "V" then
        local list = {}
        for entry in (f[4] or ""):gmatch("[^,]+") do
            local m, l, o = entry:match("^(%d+):(%d+):(.+)$")
            if m then list[#list + 1] = { mapID = tonumber(m), level = tonumber(l), owner = o, short = short(o) } end
        end
        if #list >= 2 then
            self.vote = { id = f[2], keys = list, votes = {}, endsAt = GetTime() + (tonumber(f[3]) or VOTE_SECONDS), host = sender }
            if ns.KeysUI then ns.KeysUI:Show(); ns.KeysUI:Refresh() end
        end
    elseif f[1] == "B" then
        local v, i = self.vote, tonumber(f[3])
        if v and v.id == f[2] and i and v.keys[i] then v.votes[sender] = i; if ns.KeysUI then ns.KeysUI:Refresh() end end
    elseif f[1] == "W" then
        local mapID, level = tonumber(f[2]), tonumber(f[3])
        if mapID and level then
            self.vote = nil
            self:Remember(mapID, level, f[4])
            self:ShowPopup(mapID, level, f[4])
        end
    end
end

-- Typed votes in party chat: the number or the short name ("2", "mt").
function KR:OnChatVote(text, sender)
    local v = self.vote
    if not v or GetTime() > v.endsAt or not text or ns.IsSecret(text) or ns.IsSecret(sender) then return end
    local t = strtrim and strtrim(text):upper() or text:upper()
    local idx = tonumber(t)
    if not (idx and v.keys[idx]) then
        idx = nil
        for i, k in ipairs(v.keys) do if KR.Abbrev(k.mapID) == t then idx = i end end
    end
    if idx then
        v.votes[ns.NormalizeSender(sender) or sender] = idx
        if ns.KeysUI then ns.KeysUI:Refresh() end
    end
end

function KR:StartVote(list)
    if #list < 2 then return false, "A vote needs at least two eligible keys." end
    local parts, chat = {}, {}
    for i, k in ipairs(list) do
        parts[#parts + 1] = ("%d:%d:%s"):format(k.mapID, k.level, k.owner)
        chat[#chat + 1] = ("%d) %s +%d"):format(i, KR.Abbrev(k.mapID), k.level)
    end
    local id = tostring(time())
    self.vote = { id = id, keys = list, votes = {}, endsAt = GetTime() + VOTE_SECONDS, host = ns.me }
    self:Send(("V^%s^%d^%s"):format(id, VOTE_SECONDS, table.concat(parts, ",")))
    if IsInGroup() then
        C_ChatInfo.SendChatMessage(("Keystone vote (%ds) - type the number or short name: %s"):format(VOTE_SECONDS, table.concat(chat, "   ")), "PARTY")
    end
    C_Timer.After(VOTE_SECONDS, function() KR:FinishVote(id) end)
    return true
end

function KR:CastVote(i)
    local v = self.vote
    if not v or not v.keys[i] or GetTime() > v.endsAt then return end
    v.votes[ns.me] = i
    self:Send(("B^%s^%d"):format(v.id, i))
    if ns.KeysUI then ns.KeysUI:Refresh() end
end

function KR:Tally()
    local v, counts = self.vote, {}
    if not v then return counts end
    for _, i in pairs(v.votes) do counts[i] = (counts[i] or 0) + 1 end
    return counts
end

-- Highest votes wins; a tie (or no votes at all) is settled by a spin.
function KR:FinishVote(id)
    local v = self.vote
    if not v or v.id ~= id or v.host ~= ns.me then return end
    local counts, best, tied = self:Tally(), 0, {}
    for i = 1, #v.keys do
        local c = counts[i] or 0
        if c > best then best, tied = c, { i } elseif c == best then tied[#tied + 1] = i end
    end
    local winner = tied[math.random(1, #tied)]
    self.vote = nil
    if #tied > 1 and ns.KeysUI and ns.KeysUI:IsShown() then
        ns.KeysUI:SpinTo(v.keys, winner, "vote")             -- tie: the wheel settles it
    else
        self:Announce(v.keys[winner], "vote")
    end
end

-- ---------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------
function KR:Remember(mapID, level, owner, how)
    local h = db().history
    table.insert(h, 1, { t = time(), mapID = mapID, level = level, owner = owner, how = how })
    while #h > 10 do table.remove(h) end
end

function KR:Announce(k, how)
    if not k then return end
    local name = KR.MapInfo(k.mapID)
    local owner = k.short or short(k.owner)
    local who = owner .. ((owner:sub(-1) == "s") and "'" or "'s")
    if IsInGroup() then
        C_ChatInfo.SendChatMessage(("Keystone Roulette: %s %s +%d - %s"):format(who, name, k.level, KR.JOKES[math.random(1, #KR.JOKES)]), "PARTY")
    end
    self:Send(("W^%d^%d^%s"):format(k.mapID, k.level, k.owner))
    self:Remember(k.mapID, k.level, k.owner, how)
    self:ShowPopup(k.mapID, k.level, k.owner)
    if ns.KeysUI then ns.KeysUI:Refresh() end
end

-- ---------------------------------------------------------------------
-- Teleports: found in the spellbook's dungeon-teleport flyouts by the
-- dungeon's name ("Teleport to the entrance to <dungeon>"), so new
-- seasons need no updates. A few known IDs are a fallback.
-- ---------------------------------------------------------------------
local FALLBACK = { [161] = 159898, [402] = 393273, [399] = 393256 }

-- Part of the dungeon picture to use: left, right, top, bottom. The game's
-- picture file has padding: measured with /tu keys art, the parchment frame
-- spans ~2-72% across and ~2-66% down, and the scene inside it ~4-70% x
-- ~6-63%. This takes the scene's middle at the popup's 2:1 shape (no
-- stretching, none of the frame or padding). /tu keys art stays available
-- in case a patch changes the picture layout.
KR.ART_CROP = { 0.09, 0.65, 0.06, 0.63 }

function KR.Teleport(mapID)
    local dungeon = KR.MapInfo(mapID):lower()
    if GetNumFlyouts and GetFlyoutID and GetFlyoutInfo and GetFlyoutSlotInfo then
        for i = 1, GetNumFlyouts() do
            local fid = GetFlyoutID(i)
            local _, _, slots = GetFlyoutInfo(fid)
            for s = 1, slots or 0 do
                local spellID, _, known = GetFlyoutSlotInfo(fid, s)
                if spellID then
                    local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
                    if desc and desc ~= "" then
                        if desc:lower():find(dungeon, 1, true) then return spellID, known and true or false end
                    elseif C_Spell.RequestLoadSpellData then
                        C_Spell.RequestLoadSpellData(spellID)
                    end
                end
            end
        end
    end
    local id = FALLBACK[mapID]
    if id then
        local known = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
        return id, known and true or false
    end
    return nil, false
end

function KR:EnsurePopup()
    if self.popup then return self.popup end
    -- not on Esc / not raised on click: the secure Teleport button sits on top of it
    local p = UI.Window("TitanUpKeyPopup", 380, 190, { point = { "TOP", 0, -160 }, strata = "DIALOG", border = C.accent,
        drag = true, noTop = true, noEsc = true })
    -- dungeon art, edge to edge: the game's picture has its own painted
    -- frame around the scene, so crop that off (ART_CROP) and fill the popup
    p.art = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.art:SetPoint("TOPLEFT", 1, -1); p.art:SetPoint("BOTTOMRIGHT", -1, 1)
    p.art:SetTexCoord(KR.ART_CROP[1], KR.ART_CROP[2], KR.ART_CROP[3], KR.ART_CROP[4])
    p.art:SetAlpha(0.6)
    -- darker toward the bottom so the button and hint stay readable
    p.shade = p:CreateTexture(nil, "BACKGROUND", nil, 2)
    p.shade:SetPoint("TOPLEFT", 1, -1); p.shade:SetPoint("BOTTOMRIGHT", -1, 1)
    p.shade:SetColorTexture(1, 1, 1, 1)
    if p.shade.SetGradient and CreateColor then
        p.shade:SetGradient("VERTICAL", CreateColor(0.03, 0.04, 0.06, 0.92), CreateColor(0.03, 0.04, 0.06, 0.15))
    else
        p.shade:SetColorTexture(0.03, 0.04, 0.06, 0.45)
    end
    p.title = UI.Text(p, "GameFontNormalSmall", C.accent, "KEYSTONE ROULETTE", "TOP", 0, -12)
    p.name = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.name:SetPoint("TOP", 0, -36)
    p.owner = UI.Text(p, "GameFontHighlight", C.text, nil, "TOP", p.name, "BOTTOM", 0, -6)
    p.status = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "BOTTOM", 0, 16)
    -- placeholder shown whenever the real (secure) button can't be used
    p.fake = UI.Button(p, 170, 34, "Teleport", nil, nil)
    p.fake:SetPoint("BOTTOM", 0, 36)
    UI.SetDisabled(p.fake, true)
    local close = UI.Button(p, 22, 20, "X", "Close", function() KR:HidePopup() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    self.popup = p
    return p
end

function KR:ShowPopup(mapID, level, owner)
    local p = self:EnsurePopup()
    local name, _, bg = KR.MapInfo(mapID)
    p.mapID = mapID
    if bg then p.art:SetTexture(bg) end
    p.name:SetText(("%s  |cffffd94d+%d|r"):format(name, level))
    p.owner:SetText(owner and (short(owner) .. "'s key") or "")
    p:Show()
    self:SetupTeleport()
end

-- The Teleport button is a secure spell button: it can only be set up out
-- of combat. In combat the popup shows "Ready after combat" and this runs
-- again when combat ends.
function KR:SetupTeleport()
    local p = self.popup
    if not (p and p:IsShown()) then return end
    local spellID, known = KR.Teleport(p.mapID)
    if InCombatLockdown() then
        self.popupPending = true
        p.fake.label:SetText("Teleport")
        p.fake:Show()
        p.status:SetText("Ready after combat")
        return
    end
    self.popupPending = nil
    if not self.tp then
        local b = CreateFrame("Button", "TitanUpKeyTeleport", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
        b:SetSize(170, 34)
        b:RegisterForClicks("AnyUp", "AnyDown")
        UI.Skin(b, C.accentDim or C.panel, C.accent)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText("Teleport")
        b:SetFrameStrata("DIALOG")
        self.tp = b
    end
    local b = self.tp
    if spellID and known then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", spellID)
        b:ClearAllPoints()
        b:SetPoint("BOTTOM", p, "BOTTOM", 0, 36)
        b:SetFrameLevel(p:GetFrameLevel() + 10)
        b:Show()
        p.fake:Hide()
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
        local left = cd and cd.duration and cd.duration > 1.5 and (cd.startTime + cd.duration - GetTime()) or 0
        p.status:SetText(left > 0 and ("On cooldown: %d:%02d"):format(math.floor(left / 60), math.floor(left % 60)) or "Click to teleport to the entrance")
    else
        b:Hide()
        p.fake:Show()
        p.status:SetText(spellID and "You haven't unlocked this teleport yet (time a +10 here)" or "No teleport found for this dungeon")
    end
end

function KR:HidePopup()
    if self.popup then self.popup:Hide() end
    if self.tp then
        if InCombatLockdown() then self.popupPending = true else self.tp:Hide() end
    end
end

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------
local V = {}
ns.KeysUI = V
local W, H = 600, 600
local WHEEL = 250

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpKeys", "keys", "KEYSTONE ROULETTE", W, H, { mark = false,
        onShow = function() KR:RequestKeys(); V:Refresh() end })
    f:SetScript("OnHide", function() V:HideIconTeleports() end)
    local refresh = UI.Button(f, 90, 22, "Refresh", "Ask the group for their keys again", function() KR.lastRequest = nil; KR:RequestKeys(); V:Refresh() end)
    refresh:SetPoint("RIGHT", self.header.close, "LEFT", -8, 0)
    UI.Text(f, "GameFontHighlightSmall", C.muted, "Your group's keys - spin for one, or put it to a vote.", "TOPLEFT", 18, -12)

    -- wheel
    local wheelBox = CreateFrame("Frame", nil, f)
    wheelBox:SetSize(WHEEL, WHEEL)
    wheelBox:SetPoint("TOPLEFT", 22, -52)
    self.wheel = wheelBox:CreateTexture(nil, "ARTWORK")
    self.wheel:SetAllPoints()
    self.pointer = f:CreateTexture(nil, "OVERLAY")
    self.pointer:SetTexture(ns.MEDIA .. "Down")
    self.pointer:SetSize(26, 26)
    self.pointer:SetPoint("BOTTOM", wheelBox, "TOP", 0, -10)
    self.wheelBox = wheelBox
    self.sliceLabels = {}
    for i = 1, 5 do
        local t = wheelBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetTextColor(1, 1, 1)
        self.sliceLabels[i] = t
    end
    self.wheelEmpty = UI.Text(f, "GameFontHighlight", C.muted, nil, "CENTER", wheelBox, "CENTER", 0, 0)
    self.angle = 0

    -- key list
    local lx = WHEEL + 50
    UI.Text(f, "GameFontNormalSmall", C.accent, "KEYS", "TOPLEFT", lx, -52)
    self.keyRows = {}
    for i = 1, 5 do
        local r = CreateFrame("Frame", nil, f, "BackdropTemplate")
        r:SetSize(W - lx - 18, 42)
        r:SetPoint("TOPLEFT", lx, -70 - (i - 1) * 46)
        UI.Skin(r, C.panel, C.line)
        -- the icon's own frame, placed on the row: the teleport button attaches
        -- to it, and the icon texture attaches to it - never the other way round
        -- (WoW checks the whole chain: a spell button can't hang off a texture,
        -- even through another frame)
        local hover = CreateFrame("Frame", nil, r)
        hover:SetSize(32, 32)
        hover:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.iconFrame = hover
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetAllPoints(hover)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(s)
            local hint = r.iconHint
            if type(hint) ~= "string" then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(hint, 1, 1, 1)
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.name = UI.Text(r, "GameFontHighlight", C.text, nil, "TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
        r.name:SetWidth(150); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.owner = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        r.toggle = UI.Button(r, 52, 22, "", "Leave this dungeon out of spins and votes", function()
            if r.mapID then db().excluded[r.mapID] = not db().excluded[r.mapID] or nil; V:Refresh() end
        end)
        r.toggle:SetPoint("RIGHT", -6, 0)
        r.vote = UI.Button(r, 52, 22, "Vote", nil, function() if r.voteIndex then KR:CastVote(r.voteIndex) end end)
        r.vote:SetPoint("RIGHT", r.toggle, "LEFT", -4, 0)
        r.count = UI.Text(r, "GameFontNormal", C.accent, nil, "RIGHT", r.vote, "LEFT", -6, 0)
        r:Hide()
        self.keyRows[i] = r
    end
    self.missingText = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", lx, -70 - 5 * 46)
    self.missingText:SetWidth(W - lx - 18)
    self.missingText:SetJustifyH("LEFT")

    -- filters
    local fy = -52 - WHEEL - 26
    UI.Text(f, "GameFontHighlight", C.text, "Key levels", "TOPLEFT", 22, fy - 4)
    -- [-] [ 12 ] [+]: type a level (blank = any) or nudge with -/+
    local function setLevel(key, v)
        v = tonumber(v) or 0
        if v ~= 0 then v = math.max(2, math.min(30, math.floor(v))) end
        db()[key] = v
        local d = db()
        if d.min > 0 and d.max > 0 and d.min > d.max then d.min, d.max = d.max, d.min end
        V:Refresh()
    end
    local function stepper(x, key)
        local minus = UI.Button(f, 22, 22, "-", "One lower (0 = any)", function()
            local v = db()[key]; setLevel(key, v <= 2 and 0 or v - 1)
        end)
        minus:SetPoint("TOPLEFT", x, fy)
        local box = UI.EditBox(f, 44, 22, { center = true, max = 3, keys = false })
        box:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        local function commit() setLevel(key, (box:GetText() or ""):gsub("[^%d]", "")) end
        box:SetScript("OnEnterPressed", function(s) commit(); s:ClearFocus() end)
        box:SetScript("OnEditFocusLost", commit)
        box:SetScript("OnEditFocusGained", function(s) if db()[key] == 0 then s:SetText("") end s:HighlightText() end)
        box:SetScript("OnEscapePressed", function(s) s:ClearFocus(); V:Refresh() end)
        local plus = UI.Button(f, 22, 22, "+", "One higher", function()
            local v = db()[key]; setLevel(key, v == 0 and 2 or v + 1)
        end)
        plus:SetPoint("LEFT", box, "RIGHT", 4, 0)
        return box
    end
    self.minText = stepper(110, "min")
    UI.Text(f, "GameFontHighlightSmall", C.muted, "to", "TOPLEFT", 214, fy - 5)
    self.maxText = stepper(236, "max")
    UI.Text(f, "GameFontHighlight", C.text, "Chances", "TOPLEFT", 360, fy - 4)
    self.weightBtn = UI.Button(f, 150, 22, "", "Equal chances for every key, or favor higher keys", function()
        db().weight = (db().weight == "equal") and "higher" or "equal"; V:Refresh()
    end)
    self.weightBtn:SetPoint("TOPLEFT", 430, fy)

    -- actions
    local ay = fy - 40
    self.spinBtn = UI.Button(f, 160, 34, "Spin the wheel", nil, function() V:Spin() end)
    self.spinBtn:SetPoint("TOPLEFT", 22, ay)
    UI.SetActive(self.spinBtn, true)
    self.voteBtn = UI.Button(f, 140, 34, "Vote (" .. VOTE_SECONDS .. "s)", "Everyone picks: Titan Up users click Vote, anyone can type the number or short name in party chat", function()
        local ok, err = KR:StartVote(KR:Eligible((KR:Collect())))
        if not ok then V.flash = err end
        V:Refresh()
    end)
    self.voteBtn:SetPoint("LEFT", self.spinBtn, "RIGHT", 10, 0)
    self.status = UI.Text(f, "GameFontHighlight", C.text, nil, "LEFT", self.voteBtn, "RIGHT", 14, 0)
    self.status:SetWidth(W - 360)
    self.status:SetJustifyH("LEFT")

    -- history
    local hy = ay - 52
    UI.Text(f, "GameFontNormalSmall", C.accent, "RECENT PICKS", "TOPLEFT", 22, hy)
    self.histRows = {}
    for i = 1, 10 do
        local t = UI.Text(f, "GameFontHighlightSmall", nil, nil, "TOPLEFT", 22 + ((i - 1) % 2) * 285, hy - 18 - math.floor((i - 1) / 2) * 16)
        t:SetWidth(280); t:SetJustifyH("LEFT"); t:SetWordWrap(false)
        self.histRows[i] = t
    end
    f:SetScript("OnUpdate", function(_, elapsed) V:OnUpdate(elapsed) end)
end

-- Wheel: texture for n slices; labels ride along at each slice's middle.
function V:DrawWheel(list)
    local n = math.max(1, math.min(5, #list))
    self.wheel:SetTexture(ns.MEDIA .. "Roulette" .. n)
    if self.wheel.SetRotation then self.wheel:SetRotation(self.angle) end
    for i, t in ipairs(self.sliceLabels) do
        local k = list[i]
        if k and i <= 5 then
            local a = (i - 0.5) * (2 * math.pi / n) - self.angle
            local r = WHEEL * 0.31
            t:ClearAllPoints()
            t:SetPoint("CENTER", self.wheelBox, "CENTER", r * math.sin(a), r * math.cos(a))
            t:SetText(("%s\n+%d"):format(KR.Abbrev(k.mapID), k.level))
            t:Show()
        else
            t:Hide()
        end
    end
end

function V:Spin()
    if self.spinning then return end
    local list = KR:Eligible((KR:Collect()))
    if #list == 0 then self.flash = "No eligible keys - check the level range and left-out dungeons."; self:Refresh() return end
    self:SpinTo(list, KR:Pick(list), "spin")
end

-- Animate to slice `target` of `list`, then announce it.
function V:SpinTo(list, target, how)
    self:EnsureFrame()
    local n = math.max(1, math.min(5, #list))
    local step = 2 * math.pi / n
    local goal = (target - 0.5) * step + (math.random() - 0.5) * step * 0.6     -- land somewhere inside the slice
    local start = self.angle % (2 * math.pi)
    local delta = (goal - start) % (2 * math.pi) + 2 * math.pi * 5
    self.spinning = { list = list, target = target, how = how, from = start, delta = delta, t0 = GetTime(), lastSlice = -1 }
    self.angle = start
    self.flash = nil
    self:Refresh()
end

function V:OnUpdate()
    local s = self.spinning
    if s then
        local p = math.min(1, (GetTime() - s.t0) / SPIN_SECONDS)
        local eased = 1 - (1 - p) ^ 3
        self.angle = s.from + s.delta * eased
        local n = math.max(1, math.min(5, #s.list))
        local slice = math.floor((self.angle % (2 * math.pi)) / (2 * math.pi / n))
        if slice ~= s.lastSlice then
            s.lastSlice = slice
            if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
        end
        self:DrawWheel(s.list)
        if p >= 1 then
            self.spinning = nil
            self.landed = s.list[s.target]
            KR:Announce(s.list[s.target], s.how)
        end
    elseif KR.vote then
        local left = KR.vote.endsAt - GetTime()
        if math.floor(left) ~= self.lastSecond then self.lastSecond = math.floor(left); self:Refresh() end
    end
end

-- Each key's icon is a teleport button for that dungeon. Spell buttons can
-- only be set up out of combat, and a window holding them couldn't open or
-- close in combat, so they sit over the icons (parented to the screen),
-- hide when combat starts and come back when it ends.
function V:SetupIconTeleports()
    if not self.frame then return end
    self.iconTP = self.iconTP or {}
    if InCombatLockdown() then self:HideIconTeleports(); return end
    for i, r in ipairs(self.keyRows) do
        local b = self.iconTP[i]
        local mapID = r:IsShown() and self.rowMap and self.rowMap[i]
        local spellID, known
        if mapID then spellID, known = KR.Teleport(mapID) end
        r.icon:SetDesaturated(mapID ~= nil and not known)
        r.icon:SetAlpha((mapID and not known) and 0.55 or 1)
        if mapID and spellID and known and self.frame:IsShown() then
            if not b then
                b = CreateFrame("Button", "TitanUpKeyTP" .. i, UIParent, "SecureActionButtonTemplate")
                b:RegisterForClicks("AnyUp", "AnyDown")
                b:SetFrameStrata("DIALOG")
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.18)
                b:SetScript("OnEnter", function(s)
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Teleport to " .. (s.dungeon or "the dungeon"), 1, 1, 1)
                    local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(s.spellID)
                    local start, dur = cd and ns.Safe.Num(cd.startTime), cd and ns.Safe.Num(cd.duration)
                    local left = (start and dur and dur > 1.5) and (start + dur - GetTime()) or 0
                    GameTooltip:AddLine(left > 0 and ("On cooldown %d:%02d"):format(math.floor(left / 60), math.floor(left % 60)) or "Click to teleport", 0.8, 0.82, 0.86)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.iconTP[i] = b
            end
            b.spellID, b.dungeon = spellID, (KR.MapInfo(mapID))
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", spellID)
            b:ClearAllPoints()
            b:SetAllPoints(r.iconFrame)
            -- the cooldown sweep lives on the plain icon frame, never on the
            -- protected spell button (12.1.5: addons can't set cooldowns on
            -- protected cooldown frames)
            self.rowCD = self.rowCD or {}
            local sweep = self.rowCD[i]
            if not sweep then
                sweep = CreateFrame("Cooldown", nil, r.iconFrame, "CooldownFrameTemplate")
                sweep:SetAllPoints()
                self.rowCD[i] = sweep
            end
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
            local start, dur = cd and ns.Safe.Num(cd.startTime), cd and ns.Safe.Num(cd.duration)
            if start and dur and dur > 1.5 then sweep:SetCooldown(start, dur) else sweep:Clear() end
            b:Show()
        elseif b then
            b:Hide()
            if self.rowCD and self.rowCD[i] then self.rowCD[i]:Clear() end      -- no teleport on this row now: no sweep either
        end
        -- a plain tooltip for icons that can't teleport
        r.iconHint = mapID and (not spellID and "No teleport for this dungeon" or (not known and "Teleport not unlocked yet")) or nil
    end
end

function V:HideIconTeleports(combatStarting)
    for _, b in pairs(self.iconTP or {}) do
        if combatStarting or not InCombatLockdown() then b:Hide() end
    end
end

function V:Refresh()
    if not self.frame then return end
    local keys, missing = KR:Collect()
    local d = db()
    local vote = KR.vote
    local shown = vote and vote.keys or keys
    local eligible = KR:Eligible(keys)
    local counts = KR:Tally()
    -- key list
    for i, r in ipairs(self.keyRows) do
        local k = shown[i]
        if k then
            local name, icon = KR.MapInfo(k.mapID)
            r.mapID = k.mapID
            self.rowMap = self.rowMap or {}
            self.rowMap[i] = k.mapID
            r.icon:SetTexture(icon)
            r.name:SetText(("%s  |cffffd94d+%d|r"):format(name, k.level))
            r.owner:SetText(UI.ClassName(k.short or short(k.owner), k.class) .. (k.source and ("  |cff8a8f9c" .. k.source .. "|r") or ""))
            local out = d.excluded[k.mapID]
            r.toggle.label:SetText(out and "Out" or "In")
            UI.SetActive(r.toggle, not out)
            r.toggle:SetShown(not vote)
            r.voteIndex = vote and i or nil
            r.vote:SetShown(vote ~= nil)
            UI.SetActive(r.vote, vote and vote.votes[ns.me] == i)
            r.count:SetText(vote and (counts[i] and tostring(counts[i]) or "0") or "")
            r:SetAlpha((vote or not out) and 1 or 0.5)
            r:Show()
        else
            if self.rowMap then self.rowMap[i] = nil end
            r:Hide()
        end
    end
    local names = {}
    for _, m in ipairs(missing) do names[#names + 1] = m.short end
    self.missingText:SetText(#names > 0 and ("No key info: " .. table.concat(names, ", ") .. "\n(they need Titan Up, BigWigs or Details)") or (#keys == 0 and "No keys found in your group yet." or ""))
    -- wheel
    if not self.spinning then
        local list = vote and vote.keys or eligible
        self.wheelEmpty:SetText(#list == 0 and "No eligible keys" or "")
        if #list > 0 then self:DrawWheel(list) else self.wheel:SetTexture(ns.MEDIA .. "Roulette1"); for _, t in ipairs(self.sliceLabels) do t:Hide() end end
    end
    -- filters
    if not self.minText:HasFocus() then self.minText:SetText(d.min == 0 and "any" or tostring(d.min)) end
    if not self.maxText:HasFocus() then self.maxText:SetText(d.max == 0 and "any" or tostring(d.max)) end
    self.weightBtn.label:SetText(d.weight == "higher" and "Favor higher keys" or "Equal chances")
    UI.SetDisabled(self.spinBtn, self.spinning ~= nil or vote ~= nil)
    UI.SetDisabled(self.voteBtn, self.spinning ~= nil or vote ~= nil or #eligible < 2)
    -- status
    local st
    if self.flash then st = "|cffffa340" .. self.flash .. "|r"
    elseif vote then st = ("Voting... %ds left%s"):format(math.max(0, math.ceil(vote.endsAt - GetTime())), vote.host ~= ns.me and ("  (started by " .. short(vote.host) .. ")") or "")
    elseif self.spinning then st = "Spinning..."
    elseif self.landed then st = ("|cff66e08c%s +%d|r it is!"):format(KR.MapInfo(self.landed.mapID), self.landed.level)
    else st = ("%d of %d keys eligible"):format(#eligible, #keys) end
    self.status:SetText(st)
    self:SetupIconTeleports()
    -- history
    for i, t in ipairs(self.histRows) do
        local h = d.history[i]
        t:SetText(h and ("|cff8a8f9c%s|r  %s +%d  |cff8a8f9c%s%s|r"):format(date("%a %H:%M", h.t), KR.MapInfo(h.mapID), h.level, short(h.owner) or "", h.how == "vote" and " (vote)" or "") or ((i == 1) and "|cff8a8f9cNothing picked yet.|r" or ""))
    end
end

ns.RegisterModule({
    key = "keys", name = "Keystone Roulette", icon = ns.MEDIA .. "Keys", group = "uitweaks", order = 2,
    desc = "Spin a wheel of your group's keys - or vote - and teleport straight there.",
    view = V,
})
