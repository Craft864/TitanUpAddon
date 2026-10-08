-- Titan Up - Tweaks/DeathAlerts.lua
-- Death Alerts (a UI Tweak): when someone in your group dies, a banner
-- slides in - role icon, class-colored name, and the fight time from the
-- Combat Timer ("Brakk  2:31"). Up to three stack, newest on top.
--   * Tanks and healers get a bigger line and their own sound; your own
--     death has its own sound too.
--   * Wipes: after several deaths in a few seconds the single alerts
--     collapse into one "Wipe likely - 6 dead" banner and one sound, and
--     stay quiet until combat ends.
--   * Sounds: WoW's built-in alerts, plus every sound registered with
--     LibSharedMedia (BigWigs, DBM, sound packs...), each with a preview.
-- Uses Midnight's UNIT_DIED event (no combat log). Nothing is built until
-- the first alert, the test button, or the settings page.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local DA = {}
ns.DeathAlerts = DA

local MAX_ROWS = 3
local WIPE_WINDOW = 8                   -- seconds
local SIZES = { small = 16, medium = 22, large = 30 }
DA.WHERE = { { "instances", "Raids & dungeons" }, { "raids", "Raids only" }, { "everywhere", "Everywhere" } }
DA.DURATIONS = { 3, 4, 6, 8 }
DA.CHANNELS = { "Master", "SFX", "Dialog", "Ambience" }

-- WoW's own alert sounds (sound kits, always present) ...
local KITS = {
    { "WoW: Raid Warning", "RAID_WARNING" },
    { "WoW: Ready Check", "READY_CHECK" },
    { "WoW: Alarm Clock", "ALARM_CLOCK_WARNING_3" },
    { "WoW: Boss Emote", "RAID_BOSS_EMOTE_WARNING" },
    { "WoW: Invite", "IG_PLAYER_INVITE" },
}
-- ... and three game sound files (the extras DeathTracer adds)
if LSM then
    LSM:Register("sound", "WoW: Quest Failed", 567459)
    LSM:Register("sound", "WoW: Create Character", 567522)
    LSM:Register("sound", "WoW: Angered Wisp", 567285)
end

local function db() return ns.udb.deathAlerts end

function DA:Init()
    ns.On("UNIT_DIED", function(guid) DA:OnUnitDied(guid) end)
    ns.On("PLAYER_REGEN_DISABLED", function() DA:OnCombatStart() end)
    ns.On("ENCOUNTER_START", function() DA:OnCombatStart(true) end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        -- dying in a raid boss fight takes you out of combat, but the pull
        -- goes on: there the boss fight's end closes it
        if ns.InRaidInstance() and ns.Safe.Call(IsEncounterInProgress) then return end
        DA:OnCombatEnd()
    end)
    ns.On("ENCOUNTER_END", function() DA:OnCombatEnd() end)
end

