-- Titan Up - DeathRoll/DeathRollUI.lua
-- Lobby (new challenge, open challenges, your record) and the room view
-- (player cards, big rolling number, roll button, history), plus the
-- challenge pop-up and the clickable chat link.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local DR

local V = {}
ns.DeathRollUI = V

local W, H = 880, 570          -- the standard module size
local PLAY_W = 500             -- the game; standings / spectators sit to the right
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local LINK = "addon:TitanUp:dr:"

local function fmtGold(n) return DR.Fmt(n) .. GOLD end

local function classColor(name)
    if DR.sim and name == DR.sim.opp then return 0.78, 0.61, 0.43 end   -- warrior tan
    local class = ns.ClassOf(name)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b end
    return C.text[1], C.text[2], C.text[3]
end

local function colored(name)
    local r, g, b = classColor(name)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, ns.Short(name))
end

-- rightInset: stop the line early (the top heading shares its line with
-- the window's X / cog / Lobby button)
local function section(parent, text, y, rightInset)
    local t = UI.Text(parent, "GameFontNormalSmall", C.muted, text, "TOPLEFT", 16, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    line:SetHeight(1)
    line:SetPoint("LEFT", t, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", -(rightInset or 16), 0)
    return t
end

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
-- Built the first time it's needed (nothing at login).
function V:Init()
    DR = ns.DeathRoll
    local function onLink(link)
        if type(link) == "string" and link:find("^" .. LINK) then
            local id = link:sub(#LINK + 1)
            DR:Watch(id)          -- ask the challenger for the latest state, like the Watch button
            V:ShowRoom(id)
        end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, V)
    end
    if SetItemRef then hooksecurefunc("SetItemRef", function(link) onLink(link) end) end
end

function V:Create()
    local f, header = ns.Nav:Window(self, "TitanUpDeathRoll", "deathroll", "DEATH ROLL", W, H, { mark = { 400, 0.07, -30 } })
    self:CreateSpectators(f)
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", PLAY_W, -12); sep:SetPoint("BOTTOMLEFT", PLAY_W, 12); sep:SetWidth(1)
    self.backBtn = UI.Button(header, 70, 22, "< Lobby", "Back to the lobby", function() V:ShowLobby() end)
    self.backBtn:SetPoint("RIGHT", header.close, "LEFT", -9, 0)
    self.backBtn:SetFrameLevel(header.close:GetFrameLevel())

    self.lobby = CreateFrame("Frame", nil, f)
    self.lobby:SetPoint("TOPLEFT", 0, -14)
    self.lobby:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", PLAY_W, 0)
    self.room = CreateFrame("Frame", nil, f)
    self.room:SetPoint("TOPLEFT", 0, -14)
    self.room:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", PLAY_W, 0)
    -- the guild standings: beside the lobby (the spectators take this side in a game)
    self.standings = CreateFrame("Frame", nil, f)
    self.standings:SetPoint("TOPLEFT", PLAY_W, -14)
    self.standings:SetPoint("BOTTOMRIGHT")
    self:CreateLobby(self.lobby)
    self:CreateRoom(self.room)
    self:CreateStandings(self.standings)
    self:ShowLobby()
end

-- ---------------------------------------------------------------------
-- Lobby
-- ---------------------------------------------------------------------
function V:CreateLobby(p)
    section(p, "NEW CHALLENGE", -6)
    UI.Text(p, "GameFontHighlightSmall", C.muted, "Wager (gold)", "TOPLEFT", 16, -30)
    self.wager = UI.EditBox(p, 150, 26, { inset = 8, numeric = true, max = 9 })
    self.wager:SetPoint("TOPLEFT", 16, -46)
    self.wager:SetText("10000")
    UI.Tip(self.wager, "Wager (gold)", nil, "Also the first roll: the challenger rolls 1 to the wager.")
    UI.Text(p, "GameFontHighlightSmall", C.muted, "Opponent", "TOPLEFT", 180, -30)
    self.oppBtn = UI.Button(p, 120, 26, "Anyone", "Open to anyone in your group, or challenge one person (only they can accept)", function() V:ShowOpponentMenu() end)
    self.oppBtn:SetPoint("TOPLEFT", 180, -46)
    local create = UI.Button(p, 128, 26, "Create challenge", nil, function()
        local room = DR:Create(V.wager:GetText(), V.target)
        if room then V:ShowRoom(room.id) end
    end)
    create:SetPoint("TOPRIGHT", -16, -46)
    UI.SetActive(create, true)
    self.announceCheck = UI.Check(p, "Announce in chat", "Post a line in party/raid chat when a challenge starts and ends",
        function() return ns.udb.deathroll.announce end, function(on) ns.udb.deathroll.announce = on end)
    self.announceCheck:SetPoint("TOPLEFT", create, "BOTTOMLEFT", 0, -6)

    section(p, "OPEN CHALLENGES", -92)
    self.openRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(PLAY_W - 32, 26)
        row:SetPoint("TOPLEFT", 16, -112 - (i - 1) * 30)
        row.text = UI.Text(row, "GameFontHighlightSmall", nil, nil, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -150, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.join = UI.Button(row, 66, 22, "Join", nil, function() if row.room then DR:Join(row.room.id); V:ShowRoom(row.room.id) end end)
        row.join:SetPoint("RIGHT", -72, 0)
        row.watch = UI.Button(row, 66, 22, "Watch", nil, function()
            if row.room then row.room.watching = true; DR:Watch(row.room.id); V:ShowRoom(row.room.id) end
        end)
        row.watch:SetPoint("RIGHT", 0, 0)
        self.openRows[i] = row
    end
    self.noOpen = UI.Text(p, "GameFontHighlightSmall", C.muted, "No challenges in your group right now.", "TOPLEFT", 20, -118)

    section(p, "YOUR RECORD", -278)
    self.recordText = UI.Text(p, "GameFontNormal", nil, nil, "TOPLEFT", 16, -300)
    self.debtRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(PLAY_W - 32, 24)
        row:SetPoint("TOPLEFT", 16, -326 - (i - 1) * 28)
        row.text = UI.Text(row, "GameFontHighlightSmall", nil, nil, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -90, 0)
        row.text:SetJustifyH("LEFT")
        -- winner's rows: Mark paid; loser's rows: Check (ask the winner's addon)
        row.paid = UI.Button(row, 82, 22, "Mark paid", nil, function()
            local e = row.entry
            if not e then return end
            if e.w == ns.me then ns.DRLedger:MarkPaid(e.id) else ns.DRLedger:CheckDebt(e.id) end
            V:RefreshLobby()
        end)
        row.paid:SetScript("OnEnter", function(s)
            s.hover = true; UI.Paint(s)
            local e = row.entry
            if not e then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            if e.w == ns.me then
                GameTooltip:SetText("Mark paid", 1, 1, 1)
                GameTooltip:AddLine("They paid you some other way (mail, etc.). Trades are detected automatically. You're the winner, so your confirmation is what counts.", 0.8, 0.82, 0.86, true)
            else
                GameTooltip:SetText("Check", 1, 1, 1)
                GameTooltip:AddLine(("Ask %s's addon whether it has confirmed your payment. The winner is the source of truth."):format(ns.Short(e.w)), 0.8, 0.82, 0.86, true)
            end
            GameTooltip:Show()
        end)
        row.paid:SetPoint("RIGHT")
        self.debtRows[i] = row
    end

    -- temporary: practice mode, tucked into the corner
    local practice = UI.Button(p, 64, 18, "Practice", "Play against a fake opponent to try it out (/tu roll sim)", function()
        DR:StartSim(tonumber(V.wager:GetText()))
    end)
    practice.label:SetFontObject("GameFontHighlightSmall")
    practice:SetPoint("BOTTOMRIGHT", -10, 10)
    self.practiceBtn = practice
end

-- (Death Roll has no settings page: "Announce in chat" is a checkbox on the
-- lobby, and rolls are always held back from chat until they land.)
function V:RefreshOptions() if self.announceCheck then self.announceCheck:Refresh() end end

function V:ShowOpponentMenu()
    local items = { { text = "Anyone in the group", checked = V.target == nil, onClick = function() V.target = nil; V:RefreshLobby() end } }
    for _, name in ipairs(ns.GroupNames()) do
        if name ~= ns.me then
            items[#items + 1] = { text = ns.Short(name), checked = V.target == name, onClick = function() V.target = name; V:RefreshLobby() end }
        end
    end
    if #items == 1 then items[2] = { text = "(join a group to challenge someone)", muted = true } end
    UI.Menu(self.oppBtn, items)
end

function V:RefreshLobby()
    if self.specPanel then self.specPanel:Hide() end
    self.oppBtn.label:SetText(V.target and ns.Short(V.target) or "Anyone")

    local open = {}
    for _, room in pairs(DR.rooms) do
        local live = room.state == "open" or room.state == "seated" or room.state == "rolling"
        if live and room.host ~= ns.me and room.opponent ~= ns.me then open[#open + 1] = room end
    end
    table.sort(open, function(a, b) return a.created > b.created end)
    for i, row in ipairs(self.openRows) do
        local room = open[i]
        row.room = room
        row:SetShown(room ~= nil)
        if room then
            local who = room.target and (colored(room.host) .. " vs " .. colored(room.target)) or (colored(room.host) .. " vs anyone")
            if room.opponent then who = colored(room.host) .. " vs " .. colored(room.opponent) end
            row.text:SetText(("%s   %s"):format(who, fmtGold(room.wager)))
            local canJoin = room.state == "open" and (not room.target or room.target == ns.me)
            row.join:SetShown(canJoin)
        end
    end
    self.noOpen:SetShown(#open == 0)

    local _, by = ns.DRLedger:Stats()
    local me = by[ns.me] or { wins = 0, losses = 0, net = 0 }
    local netText = (me.net >= 0 and "|cff66e08c+" or "|cffff5a5a-") .. DR.Fmt(math.abs(me.net)) .. "|r" .. GOLD
    self.recordText:SetText(("Won %d   Lost %d   Net %s"):format(me.wins, me.losses, netText))
    local unpaid = ns.DRLedger:MyUnpaid()
    for i, row in ipairs(self.debtRows) do
        local e = unpaid[i]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            local owed = ns.DRLedger:Owed(e)
            local partial = (e.paid or 0) > 0 and ("  |cff8a8f9c(" .. DR.Fmt(e.paid) .. " of " .. DR.Fmt(e.g) .. " paid)|r") or ""
            if e.w == ns.me then
                row.text:SetText(("%s owes you %s%s"):format(colored(e.l), fmtGold(owed), partial))
                row.paid.label:SetText("Mark paid")
                row.paid:Show()
            else
                local waiting = ((e.sent or 0) > (e.paid or 0)) and ("  |cff8a8f9c(sent " .. DR.Fmt(e.sent) .. " - waiting for them to confirm)|r") or partial
                row.text:SetText(("|cffff9f40You owe|r %s %s%s"):format(colored(e.w), fmtGold(owed), waiting))
                row.paid.label:SetText("Check")         -- only the winner can confirm; you can ask
                row.paid:Show()
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Standings: everyone's totals + recent games (both scrollable)
-- ---------------------------------------------------------------------
local function scrollList(parent, y, rows, rowH, onScroll)
    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", 16, y)
    area:SetPoint("RIGHT", -16, 0)
    area:SetHeight(rows * rowH + 4)
    area:EnableMouseWheel(true)
    area.offset = 0
    area:SetScript("OnMouseWheel", function(_, d) area.offset = area.offset - d; onScroll() end)
    area.rows = {}
    for i = 1, rows do
        local r = CreateFrame("Frame", nil, area)
        r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 4, -2 - (i - 1) * rowH)
        r:SetPoint("RIGHT", -10, 0)
        area.rows[i] = r
    end
    local track = area:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", -2, -2)
    track:SetPoint("BOTTOMRIGHT", -2, 2)
    area.track = track
    area.thumb = area:CreateTexture(nil, "ARTWORK")
    area.thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    area.thumb:SetWidth(3)
    function area:Layout(total)
        local n = #self.rows
        local maxOff = math.max(0, total - n)
        self.offset = math.max(0, math.min(maxOff, self.offset))
        local scroll = total > n
        self.track:SetShown(scroll)
        self.thumb:SetShown(scroll)
        if scroll then
            local h = self:GetHeight() - 4
            if type(h) ~= "number" or h <= 0 then h = n * rowH end
            local th = math.max(10, h * n / total)
            self.thumb:SetHeight(th)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -2 - (h - th) * (self.offset / maxOff))
        end
        return self.offset
    end
    return area
end

function V:CreateStandings(p)
    section(p, "GUILD STANDINGS", -6)
    local note = UI.Text(p, "GameFontHighlightSmall", C.muted, "Shared with your group and guild. Only games both players confirmed count.", "TOPLEFT", 16, -24)
    note:SetPoint("RIGHT", -16, 0); note:SetJustifyH("LEFT"); note:SetWordWrap(false)
    local function header(x, text, justify, w)
        local t = UI.Text(p, "GameFontHighlightSmall", C.muted, text, "TOPLEFT", x, -42)
        t:SetWidth(w); t:SetJustifyH(justify)
    end
    header(20, "#  PLAYER", "LEFT", 126)
    header(148, "W-L", "CENTER", 50)
    header(200, "NET", "RIGHT", 76)
    header(278, "UNPAID", "RIGHT", 76)
    self.standList = scrollList(p, -58, 9, 20, function() V:RefreshStandings() end)
    for _, r in ipairs(self.standList.rows) do
        r.name = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 0, 0); r.name:SetWidth(126); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.wl = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 128, 0); r.wl:SetWidth(50); r.wl:SetJustifyH("CENTER")
        r.net = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 180, 0); r.net:SetWidth(76); r.net:SetJustifyH("RIGHT")
        r.unpaid = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 258, 0); r.unpaid:SetWidth(76); r.unpaid:SetJustifyH("RIGHT")
    end
    self.standEmpty = UI.Text(p, "GameFontHighlightSmall", C.muted, "No games yet - play one, or group with someone who has.", "TOPLEFT", 20, -64)
    self.standEmpty:SetPoint("RIGHT", -16, 0); self.standEmpty:SetJustifyH("LEFT")

    section(p, "RECENT GAMES", -260)
    self.gameList = scrollList(p, -280, 11, 20, function() V:RefreshStandings() end)
    for _, r in ipairs(self.gameList.rows) do
        r.text = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 0, 0); r.text:SetPoint("RIGHT", -110, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.tag = UI.Text(r, "GameFontHighlightSmall", nil, nil, "RIGHT", 0, 0); r.tag:SetWidth(108); r.tag:SetJustifyH("RIGHT")
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(s)
            local g = s.game
            if not g then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(ns.Short(g.w) .. " beat " .. ns.Short(g.l), 1, 1, 1)
            GameTooltip:AddLine(DR.Fmt(g.g) .. " gold, " .. (g.r or 0) .. " rolls" .. (g.t and g.t > 0 and ("  -  " .. date("%b %d %H:%M", g.t)) or ""), 0.8, 0.82, 0.86)
            GameTooltip:AddLine((g.paid or 0) >= g.g and "Paid in full" or ("Paid " .. DR.Fmt(g.paid or 0) .. " of " .. DR.Fmt(g.g)), 0.8, 0.82, 0.86)
            if g.conflict then
                GameTooltip:AddLine("Disputed: the two players' records didn't match before it was confirmed. Not counted.", 1, 0.4, 0.4, true)
            elseif ns.DRLedger:Confirmed(g) then
                GameTooltip:AddLine("Confirmed by both players - locked.", 0.4, 0.9, 0.55)
            else
                GameTooltip:AddLine("Pending: reported by one player so far. Counts once the other player's copy matches.", 1, 0.65, 0.25, true)
            end
            if (g.rejected or 0) > 0 then
                GameTooltip:AddLine(("Ignored %d changed cop%s sent after it was confirmed (last from %s)."):format(
                    g.rejected, g.rejected == 1 and "y" or "ies", ns.Short(g.rejectedBy or "?")), 1, 0.4, 0.4, true)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

-- (the standings sit beside the lobby now)
function V:ShowStandings() self:ShowLobby() end

function V:RefreshStandings()
    local list = ns.DRLedger:Stats()
    local off = self.standList:Layout(#list)
    self.standEmpty:SetShown(#list == 0)
    for i, r in ipairs(self.standList.rows) do
        local s = list[i + off]
        r:SetShown(s ~= nil)
        if s then
            r.name:SetText(("%d.  %s%s"):format(i + off, colored(s.name), s.name == ns.me and " |cff8a8f9c(you)|r" or ""))
            r.wl:SetText(s.wins .. "-" .. s.losses)
            r.net:SetText(((s.net >= 0) and "|cff66e08c+" or "|cffff5a5a-") .. DR.Fmt(math.abs(s.net)) .. "|r")
            local unpaid = ""
            if s.owes > 0 then unpaid = "|cffff9f40owes " .. DR.Fmt(s.owes) .. "|r"
            elseif s.owed > 0 then unpaid = "|cff8a8f9cis owed " .. DR.Fmt(s.owed) .. "|r" end
            r.unpaid:SetText(unpaid)
        end
    end
    local games = ns.DRLedger:Recent()
    local goff = self.gameList:Layout(#games)
    for i, r in ipairs(self.gameList.rows) do
        local g = games[i + goff]
        r.game = g
        r:SetShown(g ~= nil)
        if g then
            r.text:SetText(("%s beat %s  %s"):format(colored(g.w), colored(g.l), fmtGold(g.g)))
            local tag
            if g.conflict then tag = "|cffff5a5adisputed|r"
            elseif not ns.DRLedger:Confirmed(g) then tag = "|cff8a8f9cpending|r"
            elseif (g.paid or 0) >= g.g then tag = "|cff66e08cpaid|r"
            else tag = "|cffffa340unpaid|r" end
            if (g.rejected or 0) > 0 then tag = tag .. " |cffff5a5a!|r" end
            r.tag:SetText(tag)
        end
    end
end

-- ---------------------------------------------------------------------
-- Room
-- ---------------------------------------------------------------------
local function playerCard(parent, x)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Skin(c, C.panel, C.line)
    c:SetSize(200, 64)
    c:SetPoint("TOPLEFT", x, -54)
    c.name = UI.Text(c, "GameFontNormalLarge", nil, nil, "TOP", 0, -12)
    c.status = UI.Text(c, "GameFontHighlightSmall", C.muted, nil, "TOP", c.name, "BOTTOM", 0, -6)
    return c
end

function V:CreateRoom(p)
    self.wagerText = UI.Text(p, "GameFontNormalLarge", nil, nil, "TOP", 0, -6)
    self.subText = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "TOP", self.wagerText, "BOTTOM", 0, -4)

    self.cardA = playerCard(p, 20)
    self.cardB = playerCard(p, PLAY_W - 220)
    UI.Text(p, "GameFontNormal", C.muted, "VS", "TOP", 0, -78)

    -- The big number
    self.bigNum = p:CreateFontString(nil, "OVERLAY")
    self.bigNum:SetFont(STANDARD_TEXT_FONT, 60, "THICKOUTLINE")
    self.bigNum:SetPoint("TOP", 0, -140)
    self.bigNum:SetTextColor(1, 0.85, 0.3)
    self.bigLabel = UI.Text(p, "GameFontHighlight", C.muted, nil, "TOP", self.bigNum, "BOTTOM", 0, -6)

    self.action = UI.Button(p, 260, 40, "", nil, function() V:OnAction() end)
    self.action:SetPoint("TOP", 0, -248)
    self.action.label:SetFontObject("GameFontNormalLarge")
    self.secondary = UI.Button(p, 120, 24, "Cancel", nil, function() V:OnSecondary() end)
    self.secondary:SetPoint("TOP", self.action, "BOTTOM", -64, -8)
    self.tertiary = UI.Button(p, 120, 24, "", nil, function() V:OnTertiary() end)
    self.tertiary:SetPoint("TOP", self.action, "BOTTOM", 64, -8)

    self.warning = UI.Text(p, "GameFontHighlightSmall", C.warn, nil, "TOP", 0, -330)

    section(p, "ROLLS", -350)
    self.histCount = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", -24, -350)
    -- scrollable roll list (mouse wheel), newest first
    self.histList = scrollList(p, -366, 7, 18, function() V:RefreshRoom() end)
    for _, r in ipairs(self.histList.rows) do
        r.text = UI.Text(r, "GameFontHighlightSmall", nil, nil, "LEFT", 4, 0)
        r.text:SetPoint("RIGHT", -4, 0); r.text:SetJustifyH("LEFT")
    end

    -- roll animation driver
    p:SetScript("OnUpdate", function() V:Animate() end)
end

function V:ShowLobby()
    self:EnsureFrame()
    DR:SetWatching(nil)
    self.roomId = nil
    self.view = "lobby"
    self.room:Hide()
    self.lobby:Show()
    self.standings:Show()
    self.backBtn:Hide()
    self:RefreshLobby()
    self:RefreshStandings()
end

function V:ShowRoom(id)
    if not DR.rooms[id] then
        ns.Print("That death roll isn't available any more.")
        return
    end
    self:EnsureFrame()
    if self.roomId ~= id then self.histList.offset = 0 end
    self.roomId = id
    self.view = "room"
    self.anim = nil
    self.lobby:Hide()
    self.standings:Hide()
    self.room:Show()
    self.backBtn:Show()
    if not self.frame:IsShown() then self.frame:Show() end
    DR:SetWatching(id)
    self:RefreshRoom()
end

function V:Refresh()
    if not self.frame then return end
    if self.roomId then self:RefreshRoom()
    else self:RefreshLobby(); self:RefreshStandings() end
end

local function cardState(card, room, name, isTurn, landing)
    if not name then
        card.name:SetText("|cff8a8f9c" .. (room.target and ns.Short(room.target) or "Open seat") .. "|r")
        card.status:SetText(room.target and "invited" or "waiting for someone to join")
        UI.Skin(card, C.panel, C.line)
        return
    end
    card.name:SetText(colored(name) .. (name == ns.me and " |cff8a8f9c(you)|r" or ""))
    local status
    if landing then
        -- a roll is still landing on screen: don't give the result away yet
        status = isTurn and "|cff4fc3f7rolling...|r" or "waiting"
    elseif room.state == "done" then
        status = (name == room.winner) and "|cff66e08cWINNER|r" or "|cffff5a5aROLLED A 1|r"
    elseif room.state == "rolling" then
        status = isTurn and "|cff4fc3f7rolling...|r" or "waiting"
    elseif room.state == "cancelled" then
        status = "cancelled"
    else
        status = room.ready[name] and "|cff66e08cready|r" or "deciding..."
    end
    card.status:SetText(status)
    UI.Skin(card, isTurn and C.accentDim or C.panel, isTurn and C.accent or C.line)
end

function V:RefreshRoom()
    self:RefreshSpectators()
    local room = DR.rooms[self.roomId or ""]
    if not room then return self:ShowLobby() end
    local me = ns.me
    local mine = DR:IsPlayer(room, me)
    self.wagerText:SetText(fmtGold(room.wager))
    self.subText:SetText("First roll 1-" .. DR.Fmt(room.start) .. " - whoever rolls a 1 loses")
    local a = self.anim
    local turn = a and a.who or room.turn
    cardState(self.cardA, room, room.host, turn == room.host, a)
    cardState(self.cardB, room, room.opponent, room.opponent ~= nil and turn == room.opponent, a)

    if not self.anim then
        if room.state == "rolling" then
            local last = room.rolls[#room.rolls]
            self.bigNum:SetText(last and DR.Fmt(last.roll) or DR.Fmt(room.max))
            self.bigNum:SetTextColor(1, 0.85, 0.3)
            self.bigLabel:SetText(ns.Short(room.turn) .. " rolls 1-" .. DR.Fmt(room.max)
                .. (DR:Paused() and "   |cffffa340(paused until combat ends)|r" or ""))
        elseif room.state == "done" then
            self.bigNum:SetText("1")
            self.bigNum:SetTextColor(1, 0.25, 0.25)
            self.bigLabel:SetText(("%s wins %s!  %s pays up."):format(colored(room.winner), fmtGold(room.wager), colored(room.loser)))
        elseif room.state == "cancelled" then
            self.bigNum:SetText("-")
            self.bigNum:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            local why = room.cancelledBy == "expired" and "Nobody joined in time." or room.cancelledBy == "left" and "A player left the group." or "Cancelled."
            self.bigLabel:SetText(why)
        else
            self.bigNum:SetText(DR.Fmt(room.start))
            self.bigNum:SetTextColor(0.75, 0.78, 0.84)
            local waitText
            if room.state ~= "open" then
                waitText = "Waiting for both players to accept"
            elseif room.declinedBy then
                waitText = "|cffffa340" .. ns.Short(room.declinedBy) .. " declined.|r" .. (room.host == ns.me and "  Open it to anyone, or cancel." or "")
            elseif room.target then
                waitText = "Waiting for " .. colored(room.target) .. " to accept..."
            else
                waitText = "Waiting for an opponent..."
            end
            self.bigLabel:SetText(waitText)
        end
    end

    -- buttons
    local action, actionOn, secondary, tertiary = nil, false, nil, nil
    if room.state == "open" then
        if room.host == me then
            if room.declinedBy then
                action, actionOn, secondary = "Open to anyone", true, "Cancel"
            elseif room.target then
                action, secondary, tertiary = "Waiting for " .. ns.Short(room.target) .. "...", "Cancel", "Open to anyone"
            else
                action, secondary = "Waiting for opponent...", "Cancel"
            end
        elseif room.target == me then
            action, actionOn, secondary = room.joinRequested and "Joining..." or "Join challenge", not room.joinRequested, "Decline"
        elseif not room.target then
            action, actionOn = room.joinRequested and "Joining..." or "Join challenge", not room.joinRequested
        else
            action = "Reserved for " .. ns.Short(room.target)
        end
    elseif room.state == "seated" then
        if mine and not room.ready[me] then
            action, actionOn, secondary = "Accept " .. DR.Fmt(room.wager) .. "g", true, "Decline"
        elseif mine then
            action, secondary = "Waiting for " .. ns.Short(DR:Other(room, me)) .. "...", "Cancel"
        else
            action = "Waiting for players to accept"
        end
    elseif room.state == "rolling" then
        if self.anim then
            action = "Rolling..."           -- the number hasn't landed yet
        elseif DR:Paused() and mine then
            action = "Paused - in combat"
        elseif room.turn == me then
            action, actionOn = "ROLL  1-" .. DR.Fmt(room.max), not (room.pendingRoll and GetTime() - room.pendingRoll < 4)
        else
            action = ns.Short(room.turn) .. "'s turn"
        end
        if mine then secondary = "Cancel game" end
    elseif room.state == "done" then
        if self.anim then
            -- the final roll is still landing on screen: no buttons yet
        else
            if mine then
                action, actionOn = "Rematch", true
                if room.loser == me and not room.sim then tertiary = "Open trade" end
            else
                action = "Game over"
            end
            secondary = "Lobby"
        end
    else
        action, secondary = "Back to lobby", nil
        actionOn = true
    end
    self.action:SetShown(action ~= nil)
    self.action.label:SetText(action or "")
    UI.SetDisabled(self.action, not actionOn)
    UI.SetActive(self.action, actionOn)
    self.secondary:SetShown(secondary ~= nil)
    self.secondary.label:SetText(secondary or "")
    self.tertiary:SetShown(tertiary ~= nil)
    -- one button: centered under the main button; two: side by side around the center
    local both = secondary ~= nil and tertiary ~= nil
    self.secondary:ClearAllPoints()
    self.secondary:SetPoint("TOP", self.action, "BOTTOM", both and -64 or 0, -8)
    self.tertiary:ClearAllPoints()
    self.tertiary:SetPoint("TOP", self.action, "BOTTOM", both and 64 or 0, -8)
    self.tertiary.label:SetText(tertiary or "")
    self.warning:SetText(room.warning or "")

    -- history, newest first (scrolls); the roll still landing on screen isn't listed yet
    local total, rows = #room.rolls - (self.anim and 1 or 0), #self.histList.rows
    local off = self.histList:Layout(total)
    self.histCount:SetText(total > rows and ("showing %d-%d of %d  (scroll)"):format(off + 1, math.min(total, off + rows), total)
        or (total > 0 and (total .. (total == 1 and " roll" or " rolls")) or ""))
    for i, row in ipairs(self.histList.rows) do
        local r = room.rolls[total - off - i + 1]
        local hit = r and (r.roll == 1 and "|cffff5a5a1|r" or ("|cffffd94d" .. DR.Fmt(r.roll) .. "|r"))
        row.text:SetText(r and ("%d.  %s rolled %s  |cff8a8f9c(1-%s)|r"):format(total - off - i + 1, colored(r.who), hit, DR.Fmt(r.max)) or "")
    end
end

function V:OnAction()
    local room = DR.rooms[self.roomId or ""]
    if not room then return self:ShowLobby() end
    if room.state == "open" then
        if room.host == ns.me then
            if room.declinedBy then DR:OpenToAnyone(room.id) end
        else
            DR:Join(room.id)
        end
    elseif room.state == "seated" then
        DR:Accept(room.id)
    elseif room.state == "rolling" then
        DR:Roll()
        self:RefreshRoom()
    elseif room.state == "done" then
        local new = DR:Rematch(room.id)
        if new then self:ShowRoom(new.id) end
    else
        self:ShowLobby()
    end
end

function V:OnSecondary()
    local room = DR.rooms[self.roomId or ""]
    if not room then return self:ShowLobby() end
    if room.state == "done" then return self:ShowLobby() end
    -- the challenged / seated player turning it down: the game stays open for the challenger
    if room.host ~= ns.me and ((room.state == "open" and room.target == ns.me) or (room.state == "seated" and room.opponent == ns.me)) then
        DR:Decline(room.id)
        return self:ShowLobby()
    end
    if room.state == "rolling" then
        UI.Prompt({
            title = "Cancel this death roll?", noInput = true, accept = "Cancel game",
            help = ("Nobody wins or loses the %sg - the game just stops. Your opponent sees that you cancelled."):format(DR.Fmt(room.wager)),
            onAccept = function() DR:Cancel(room.id) end,
        })
        return
    end
    DR:Cancel(room.id)
end

function V:OnTertiary()
    local room = DR.rooms[self.roomId or ""]
    if room and room.state == "open" and room.host == ns.me then return DR:OpenToAnyone(room.id) end
    if not room or room.loser ~= ns.me then return end
    local unit = ns.UnitForName(room.winner)
    if unit and InitiateTrade then
        InitiateTrade(unit)
        ns.Print(("Trade %s with %s."):format(fmtGold(room.wager), ns.Short(room.winner)))
    else
        ns.Print(ns.Short(room.winner) .. " needs to be close enough to trade.")
    end
end

-- ---------------------------------------------------------------------
-- Roll animation: numbers spin, slow down, land on the result.
-- ---------------------------------------------------------------------
local SPIN = 1.15
V.SPIN = SPIN                   -- the logic side times the result announcement from this

function V:Animate()
    local a = self.anim
    if not a then return end
    local t = GetTime() - a.t0
    if t < SPIN then
        local interval = 0.03 + 0.17 * (t / SPIN) ^ 2       -- slows down
        if GetTime() - (a.lastTick or 0) >= interval then
            a.lastTick = GetTime()
            self.bigNum:SetText(DR.Fmt(math.random(1, a.max)))
            if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
        end
        self.bigNum:SetTextColor(0.85, 0.88, 0.95)
        self.bigNum:ClearAllPoints()
        self.bigNum:SetPoint("TOP", 0, -140)
        return
    end
    if not a.landed then
        a.landed = true
        self.bigNum:SetText(DR.Fmt(a.roll))
        if a.roll == 1 then
            self.bigNum:SetTextColor(1, 0.2, 0.2)
            self.bigLabel:SetText("|cffff5a5aDEATH!|r  " .. colored(a.who) .. " rolled a 1")
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        else
            self.bigNum:SetTextColor(1, 0.85, 0.3)
            self.bigLabel:SetText(colored(a.who) .. " rolled " .. DR.Fmt(a.roll))
        end
    end
    local after = t - SPIN
    -- landing "punch": grow then settle; a 1 also shakes
    local size = 60 + 22 * math.max(0, 1 - after / 0.3)
    self.bigNum:SetFont(STANDARD_TEXT_FONT, size, "THICKOUTLINE")
    local dx = 0
    if a.roll == 1 and after < 0.6 then dx = math.sin(after * 60) * 8 * (1 - after / 0.6) end
    self.bigNum:ClearAllPoints()
    self.bigNum:SetPoint("TOP", dx, -140)
    if after > 1.4 then
        self.bigNum:SetFont(STANDARD_TEXT_FONT, 60, "THICKOUTLINE")
        self.anim = nil
        local hl = self.histList     -- scrolled back? stay on the same rolls now the new one is listed
        if a.bump and hl.offset > 0 then hl.offset = hl.offset + 1 end
        self:RefreshRoom()
    end
end

-- ---------------------------------------------------------------------
-- Events from the logic side
-- ---------------------------------------------------------------------
function V:OnChange(room, what, extra)
    if what == "new" and room.host ~= ns.me and (not room.target or room.target == ns.me) then
        self:Toast(room)
    end
    if what == "seated" and room.opponent == ns.me then
        self:ShowRoom(room.id)
    end
    if what == "roll" and self.roomId == room.id then
        -- scrolled back? stay on the same rolls instead of jumping to the newest
        local hl = self.histList
        if self:IsShown() then
            self.anim = { t0 = GetTime(), roll = extra.roll, max = extra.max, who = extra.who, bump = true }
        elseif hl and hl.offset > 0 then
            hl.offset = hl.offset + 1
        end
    end
    if what == "spectators" and self.roomId == room.id then self:RefreshSpectators() end
    if what == "opened" and room.host ~= ns.me then self:Toast(room, true) end
    if what == "declined" then
        if self.toast and self.toast.room == room and room.declinedBy == ns.me then self.toast:Hide() end
        if room.host == ns.me then
            ns.Print(("%s declined your death roll.  |H%s%s|h|cff4fc3f7[Open it to anyone]|r|h"):format(colored(room.declinedBy), LINK, room.id))
        end
    end
    if self:IsShown() then self:Refresh() end
end

-- ---------------------------------------------------------------------
-- Spectator panel (beside the game, in the standings' place)
-- ---------------------------------------------------------------------
local SPEC_ROWS, SPEC_ROW = 24, 18

function V:CreateSpectators(f)
    local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.Skin(p, C.panel, C.line)
    p:SetPoint("TOPLEFT", PLAY_W + 12, -14)
    p:SetPoint("RIGHT", -12, 0)
    p:EnableMouse(true)
    self.specPanel = p
    UI.Text(p, "GameFontNormalSmall", C.accent, "SPECTATORS", "TOPLEFT", 12, -10)
    self.specCount = UI.Text(p, "GameFontNormalSmall", C.muted, nil, "TOPRIGHT", -12, -10)
    self.specRows = {}
    for i = 1, SPEC_ROWS do
        local t = UI.Text(p, "GameFontHighlight", nil, nil, "TOPLEFT", 12, -30 - (i - 1) * SPEC_ROW)
        t:SetPoint("RIGHT", -10, 0); t:SetJustifyH("LEFT"); t:SetWordWrap(false)
        self.specRows[i] = t
    end
    self.specEmpty = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 12, -30)
    self.specEmpty:SetPoint("RIGHT", -10, 0); self.specEmpty:SetJustifyH("LEFT")
    f:HookScript("OnHide", function() DR:SetWatching(nil) end)
    p:Hide()
end


function V:RefreshSpectators()
    local p = self.specPanel
    if not p then return end
    local room = self.view == "room" and DR.rooms[self.roomId or ""]
    p:SetShown(room and true or false)
    if not room then return end
    local list, total = DR:SpectatorNames(room)
    self.specCount:SetText(total > 0 and total or "")
    for i, t in ipairs(self.specRows) do
        local n = list[i]
        if n and i == SPEC_ROWS and total > SPEC_ROWS then
            t:SetText(("|cff8a8f9c+%d more|r"):format(total - SPEC_ROWS + 1))
        elseif n then
            t:SetText(colored(n) .. (n == ns.me and " |cff8a8f9c(you)|r" or ""))
        else
            t:SetText("")
        end
    end
    if total > #list and #list < SPEC_ROWS then
        self.specRows[#list + 1]:SetText(("|cff8a8f9c+%d more|r"):format(total - #list))
    end
    if room.sim then
        self.specEmpty:SetText("Practice game - no spectators.")
    elseif total == 0 then
        self.specEmpty:SetText("No one watching yet. Guildmates in your group can watch from the chat link or the lobby.")
    else
        self.specEmpty:SetText("")
    end
    -- as tall as its names (or the note when nobody's watching)
    local shown = 0
    for _, t in ipairs(self.specRows) do if t:GetText() ~= "" then shown = shown + 1 end end
    local eh = self.specEmpty:GetStringHeight()
    p:SetHeight(30 + (shown > 0 and shown * SPEC_ROW or ((type(eh) == "number" and eh > 0) and eh or 42)) + 10)
end

-- ---------------------------------------------------------------------
-- Challenge pop-up + chat link
-- ---------------------------------------------------------------------
function V:CreateToast()
    local t = CreateFrame("Frame", "TitanUpDeathRollToast", UIParent, "BackdropTemplate")
    UI.Skin(t, C.bg, C.accent)
    t:SetSize(380, 74)
    t:SetPoint("TOP", 0, -140)
    t:SetFrameStrata("DIALOG")
    t:Hide()
    ns.Dock:Add(t)
    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "DeathRoll")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 12, 0)
    t.text = UI.Text(t, "GameFontHighlight", nil, nil, "TOPLEFT", icon, "TOPRIGHT", 10, 2)
    t.text:SetPoint("RIGHT", -10, 0)
    t.text:SetJustifyH("LEFT")
    t.join = UI.Button(t, 90, 22, "Join", nil, function()
        t:Hide()
        if t.room then DR:Join(t.room.id); V:ShowRoom(t.room.id) end
    end)
    t.join:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -6)
    t.watch = UI.Button(t, 70, 22, "Watch", nil, function()
        t:Hide()
        if t.room then t.room.watching = true; V:ShowRoom(t.room.id) end
    end)
    t.watch:SetPoint("LEFT", t.join, "RIGHT", 6, 0)
    t.decline = UI.Button(t, 70, 22, "Decline", "Turn it down - the challenger can then open it to anyone", function()
        t:Hide()
        if t.room then DR:Decline(t.room.id) end
    end)
    t.decline:SetPoint("LEFT", t.join, "RIGHT", 6, 0)
    t.close = UI.Button(t, 70, 22, "Dismiss", nil, function() t:Hide() end)
    t.close:SetPoint("LEFT", t.watch, "RIGHT", 6, 0)
    self.toast = t
end

function V:Toast(room, opened)
    if not self.toast then self:CreateToast() end
    local t = self.toast
    t.room = room
    local forMe = room.target == ns.me
    local who = forMe and "challenges you" or (opened and "opened their death roll to anyone" or "started a death roll")
    t.text:SetText(("%s %s for %s"):format(colored(room.host), who, fmtGold(room.wager)))
    -- a challenge meant for you: Join / Decline / Dismiss; otherwise Join / Watch / Dismiss
    t.decline:SetShown(forMe)
    t.watch:SetShown(not forMe)
    t.close:ClearAllPoints()
    t.close:SetPoint("LEFT", forMe and t.decline or t.watch, "RIGHT", 6, 0)
    t:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
    local token = {}
    t.token = token
    C_Timer.After(20, function() if t.token == token then t:Hide() end end)
    ns.Print(("%s %s for %s  |H%s%s|h|cff4fc3f7[Open death roll]|r|h"):format(colored(room.host), who, fmtGold(room.wager), LINK, room.id))
end

ns.RegisterModule({
    key = "deathroll", name = "Death Roll", icon = ns.MEDIA .. "DeathRoll", group = "games", order = 1,
    desc = "Challenge a guildmate - first to roll a 1 pays up.",
    view = V,
})
