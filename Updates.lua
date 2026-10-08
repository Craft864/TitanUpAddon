-- Titan Up - Updates.lua
--   * Version check: "Check guild versions" (Settings) asks every online
--     guildmate's Titan Up for its version and lists them. Anyone who sees a
--     newer version than their own gets a one-time "please update" pop-up.
--   * What's new: a short note once after an update (never on a first install).
--   * Blizzard's addon menu (by the minimap) and key bindings.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local UP = {}
ns.Updates = UP

local PREFIX = "TitanUpVC"

-- What's new, per version, newest first. After an update the pop-up shows
-- every version since you last played; Settings > Titan Up lists them too.
UP.NOTES = {
    { "0.29.0", {
        "New layout: Titan Up is now one window with a list of modules down the left side. Home is at the top and opens first (/tu, the minimap button or the key binding): last pull, Raid Check, loot to trade, your games. Click any module on the left and it opens in the same spot. The \"<\" button shrinks the list to icons.",
        "Pull Report and Raid Scorecard are now one \"Reports\" entry with Tonight / This week tabs.",
        "UI Tweaks: each tweak's options now show right beside its switch (they're no longer in Settings).",
        "Every window is the same, wider size and uses the room: the Pull Report shows pulls, deaths and details side by side; Wowdle keeps its keyboard with guild standings always on the right; Death Roll shows standings or spectators beside the game.",
        "Pop-ups (Pull Report summary, Raid Check alert, game invites, what's new) now stack in one spot. Drag one to move them all; Settings > Titan Up > \"Reset alert position\" puts them back.",
        "The Pull Report and Raid Check results no longer jump over a window you're using - you get a small \"Open\" notice instead.",
    } },
    { "0.28.0", {
        "Version check (Settings > Titan Up, or /tu versions): now lists just your group, and the window opens straight away with everyone \"waiting...\" - each name fills in the moment that person answers (green = current, orange = behind). Anyone who hasn't answered after 5 seconds shows \"no Titan Up\"; offline players and people outside the guild are marked too. \"Check again\" re-asks.",
    } },
    { "0.27.0", {
        "Loot: a new roll window (off by default - turn it on in Loot settings). Every item up for a roll in one window instead of Blizzard's separate pop-ups: Need / Greed / Transmog / Pass, plus BIS / Sidegrade / 2pc / 4pc tags (tick any) and a short note. Click an item to see what the rest of the raid tagged and rolled, and who won - so if a Sidegrade beats someone's BIS you can sort out a trade. Tags and notes are seen by raiders running Titan Up. \"Preview the roll window\" in Loot settings shows it with sample items; /tu rolls reopens it.",
        "Death Roll: nothing gives a roll away before the number lands - the button reads \"Rolling...\", and the new history line and the winner only show once the animation ends.",
    } },
    { "0.26.0", {
        "Death Roll: the spectator list now shows - a small list beside the game window (right side, or left if there's no room), as tall as its names. It was built before but never placed on screen.",
        "Death Roll: sharing a long game history no longer delays a live game's moves.",
        "Behind the scenes: about 1,550 lines of code removed by sharing common pieces between windows and features. Nothing should look or work differently - tell Ryan if something does.",
        "Removed the testing-only commands (/tb sim, /tb loop, /tu deaths test / fake / clear / check, /tu keys art, /tu split debug).",
    } },
    { "0.25.3", {
        "Pull Report: pulls under 20 seconds that aren't kills (resets, bad pulls) aren't counted - not in the report, not in the Raid Scorecard, and they don't use up a pull number. Both windows show how many short pulls there were.",
        "Death Roll: the \"Announce in chat\" checkbox shows its check again (it was working, just drawn hidden), and announcements now post in any group, not only all-guild ones.",
        "Death Roll: \"< Lobby\" is back, so you can return from Standings (or a game) without a /reload.",
    } },
    { "0.25.2", {
        "/tu mem now breaks the number down: saved data per area (largest first), which windows you've opened this session (they stay built until /reload), and the rest (code and everything else).",
        "Pull Report pop-ups are now off by default: \"Opens after a raid pull\" starts at Never and \"My death summary\" stays off. If yours was still on the old \"When I'm raid leader\" default, it's switched to Never once; turn it back on in Settings and it stays.",
    } },
    { "0.25.1", {
        "Macro Share: drag a macro from your macro book (or an action bar) into the window to fill in its name, text and icon, then send it. Shared macros keep their real icon.",
    } },
    { "0.25.0", {
        "New: Macro Share (Raid Tools). In a raid, the leader or an assistant can send a macro to the whole raid, a role, a class or one person. You get a toast, and the macro waits in Macro Share - drag its icon onto a bar and it's made as a character macro and placed in one go.",
        "Fix: group-only features (Pull Report, Death Roll, Keystone Roulette and others) no longer ignore a raid member whose messages arrive without their realm name.",
    } },
}