-- ---------------------------------------------------------------------
-- Sounds
-- ---------------------------------------------------------------------
function DA.SoundList()
    local list, seen = { "None" }, { None = true }
    for _, k in ipairs(KITS) do
        if SOUNDKIT and SOUNDKIT[k[2]] then list[#list + 1] = k[1]; seen[k[1]] = true end
    end
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            if not seen[name] then list[#list + 1] = name; seen[name] = true end
        end
    end
    return list
end

function DA.Play(name)
    if not name or name == "None" then return end
    local channel = db().channel or "Master"
    for _, k in ipairs(KITS) do
        if k[1] == name then
            if SOUNDKIT and SOUNDKIT[k[2]] then PlaySound(SOUNDKIT[k[2]], channel) end
            return
        end
    end
    local file = LSM and LSM:Fetch("sound", name, true)
    if file and file ~= 1 then PlaySoundFile(file, channel) end
end

-- ---------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------
local function whereOK()
    local w = db().where
    if w == "everywhere" then return true end
    local inInstance, kind = IsInInstance()
    if w == "raids" then return inInstance and kind == "raid" end
    return inInstance and (kind == "raid" or kind == "party")
end

function DA:OnUnitDied(guid)
    if not db().enabled or not whereOK() then return end
    -- a real death of someone in the group (Feign Death filtered out)
    ns.PullReport.GroupDeath(guid, function(unit, full, class, isMe)
        local role = ns.Safe.Text(UnitGroupRolesAssigned(unit)) or "NONE"
        local inInstance, kind = IsInInstance()
        if db().tankHealOnly and inInstance and kind == "raid" and not isMe and role ~= "TANK" and role ~= "HEALER" then return end
        DA:Add({ name = ns.Short(full), role = role, class = class, me = isMe })
    end)
end

-- fight time from the Combat Timer, if it's running
local function fightTime()
    local T = ns.Timer
    if T and T.startAt then return GetTime() - T.startAt end
end

function DA:OnCombatStart(force)
    if force or not self.inPull then
        self.inPull, self.log, self.recent, self.wiping = true, {}, {}, false
    end
end

function DA:OnCombatEnd()
    if self.log and #self.log > 0 then db().lastPull = self.log end
    self.inPull, self.wiping = false, false
    if self.wipeRow then self.wipeRow.hideAt = GetTime() + 1.5 end
end

function DA:Add(e)
    e.at = GetTime()
    e.ft = fightTime()
    self.log = self.log or {}
    table.insert(self.log, { name = e.name, role = e.role, class = e.class, ft = e.ft })
    if not self.inPull then db().lastPull = self.log end
    -- recent deaths for wipe detection
    self.recent = self.recent or {}
    table.insert(self.recent, e.at)
    while self.recent[1] and e.at - self.recent[1] > WIPE_WINDOW do table.remove(self.recent, 1) end
    local threshold = IsInRaid() and 4 or 3
    if db().collapse and (self.wiping or #self.recent >= threshold) then
        local first = not self.wiping
        self.wiping = true
        self.wipeCount = first and #self.recent or (self.wipeCount or 0) + 1
        self:ShowWipe(first)
        return
    end
    if db().chat then ns.Print(("%s died%s."):format(UI.ClassName(e.name, e.class), e.ft and (" at " .. DA.Clock(e.ft)) or "")) end
    self:ShowAlert(e)
    if e.me and db().selfSoundOn then DA.Play(db().selfSound)
    elseif db().roleSounds and e.role == "TANK" then DA.Play(db().tankSound)
    elseif db().roleSounds and e.role == "HEALER" then DA.Play(db().healerSound)
    else DA.Play(db().sound) end
end

DA.Clock = UI.Clock

-- ---------------------------------------------------------------------
-- Banner
-- ---------------------------------------------------------------------
local ROLE_ATLAS = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal", DAMAGER = "groupfinder-icon-role-large-dps" }

function DA:EnsureBanner()
    if self.banner then return self.banner end
    local f = CreateFrame("Frame", "TitanUpDeathAlerts", UIParent, "BackdropTemplate")
    f:SetSize(360, 40)
    f:SetFrameStrata("HIGH")
    UI.Draggable(f, db, { "TOP", "TOP", 0, -220 }, "Drag to move - click the anchor again to lock", nil, function() return DA.unlocked end)
    f.rows = {}
    for i = 1, MAX_ROWS + 1 do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(360, 34)
        -- no background: just the role icon and outlined text, centered
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetPoint("LEFT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetShadowOffset(1, -1)
        r.time = r:CreateFontString(nil, "OVERLAY")
        r.time:SetPoint("LEFT", r.text, "RIGHT", 10, 0)
        r.time:SetShadowOffset(1, -1)
        r:Hide()
        f.rows[i] = r
    end
    f:SetScript("OnUpdate", function() DA:Animate() end)
    self.banner = f
    f:Place()
    return f
end

function DA:ResetPosition() self:EnsureBanner():ResetPlace() end

local function styleRow(r, e)
    local base = SIZES[db().size] or 22
    local big = (e.role == "TANK" or e.role == "HEALER" or e.me)
    local fs = big and base + 4 or base
    r:SetHeight(fs + 16)
    r.text:SetFont(STANDARD_TEXT_FONT, fs, "OUTLINE")
    r.time:SetFont(STANDARD_TEXT_FONT, math.max(11, fs - 8), "OUTLINE")
    r.icon:SetSize(fs + 4, fs + 4)
    if e.wipe then
        r.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        r.text:SetText(("|cffff5a5aWipe likely|r - %d dead"):format(e.count))
        r.time:SetText("")
        return
    end
    if e.role and ROLE_ATLAS[e.role] then r.icon:SetAtlas(ROLE_ATLAS[e.role], false) else r.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") end
    local name = UI.ClassName(e.name, e.class)
    r.text:SetText(e.me and (name .. "  |cffff5a5a(you)|r") or name)
    r.time:SetText(e.ft and ("|cffbbbbbb" .. DA.Clock(e.ft) .. "|r") or "")
end

-- each row is as wide as what it shows (icon + name + time), so rows centre
local function fitRow(r)
    local function w(fs) local x = fs:GetStringWidth() return type(x) == "number" and x or 0 end
    local tw = w(r.time)
    r:SetWidth(math.min(520, (r.icon:GetWidth() or 0) + 8 + w(r.text) + (tw > 0 and (10 + tw) or 0)))
end

function DA:ShowAlert(e)
    local f = self:EnsureBanner()
    self.active = self.active or {}
    e.shownAt, e.hideAt = GetTime(), GetTime() + (db().duration or 4)
    table.insert(self.active, 1, e)
    while #self.active > MAX_ROWS do table.remove(self.active) end
    self:Layout()
    f:Show()
end

function DA:ShowWipe(first)
    local f = self:EnsureBanner()
    self.active = { { wipe = true, count = self.wipeCount, shownAt = GetTime(), hideAt = GetTime() + 30 } }
    self.wipeRow = self.active[1]
    if first then DA.Play(db().sound) end
    self:Layout()
    f:Show()
end

function DA:Layout()
    local f = self.banner
    local y = 0
    self.rowEntry = {}
    for i, r in ipairs(f.rows) do
        local e = self.active[i]
        if e then
            styleRow(r, e)
            fitRow(r)
            r:ClearAllPoints()
            r:SetPoint("TOP", f, "TOP", 0, -y)
            y = y + r:GetHeight() + 4
            self.rowEntry[i] = e
            r:Show()
        else
            r:Hide()
        end
    end
end

-- slide in, then fade out; the OnUpdate stops when nothing is showing
function DA:Animate()
    local f = self.banner
    if not f then return end
    local now, any = GetTime(), false
    for i, r in ipairs(f.rows) do
        local e = self.rowEntry and self.rowEntry[i]
        if e then
            local age = now - e.shownAt
            local slide = math.min(1, age / 0.18)
            r:SetAlpha(math.min(slide, math.max(0, (e.hideAt - now) / 0.6)))
            if r.slidIn ~= e then                                   -- (once in place, it stays put)
                r.text:SetPoint("LEFT", r.icon, "RIGHT", 8 + (1 - slide) * 30, 0)
                if slide >= 1 then r.slidIn = e end
            end
            if now < e.hideAt then any = true end
        end
    end
    if self.active then
        for i = #self.active, 1, -1 do if now >= self.active[i].hideAt then table.remove(self.active, i) end end
    end
    if not any and not self.unlocked then
        self.active = {}
        if self.wiping and not self.inPull then self.wiping = false end
        f:Hide()
    end
end

function DA:SetUnlocked(on)
    self.unlocked = on and true or false
    local f = self:EnsureBanner()
    f:EnableMouse(self.unlocked)
    f.hint:SetShown(self.unlocked)
    if self.unlocked then
        self.active = { { name = "Brakk", role = "TANK", class = "WARRIOR", ft = 151, shownAt = GetTime() - 1, hideAt = GetTime() + 3600 } }
        self:Layout()
        f:Show()
    else
        self.active = {}
        self:Layout()
    end
end

-- Test: one of each kind, then the wipe banner
function DA:Test()
    local samples = {
        { name = "Brakk", role = "TANK", class = "WARRIOR", ft = 151 },
        { name = "Kev", role = "HEALER", class = "PRIEST", ft = 154 },
        { name = "Mossy", role = "DAMAGER", class = "MAGE", ft = 158 },
    }
    for i, s in ipairs(samples) do
        C_Timer.After((i - 1) * 0.7, function()
            DA:ShowAlert(s)
            DA.Play(s.role == "TANK" and db().roleSounds and db().tankSound or s.role == "HEALER" and db().roleSounds and db().healerSound or db().sound)
        end)
    end
    if db().collapse then
        C_Timer.After(3.2, function() DA.wipeCount = 6; DA:ShowWipe(true); DA.active[1].hideAt = GetTime() + 3 end)
    end
end

-- ---------------------------------------------------------------------
-- Sound picker: a scrollable list with a preview button on each row
-- ---------------------------------------------------------------------
local PICK_ROWS = 12
function DA:PickSound(anchor, current, onPick)
    local p = self.picker
    if not p then
        p = CreateFrame("Frame", "TitanUpSoundPicker", UIParent, "BackdropTemplate")
        UI.Skin(p, C.panel, C.accent)
        p:SetSize(260, PICK_ROWS * 22 + 10)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:EnableMouse(true)
        p:EnableMouseWheel(true)
        p:SetScript("OnMouseWheel", function(_, delta) DA.pickOffset = math.max(0, math.min((DA.pickOffset or 0) - delta * 3, #DA.pickList - PICK_ROWS)); DA:RefreshPicker() end)
        p.rows = {}
        for i = 1, PICK_ROWS do
            local r = CreateFrame("Button", nil, p)
            r:SetHeight(22)
            r:SetPoint("TOPLEFT", 4, -5 - (i - 1) * 22)
            r:SetPoint("RIGHT", -30, 0)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -4, 0); r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
            r:SetScript("OnClick", function(s) p:Hide(); if DA.pickCallback then DA.pickCallback(s.sound) end end)
            r.play = UI.Button(p, 22, 20, ">", "Preview", function() DA.Play(r.sound) end)
            r.play:SetPoint("LEFT", r, "RIGHT", 2, 0)
            p.rows[i] = r
        end
        p:SetScript("OnHide", function() if DA.pickBlocker then DA.pickBlocker:Hide() end end)
        local blocker = CreateFrame("Button", nil, UIParent)
        blocker:SetAllPoints(UIParent)
        blocker:SetFrameStrata("FULLSCREEN")
        blocker:SetScript("OnClick", function() p:Hide() end)
        blocker:Hide()
        self.pickBlocker = blocker
        self.picker = p
    end
    self.pickList = DA.SoundList()
    self.pickCurrent, self.pickCallback = current, onPick
    local idx = 1
    for i, n in ipairs(self.pickList) do if n == current then idx = i end end
    self.pickOffset = math.max(0, math.min(idx - 3, #self.pickList - PICK_ROWS))
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    self:RefreshPicker()
    self.pickBlocker:Show()
    p:Show()
end

function DA:RefreshPicker()
    local p = self.picker
    for i, r in ipairs(p.rows) do
        local name = self.pickList[(self.pickOffset or 0) + i]
        r.sound = name
        r:SetShown(name ~= nil)
        r.play:SetShown(name ~= nil and name ~= "None")
        if name then
            local c = (name == self.pickCurrent) and C.accent or C.text
            r.text:SetText(name)
            r.text:SetTextColor(c[1], c[2], c[3])
        end
    end
end

-- ---------------------------------------------------------------------
-- Settings page (shown inside the UI Tweaks window)
-- ---------------------------------------------------------------------
function DA:BuildPage(parent)
    local pg = CreateFrame("Frame", nil, parent)
    pg:SetAllPoints()
    self.page = pg
    local d = db
    local RIGHT = -18
    local y = -8
    local function label(text, yy)
        local t = UI.Text(pg, "GameFontHighlight", C.text, text, "TOPLEFT", 18, yy - 5)
        return t
    end
    local function cycleRow(text, getLabel, onClick, tip)
        label(text, y)
        local b = UI.Button(pg, 170, 24, "", tip, function() onClick(); DA:RefreshPage() end)
        b:SetPoint("TOPRIGHT", RIGHT, y)
        b.kind, b.getLabel = "cycle", getLabel
        y = y - 32
        return b
    end
    local function toggleRow(text, key, tip)
        local b = cycleRow(text, nil, function() d()[key] = not d()[key] end, tip)
        b.kind, b.toggleKey = "toggle", key
        return b
    end
    local function soundRow(text, key)
        label(text, y)
        local play = UI.Button(pg, 24, 24, ">", "Preview", function() DA.Play(d()[key]) end)
        play:SetPoint("TOPRIGHT", RIGHT, y)
        local b = UI.Button(pg, 170, 24, "", "Choose a sound", nil)
        b:SetPoint("RIGHT", play, "LEFT", -4, 0)
        b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 8, 0); b.label:SetPoint("RIGHT", -20, 0); b.label:SetJustifyH("LEFT")
        local caret = b:CreateTexture(nil, "OVERLAY"); caret:SetTexture(ns.MEDIA .. "Down"); caret:SetSize(10, 10); caret:SetPoint("RIGHT", -6, 0)
        b:SetScript("OnClick", function() DA:PickSound(b, d()[key], function(name) d()[key] = name; DA:RefreshPage() end) end)
        b.kind, b.soundKey = "sound", key
        y = y - 32
        return b
    end
    self.ctl = {}
    local function cycle(list, cur, key)
        local i = 1
        for k, v in ipairs(list) do if (type(v) == "table" and v[1] or v) == cur then i = k end end
        local nxt = list[(i % #list) + 1]
        d()[key] = type(nxt) == "table" and nxt[1] or nxt
    end
    self.ctl.where = cycleRow("Show alerts in", function() for _, w in ipairs(DA.WHERE) do if w[1] == d().where then return w[2] end end end,
        function() cycle(DA.WHERE, d().where, "where") end)
    self.ctl.tankHeal = toggleRow("Raids: only tanks & healers", "tankHealOnly", "In raid instances, skip alerts for damage dealers (your own death still shows)")
    self.ctl.collapse = toggleRow("Collapse wipes into one banner", "collapse", "Several deaths in a few seconds become one \"Wipe likely\" banner and one sound")
    self.ctl.chat = toggleRow("Also print to my chat", "chat", "A line in your own chat window - never sent to the group")
    self.ctl.size = cycleRow("Banner size", function() return (d().size:gsub("^%l", string.upper)) end,
        function() cycle({ "small", "medium", "large" }, d().size, "size") end)
    self.ctl.duration = cycleRow("Show each alert for", function() return d().duration .. " seconds" end,
        function() cycle(DA.DURATIONS, d().duration, "duration") end)
    y = y - 6
    self.ctl.sound = soundRow("Death sound", "sound")
    self.ctl.roleSounds = toggleRow("Different sounds for tanks & healers", "roleSounds")
    self.ctl.tankSound = soundRow("    Tank died", "tankSound")
    self.ctl.healerSound = soundRow("    Healer died", "healerSound")
    self.ctl.selfOn = toggleRow("A different sound when I die", "selfSoundOn")
    self.ctl.selfSound = soundRow("    I died", "selfSound")
    self.ctl.channel = cycleRow("Sound channel", function() return d().channel end, function() cycle(DA.CHANNELS, d().channel, "channel") end)
    -- bottom: test / move / reset, and the last pull's deaths
    local test = UI.Button(pg, 90, 24, "Test", "Show sample alerts (and the wipe banner)", function() DA:Test() end)
    test:SetPoint("TOPLEFT", 18, y - 6)
    local reset
    self.anchorBtn, reset = ns.Tweaks.MoveControls(pg, DA, { after = function() DA:RefreshPage() end,
        tip = "Move the alerts: click to unlock and drag, click again to lock" })
    self.anchorBtn:SetPoint("LEFT", test, "RIGHT", 8, 0)
    reset:SetPoint("LEFT", self.anchorBtn, "RIGHT", 8, 0)
    y = y - 42
    UI.Text(pg, "GameFontNormalSmall", C.accent, "LAST PULL'S DEATHS", "TOPLEFT", 18, y)
    self.logRows = {}
    for i = 1, 8 do
        local t = UI.Text(pg, "GameFontHighlightSmall", nil, nil, "TOPLEFT", 18 + ((i - 1) % 2) * 210, y - 18 - math.floor((i - 1) / 2) * 16)
        t:SetWidth(200); t:SetJustifyH("LEFT")
        self.logRows[i] = t
    end
    self.pageHeight = -(y - 18 - 4 * 16) + 16
    return pg
end

function DA:RefreshPage()
    if not self.page then return end
    local d = db()
    for _, b in pairs(self.ctl) do
        if b.kind == "toggle" then
            local on = d[b.toggleKey]
            b.label:SetText(on and "|cff66e08cOn|r" or "Off")
            UI.SetActive(b, on)
        elseif b.kind == "sound" then
            b.label:SetText(d[b.soundKey] or "None")
        elseif b.kind == "cycle" then
            b.label:SetText(b.getLabel() or "")
        end
    end
    UI.SetDisabled(self.ctl.tankSound, not d.roleSounds)
    UI.SetDisabled(self.ctl.healerSound, not d.roleSounds)
    UI.SetDisabled(self.ctl.selfSound, not d.selfSoundOn)
    UI.SetActive(self.anchorBtn, self.unlocked)
    local log = (self.inPull and self.log and #self.log > 0) and self.log or d.lastPull or {}
    for i, t in ipairs(self.logRows) do
        local e = log[i]
        if e then
            t:SetText(("%s  %s"):format(e.ft and ("|cff8a8f9c" .. DA.Clock(e.ft) .. "|r") or "|cff8a8f9c--:--|r", UI.ClassName(e.name, e.class)))
        else
            t:SetText((i == 1) and "|cff8a8f9cNo deaths recorded yet.|r" or "")
        end
    end
end
