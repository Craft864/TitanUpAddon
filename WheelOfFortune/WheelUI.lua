-- Titan Up - WheelOfFortune/WheelUI.lua
-- Lobby (host setup + open games) and the game view: puzzle board, the
-- spinning wheel, three player cards, letter buttons, and host controls.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local WF

local V = {}
ns.WheelUI = V

local W, H = 820, 610          -- the game screen
local LOBBY_W = 660             -- the setup screen (height fits its content)
local TILE_W, TILE_H, TILE_GAP = 38, 46, 3
local WHEEL = 250

local function money(n) return "$" .. ns.DeathRoll.Fmt(n or 0) end

local colored = UI.Named
local function textBox(parent, w, maxLetters) return UI.EditBox(parent, w, 24, { inset = 6, max = maxLetters or 60 }) end

-- ---------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------
-- Built the first time it's needed (nothing at login).
function V:Init()
    WF = ns.Wheel
    local LINK = "addon:TitanUp:wof:"
    self.LINK = LINK
    local function onLink(link)
        if type(link) == "string" and link:find("^" .. LINK) then
            local id = link:sub(#LINK + 1)
            if WF.games[id] then WF:Watch(id); V:ShowGame(id) end
        end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, V)
    end
    if SetItemRef then hooksecurefunc("SetItemRef", function(link) onLink(link) end) end
end

function V:Create()
    local f, header = ns.Nav:Window(self, "TitanUpWheel", "wheel", "WHEEL OF FORTUNE", W, H, { y = 20, mark = { 480, 0.05, -40 } })
    self.backBtn = UI.Button(header, 70, 22, "< Lobby", "Back to the lobby", function() V:ShowLobby() end)
    self.backBtn:SetPoint("RIGHT", header.close, "LEFT", -8, 0)

    self.lobby = CreateFrame("Frame", nil, f)
    self.lobby:SetPoint("TOPLEFT", 0, -6)
    self.lobby:SetPoint("BOTTOMRIGHT")
    self.game = CreateFrame("Frame", nil, f)
    self.game:SetPoint("TOPLEFT", 0, -6)
    self.game:SetPoint("BOTTOMRIGHT")
    self:CreateLobby(self.lobby)
    self:CreateGame(self.game)
    self:ShowLobby()
end

