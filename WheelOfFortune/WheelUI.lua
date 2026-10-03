-- Titan Up - WheelOfFortune/WheelUI.lua
-- Lobby (host setup + open games) and the game view: puzzle board, the
-- spinning wheel, three player cards, letter buttons, and host controls.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local WF

local V = {}
ns.WheelUI = V

local W, H = 820, 640
local TILE_W, TILE_H, TILE_GAP = 38, 46, 3
local WHEEL = 250

local function money(n) return "$" .. ns.DeathRoll.Fmt(n or 0) end

local function colored(name)
    if not name then return "?" end
    local class = ns.ClassOf(name)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return ("|cff%02x%02x%02x%s|r"):format(cc.r * 255, cc.g * 255, cc.b * 255, ns.Short(name)) end
    return ns.Short(name)
end

local function textBox(parent, w, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    UI.Skin(e, C.canvas, C.line)
    e:SetSize(w, 24)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or 60)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

local function section(parent, text, x, y)
    local t = UI.Text(parent, "GameFontNormalSmall", C.muted)
    t:SetPoint("TOPLEFT", x, y)
    t:SetText(text)
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

function V:IsShown() return self.frame and self.frame:IsShown() or false end
function V:Show() self:EnsureFrame():Show() end

function V:Create()
    local f = CreateFrame("Frame", "TitanUpWheel", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    UI.Skin(f, C.bg, C.line)
    f:Hide()
    tinsert(UISpecialFrames, "TitanUpWheel")
    f:SetScript("OnShow", function() V:Refresh() end)
    UI.Watermark(f, 480, 0.05, -40)

    local header = ns.Nav:CreateHeader(f, "wheel", { title = "WHEEL OF FORTUNE", icon = ns.MEDIA .. "WheelIcon" })
    self.header = header
    self.backBtn = UI.Button(header, 70, 22, "< Lobby", "Back to the lobby", function() V:ShowLobby() end)
    self.backBtn:SetPoint("RIGHT", header.bar, "LEFT", -8, 0)

    self.lobby = CreateFrame("Frame", nil, f)
    self.lobby:SetPoint("TOPLEFT", 0, -36)
    self.lobby:SetPoint("BOTTOMRIGHT")
    self.game = CreateFrame("Frame", nil, f)
    self.game:SetPoint("TOPLEFT", 0, -36)
    self.game:SetPoint("BOTTOMRIGHT")
    self:CreateLobby(self.lobby)
    self:CreateGame(self.game)
    self:ShowLobby()
end

-- ---------------------------------------------------------------------
-- Lobby
-- ---------------------------------------------------------------------
function V:CreateLobby(p)
    section(p, "HOST A GAME", 16, -8)
    local help = UI.Text(p, "GameFontHighlightSmall", C.muted)
    help:SetPoint("TOPLEFT", 16, -26)
    help:SetText("You run the game and see the answers; three players take the seats. Up to 5 rounds. Puzzles: 4 rows of 14 letters.")
    -- ready-made puzzle helpers
    self.themeIndex = 1
    self.themeBtn = UI.Button(p, 168, 22, "", "Which ready-made puzzles Random and Fill all pick from", function()
        V.themeIndex = (V.themeIndex % #WF.THEMES) + 1
        V:RefreshTheme()
    end)
    self.themeBtn:SetPoint("TOPRIGHT", -112, -44)
    local fill = UI.Button(p, 90, 22, "Fill all", "Fill every round with a different random puzzle", function()
        local taken = {}
        for _, row in ipairs(V.setupRows) do
            local pz = WF.RandomPuzzle(V:Theme(), taken)
            if pz then
                row.cat:SetText(pz[1]); row.phrase:SetText(pz[2])
                taken[pz[2]] = true
            end
        end
    end)
    fill:SetPoint("LEFT", self.themeBtn, "RIGHT", 6, 0)
    self:RefreshTheme()
    local cl = UI.Text(p, "GameFontHighlightSmall", C.muted); cl:SetPoint("TOPLEFT", 40, -48); cl:SetText("Category")
    local pl = UI.Text(p, "GameFontHighlightSmall", C.muted); pl:SetPoint("TOPLEFT", 214, -48); pl:SetText("Puzzle")
    self.setupRows = {}
    for i = 1, WF.MAX_ROUNDS do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(W - 32, 26)
        row:SetPoint("TOPLEFT", 16, -64 - (i - 1) * 30)
        local n = UI.Text(row, "GameFontNormal", C.muted); n:SetPoint("LEFT", 0, 0); n:SetText(i .. ".")
        row.cat = textBox(row, 164, 24); row.cat:SetPoint("LEFT", 22, 0)
        row.phrase = textBox(row, 440, 56); row.phrase:SetPoint("LEFT", row.cat, "RIGHT", 10, 0)
        row.random = UI.Button(row, 70, 24, "Random", "Fill this round with a ready-made puzzle (from the theme picked above)", function()
            local pz = WF.RandomPuzzle(V:Theme(), V:TakenPhrases(row))
            if pz then row.cat:SetText(pz[1]); row.phrase:SetText(pz[2]) end
        end)
        row.random:SetPoint("LEFT", row.phrase, "RIGHT", 8, 0)
        row.clear = UI.Button(row, 24, 24, "X", "Clear this round", function() row.cat:SetText(""); row.phrase:SetText("") end)
        row.clear:SetPoint("LEFT", row.random, "RIGHT", 4, 0)
        self.setupRows[i] = row
    end
    self.setupRows[1].cat:SetText("PHRASE")

    local open = UI.Button(p, 160, 30, "Open game", "Post the game to your group so players can take seats", function()
        local list = {}
        for _, row in ipairs(V.setupRows) do
            if row.phrase:GetText() ~= "" then list[#list + 1] = { row.cat:GetText(), row.phrase:GetText() } end
        end
        local g = WF:Host(list)
        if g then V:ShowGame(g.id) end
    end)
    open:SetPoint("TOPLEFT", 16, -222)
    UI.SetActive(open, true)
    local practice = UI.Button(p, 130, 30, "Practice solo", "Play against two bots with a fake host (/tu wheel sim)", function()
        local g = WF:StartSim()
        if g then V:ShowGame(g.id) end
    end)
    practice:SetPoint("LEFT", open, "RIGHT", 10, 0)

    section(p, "OPEN GAMES IN YOUR GROUP", 16, -276)
    self.openRows = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(W - 32, 28)
        row:SetPoint("TOPLEFT", 16, -296 - (i - 1) * 32)
        row.text = UI.Text(row, "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.join = UI.Button(row, 90, 24, "Take a seat", nil, function() if row.g then WF:Join(row.g.id); V:ShowGame(row.g.id) end end)
        row.join:SetPoint("RIGHT", -84, 0)
        row.watch = UI.Button(row, 76, 24, "Watch", nil, function() if row.g then WF:Watch(row.g.id); V:ShowGame(row.g.id) end end)
        row.watch:SetPoint("RIGHT", 0, 0)
        self.openRows[i] = row
    end
    self.noGames = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.noGames:SetPoint("TOPLEFT", 20, -302)
    self.noGames:SetText("No games right now - host one above.")
end

function V:Theme() return WF.THEMES[self.themeIndex or 1].key end

function V:RefreshTheme()
    self.themeBtn.label:SetText("Random from: " .. WF.THEMES[self.themeIndex or 1].label)
end

-- Phrases already used in the other rounds (so Random doesn't repeat them).
function V:TakenPhrases(except)
    local taken = {}
    for _, row in ipairs(self.setupRows) do
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
            row.text:SetText(("%s's game  |cff8a8f9c%d round%s - %s|r"):format(colored(g.host), g.rounds, g.rounds == 1 and "" or "s", status))
            row.join:SetShown(g.state == "lobby" and #g.seats < WF.SEATS and g.host ~= ns.me and not WF.SeatOf(g, ns.me))
        end
    end
    self.noGames:SetShown(#list == 0)
end

-- ---------------------------------------------------------------------
-- Game view
-- ---------------------------------------------------------------------
function V:CreateGame(p)
    self.catText = UI.Text(p, "GameFontNormalLarge", C.accent)
    self.catText:SetPoint("TOP", 0, -4)
    self.roundText = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.roundText:SetPoint("TOPRIGHT", -16, -8)

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
    self.wedgeText = UI.Text(p, "GameFontNormalLarge")
    self.wedgeText:SetPoint("TOP", wheelFrame, "BOTTOM", 0, -6)

    -- player cards
    self.cards = {}
    for i = 1, WF.SEATS do
        local c = CreateFrame("Frame", nil, p, "BackdropTemplate")
        UI.Skin(c, C.panel, C.line)
        c:SetSize(166, 72)
        c:SetPoint("TOPLEFT", 300 + (i - 1) * 172, -262)
        c.name = UI.Text(c, "GameFontNormal"); c.name:SetPoint("TOP", 0, -8)
        c.round = UI.Text(c, "GameFontNormalLarge"); c.round:SetPoint("TOP", c.name, "BOTTOM", 0, -4)
        c.total = UI.Text(c, "GameFontHighlightSmall", C.muted); c.total:SetPoint("TOP", c.round, "BOTTOM", 0, -3)
        self.cards[i] = c
    end

    self.status = UI.Text(p, "GameFontHighlightLarge")
    self.status:SetPoint("TOPLEFT", 300, -346)
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
    self.vowelHint = UI.Text(p, "GameFontHighlightSmall", C.muted)
    self.vowelHint:SetPoint("LEFT", self.solveBtn, "RIGHT", 12, 0)

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
    local vl = UI.Text(p, "GameFontHighlightSmall", C.muted)
    vl:SetPoint("TOPLEFT", 300, -490)
    vl:SetText("BUY A VOWEL  $250")
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
    local ht = UI.Text(hp, "GameFontNormalSmall", C.accent)
    ht:SetPoint("TOPLEFT", 10, -8)
    ht:SetText("HOST  (only you can see this)")
    self.answerText = UI.Text(hp, "GameFontHighlight")
    self.answerText:SetPoint("TOPLEFT", 10, -26)
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
            text = text .. ("\n|cffffd94d%s wins the game with %s!|r"):format(colored(g.seats[bi]), money(best))
        else
            text = text .. "  |cff8a8f9cWaiting for the host to start the next round.|r"
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

    -- host panel
    self.hostPanel:SetShown(amHost)
    if amHost then
        local phrase = g.phrase or ""
        self.answerText:SetText(g.state == "lobby" and ("%d puzzle(s) ready. Players: %d/%d"):format(g.rounds, #g.seats, WF.SEATS)
            or ("Answer: |cffffd94d" .. phrase .. "|r"))
        self.hostStart:SetShown(g.state == "lobby")
        UI.SetDisabled(self.hostStart, #g.seats == 0)
        self.hostNext:SetShown(g.state == "roundover")
        self.hostSkip:SetShown(g.state == "playing")
        self.hostEnd:SetShown(g.state ~= "over" and g.state ~= "cancelled")
    end
end

-- ---------------------------------------------------------------------
-- Animation: the wheel spin and freshly revealed tiles
-- ---------------------------------------------------------------------
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
    t.text = UI.Text(t, "GameFontHighlight")
    t.text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 2)
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
    desc = "Host a game for three players: spin, call letters, buy vowels, solve the puzzle.",
    show = function() V:Show() end,
    hide = function() if V.frame then V.frame:Hide() end end,
    isShown = function() return V:IsShown() end,
    frame = function() return V.frame end,
    sim = function() local g = ns.Wheel:StartSim(); if g then V:ShowGame(g.id) end end,
})
