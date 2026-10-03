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

local W, H = 460, 560
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

local function editBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    UI.Skin(e, C.canvas, C.line)
    e:SetSize(w, 26)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(9)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

local function section(parent, text, y)
    local t = UI.Text(parent, "GameFontNormalSmall", C.muted)
    t:SetPoint("TOPLEFT", 16, y)
    t:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    line:SetHeight(1)
    line:SetPoint("LEFT", t, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", -16, 0)
    return t
end

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
-- Built the first time it's needed (nothing at login).
function V:EnsureFrame()
    if not self.frame then self:Create() end
    return self.frame
end

function V:Init()
    DR = ns.DeathRoll
    local function onLink(link)
        if type(link) == "string" and link:find("^" .. LINK) then
            V:ShowRoom(link:sub(#LINK + 1))
        end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, V)
    end
    if SetItemRef then hooksecurefunc("SetItemRef", function(link) onLink(link) end) end
end

function V:IsShown() return self.frame and self.frame:IsShown() or false end
function V:Show() self:EnsureFrame():Show() end
function V:Toggle() if self:IsShown() then self.frame:Hide() else self:Show() end end

function V:Create()
    local f = CreateFrame("Frame", "TitanUpDeathRoll", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(W, H)
    f:SetPoint("CENTER", 200, 40)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Skin(f, C.bg, C.line)
    f:Hide()
    tinsert(UISpecialFrames, "TitanUpDeathRoll")
    f:SetScript("OnShow", function() V:Refresh() end)
    UI.Watermark(f, 400, 0.07, -30)

    local header = ns.Nav:CreateHeader(f, "deathroll", { title = "DEATH ROLL", icon = ns.MEDIA .. "DeathRoll" })
    self.header = header
    self.moduleBar = header.bar
    self.backBtn = UI.Button(header, 70, 22, "< Lobby", "Back to the lobby", function() V:ShowLobby() end)
    self.backBtn:SetPoint("RIGHT", header.bar, "LEFT", -8, 0)

    self.lobby = CreateFrame("Frame", nil, f)
    self.lobby:SetPoint("TOPLEFT", 0, -44)
    self.lobby:SetPoint("BOTTOMRIGHT")
    self.room = CreateFrame("Frame", nil, f)
    self.room:SetPoint("TOPLEFT", 0, -44)
    self.room:SetPoint("BOTTOMRIGHT")
    self.standings = CreateFrame("Frame", nil, f)
    self.standings:SetPoint("TOPLEFT", 0, -44)
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
    local wl = UI.Text(p, "GameFontHighlightSmall", C.muted)
    wl:SetPoint("TOPLEFT", 16, -30)
    wl:SetText("Wager (gold)")
    self.wager = editBox(p, 130)
    self.wager:SetPoint("TOPLEFT", 16, -46)
    self.wager:SetText("10000")
    local sl = UI.Text(p, "GameFontHighlightSmall", C.muted)
    sl:SetPoint("TOPLEFT", 160, -30)
    sl:SetText("First roll (blank = wager)")
    self.start = editBox(p, 130)
    self.start:SetPoint("TOPLEFT", 160, -46)
    local ol = UI.Text(p, "GameFontHighlightSmall", C.muted)
    ol:SetPoint("TOPLEFT", 304, -30)
    ol:SetText("Opponent")
    self.oppBtn = UI.Button(p, 140, 26, "Anyone", "Open to anyone in your group, or challenge one person", function() V:ShowOpponentMenu() end)
    self.oppBtn:SetPoint("TOPLEFT", 304, -46)

    self.announceBtn = UI.Button(p, 196, 24, "", "Post a line in party/raid chat when a challenge starts and when it ends", function()
        ns.udb.deathroll.announce = not ns.udb.deathroll.announce
        V:RefreshLobby()
    end)
    self.announceBtn:SetPoint("TOPLEFT", 16, -84)
    self.delayBtn = UI.Button(p, 196, 24, "", "While a game is rolling, its roll lines are held back from chat until the roll lands on screen, so chat can't spoil it. Normal /rolls are never touched.", function()
        ns.udb.deathroll.delayChat = not ns.udb.deathroll.delayChat
        DR:UpdateFilter()
        V:RefreshLobby()
    end)
    self.delayBtn:SetPoint("TOPLEFT", 16, -112)
    local create = UI.Button(p, 160, 28, "Create challenge", nil, function()
        local room = DR:Create(V.wager:GetText(), V.start:GetText(), V.target)
        if room then V:ShowRoom(room.id) end
    end)
    create:SetPoint("TOPRIGHT", -16, -82)
    UI.SetActive(create, true)
    local practice = UI.Button(p, 110, 22, "Practice solo", "Play against a fake opponent to try it out (/tu roll sim)", function()
        DR:StartSim(tonumber(V.wager:GetText()))
    end)
    practice:SetPoint("TOPRIGHT", create, "BOTTOMRIGHT", 0, -6)

    section(p, "OPEN CHALLENGES", -150)
    self.openRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(W - 32, 26)
        row:SetPoint("TOPLEFT", 16, -170 - (i - 1) * 30)
        row.text = UI.Text(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
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
    self.noOpen = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.noOpen:SetPoint("TOPLEFT", 20, -176)
    self.noOpen:SetText("No challenges in your group right now.")

    section(p, "YOUR RECORD", -330)
    local standingsBtn = UI.Button(p, 96, 22, "Standings", "Everyone's death roll totals, shared between Titan Up users when you group", function() V:ShowStandings() end)
    standingsBtn:SetPoint("TOPRIGHT", -16, -324)
    self.recordText = UI.Text(p, "GameFontNormal")
    self.recordText:SetPoint("TOPLEFT", 16, -352)
    self.debtRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(W - 32, 24)
        row:SetPoint("TOPLEFT", 16, -378 - (i - 1) * 28)
        row.text = UI.Text(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -90, 0)
        row.text:SetJustifyH("LEFT")
        row.paid = UI.Button(row, 82, 22, "Mark paid", "They paid you some other way (mail, etc.) - mark it settled. Trades are detected automatically. Only the winner can confirm a payment.", function()
            if row.entry then ns.DRLedger:MarkPaid(row.entry.id); V:RefreshLobby() end
        end)
        row.paid:SetPoint("RIGHT")
        self.debtRows[i] = row
    end
end

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
    self.oppBtn.label:SetText(V.target and ns.Short(V.target) or "Anyone")
    self.announceBtn.label:SetText(ns.udb.deathroll.announce and "Announce in chat: ON" or "Announce in chat: OFF")
    UI.SetActive(self.announceBtn, ns.udb.deathroll.announce)
    self.delayBtn.label:SetText(ns.udb.deathroll.delayChat and "Delay rolls in chat: ON" or "Delay rolls in chat: OFF")
    UI.SetActive(self.delayBtn, ns.udb.deathroll.delayChat)

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
            row.text:SetText(("%s   %s   |cff8a8f9c1-%s|r"):format(who, fmtGold(room.wager), DR.Fmt(room.start)))
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
                row.paid:Show()
            else
                local waiting = ((e.sent or 0) > (e.paid or 0)) and ("  |cff8a8f9c(sent " .. DR.Fmt(e.sent) .. " - waiting for them to confirm)|r") or partial
                row.text:SetText(("|cffff9f40You owe|r %s %s%s"):format(colored(e.w), fmtGold(owed), waiting))
                row.paid:Hide()          -- only the winner can confirm they were paid
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
    local note = UI.Text(p, "GameFontHighlightSmall", C.muted)
    note:SetPoint("TOPLEFT", 16, -24)
    note:SetText("Synced with your group and guild. Only games confirmed by both players count.")
    local function header(x, text, justify, w)
        local t = UI.Text(p, "GameFontHighlightSmall", C.muted)
        t:SetPoint("TOPLEFT", x, -42)
        t:SetWidth(w)
        t:SetJustifyH(justify)
        t:SetText(text)
    end
    header(20, "#  PLAYER", "LEFT", 150)
    header(176, "W-L", "CENTER", 60)
    header(240, "NET", "RIGHT", 100)
    header(344, "UNPAID", "RIGHT", 90)
    self.standList = scrollList(p, -58, 9, 20, function() V:RefreshStandings() end)
    for _, r in ipairs(self.standList.rows) do
        r.name = UI.Text(r, "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(150); r.name:SetJustifyH("LEFT")
        r.wl = UI.Text(r, "GameFontHighlightSmall"); r.wl:SetPoint("LEFT", 160, 0); r.wl:SetWidth(60); r.wl:SetJustifyH("CENTER")
        r.net = UI.Text(r, "GameFontHighlightSmall"); r.net:SetPoint("LEFT", 224, 0); r.net:SetWidth(100); r.net:SetJustifyH("RIGHT")
        r.unpaid = UI.Text(r, "GameFontHighlightSmall"); r.unpaid:SetPoint("LEFT", 328, 0); r.unpaid:SetWidth(90); r.unpaid:SetJustifyH("RIGHT")
    end
    self.standEmpty = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.standEmpty:SetPoint("TOPLEFT", 20, -64)
    self.standEmpty:SetText("No games yet - play one, or group with someone who has.")

    section(p, "RECENT GAMES", -260)
    self.gameList = scrollList(p, -280, 11, 20, function() V:RefreshStandings() end)
    for _, r in ipairs(self.gameList.rows) do
        r.text = UI.Text(r, "GameFontHighlightSmall"); r.text:SetPoint("LEFT", 0, 0); r.text:SetPoint("RIGHT", -110, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.tag = UI.Text(r, "GameFontHighlightSmall"); r.tag:SetPoint("RIGHT", 0, 0); r.tag:SetWidth(108); r.tag:SetJustifyH("RIGHT")
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

function V:ShowStandings()
    self:EnsureFrame()
    self.view = "standings"
    self.roomId = nil
    self.lobby:Hide()
    self.room:Hide()
    self.standings:Show()
    self.backBtn:Show()
    self:RefreshStandings()
end

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
    c.name = UI.Text(c, "GameFontNormalLarge")
    c.name:SetPoint("TOP", 0, -12)
    c.status = UI.Text(c, "GameFontHighlightSmall", C.muted)
    c.status:SetPoint("TOP", c.name, "BOTTOM", 0, -6)
    return c
end

function V:CreateRoom(p)
    self.wagerText = UI.Text(p, "GameFontNormalLarge")
    self.wagerText:SetPoint("TOP", 0, -6)
    self.subText = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.subText:SetPoint("TOP", self.wagerText, "BOTTOM", 0, -4)

    self.cardA = playerCard(p, 20)
    self.cardB = playerCard(p, W - 220)
    local vs = UI.Text(p, "GameFontNormal", C.muted)
    vs:SetPoint("TOP", 0, -78)
    vs:SetText("VS")

    -- The big number
    self.bigNum = p:CreateFontString(nil, "OVERLAY")
    self.bigNum:SetFont(STANDARD_TEXT_FONT, 60, "THICKOUTLINE")
    self.bigNum:SetPoint("TOP", 0, -140)
    self.bigNum:SetTextColor(1, 0.85, 0.3)
    self.bigLabel = UI.Text(p, "GameFontHighlight", C.muted)
    self.bigLabel:SetPoint("TOP", self.bigNum, "BOTTOM", 0, -6)

    self.action = UI.Button(p, 260, 40, "", nil, function() V:OnAction() end)
    self.action:SetPoint("TOP", 0, -248)
    self.action.label:SetFontObject("GameFontNormalLarge")
    self.secondary = UI.Button(p, 120, 24, "Cancel", nil, function() V:OnSecondary() end)
    self.secondary:SetPoint("TOP", self.action, "BOTTOM", -64, -8)
    self.tertiary = UI.Button(p, 120, 24, "", nil, function() V:OnTertiary() end)
    self.tertiary:SetPoint("TOP", self.action, "BOTTOM", 64, -8)

    self.warning = UI.Text(p, "GameFontHighlightSmall", C.warn)
    self.warning:SetPoint("TOP", 0, -330)

    section(p, "ROLLS", -350)
    self.histCount = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.histCount:SetPoint("TOPRIGHT", -24, -350)
    -- scrollable roll list (mouse wheel), newest first
    local area = CreateFrame("Frame", nil, p)
    area:SetPoint("TOPLEFT", 16, -366)
    area:SetPoint("RIGHT", -16, 0)
    area:SetHeight(7 * 18 + 4)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta) V:ScrollHistory(-delta) end)
    self.histArea = area
    self.histOffset = 0
    self.histRows = {}
    for i = 1, 7 do
        local t = UI.Text(area, "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", 8, -4 - (i - 1) * 18)
        t:SetPoint("RIGHT", -14, 0)
        t:SetJustifyH("LEFT")
        self.histRows[i] = t
    end
    local track = area:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", -4, -4)
    track:SetPoint("BOTTOMRIGHT", -4, 2)
    self.histTrack = track
    local thumb = area:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    thumb:SetWidth(3)
    self.histThumb = thumb

    -- roll animation driver
    p:SetScript("OnUpdate", function() V:Animate() end)
end

function V:ShowLobby()
    self:EnsureFrame()
    self.roomId = nil
    self.view = "lobby"
    self.room:Hide()
    self.standings:Hide()
    self.lobby:Show()
    self.backBtn:Hide()
    self:RefreshLobby()
end

function V:ShowRoom(id)
    if not DR.rooms[id] then
        ns.Print("That death roll isn't available any more.")
        return
    end
    if self.roomId ~= id then self.histOffset = 0 end
    self:EnsureFrame()
    self.roomId = id
    self.view = "room"
    self.anim = nil
    self.lobby:Hide()
    self.standings:Hide()
    self.room:Show()
    self.backBtn:Show()
    if not self.frame:IsShown() then self.frame:Show() end
    self:RefreshRoom()
end

function V:Refresh()
    if not self.frame then return end
    if self.view == "standings" then self:RefreshStandings()
    elseif self.roomId then self:RefreshRoom()
    else self:RefreshLobby() end
end

local function cardState(card, room, name, isTurn)
    if not name then
        card.name:SetText("|cff8a8f9c" .. (room.target and ns.Short(room.target) or "Open seat") .. "|r")
        card.status:SetText(room.target and "invited" or "waiting for someone to join")
        UI.Skin(card, C.panel, C.line)
        return
    end
    card.name:SetText(colored(name) .. (name == ns.me and " |cff8a8f9c(you)|r" or ""))
    local status
    if room.state == "done" then
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
    local room = DR.rooms[self.roomId or ""]
    if not room then return self:ShowLobby() end
    local me = ns.me
    local mine = DR:IsPlayer(room, me)
    self.wagerText:SetText(fmtGold(room.wager))
    self.subText:SetText("First roll 1-" .. DR.Fmt(room.start) .. " - whoever rolls a 1 loses")
    cardState(self.cardA, room, room.host, room.turn == room.host)
    cardState(self.cardB, room, room.opponent, room.opponent ~= nil and room.turn == room.opponent)

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
            self.bigLabel:SetText(room.state == "open" and "Waiting for an opponent..." or "Waiting for both players to accept")
        end
    end

    -- buttons
    local action, actionOn, secondary, tertiary = nil, false, nil, nil
    if room.state == "open" then
        if room.host == me then
            action, secondary = "Waiting for opponent...", "Cancel"
        elseif not room.target or room.target == me then
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
        if DR:Paused() and mine then
            action = "Paused - in combat"
        elseif room.turn == me then
            action, actionOn = "ROLL  1-" .. DR.Fmt(room.max), not (room.pendingRoll and GetTime() - room.pendingRoll < 4)
        else
            action = ns.Short(room.turn) .. "'s turn"
        end
        if mine then secondary = "Cancel game" end
    elseif room.state == "done" then
        if mine then
            action, actionOn = "Rematch", true
            if room.loser == me and not room.sim then tertiary = "Open trade" end
        else
            action = "Game over"
        end
        secondary = "Lobby"
    else
        action, secondary = "Back to lobby", nil
        actionOn = true
    end
    self.action.label:SetText(action or "")
    UI.SetDisabled(self.action, not actionOn)
    UI.SetActive(self.action, actionOn)
    self.secondary:SetShown(secondary ~= nil)
    self.secondary.label:SetText(secondary or "")
    self.tertiary:SetShown(tertiary ~= nil)
    self.tertiary.label:SetText(tertiary or "")
    self.warning:SetText(room.warning or "")

    -- history, newest first, scrolled by histOffset
    local total, rows = #room.rolls, #self.histRows
    local maxOff = math.max(0, total - rows)
    self.histOffset = math.max(0, math.min(maxOff, self.histOffset or 0))
    local off = self.histOffset
    if total > rows then
        self.histCount:SetText(("showing %d-%d of %d  (scroll)"):format(off + 1, math.min(total, off + rows), total))
        self.histTrack:Show()
        self.histThumb:Show()
        local trackH = rows * 18 - 2
        local thumbH = math.max(12, trackH * rows / total)
        local pos = (maxOff > 0) and (off / maxOff) or 0
        self.histThumb:SetHeight(thumbH)
        self.histThumb:ClearAllPoints()
        self.histThumb:SetPoint("TOPRIGHT", self.histArea, "TOPRIGHT", -4, -4 - (trackH - thumbH) * pos)
    else
        self.histCount:SetText(total > 0 and (total .. (total == 1 and " roll" or " rolls")) or "")
        self.histTrack:Hide()
        self.histThumb:Hide()
    end
    for i, t in ipairs(self.histRows) do
        local r = room.rolls[total - off - i + 1]
        if r then
            local hit = r.roll == 1 and "|cffff5a5a1|r" or ("|cffffd94d" .. DR.Fmt(r.roll) .. "|r")
            t:SetText(("%d.  %s rolled %s  |cff8a8f9c(1-%s)|r"):format(total - off - i + 1, colored(r.who), hit, DR.Fmt(r.max)))
        else
            t:SetText("")
        end
    end
end

function V:ScrollHistory(delta)
    self.histOffset = (self.histOffset or 0) + delta
    self:RefreshRoom()
end

function V:OnAction()
    local room = DR.rooms[self.roomId or ""]
    if not room then return self:ShowLobby() end
    if room.state == "open" then
        DR:Join(room.id)
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
        if (self.histOffset or 0) > 0 then self.histOffset = self.histOffset + 1 end
        if self:IsShown() then
            self.anim = { t0 = GetTime(), roll = extra.roll, max = extra.max, who = extra.who }
        end
    end
    if self:IsShown() then self:Refresh() end
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
    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "DeathRoll")
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 12, 0)
    t.text = UI.Text(t, "GameFontHighlight")
    t.text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 2)
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
    t.close = UI.Button(t, 70, 22, "Dismiss", nil, function() t:Hide() end)
    t.close:SetPoint("LEFT", t.watch, "RIGHT", 6, 0)
    self.toast = t
end

function V:Toast(room)
    if not self.toast then self:CreateToast() end
    local t = self.toast
    t.room = room
    local who = room.target == ns.me and "challenges you" or "started a death roll"
    t.text:SetText(("%s %s for %s"):format(colored(room.host), who, fmtGold(room.wager)))
    t:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
    local token = {}
    t.token = token
    C_Timer.After(20, function() if t.token == token then t:Hide() end end)
    ns.Print(("%s %s for %s  |H%s%s|h|cff4fc3f7[Open death roll]|r|h"):format(colored(room.host), who, fmtGold(room.wager), LINK, room.id))
end

ns.RegisterModule({
    key = "deathroll", name = "Death Roll", icon = ns.MEDIA .. "DeathRoll", group = "games", order = 1,
    desc = "Challenge a guildmate to a death roll. First to roll a 1 pays up.",
    show = function() V:Show() end,
    hide = function() if V.frame then V.frame:Hide() end end,
    isShown = function() return V:IsShown() end,
    frame = function() return V.frame end,
})