-- the notes as text: every version newer than `since` (or all), newest first
function UP.NotesText(since)
    local out = {}
    for _, v in ipairs(UP.NOTES) do
        if not since or ns.VersionNewer(v[1], since) then
            if #out > 0 then out[#out + 1] = "" end
            out[#out + 1] = "|cff4fc3f7v" .. v[1] .. "|r"
            for _, line in ipairs(v[2]) do out[#out + 1] = "-  " .. line end
        end
    end
    return table.concat(out, "\n")
end

-- "0.23.1" vs "0.24.0": is a newer than b?
function ns.VersionNewer(a, b)
    local function parts(v) local t = {} for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end return t end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

function UP:Init()
    ns.Listen(PREFIX, "guild", function(msg, sender) UP:OnMessage(msg, sender) end)
    C_Timer.After(8, function() UP:WhatsNewCheck() end)
end

-- ---------------------------------------------------------------------
-- Version check: your group only. The window opens at once with everyone
-- "waiting..."; each row fills in as that person answers. No answer after
-- 5 seconds = no Titan Up (older versions answer within 4).
-- ---------------------------------------------------------------------
--   Q version     "what version are you on?" (also says what the asker runs)
--   V version     the answer
local TIMEOUT = 5

function UP:Check()
    if not IsInGroup() then
        ns.Print("The version check lists your group - join a party or raid first.")
        return
    end
    local roster = {}
    for _, unit in ipairs(ns.GroupUnits()) do
        local name = UnitExists(unit) and ns.FullName(unit)
        if name then
            local r = { name = name, class = ns.Safe.Class(unit) }
            if name == ns.me then r.v = ns.VERSION
            elseif UnitIsConnected and UnitIsConnected(unit) == false then r.offline = true
            elseif UnitIsInMyGuild and not UnitIsInMyGuild(unit) then r.noGuild = true end   -- the guild channel can't reach them
            roster[name] = r
        end
    end
    self.roster, self.timedOut = roster, false
    self.checkId = (self.checkId or 0) + 1
    local id = self.checkId
    if not ns.SendFields(PREFIX, "Q", ns.VERSION) then ns.Print("The version check asks over your guild's addon channel - it needs a guild.") end
    self:ShowResults()
    C_Timer.After(TIMEOUT, function()
        if UP.checkId ~= id then return end
        UP.timedOut = true
        UP:RefreshResults()
    end)
end

function UP:OnMessage(msg, sender)
    local kind, ver = msg:match("^([QV])%^([%d%.]+)$")
    if not kind then return end
    self:Saw(ver)
    if kind == "Q" then
        -- your group's check: answer at once; anyone else's (older versions
        -- still check the whole guild): after a short random wait
        if ns.InMyGroup(sender) then ns.SendFields(PREFIX, "V", ns.VERSION)
        else C_Timer.After(math.random() * 4, function() ns.SendFields(PREFIX, "V", ns.VERSION) end) end
    elseif kind == "V" then
        local r = self.roster and self.roster[sender]
        if r then
            r.v, r.offline, r.noGuild = ver, nil, nil
            self:RefreshResults()
        end
    end
end

-- someone runs a newer Titan Up than us: remind once per session
function UP:Saw(ver)
    if self.nagged or not ns.VersionNewer(ver, ns.VERSION) then return end
    self.nagged = ver
    self:ShowUpdate(ver)
end

function UP:Latest()
    local best = ns.VERSION
    for _, r in pairs(self.roster or {}) do if r.v and ns.VersionNewer(r.v, best) then best = r.v end end
    return best
end

-- the group, alphabetical (rows stay put while answers come in), plus a summary
function UP:ResultLines()
    local latest = self:Latest()
    local list = {}
    for _, r in pairs(self.roster or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return a.name < b.name end)
    local lines, have, behind, waiting, missing = {}, 0, 0, 0, 0
    for _, r in ipairs(list) do
        local status
        if r.v then
            have = have + 1
            local old = ns.VersionNewer(latest, r.v)
            if old then behind = behind + 1 end
            status = old and ("|cffffa340v" .. r.v .. "  (behind)|r") or ("|cff66e08cv" .. r.v .. "|r")
        elseif r.offline then
            status = "|cff8a8f9coffline|r"
        elseif r.noGuild then
            status = "|cff8a8f9cnot in the guild - can't check|r"
        elseif self.timedOut then
            missing = missing + 1
            status = "|cffff5a5ano Titan Up|r"
        else
            waiting = waiting + 1
            status = "|cff8a8f9cwaiting...|r"
        end
        lines[#lines + 1] = UI.ClassName(r.name, r.class) .. (r.name == ns.me and " |cff8a8f9c(you)|r" or "") .. "  " .. status
    end
    local summary = ("Newest: v%s  -  %d of %d have Titan Up, %d behind"):format(latest, have, #list, behind)
    if waiting > 0 then summary = summary .. (", waiting for %d"):format(waiting)
    elseif missing > 0 then summary = summary .. (", %d without it"):format(missing) end
    return lines, summary
end

function UP:ShowResults()
    local f = self:Panel("versions", "RAID VERSIONS")
    if not f.again then
        f.again = UI.Button(f, 100, 24, "Check again", "Ask everyone in your group again", function() UP:Check() end)
        f.again:SetPoint("BOTTOM", -52, 12)
        f.ok:ClearAllPoints()
        f.ok:SetPoint("BOTTOM", 52, 12)
    end
    self:RefreshResults(true)
    f:Show()
end

function UP:RefreshResults(force)
    local f = self.panels.versions
    if not f or not (force or f:IsShown()) then return end
    if not self.roster then
        f.body:SetText("|cff8a8f9cJoin a party or raid, then Check again.|r")
    else
        local lines, summary = self:ResultLines()
        f.body:SetText("|cff8a8f9c" .. summary .. ".|r\n\n" .. table.concat(lines, "\n"))
    end
    local scroll = f.scroll
    self:Fit(f)
    if scroll and not force then self:ScrollPanel(f, scroll) end      -- answers arriving don't jump the list back up
end

function UP:ShowUpdate(ver)
    local f = self:Panel("update", "TITAN UP UPDATE")
    f.body:SetText(("A newer Titan Up is out: |cff66e08cv%s|r (you have v%s).\n\nUpdate through CurseForge, then /reload."):format(ver, ns.VERSION))
    self:Fit(f)
    f:Show()
end

-- ---------------------------------------------------------------------
-- What's new (once per version; never on a first install)
-- ---------------------------------------------------------------------
function UP:WhatsNewCheck()
    local seen = ns.udb.seenVersion
    ns.udb.seenVersion = ns.VERSION
    if seen and seen ~= ns.VERSION and ns.VersionNewer(ns.VERSION, seen) then self:ShowWhatsNew(seen) end
end

function UP:ShowWhatsNew(since)
    local f = self:Panel("whatsnew", "WHAT'S NEW IN TITAN UP v" .. ns.VERSION)
    f.body:SetText(UP.NotesText(since))
    self:Fit(f)
    f:Show()
end

-- a small reusable message panel; Fit() sizes it to its text (OK always
-- below the text), with a scroll bar if the text is very long
local PANEL_W, PANEL_MAX = 420, 460
UP.panels = {}
function UP:Panel(key, title)
    local f = self.panels[key]
    if not f then
        f = UI.Window("TitanUpPanel_" .. key, PANEL_W, 200, { point = { "TOP", 0, -140 }, strata = "DIALOG", border = C.accent,
            drag = true, noTop = true })
        f.title = UI.Text(f, "GameFontNormal", C.accent, nil, "TOPLEFT", 14, -12)
        local x = UI.Button(f, 22, 20, "X", "Close", function() f:Hide() end)
        x:SetPoint("TOPRIGHT", -6, -6)
        -- the text, inside a clipped area that scrolls when it's long
        f.view = CreateFrame("Frame", nil, f)
        f.view:SetPoint("TOPLEFT", 14, -38)
        f.view:SetSize(PANEL_W - 40, 100)
        if f.view.SetClipsChildren then f.view:SetClipsChildren(true) end
        f.view:EnableMouseWheel(true)
        f.view:SetScript("OnMouseWheel", function(_, d) UP:ScrollPanel(f, -d * 30) end)
        f.body = UI.Text(f.view, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 0, 0)
        f.body:SetWidth(PANEL_W - 44); f.body:SetJustifyH("LEFT"); f.body:SetSpacing(2)
        f.track = f:CreateTexture(nil, "ARTWORK")
        f.track:SetColorTexture(1, 1, 1, 0.06)
        f.track:SetWidth(6)
        f.thumb = f:CreateTexture(nil, "OVERLAY")
        f.thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
        f.thumb:SetWidth(6)
        f.ok = UI.Button(f, 90, 24, "OK", nil, function() f:Hide() end)
        f.ok:SetPoint("BOTTOM", 0, 12)
        UI.SetActive(f.ok, true)
        self.panels[key] = f
        ns.Dock:Add(f)              -- stacks with the other pop-ups
    end
    f.title:SetText(title)
    return f
end

-- size the panel to its text: title + text + OK; cap it and scroll beyond
function UP:Fit(f)
    local h = f.body:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then
        local lines = 1
        for _ in (f.body:GetText() or ""):gmatch("\n") do lines = lines + 1 end
        h = lines * 14
    end
    f.textH = h
    local viewH = math.min(h, PANEL_MAX - 38 - 52)
    f.view:SetHeight(viewH)
    f:SetHeight(38 + viewH + 52)
    f.scroll = 0
    self:ScrollPanel(f, 0)
end

function UP:ScrollPanel(f, by)
    local viewH = f.view:GetHeight() or 0
    local max = math.max(0, (f.textH or 0) - viewH)
    f.scroll = math.max(0, math.min(max, (f.scroll or 0) + by))
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", 0, f.scroll)
    local show = max > 0
    f.track:SetShown(show); f.thumb:SetShown(show)
    if show then
        f.track:ClearAllPoints()
        f.track:SetPoint("TOPLEFT", f.view, "TOPRIGHT", 8, 0)
        f.track:SetHeight(viewH)
        local th = math.max(24, viewH * viewH / f.textH)
        f.thumb:SetHeight(th)
        f.thumb:ClearAllPoints()
        f.thumb:SetPoint("TOPLEFT", f.view, "TOPRIGHT", 8, -((viewH - th) * f.scroll / max))
    end
end

-- ---------------------------------------------------------------------
-- Blizzard's addon menu + key bindings (globals the game looks up by name)
-- ---------------------------------------------------------------------
function TitanUp_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        if ns.Settings then ns.Settings:Toggle() end
    else
        TitanUp_Binding("hub")
    end
end

function TitanUp_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("Titan Up " .. ns.VERSION, 1, 1, 1)
    GameTooltip:AddLine("Left-click: open / close Titan Up   Right-click: settings", 0.8, 0.82, 0.86)
    GameTooltip:Show()
end

function TitanUp_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- key bindings (Bindings.xml): open / close the Titan Up window or a module
function TitanUp_Binding(key)
    if key == "hub" then
        if ns.Hub then ns.Hub:Toggle() end
        return
    end
    local m = ns.Nav and ns.Nav.byKey and ns.Nav.byKey[key]
    if not m then return end
    if m.isShown and m.isShown() then m.hide() else ns.Nav:Switch(key) end
end

BINDING_HEADER_TITANUP = "Titan Up"
BINDING_NAME_TITANUP_HUB = "Open / close Titan Up"
BINDING_NAME_TITANUP_BOARD = "Open / close TitanBoard"
BINDING_NAME_TITANUP_PULLREPORT = "Open / close the Pull Report"