-- ---------------------------------------------------------------------
-- Lobby
-- ---------------------------------------------------------------------
function V:CreateLobby(p)
    -- two ways to play: everyone plays (no host), or a host runs it
    self.mode = "play"
    self.modeBtns = {}
    for i, m in ipairs({ { "play", "Play together", "Everyone plays - including you. Random puzzles; nobody sees the answer." },
                         { "host", "Host a game", "You write the puzzles (and a prize), watch, and run it; 3 players take the seats." } }) do
        local b = UI.Button(p, 116, 24, m[2], m[3], function() V.mode = m[1]; V:LayoutLobby(); V:RefreshLobby() end)
        b:SetPoint("TOPLEFT", 16 + (i - 1) * 120, -6)
        self.modeBtns[m[1]] = b
    end
    self.help = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 16, -34)

    -- ready-made puzzles: theme dropdown + Fill all, on the heading line
    self.themeIndex = 1
    local fill = UI.Button(p, 70, 22, "Fill all", "Fill every round shown with a different random puzzle", function()
        local taken = {}
        for i = 1, V.roundCount do
            local row = V.setupRows[i]
            local pz = WF.RandomPuzzle(V:Theme(), taken)
            if pz then
                row.cat:SetText(pz[1]); row.phrase:SetText(pz[2])
                taken[pz[2]] = true
            end
        end
    end)
    fill:SetPoint("TOPRIGHT", -40, -6)           -- clear of the X
    self.fillBtn = fill
    self.themeBtn = UI.Button(p, 160, 22, "", "Which ready-made puzzles the dice and Fill all pick from", function() V:ThemeMenu() end)
    self.themeBtn:SetPoint("RIGHT", fill, "LEFT", -6, 0)
    self.themeBtn.label:ClearAllPoints()
    self.themeBtn.label:SetPoint("LEFT", 8, 0)
    local arrow = self.themeBtn:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ns.MEDIA .. "Down")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    self:RefreshTheme()

    local cl = UI.Text(p, "GameFontHighlightSmall", C.muted, "Category", "TOPLEFT", 40, -50)
    local pl = UI.Text(p, "GameFontHighlightSmall", C.muted, "Puzzle", "TOPLEFT", 188, -50)
    self.catLabel, self.puzLabel = cl, pl
    -- rounds: only as many rows as you've added (1-5); X removes a round
    self.setupRows = {}
    for i = 1, WF.MAX_ROUNDS do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(LOBBY_W - 32, 26)
        row:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 30)
        UI.Text(row, "GameFontNormal", C.muted, i .. ".", "LEFT", 0, 0)
        row.cat = textBox(row, 140, 24); row.cat:SetPoint("LEFT", 22, 0)
        row.phrase = textBox(row, 396, 56); row.phrase:SetPoint("LEFT", row.cat, "RIGHT", 10, 0)
        row.random = UI.IconButton(row, 24, ns.MEDIA .. "Dice", "Random puzzle for this round (from the theme picked above)", function()
            local pz = WF.RandomPuzzle(V:Theme(), V:TakenPhrases(row))
            if pz then row.cat:SetText(pz[1]); row.phrase:SetText(pz[2]) end
        end)
        row.random.keepIconColor = true
        row.random:SetPoint("LEFT", row.phrase, "RIGHT", 8, 0)
        row.clear = UI.Button(row, 24, 24, "X", "Remove this round", function() V:RemoveRound(i) end)
        row.clear:SetPoint("LEFT", row.random, "RIGHT", 4, 0)
        self.setupRows[i] = row
    end
    self.setupRows[1].cat:SetText("PHRASE")
    self.addRound = UI.Button(p, 110, 22, "+ Add round", "Add another round (up to " .. WF.MAX_ROUNDS .. ")", function() V:AddRound() end)
    self.roundCount = 1
    self:LayoutRounds()

    -- Host: an optional prize (a number shows as gold)
    self.prizeLabel = UI.Text(p, "GameFontHighlight", C.text, "Prize")
    self.prizeBox = textBox(p, 300, 48)
    self.prizeHint = UI.Text(p, "GameFontHighlightSmall", C.muted, "optional - a number shows as gold, e.g. 10000")
    -- Play together: how many rounds
    self.playRounds = 3
    self.playLabel = UI.Text(p, "GameFontHighlight", C.text, "Rounds")
    self.playMinus = UI.Button(p, 24, 24, "-", nil, function() V.playRounds = math.max(1, V.playRounds - 1); V:RefreshLobby() end)
    self.playValue = UI.Text(p, "GameFontNormalLarge", C.text)
    self.playPlus = UI.Button(p, 24, 24, "+", nil, function() V.playRounds = math.min(WF.MAX_ROUNDS, V.playRounds + 1); V:RefreshLobby() end)

    local open = UI.Button(p, 180, 32, "Open game", "Post the game to your group so players can take seats", function()
        local g
        if V.mode == "play" then
            g = WF:Play(V.playRounds, V:Theme())
        else
            local list = {}
            for i = 1, V.roundCount do
                local row = V.setupRows[i]
                if row.phrase:GetText() ~= "" then list[#list + 1] = { row.cat:GetText(), row.phrase:GetText() } end
            end
            g = WF:Host(list, V.prizeBox:GetText())
        end
        if g then V:ShowGame(g.id) end
    end)
    open:SetPoint("TOP", 0, -248)
    UI.SetActive(open, true)
    local solo = UI.Button(p, 120, 22, "Play solo", "Play against two bots, with a bot host (/tu wheel sim)", function()
        local g = WF:StartSim()
        if g then V:ShowGame(g.id) end
    end)
    solo:SetPoint("TOP", open, "BOTTOM", 0, -6)
    self.openBtn, self.soloBtn = open, solo

    self.openHeading = UI.Text(p, "GameFontNormalSmall", C.muted, "OPEN GAMES IN YOUR GROUP", "TOPLEFT", 16, -326)
    self.openRows = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(LOBBY_W - 32, 28)
        row.text = UI.Text(row, "GameFontHighlight", nil, nil, "LEFT", 4, 0)
        row.join = UI.Button(row, 90, 24, "Take a seat", nil, function() if row.g then WF:Join(row.g.id); V:ShowGame(row.g.id) end end)
        row.join:SetPoint("RIGHT", -84, 0)
        row.watch = UI.Button(row, 76, 24, "Watch", nil, function() if row.g then WF:Watch(row.g.id); V:ShowGame(row.g.id) end end)
        row.watch:SetPoint("RIGHT", 0, 0)
        self.openRows[i] = row
    end
    self.noGames = UI.Text(p, "GameFontHighlightSmall", C.muted, "No games right now - host one above.", "TOPLEFT", 20, -352)
end

function V:Theme() return WF.THEMES[self.themeIndex or 1].key end

function V:RefreshTheme()
    self.themeBtn.label:SetText("Random from: " .. WF.THEMES[self.themeIndex or 1].label)
end

function V:ThemeMenu()
    local items = {}
    for i, t in ipairs(WF.THEMES) do
        items[#items + 1] = { text = t.label, checked = (self.themeIndex or 1) == i, onClick = function()
            V.themeIndex = i
            V:RefreshTheme()
        end }
    end
    UI.Menu(self.themeBtn, items)
end

-- Show rows 1..roundCount; "+ Add round" sits under the last one.
function V:LayoutRounds()
    for i, row in ipairs(self.setupRows) do row:SetShown(self.mode == "host" and i <= self.roundCount) end
    self.addRound:ClearAllPoints()
    self.addRound:SetPoint("TOPLEFT", 38, -64 - self.roundCount * 30 - 2)
    self.addRound:SetShown(self.roundCount < WF.MAX_ROUNDS)
    self:LayoutLobby()
end

-- Resize a window while keeping its top-center (the tab) where it is.
local resizeKeepCorner = UI.ResizeKeepTab
V.ResizeKeepCorner = resizeKeepCorner

-- The setup screen grows with its content: rounds, the buttons, and as
-- many open-game rows as there are games.
function V:LayoutLobby()
    if not self.openBtn then return end
    local host = self.mode == "host"
    for key, b in pairs(self.modeBtns) do UI.SetActive(b, key == self.mode) end
    self.help:SetText(host and "You write the puzzles and watch - 3 players take the seats."
        or "Everyone plays, including you. Random puzzles - nobody sees the answer.")
    self.fillBtn:SetShown(host)
    self.catLabel:SetShown(host); self.puzLabel:SetShown(host)
    for i, row in ipairs(self.setupRows) do row:SetShown(host and i <= self.roundCount) end
    self.addRound:SetShown(host and self.roundCount < WF.MAX_ROUNDS)
    for _, w in ipairs({ self.prizeLabel, self.prizeBox, self.prizeHint }) do w:SetShown(host) end
    for _, w in ipairs({ self.playLabel, self.playMinus, self.playValue, self.playPlus }) do w:SetShown(not host) end
    self.openBtn.label:SetText(host and "Open game" or "Start a game")
    local y
    if host then
        y = -64 - self.roundCount * 30
        y = y - (self.roundCount < WF.MAX_ROUNDS and 30 or 6)          -- + Add round
        self.prizeLabel:ClearAllPoints(); self.prizeLabel:SetPoint("TOPLEFT", 38, y - 4)
        self.prizeBox:ClearAllPoints(); self.prizeBox:SetPoint("TOPLEFT", 90, y)
        self.prizeHint:ClearAllPoints(); self.prizeHint:SetPoint("LEFT", self.prizeBox, "RIGHT", 8, 0)
        y = y - 32
    else
        self.playLabel:ClearAllPoints(); self.playLabel:SetPoint("TOPLEFT", 38, -64)
        self.playMinus:ClearAllPoints(); self.playMinus:SetPoint("TOPLEFT", 110, -60)
        self.playValue:ClearAllPoints(); self.playValue:SetPoint("LEFT", self.playMinus, "RIGHT", 12, 0)
        self.playPlus:ClearAllPoints(); self.playPlus:SetPoint("LEFT", self.playMinus, "RIGHT", 40, 0)
        y = -96
    end
    self.openBtn:ClearAllPoints()
    self.openBtn:SetPoint("TOP", 0, y - 12)
    y = y - 12 - 32 - 6 - 22                                         -- Open game + Play solo
    self.openHeading:ClearAllPoints()
    self.openHeading:SetPoint("TOPLEFT", 16, y - 20)
    local listTop = y - 40
    local shown = 0
    for i, row in ipairs(self.openRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, listTop - (i - 1) * 32)
        if row:IsShown() then shown = shown + 1 end
    end
    self.noGames:ClearAllPoints()
    self.noGames:SetPoint("TOPLEFT", 20, listTop - 6)
    local listH = math.max(1, shown) * 32
    local height = 6 - listTop + listH + 12
    if not self.gameId then resizeKeepCorner(self.frame, LOBBY_W, height) end
end

function V:AddRound()
    if self.roundCount >= WF.MAX_ROUNDS then return end
    self.roundCount = self.roundCount + 1
    local row = self.setupRows[self.roundCount]
    row.cat:SetText(""); row.phrase:SetText("")
    self:LayoutRounds()
end

-- Remove a round: the rounds below move up. The last remaining round just clears.
function V:RemoveRound(i)
    local rows = self.setupRows
    if self.roundCount <= 1 then
        rows[1].cat:SetText(""); rows[1].phrase:SetText("")
        return
    end
    for k = i, self.roundCount - 1 do
        rows[k].cat:SetText(rows[k + 1].cat:GetText())
        rows[k].phrase:SetText(rows[k + 1].phrase:GetText())
    end
    local last = rows[self.roundCount]
    last.cat:SetText(""); last.phrase:SetText("")
    self.roundCount = self.roundCount - 1
    self:LayoutRounds()
end

-- Phrases already used in the other rounds (so Random doesn't repeat them).
function V:TakenPhrases(except)
    local taken = {}
    for i = 1, self.roundCount or #self.setupRows do
        local row = self.setupRows[i]
        if row ~= except then
            local t = WF.Clean(row.phrase:GetText(), 56)
            if t ~= "" then taken[t] = true end
        end
    end
    return taken
end

function V:RefreshLobby()
    local list = {}
    for _, g in pairs(WF.games) do
        if g.state ~= "cancelled" and g.state ~= "over" then list[#list + 1] = g end
    end
    table.sort(list, function(a, b) return a.created > b.created end)
    for i, row in ipairs(self.openRows) do
        local g = list[i]
        row.g = g
        row:SetShown(g ~= nil)
        if g then
            local status = g.state == "lobby" and ("%d/%d seats"):format(#g.seats, WF.SEATS) or ("round %d of %d"):format(g.round, g.rounds)
            local prize = WF.PrizeText(g.prize)
            row.text:SetText(("%s's game  |cff8a8f9c%d round%s - %s - %s|r%s"):format(colored(g.host), g.rounds, g.rounds == 1 and "" or "s", status,
                g.auto and "everyone plays" or "hosted", prize and ("  |cffffd94dPrize: " .. prize .. "|r") or ""))
            row.join:SetShown(g.state == "lobby" and #g.seats < WF.SEATS and g.host ~= ns.me and not WF.SeatOf(g, ns.me))
        end
    end
    self.noGames:SetShown(#list == 0)
    if self.playValue then self.playValue:SetText(tostring(self.playRounds)) end
    self:LayoutLobby()
end

-- ---------------------------------------------------------------------
-- Game view
-- ---------------------------------------------------------------------
function V:CreateGame(p)
    self.catText = UI.Text(p, "GameFontNormalLarge", C.accent, nil, "TOP", 0, -4)
    self.roundText = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.roundText:SetPoint("TOPLEFT", 16, -8)     -- "< Lobby" and the X are top-right
    -- left gutter (beside the board): the prize and the turn countdown
    self.prizeText = UI.Text(p, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 16, -26)
    self.prizeText:SetWidth(92); self.prizeText:SetJustifyH("LEFT")
    self.timerLabel = UI.Text(p, "GameFontHighlightSmall", C.muted, "Turn timer", "TOPLEFT", 16, -96)
    self.timerText = UI.Text(p, "GameFontNormalHuge", C.text, nil, "TOPLEFT", self.timerLabel, "BOTTOMLEFT", 0, -4)

    -- puzzle board
    local boardW = WF.COLS * (TILE_W + TILE_GAP) - TILE_GAP
    local board = CreateFrame("Frame", nil, p, "BackdropTemplate")
    UI.Skin(board, { 0.03, 0.10, 0.07, 1 }, { 0.75, 0.62, 0.25, 1 })
    board:SetSize(boardW + 16, WF.ROWS * (TILE_H + TILE_GAP) - TILE_GAP + 16)
    board:SetPoint("TOP", 0, -26)
    self.board = board
    self.tiles = {}
    for r = 1, WF.ROWS do
        for c = 1, WF.COLS do
            local t = CreateFrame("Frame", nil, board)
            t:SetSize(TILE_W, TILE_H)
            t:SetPoint("TOPLEFT", 8 + (c - 1) * (TILE_W + TILE_GAP), -8 - (r - 1) * (TILE_H + TILE_GAP))
            t.bg = t:CreateTexture(nil, "BACKGROUND")
            t.bg:SetAllPoints()
            t.letter = t:CreateFontString(nil, "OVERLAY")
            t.letter:SetFont(STANDARD_TEXT_FONT, 26, "")
            t.letter:SetPoint("CENTER", 0, -1)
            t.letter:SetTextColor(0.08, 0.08, 0.1)
            t.state = {}           -- plain table: used, ch, flash
            self.tiles[(r - 1) * WF.COLS + c] = t
        end
    end

    -- the wheel
    local wheelFrame = CreateFrame("Frame", nil, p)
    wheelFrame:SetSize(WHEEL, WHEEL)
    wheelFrame:SetPoint("TOPLEFT", 24, -262)
    self.wheel = wheelFrame:CreateTexture(nil, "ARTWORK")
    self.wheel:SetTexture(ns.MEDIA .. "Wheel")
    self.wheel:SetAllPoints()
    local pointer = wheelFrame:CreateTexture(nil, "OVERLAY")
    pointer:SetTexture(ns.MEDIA .. "WheelPointer")
    pointer:SetSize(30, 30)
    pointer:SetPoint("BOTTOM", wheelFrame, "TOP", 0, -14)
    self.wheelRot = 0
    self.wedgeText = UI.Text(p, "GameFontNormalLarge", nil, nil, "TOP", wheelFrame, "BOTTOM", 0, -6)

    -- player cards
    self.cards = {}
    for i = 1, WF.SEATS do
        local c = CreateFrame("Frame", nil, p, "BackdropTemplate")
        UI.Skin(c, C.panel, C.line)
        c:SetSize(166, 72)
        c:SetPoint("TOPLEFT", 300 + (i - 1) * 172, -262)
        c.name = UI.Text(c, "GameFontNormal", nil, nil, "TOP", 0, -8)
        c.round = UI.Text(c, "GameFontNormalLarge", nil, nil, "TOP", c.name, "BOTTOM", 0, -4)
        c.total = UI.Text(c, "GameFontHighlightSmall", C.muted, nil, "TOP", c.round, "BOTTOM", 0, -3)
        self.cards[i] = c
    end

    self.status = UI.Text(p, "GameFontHighlightLarge", nil, nil, "TOPLEFT", 300, -346)
    self.status:SetWidth(500)
    self.status:SetJustifyH("LEFT")

    -- main actions
    self.spinBtn = UI.Button(p, 120, 34, "SPIN", "Spin the wheel", function() WF:Act("spin") end)
    self.spinBtn:SetPoint("TOPLEFT", 300, -376)
    self.spinBtn.label:SetFontObject("GameFontNormalLarge")
    self.solveBtn = UI.Button(p, 120, 34, "SOLVE", "Type the whole puzzle", function()
        UI.Prompt({ title = "Solve the puzzle", help = "Type the whole answer. Wrong answers pass the turn.", accept = "Solve",
            onAccept = function(text) WF:Act("solve", text) end })
    end)
    self.solveBtn:SetPoint("LEFT", self.spinBtn, "RIGHT", 8, 0)
    self.solveBtn.label:SetFontObject("GameFontNormalLarge")
    self.vowelHint = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "LEFT", self.solveBtn, "RIGHT", 12, 0)

    -- letters: consonants (after a spin) and vowels ($250)
    self.letterBtns = {}
    local function letterButton(ch, x, y, tip)
        local b = UI.Button(p, 32, 28, ch, tip, function()
            WF:Act(WF.VOWELS:find(ch, 1, true) and "vowel" or "letter", ch)
        end)
        b:SetPoint("TOPLEFT", x, y)
        b.label:SetFontObject("GameFontNormal")
        self.letterBtns[ch] = b
    end
    local i = 0
    for ch in WF.CONSONANTS:gmatch(".") do
        local row, col = math.floor(i / 11), i % 11
        letterButton(ch, 300 + col * 35, -420 - row * 32, "Call " .. ch)
        i = i + 1
    end
    UI.Text(p, "GameFontHighlightSmall", C.muted, "BUY A VOWEL  $250", "TOPLEFT", 300, -490)
    i = 0
    for ch in WF.VOWELS:gmatch(".") do
        letterButton(ch, 420 + i * 35, -484, "Buy " .. ch .. " for $250")
        i = i + 1
    end

    -- seat / lobby controls
    self.seatBtn = UI.Button(p, 140, 30, "Take a seat", nil, function()
        local g = V:Game()
        if not g then return end
        if WF.SeatOf(g, ns.me) then WF:Leave(g.id) else WF:Join(g.id) end
    end)
    self.seatBtn:SetPoint("TOPLEFT", 300, -376)

    -- host panel
    local hp = CreateFrame("Frame", nil, p, "BackdropTemplate")
    UI.Skin(hp, C.panel, C.accentDim)
    hp:SetSize(W - 48, 66)
    hp:SetPoint("BOTTOM", 0, 10)
    self.hostPanel = hp
    UI.Text(hp, "GameFontNormalSmall", C.accent, "HOST  (only you can see this)", "TOPLEFT", 10, -8)
    self.answerText = UI.Text(hp, "GameFontHighlight", nil, nil, "TOPLEFT", 10, -26)
    self.answerText:SetWidth(440)
    self.answerText:SetJustifyH("LEFT")
    self.hostStart = UI.Button(hp, 100, 26, "Start game", nil, function() WF:Start() end)
    self.hostNext = UI.Button(hp, 100, 26, "Next round", nil, function() WF:HostNextRound() end)
    self.hostSkip = UI.Button(hp, 90, 26, "Skip turn", "Move on if someone's AFK", function() WF:HostSkip() end)
    self.hostEnd = UI.Button(hp, 90, 26, "End game", nil, function()
        UI.Prompt({ title = "End the game?", noInput = true, accept = "End game", help = "Closes the game for everyone.",
            onAccept = function() WF:HostEnd() end })
    end)
    self.hostEnd:SetPoint("RIGHT", -10, -6)
    self.hostSkip:SetPoint("RIGHT", self.hostEnd, "LEFT", -6, 0)
    self.hostNext:SetPoint("RIGHT", self.hostSkip, "LEFT", -6, 0)
    self.hostStart:SetPoint("RIGHT", self.hostNext, "LEFT", -6, 0)

    p:SetScript("OnUpdate", function() V:Animate() end)
end

function V:Game() return WF.games[self.gameId or ""] end

function V:ShowLobby()
    self:EnsureFrame()
    self.gameId = nil
    self.game:Hide()
    self.lobby:Show()
    self.backBtn:Hide()
    self:RefreshLobby()
end

function V:ShowGame(id)
    if not WF.games[id] then return end
    self:EnsureFrame()
    if self.gameId ~= id then
        self.prevMask = nil
        self.spinAnim = nil          -- a spin from another game doesn't block this one
    end
    self.gameId = id
    WF.current = id
    self.lobby:Hide()
    self.game:Show()
    self.backBtn:Show()
    V.ResizeKeepCorner(self.frame, W, H)          -- the game screen keeps its full size
    if not self.frame:IsShown() then self.frame:Show() end
    self:RefreshGame()
end

function V:Refresh()
    if not self.frame then return end
    if self.gameId then self:RefreshGame() else self:RefreshLobby() end
end

-- Messages from the referee, in words.
function V:StatusText(g)
    local who = colored(g.seats[g.turn])
    local m, a = g.msg, g.arg or ""
    if g.state == "lobby" then return ("Waiting for players (%d/%d)..."):format(#g.seats, WF.SEATS) end
    if g.state == "cancelled" then return "The game was closed." end
    if m == "solved" then
        local seat, win = a:match("^(%d+):(%d+)$")
        local text = ("%s solved it and banks %s!"):format(colored(g.seats[tonumber(seat) or 0]), money(tonumber(win)))
        if g.state == "over" then
            local best, bi = -1, 1
            for i = 1, #g.seats do if (g.total[i] or 0) > best then best, bi = g.total[i] or 0, i end end
            local prize = WF.PrizeText(g.prize)
            text = text .. ("\n|cffffd94d%s wins the game with %s!|r"):format(colored(g.seats[bi]), money(best))
                .. (prize and ("\n|cffffd94d%s wins the prize: %s|r"):format(colored(g.seats[bi]), prize) or "")
        else
            text = text .. (g.engine and "  |cff8a8f9cNext round starting...|r" or "  |cff8a8f9cWaiting for the host to start the next round.|r")
        end
        return text
    end
    local lead
    if m == "round" then lead = ("Round %s - %s goes first."):format(a, who)
    elseif m == "spinning" then return who .. " is spinning..."
    elseif m == "spun" then return ("%s spun %s - pick a consonant."):format(who, money(tonumber(a)))
    elseif m == "bankrupt" then lead = "|cffff5a5aBANKRUPT!|r Round money gone."
    elseif m == "loseturn" then lead = "|cffffa340Lose a Turn!|r"
    elseif m == "found" then
        local L, n, amount = a:match("^(%a)(%d+):(%d+)$")
        lead = ("There %s %s %s%s!  |cff66e08c+%s|r"):format(n == "1" and "is" or "are", n, L, n == "1" and "" or "'s", money(tonumber(amount)))
    elseif m == "foundvowel" then
        local L, n = a:match("^(%a)(%d+)$")
        lead = ("There %s %s %s%s."):format(n == "1" and "is" or "are", n, L, n == "1" and "" or "'s")
    elseif m == "none" then lead = ("No %s's."):format(a)
    elseif m == "already" then lead = a .. " was already called."
    elseif m == "wrong" then lead = "That's not it."
    elseif m == "noconsonants" then lead = "No consonants left - buy a vowel or solve."
    elseif m == "skipped" then lead = "Turn skipped."
    elseif m == "timeout" then
        local s = tonumber(a)
        lead = ("%s ran out of time."):format(s and g.seats[s] and colored(g.seats[s]) or "They")
    end
    local prompt = (g.phase == "letter") and "" or (who .. "'s turn.")
    return lead and (lead .. "  " .. prompt) or prompt
end

function V:RefreshGame()
    local g = self:Game()
    if not g then return self:ShowLobby() end
    local amHost = g.host == ns.me
    local mySeat = WF.SeatOf(g, ns.me)
    self.catText:SetText(g.state == "lobby" and "WHEEL OF FORTUNE" or g.cat)
    local prize = WF.PrizeText(g.prize)
    self.prizeText:SetText(prize and ("|cffffd94dPrize|r\n" .. prize) or (g.auto and "|cff8a8f9cEveryone plays|r" or ""))
    self:UpdateTimer(g)
    self.roundText:SetText(g.round > 0 and ("Round %d of %d"):format(g.round, g.rounds) or (g.rounds .. " round" .. (g.rounds == 1 and "" or "s")))

    -- board
    local rows = (g.mask ~= "" and WF.Layout(g.mask)) or {}
    local newly = {}
    if self.prevMask and self.prevMask ~= g.mask and #self.prevMask == #g.mask then
        for k = 1, #g.mask do
            if self.prevMask:sub(k, k) == "_" and g.mask:sub(k, k) ~= "_" then newly[g.mask:sub(k, k)] = true end
        end
    end
    self.prevMask = g.mask
    for _, t in ipairs(self.tiles) do t.state.used = false end
    local startRow = math.floor((WF.ROWS - #rows) / 2)
    for ri, text in ipairs(rows) do
        local startCol = math.floor((WF.COLS - #text) / 2)
        for k = 1, #text do
            local ch = text:sub(k, k)
            if ch ~= " " then
                local t = self.tiles[(startRow + ri - 1) * WF.COLS + startCol + k]
                if t then
                    t.state.used = true
                    t.state.ch = ch
                    if newly[ch] then t.state.flash = GetTime() end
                end
            end
        end
    end
    for _, t in ipairs(self.tiles) do
        local st = t.state
        if not st.used then
            t.bg:SetColorTexture(0.10, 0.42, 0.28, 1)
            t.letter:SetText("")
            st.flash = nil
        elseif st.ch == "_" then
            t.bg:SetColorTexture(0.95, 0.95, 0.93, 1)
            t.letter:SetText("")
        else
            if not st.flash then t.bg:SetColorTexture(0.95, 0.95, 0.93, 1) end
            t.letter:SetText(st.ch)
        end
    end

    -- players
    for i, c in ipairs(self.cards) do
        local name = g.seats[i]
        if name then
            local gone = g.gone and g.gone[name]
            c.name:SetText(colored(name) .. (name == ns.me and " |cff8a8f9c(you)|r" or "") .. (gone and " |cffff5a5a(left)|r" or ""))
            c.round:SetText(money(g.bank[i]))
            c.total:SetText("total " .. money(g.total[i]))
            local active = g.state == "playing" and g.turn == i
            UI.Skin(c, active and C.accentDim or C.panel, active and C.accent or C.line)
        else
            c.name:SetText("|cff8a8f9cOpen seat|r")
            c.round:SetText("")
            c.total:SetText("")
            UI.Skin(c, C.panel, C.line)
        end
    end

    self.status:SetText(self:StatusText(g))
    if g.phase == "spinning" then
        self.wedgeText:SetText("")
    elseif g.msg == "spun" then
        self.wedgeText:SetText("|cffffd94d" .. money(g.value) .. "|r")
    elseif g.msg == "bankrupt" then
        self.wedgeText:SetText("|cffff5a5aBANKRUPT|r")
    elseif g.msg == "loseturn" then
        self.wedgeText:SetText("|cffffa340LOSE A TURN|r")
    end

    -- controls
    local myTurn = g.state == "playing" and mySeat and g.turn == mySeat and not self.spinAnim
    local cLeft, vLeft = 0, 0
    if g.mask ~= "" then
        for ch in WF.CONSONANTS:gmatch(".") do if not g.used:find(ch, 1, true) then cLeft = cLeft + 1 end end
    end
    local playing = g.state ~= "lobby"
    self.seatBtn:SetShown(g.state == "lobby" and not amHost)
    self.seatBtn.label:SetText(mySeat and "Leave seat" or "Take a seat")
    UI.SetDisabled(self.seatBtn, not mySeat and #g.seats >= WF.SEATS)
    for _, b in ipairs({ self.spinBtn, self.solveBtn }) do b:SetShown(playing) end
    UI.SetDisabled(self.spinBtn, not (myTurn and g.phase == "turn"))
    UI.SetActive(self.spinBtn, myTurn and g.phase == "turn")
    UI.SetDisabled(self.solveBtn, not (myTurn and g.phase == "turn"))
    local bank = mySeat and g.bank[mySeat] or 0
    for ch, b in pairs(self.letterBtns) do
        b:SetShown(playing)
        local used = g.used:find(ch, 1, true) ~= nil
        local isV = WF.VOWELS:find(ch, 1, true) ~= nil
        local ok = myTurn and not used and ((isV and g.phase == "turn" and bank >= WF.VOWEL_COST) or (not isV and g.phase == "letter"))
        UI.SetDisabled(b, not ok)
        b:SetAlpha(used and 0.25 or 1)
    end
    self.vowelHint:SetText(myTurn and g.phase == "turn" and bank < WF.VOWEL_COST and "Vowels cost $250 of your round money." or "")

    -- host panel (Play together: the starter runs it, but never sees the answer)
    self.hostPanel:SetShown(amHost)
    if amHost then
        local phrase = g.phrase or ""
        if g.auto then
            self.answerText:SetText(g.state == "lobby" and ("Everyone plays - %d round(s). Players: %d/%d. Start when ready."):format(g.rounds, #g.seats, WF.SEATS)
                or "Everyone plays - nobody sees the answer. Rounds move on by themselves.")
        else
            self.answerText:SetText(g.state == "lobby" and ("%d puzzle(s) ready. Players: %d/%d"):format(g.rounds, #g.seats, WF.SEATS)
                or ("Answer: |cffffd94d" .. phrase .. "|r"))
        end
        self.hostStart:SetShown(g.state == "lobby")
        UI.SetDisabled(self.hostStart, #g.seats == 0)
        self.hostNext:SetShown(g.state == "roundover" and not g.auto)
        self.hostSkip:SetShown(g.state == "playing" and not g.auto)
        self.hostEnd:SetShown(g.state ~= "over" and g.state ~= "cancelled")
    end
end

-- ---------------------------------------------------------------------
-- Animation: the wheel spin and freshly revealed tiles
-- ---------------------------------------------------------------------
-- the turn countdown (the referee sends the seconds left with each update)
function V:UpdateTimer(g)
    if not self.timerText then return end
    local left = g and g.turnEnds and math.max(0, math.ceil(g.turnEnds - GetTime()))
    local on = left ~= nil and g.state == "playing"
    self.timerLabel:SetShown(on)
    self.timerText:SetShown(on)
    if on then
        self.timerText:SetText(("0:%02d"):format(left))
        local c = left <= 5 and { 1, 0.35, 0.35 } or (left <= 10 and { 1, 0.82, 0.3 } or C.text)
        self.timerText:SetTextColor(c[1], c[2], c[3])
    end
end

function V:StartSpin(g)
    local target = math.rad((g.spin - 1) * 15) + math.rad(math.random(-5, 5))
    local from = self.wheelRot or 0
    -- always spin forward several full turns, then settle on the wedge
    local base = from + 2 * math.pi * 4
    local to = target + 2 * math.pi * math.ceil((base - target) / (2 * math.pi))
    self.spinAnim = { t0 = GetTime(), from = from, to = to, dur = WF.SPIN_TIME - 0.2 }
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
end

function V:Animate()
    -- turn countdown: redraw only when the second changes
    local gm = self:Game()
    local left = gm and gm.turnEnds and math.ceil(gm.turnEnds - GetTime()) or nil
    if left ~= self.lastLeft then self.lastLeft = left; self:UpdateTimer(gm) end
    local a = self.spinAnim
    if a then
        local t = math.min(1, (GetTime() - a.t0) / a.dur)
        local eased = 1 - (1 - t) ^ 3
        self.wheelRot = a.from + (a.to - a.from) * eased
        self.wheel:SetRotation(self.wheelRot)
        if t >= 1 then
            self.spinAnim = nil
            self.wheelRot = a.to % (2 * math.pi)
            self:RefreshGame()
        end
    end
    local now = GetTime()
    for _, t in ipairs(self.tiles) do
        if t.state.flash then
            local k = (now - t.state.flash) / 0.9
            if k >= 1 then
                t.state.flash = nil
                t.bg:SetColorTexture(0.95, 0.95, 0.93, 1)
            else
                -- blue flash fading to white, like the show
                t.bg:SetColorTexture(0.25 + 0.70 * k, 0.55 + 0.40 * k, 0.95 - 0.02 * k, 1)
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Events from the engine
-- ---------------------------------------------------------------------
function V:OnChange(what, g, extra)
    if what == "new" and g.host ~= ns.me and not WF.sim then self:Toast(g) end
    if what == "seats" and WF.SeatOf(g, ns.me) and self.gameId ~= g.id and g.host ~= ns.me then self:ShowGame(g.id) end
    if what == "state" and g.phase == "spinning" and (extra == nil or extra.spun ~= false) and self.gameId == g.id and self.frame then
        if not self.spinAnim or self.spinSq ~= g.sq then
            self.spinSq = g.sq
            self:StartSpin(g)
        end
    end
    if self:IsShown() then self:Refresh() end
end

function V:CreateToast()
    local t = CreateFrame("Frame", "TitanUpWheelToast", UIParent, "BackdropTemplate")
    UI.Skin(t, C.bg, C.accent)
    t:SetSize(380, 74)
    t:SetPoint("TOP", 0, -220)
    t:SetFrameStrata("DIALOG")
    t:Hide()
    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA .. "WheelIcon")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 12, 0)
    t.text = UI.Text(t, "GameFontHighlight", nil, nil, "TOPLEFT", icon, "TOPRIGHT", 10, 2)
    t.join = UI.Button(t, 100, 22, "Take a seat", nil, function() t:Hide(); if t.g then WF:Join(t.g.id); V:ShowGame(t.g.id) end end)
    t.join:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -6)
    t.watch = UI.Button(t, 70, 22, "Watch", nil, function() t:Hide(); if t.g then WF:Watch(t.g.id); V:ShowGame(t.g.id) end end)
    t.watch:SetPoint("LEFT", t.join, "RIGHT", 6, 0)
    t.close = UI.Button(t, 70, 22, "Dismiss", nil, function() t:Hide() end)
    t.close:SetPoint("LEFT", t.watch, "RIGHT", 6, 0)
    self.toast = t
end

function V:Toast(g)
    if not self.toast then self:CreateToast() end
    local t = self.toast
    t.g = g
    t.text:SetText(("%s is hosting Wheel of Fortune!"):format(colored(g.host)))
    t:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
    local token = {}
    t.token = token
    C_Timer.After(25, function() if t.token == token then t:Hide() end end)
    ns.Print(("%s is hosting Wheel of Fortune  |H%s%s|h|cff4fc3f7[Open game]|r|h"):format(colored(g.host), self.LINK, g.id))
end

ns.RegisterModule({
    key = "wheel", name = "Wheel of Fortune", icon = ns.MEDIA .. "WheelIcon", group = "games", order = 2,
    desc = "Host a puzzle game for three players.",
    view = V,
    sim = function() local g = ns.Wheel:StartSim(); if g then V:ShowGame(g.id) end end,
})
