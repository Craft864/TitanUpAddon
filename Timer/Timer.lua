-- Titan Up - Timer/Timer.lua
-- Combat Timer: an on-screen timer you can place anywhere and style.
--   * When it runs (automatic, not an option): inside a raid instance it
--     times boss encounters (pull to kill/wipe - trash doesn't start it and
--     dying mid-fight doesn't stop it); everywhere else, any combat.
--   * Optional: only show inside dungeons and raids; a chat line with the
--     fight's length afterwards (on by default) - only for the kinds of
--     fight picked (raid bosses by default) and only if the fight lasted
--     the minimum length (30s by default). The timer itself runs as before.
--   * Font, size, color, outline, tenths of a second.
--   * After combat it keeps the final time for 5s / 15s / 60s / always.
--   * "Move" unlocks it to drag; the settings window shows a live preview.
-- Nothing is built until it's needed, and it only ticks while running.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local T = {}
ns.Timer = T

T.FONTS = {
    { key = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", label = "Skurri", path = "Fonts\\SKURRI.TTF" },
}
T.COLORS = {
    { 1.00, 0.85, 0.30 }, { 1.00, 1.00, 1.00 }, { 0.31, 0.76, 0.97 },
    { 0.40, 0.88, 0.55 }, { 1.00, 0.35, 0.35 }, { 0.80, 0.55, 1.00 },
}
T.LINGER = { { 5, "5 seconds" }, { 15, "15 seconds" }, { 60, "1 minute" }, { -1, "Always" } }
-- the chat line: which fights, and the shortest one worth a line
T.WHERE = { { "raid", "Raid boss", "Raid boss fights" }, { "mplus", "Mythic+", "Mythic+ runs (any fight in the key)" },
            { "dungeon", "Dungeon", "Other dungeons (any fight)" }, { "world", "Other", "Everywhere else (open world, delves, ...)" } }
T.CHAT_MIN = { { 0, "Any length" }, { 10, "10 seconds" }, { 30, "30 seconds" }, { 60, "1 minute" }, { 120, "2 minutes" } }

local function db() return ns.udb.timer end

function T:Init()
    ns.On("PLAYER_REGEN_DISABLED", function() T:OnEvent("combat start") end)
    ns.On("PLAYER_REGEN_ENABLED", function() T:OnEvent("combat end") end)
    ns.On("ENCOUNTER_START", function(_, name) T:OnEvent("boss pull", not ns.IsSecret(name) and name or nil) end)
    ns.On("ENCOUNTER_END", function(_, _, _, _, success)
        -- remembered for the history (kill or wipe); success can be hidden in Midnight
        T.endedWithKill = (not ns.IsSecret(success)) and (success == 1 or success == true) or nil
        T.endedKnown = not ns.IsSecret(success) and success ~= nil
        T:OnEvent("boss end")
    end)
end

-- The automatic rules. Every decision is printed with /tu timer debug.
function T:OnEvent(what, label)
    local d = db()
    local raid = ns.InRaidInstance()
    local inInstance = IsInInstance()
    local decision
    if what == "combat start" or what == "boss pull" then
        local wanted = (what == "boss pull") == raid      -- raid: bosses only; elsewhere: any combat
        if not d.enabled then decision = "ignored (timer is off)"
        elseif not wanted then decision = raid and "ignored (in a raid only boss pulls count)" or "ignored (not in a raid: combat starts it)"
        elseif d.instanceOnly and not inInstance then decision = "ignored (only in dungeons & raids is on)"
        elseif self.startAt then decision = "ignored (already running)"
        else
            self:Start(label, what == "boss pull" and "boss" or "combat")
            decision = "started"
        end
    else
        local by = (what == "boss end") and "boss" or "combat"
        if self.startAt and self.startedBy == by then
            self:Stop()
            decision = "stopped at " .. self.Format(self.last or 0, true)
        else
            decision = self.startAt and "ignored (this fight is timed by its " .. self.startedBy .. " event)" or "ignored (not running)"
        end
    end
    if self.debug then
        ns.Print(("Timer debug: %s%s -> %s  (in raid: %s)"):format(what, label and (" [" .. label .. "]") or "", decision, raid and "yes" or "no"))
    end
end

-- ---------------------------------------------------------------------
-- Timing
-- ---------------------------------------------------------------------
function T.Format(sec, tenths)
    sec = math.max(0, sec or 0)
    local m = math.floor(sec / 60)
    local s = sec - m * 60
    if tenths then
        return ("%d:%04.1f"):format(m, math.floor(s * 10) / 10)
    end
    return ("%d:%02d"):format(m, math.floor(s))
end

-- what kind of fight this is, for the chat line
function T.Where(by)
    if by == "boss" and ns.InRaidInstance() then return "raid" end
    local inInstance, kind = IsInInstance()
    if inInstance and kind == "party" then
        local active = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
        local _, _, diffID = GetInstanceInfo()
        if active or diffID == 8 or (ns.Loot and ns.Loot.keyRun) then return "mplus" end
        return "dungeon"
    end
    return "world"
end

-- the "Combat lasted" line: on, this kind of fight picked, and long enough
function T:WantsChat(where, dur)
    local d = db()
    if not d.chatSummary or self.testing then return false end
    if not (d.chatWhere or {})[where or "world"] then return false end
    return (dur or 0) >= math.max(1, d.chatMin or 0)
end

function T:Start(label, by)
    if self.startAt then return end
    self.startAt = GetTime()
    self.startedBy = by or "combat"
    self.where = T.Where(self.startedBy)
    self.label = label
    self.hideAt = nil
    self:EnsureDisplay()
    self:Render()
    self.display:Show()
    self.display:SetScript("OnUpdate", function(_, dt)
        T._acc = (T._acc or 0) + dt
        if T._acc >= 0.1 then T._acc = 0; T:Render() end
    end)
end

function T:Stop()
    if not self.startAt then return end
    self.last = GetTime() - self.startAt
    self.lastLabel = self.label
    self.startAt = nil
    db().lastTime, db().lastLabel, db().lastAt = self.last, self.label, time()
    -- history: the last 10 real fights (tests excluded), newest first
    if not self.testing and self.last >= 1 then
        local entry = { t = time(), dur = self.last, label = self.label }
        if self.startedBy == "boss" and self.endedKnown then entry.result = self.endedWithKill and "kill" or "wipe" end
        local hist = db().history or {}
        table.insert(hist, 1, entry)
        while #hist > 10 do table.remove(hist) end
        db().history = hist
    end
    self.endedWithKill, self.endedKnown = nil, nil
    if self:WantsChat(self.where, self.last) then
        ns.Print(("Combat lasted |cffffd94d%s|r%s"):format(self.Format(self.last, db().tenths), self.label and (" (" .. self.label .. ")") or ""))
    end
    self:Render()
    local linger = db().linger
    if self.display then
        if linger and linger >= 0 then
            self.hideAt = GetTime() + linger
            self.display:SetScript("OnUpdate", function()
                if T.hideAt and GetTime() >= T.hideAt then T:HideIfIdle() end
            end)
        else
            self.display:SetScript("OnUpdate", nil)
        end
    end
    if ns.TimerUI then ns.TimerUI:Refresh() end
end

-- Hide unless it's running, unlocked for moving, or being previewed.
function T:HideIfIdle()
    if not self.display then return end
    if self.startAt or self.unlocked or self.preview then return end
    self.hideAt = nil
    self.display:SetScript("OnUpdate", nil)
    self.display:Hide()
end

-- ---------------------------------------------------------------------
-- The display
-- ---------------------------------------------------------------------
function T:EnsureDisplay()
    if self.display then return self.display end
    local f = CreateFrame("Frame", "TitanUpCombatTimer", UIParent, "BackdropTemplate")
    f:SetSize(120, 40)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(false)
    UI.Draggable(f, db, { "TOP", "TOP", 0, -140 }, "Drag to move", "GameFontNormalSmall")
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f:Hide()
    self.display = f
    f:Place()
    self:ApplyStyle()
    return f
end

function T:FontPath()
    for _, ft in ipairs(self.FONTS) do if ft.key == db().font then return ft.path end end
    return self.FONTS[1].path
end

function T:ApplyStyle()
    local f = self.display
    if not f then return end
    local d = db()
    f.text:SetFont(self:FontPath(), d.size, d.outline and "OUTLINE" or "")
    local c = self.COLORS[d.color] or self.COLORS[1]
    f.text:SetTextColor(c[1], c[2], c[3])
    f:SetSize(math.max(80, d.size * 4), d.size + 12)
    if self.unlocked then
        UI.Skin(f, { 0.05, 0.06, 0.09, 0.75 }, C.accent)
    else
        f:SetBackdrop(nil)
    end
    f.hint:SetShown(self.unlocked and true or false)
    self:Render()
end

function T:Render()
    local f = self.display
    if not f then return end
    local sec = self.startAt and (GetTime() - self.startAt) or (self.preview and not self.last and 83.4) or self.last or 0
    f.text:SetText(self.Format(sec, db().tenths))
    local label
    if self.startAt then label = self.label
    elseif self.preview and not db().enabled then label = "|cffff5a5aTimer is OFF|r"
    else label = self.lastLabel end
    f.label:SetText(label or "")
    -- while previewing a timer that's switched off, show it dimmed
    f:SetAlpha((self.preview and not db().enabled and not self.startAt) and 0.4 or 1)
end

-- /tu timer test: run it for 10 seconds, whatever the settings.
function T:Test()
    if self.startAt then ns.Print("The timer is already running.") return end
    self.testing = true
    self:Start("test", "test")
    ns.Print("Combat Timer test: running for 10 seconds.")
    C_Timer.After(10, function()
        if T.startedBy == "test" then T:Stop() end
        T.testing = nil
    end)
end

-- Move mode: unlocked, mouse-draggable, with a frame around it.
function T:SetUnlocked(on)
    self.unlocked = on and true or false
    local f = self:EnsureDisplay()
    f:EnableMouse(self.unlocked)
    self:ApplyStyle()
    if self.unlocked then f:Show() else self:HideIfIdle() end
end

-- While the settings window is open, show the timer so changes are visible.
function T:SetPreview(on)
    self.preview = on and true or false
    if self.preview then
        self:EnsureDisplay()
        self:ApplyStyle()
        self.display:Show()
    else
        if self.unlocked then self:SetUnlocked(false) end
        self:HideIfIdle()
    end
end

function T:ResetPosition() self:EnsureDisplay():ResetPlace() end

-- ---------------------------------------------------------------------
-- Settings window (the module's page)
-- ---------------------------------------------------------------------
local V = {}
ns.TimerUI = V
local W, H = 880, 570          -- the standard module size
local OPT_W = 430              -- the options column (recent fights to its right)
T.SIZE_MIN, T.SIZE_MAX = 10, 96

function T.SetSize(n)
    n = math.floor(tonumber(n) or 0)
    if n < T.SIZE_MIN then n = T.SIZE_MIN elseif n > T.SIZE_MAX then n = T.SIZE_MAX end
    ns.udb.timer.size = n
    T:ApplyStyle()
end

local function row(parent, y, label, tip)
    local t = UI.Text(parent, "GameFontHighlight", nil, label, "TOPLEFT", 18, y)
    ns.Search.Tag(V, label, tip, t, y, OPT_W - 20)
    return t
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpTimerSettings", "timer", "COMBAT TIMER", W, H, { mark = { 300, 0.05, -20 },
        onShow = function() T:SetPreview(true); V:Refresh() end })
    f:SetScript("OnHide", function() T:SetPreview(false) end)

    -- top line: the anchor (move the timer) next to the X; a small reset in
    -- the bottom-right corner
    local reset
    self.anchorBtn, reset = ns.Tweaks.MoveControls(f, T, { size = 22, resetH = 18, after = function() V:Refresh() end,
        tip = "Move the timer: click to unlock and drag it anywhere, click again to lock it in place",
        resetTip = "Put the timer back at the top of the screen" })
    self.anchorBtn:SetPoint("RIGHT", self.header.close, "LEFT", -6, 0)
    reset.label:SetFontObject("GameFontHighlightSmall")
    reset:SetPoint("BOTTOMRIGHT", -10, 10)
    self.resetBtn = reset
    local when = UI.Text(f, "GameFontHighlightSmall", C.muted, "Times boss fights in raids, and any combat everywhere else.", "TOPLEFT", 18, -12)
    when:SetPoint("RIGHT", self.anchorBtn, "LEFT", -10, 0)
    when:SetJustifyH("LEFT")

    -- left: the options; right: recent fights
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT")
    p:SetSize(OPT_W, H)
    local d = function() return ns.udb.timer end
    local RIGHT = -18
    local y = -40
    local function toggleRow(label, key, tip, after)
        row(p, y - 5, label, tip)
        local b = UI.Button(p, 160, 24, "", tip, function()
            d()[key] = not d()[key]
            if after then after() end
            V:Refresh()
        end)
        b:SetPoint("TOPRIGHT", RIGHT, y)
        y = y - 34
        return b
    end
    self.enabledBtn = toggleRow("Timer", "enabled", "Turn the combat timer on or off", function() T:ApplyStyle(); T:Render() end)

    -- Font: dropdown
    row(p, y - 5, "Font", "Choose the timer's font")
    self.fontBtn = UI.Button(p, 160, 24, "", "Choose a font", function() V:FontMenu() end)
    self.fontBtn:SetPoint("TOPRIGHT", RIGHT, y)
    self.fontBtn.label:ClearAllPoints()
    self.fontBtn.label:SetPoint("LEFT", 8, 0)
    UI.Caret(self.fontBtn, "RIGHT", -6, 0)
    y = y - 34

    -- Size:  [-] [ 30 v ] [+]
    row(p, y - 5, "Size", "How big the timer's numbers are")
    local plus = UI.Button(p, 24, 24, "+", "One size bigger", function() T.SetSize(d().size + 1); V:Refresh() end)
    plus:SetPoint("TOPRIGHT", RIGHT, y)
    local list = UI.Button(p, 22, 24, "", "Sizes in steps of 6", function() V:SizeMenu() end)
    list:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    UI.Caret(list, "CENTER")
    local box = UI.EditBox(p, 54, 24, { center = true, numeric = true, max = 3, keys = false })
    box:SetPoint("RIGHT", list, "LEFT", -2, 0)
    local function commit()
        T.SetSize(box:GetText())
        box:ClearFocus()
        V:Refresh()
    end
    box:SetScript("OnEnterPressed", commit)
    box:SetScript("OnEditFocusLost", function() T.SetSize(box:GetText()); V:Refresh() end)
    box:SetScript("OnEscapePressed", function() box:ClearFocus(); V:Refresh() end)
    local minus = UI.Button(p, 24, 24, "-", "One size smaller", function() T.SetSize(d().size - 1); V:Refresh() end)
    minus:SetPoint("RIGHT", box, "LEFT", -4, 0)
    self.sizeBox, self.sizePlus, self.sizeMinus, self.sizeList = box, plus, minus, list
    y = y - 34

    row(p, y - 5, "Color", "The timer's color")
    self.swatches = {}
    for i = #T.COLORS, 1, -1 do
        local c = T.COLORS[i]
        local b = UI.Button(p, 22, 22, "", nil, function() d().color = i; T:ApplyStyle(); V:Refresh() end)
        b:SetPoint("TOPRIGHT", RIGHT - (#T.COLORS - i) * 26, y - 1)
        local sw = b:CreateTexture(nil, "ARTWORK")
        sw:SetPoint("TOPLEFT", 4, -4)
        sw:SetPoint("BOTTOMRIGHT", -4, 4)
        sw:SetColorTexture(c[1], c[2], c[3], 1)
        self.swatches[i] = b
    end
    y = y - 34
    self.outlineBtn = toggleRow("Outline", "outline", nil, function() T:ApplyStyle() end)
    self.tenthsBtn = toggleRow("Tenths of a second", "tenths", nil, function() T:Render() end)
    row(p, y - 5, "After combat, keep showing", "How long the timer stays on screen after a fight ends")
    self.lingerBtn = UI.Button(p, 160, 24, "", nil, function()
        local i = 1
        for k, l in ipairs(T.LINGER) do if l[1] == d().linger then i = k end end
        d().linger = T.LINGER[(i % #T.LINGER) + 1][1]
        V:Refresh()
    end)
    self.lingerBtn:SetPoint("TOPRIGHT", RIGHT, y)
    y = y - 34
    self.chatBtn = toggleRow("Chat summary after combat", "chatSummary", "Print \"Combat lasted 3:42\" in your chat (only you see it) after a timed fight - pick which fights below")
    row(p, y - 5, "Summary for", "Which fights get a chat summary line")
    self.whereBtns = {}
    for i = #T.WHERE, 1, -1 do
        local w = T.WHERE[i]
        local b = UI.Button(p, 66, 24, w[2], w[3], function()
            d().chatWhere = d().chatWhere or {}
            d().chatWhere[w[1]] = not d().chatWhere[w[1]]
            V:Refresh()
        end)
        b:SetPoint("TOPRIGHT", RIGHT - (#T.WHERE - i) * 70, y)
        self.whereBtns[w[1]] = b
    end
    y = y - 34
    row(p, y - 5, "Minimum fight length", "Shorter fights get no chat line (the timer still runs and records them)")
    self.chatMinBtn = UI.Button(p, 160, 24, "", "Shorter fights get no chat line (the timer still runs and records them)", function()
        local i = 1
        for k, m in ipairs(T.CHAT_MIN) do if m[1] == d().chatMin then i = k end end
        d().chatMin = T.CHAT_MIN[(i % #T.CHAT_MIN) + 1][1]
        V:Refresh()
    end)
    self.chatMinBtn:SetPoint("TOPRIGHT", RIGHT, y)
    y = y - 34
    self.instanceBtn = toggleRow("Only in dungeons & raids", "instanceOnly", "Don't run the timer in the open world")

    -- recent fights (last 10, newest first), in the right-hand column
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", OPT_W, -40); sep:SetPoint("BOTTOMLEFT", OPT_W, 40); sep:SetWidth(1)
    local hx, hy = OPT_W + 20, -40
    UI.Text(f, "GameFontNormalSmall", C.accent, "RECENT FIGHTS", "TOPLEFT", hx, hy)
    self.historyRows = {}
    for i = 1, 10 do
        local r = {}
        local ry = hy - 24 - (i - 1) * 20
        r.dur = UI.Text(f, "GameFontHighlightSmall", nil, nil, "TOPLEFT", hx, ry); r.dur:SetWidth(60); r.dur:SetJustifyH("LEFT")
        r.label = UI.Text(f, "GameFontHighlightSmall", nil, nil, "TOPLEFT", hx + 64, ry); r.label:SetWidth(160); r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
        r.result = UI.Text(f, "GameFontHighlightSmall", nil, nil, "TOPLEFT", hx + 228, ry); r.result:SetWidth(50); r.result:SetJustifyH("LEFT")
        r.when = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", hx + 282, ry); r.when:SetWidth(W - hx - 282 - 16); r.when:SetJustifyH("RIGHT")
        self.historyRows[i] = r
    end
    self.lastText = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", hx, hy - 24)
end

function V:FontMenu()
    local items = {}
    for _, ft in ipairs(T.FONTS) do
        items[#items + 1] = { text = ft.label, checked = ns.udb.timer.font == ft.key, onClick = function()
            ns.udb.timer.font = ft.key
            T:ApplyStyle()
            V:Refresh()
        end }
    end
    UI.Menu(self.fontBtn, items)
end

function V:SizeMenu()
    local items = {}
    for n = 12, T.SIZE_MAX, 6 do
        items[#items + 1] = { text = tostring(n), checked = ns.udb.timer.size == n, onClick = function()
            T.SetSize(n)
            V:Refresh()
        end }
    end
    UI.Menu(self.sizeBox, items)
end

function V:Refresh()
    if not self.frame then return end
    local d = ns.udb.timer
    local function onOff(b, on) b.label:SetText(on and "On" or "Off"); UI.SetActive(b, on) end
    self.enabledBtn.label:SetText(d.enabled and "|cff66e08cTimer: On|r" or "|cffff5a5aTimer: Off|r")
    UI.SetActive(self.enabledBtn, d.enabled)
    for _, ft in ipairs(T.FONTS) do if ft.key == d.font then self.fontBtn.label:SetText(ft.label) end end
    if not self.sizeBox:HasFocus() then self.sizeBox:SetText(tostring(d.size)) end
    for i, b in ipairs(self.swatches) do UI.SetActive(b, i == d.color) end
    onOff(self.outlineBtn, d.outline)
    onOff(self.tenthsBtn, d.tenths)
    onOff(self.chatBtn, d.chatSummary)
    for key, b in pairs(self.whereBtns) do
        local on = (d.chatWhere or {})[key] and true or false
        UI.SetActive(b, on)
        UI.SetDisabled(b, not d.chatSummary)
    end
    for _, m in ipairs(T.CHAT_MIN) do if m[1] == d.chatMin then self.chatMinBtn.label:SetText(m[2]) end end
    UI.SetDisabled(self.chatMinBtn, not d.chatSummary)
    onOff(self.instanceBtn, d.instanceOnly)
    for _, l in ipairs(T.LINGER) do if l[1] == d.linger then self.lingerBtn.label:SetText(l[2]) end end
    UI.SetActive(self.anchorBtn, T.unlocked)
    local hist = d.history or {}
    for i, r in ipairs(self.historyRows) do
        local e = hist[i]
        r.dur:SetText(e and T.Format(e.dur, true) or "")
        r.label:SetText(e and (e.label or "Combat") or "")
        r.result:SetText(e and ns.UI.ResultTag(e.result) or "")
        r.when:SetText(e and date("%a %b %d %H:%M", e.t) or "")
    end
    self.lastText:SetText(#hist == 0 and "No fights timed yet." or "")
    T:Render()
end

ns.RegisterModule({
    key = "timer", name = "Combat Timer", icon = ns.MEDIA .. "Timer", group = "tools", order = 3,
    desc = "A combat timer you can style and place anywhere.",
    view = V,
})
