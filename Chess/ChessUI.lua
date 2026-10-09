-- Titan Up - Chess/ChessUI.lua
-- The Chess window: your games on the left, the board in the middle (your
-- pieces always at the bottom), the moves and buttons on the right.
-- Click a piece, then the square to move it to; the squares it can reach
-- are marked. A move slides across the board; the pieces each side has
-- taken show beside their names, and the move list marks every capture.
-- Nothing is built until the window is first opened.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local CH = ns.Chess
local R = ns.ChessRules

local V = {}
ns.ChessUI = V

local W, H = 880, 570
local LIST_W = 214
local SQ = 52
local BOARD_X, BOARD_Y = LIST_W + 26, -40
local SIDE_X = BOARD_X + 8 * SQ + 18
local SIDE_W = W - SIDE_X - 14
local ROWS = 9                    -- games shown in the list at once
local ROW_H = 44
local MOVE_ROWS = 13

-- High-contrast board (Ryan): near-white and deep blue squares.
local LIGHT = { 0.91, 0.93, 0.95 }
local DARK = { 0.25, 0.30, 0.42 }
local PIECES = ns.MEDIA .. "Chess\\"

local function hex(c) return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local ACCENT, MUTED, WARN, GOOD, BAD = hex(C.accent), hex(C.muted), hex(C.warn), hex(C.good), hex(C.bad)
local function col(c, s) return "|cff" .. c .. s .. "|r" end

local function texFor(p)
    if not p then return nil end
    return PIECES .. ((p == p:upper()) and "w" or "b") .. p:upper()
end

-- A piece as an inline icon in text.
local function icon(p, size)
    return ("|T%s:%d:%d|t"):format(texFor(p), size or 14, size or 14)
end

local ORDER = { "q", "r", "b", "n", "p" }

-- The pieces `color` has taken, grouped ("queen, 2 pawns" as icons), and
-- their lead in material ("+3").
function V.Captures(game, color)
    local got = {}
    for i, p in ipairs(game.taken or {}) do
        local mover = (i % 2 == 1) and "w" or "b"
        if p and mover == color then got[p:lower()] = (got[p:lower()] or 0) + 1 end
    end
    local parts = {}
    local enemy = color == "w" and "b" or "w"
    for _, k in ipairs(ORDER) do
        local n = got[k]
        if n then
            local p = enemy == "w" and k:upper() or k
            parts[#parts + 1] = icon(p, 15) .. (n > 1 and col(MUTED, tostring(n)) or "")
        end
    end
    local d = R.Material(game.pos.b) * (color == "w" and 1 or -1)
    return table.concat(parts, ""), d > 0 and d or nil
end

-- 4:05 / 0:09 ; 2d 4h / 5h 12m / 12m
local function clockText(secs)
    secs = math.max(0, math.floor(secs))
    return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end
local function daysText(secs)
    if secs <= 0 then return "out of time" end
    local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
    if d > 0 then return ("%dd %dh left"):format(d, h) end
    if h > 0 then return ("%dh %dm left"):format(h, m) end
    return ("%dm left"):format(math.max(1, m))
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------
function V:Create()
    local f = ns.Nav:Window(self, "TitanUpChess", "chess", "CHESS", W, H, { mark = false,
        onShow = function() V:OnShow() end })

    -- your games
    UI.Text(f, "GameFontNormalSmall", C.accent, "YOUR GAMES", "TOPLEFT", 16, -16)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 12, -36)
    list:SetSize(LIST_W, ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) V.listOffset = (V.listOffset or 0) - d; V:Refresh() end)
    self.rows = {}
    for i = 1, ROWS do
        local r = UI.Row(list, ROW_H - 4, 0.06, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.6 }, "GameFontHighlight")
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetWidth(LIST_W)
        local bg = r:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints()
        bg:SetColorTexture(C.canvas[1], C.canvas[2], C.canvas[3], 1)
        r.text:SetPoint("TOPLEFT", 10, -6)
        r.text:SetPoint("RIGHT", -8, 0)
        r.sub = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -23)
        r.sub:SetPoint("RIGHT", -8, 0)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)
        r:SetScript("OnClick", function(s) V:Select(s.id) end)
        self.rows[i] = r
    end
    self.listEmpty = UI.Text(list, "GameFontHighlightSmall", C.muted,
        "No games yet. Challenge a guildmate - they don't have to be online.", "TOPLEFT", 4, -6)
    self.listEmpty:SetWidth(LIST_W - 8)
    self.listEmpty:SetJustifyH("LEFT")
    local challenge = UI.Button(f, LIST_W, 26, "Challenge a guildmate", "Start a game with anyone in your guild. If they're offline, it reaches them through a guildmate running Titan Up.", function() V:AskChallenge() end)
    challenge:SetPoint("BOTTOMLEFT", 12, 14)
    UI.SetActive(challenge, true)
    self.challengeBtn = challenge

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", LIST_W + 13, -12); sep:SetPoint("BOTTOMLEFT", LIST_W + 13, 12); sep:SetWidth(1)

    -- players above and below the board
    self.topName = UI.Text(f, "GameFontHighlight", C.text, nil, "BOTTOMLEFT", f, "TOPLEFT", BOARD_X, BOARD_Y + 6)
    self.topInfo = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "BOTTOMRIGHT", f, "TOPLEFT", BOARD_X + 8 * SQ, BOARD_Y + 7)
    self.botName = UI.Text(f, "GameFontHighlight", C.text, nil, "TOPLEFT", f, "TOPLEFT", BOARD_X, BOARD_Y - 8 * SQ - 6)
    self.botInfo = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", f, "TOPLEFT", BOARD_X + 8 * SQ, BOARD_Y - 8 * SQ - 7)

    -- the board
    local board = CreateFrame("Frame", nil, f, "BackdropTemplate")
    board:SetPoint("TOPLEFT", BOARD_X - 2, BOARD_Y + 2)
    board:SetSize(8 * SQ + 4, 8 * SQ + 4)
    UI.Skin(board, C.canvas, C.line)
    self.board = board
    self.squares = {}
    for y = 0, 7 do
        for x = 0, 7 do
            local s = CreateFrame("Button", nil, board)
            s:SetSize(SQ, SQ)
            s:SetPoint("TOPLEFT", 2 + x * SQ, -2 - y * SQ)
            s:RegisterForClicks("LeftButtonUp")
            s.bg = s:CreateTexture(nil, "BACKGROUND")
            s.bg:SetAllPoints()
            s.tint = s:CreateTexture(nil, "BORDER")          -- last move / selected / check
            s.tint:SetAllPoints()
            s.tint:Hide()
            s.piece = s:CreateTexture(nil, "ARTWORK")
            s.piece:SetPoint("TOPLEFT", 3, -3)
            s.piece:SetPoint("BOTTOMRIGHT", -3, 3)
            s.dot = s:CreateTexture(nil, "OVERLAY")          -- a square the picked piece can reach
            s.dot:SetPoint("CENTER")
            s.dot:Hide()
            s.coordF = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            s.coordF:SetPoint("BOTTOMRIGHT", -2, 2)
            s.coordR = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            s.coordR:SetPoint("TOPLEFT", 2, -2)
            local hl = s:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.12)
            s.x, s.y = x, y
            s:SetScript("OnClick", function(b) V:ClickSquare(b.sq) end)
            self.squares[y * 8 + x + 1] = s
        end
    end

    -- promotion picker (over the board)
    local promo = CreateFrame("Frame", nil, board, "BackdropTemplate")
    UI.Skin(promo, C.bg, C.accent)
    promo:SetSize(4 * (SQ + 6) + 14, SQ + 44)
    promo:SetPoint("CENTER")
    promo:SetFrameLevel(board:GetFrameLevel() + 20)
    promo:EnableMouse(true)
    promo:Hide()
    UI.Text(promo, "GameFontNormalSmall", C.accent, "PROMOTE TO", "TOPLEFT", 10, -8)
    promo.buttons = {}
    for i, k in ipairs({ "q", "r", "b", "n" }) do
        local b = UI.Button(promo, SQ, SQ, "", nil, function() V:Promote(k) end)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * (SQ + 6), -28)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 4, -4); b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
        b.kind = k
        promo.buttons[i] = b
    end
    local x = UI.Button(promo, 20, 18, "X", "Cancel", function() V.promoMove = nil; V:Refresh() end)
    x:SetPoint("TOPRIGHT", -6, -6)
    self.promo = promo

    -- the piece that slides across the board when a move is made
    local slider = board:CreateTexture(nil, "OVERLAY", nil, 7)
    slider:SetSize(SQ - 6, SQ - 6)
    slider:Hide()
    self.slider = slider

    -- right side: what's happening, the moves, the buttons
    self.status = UI.Text(f, "GameFontHighlight", C.text, nil, "TOPLEFT", SIDE_X, -16)
    self.status:SetWidth(SIDE_W)
    self.status:SetJustifyH("LEFT")
    self.note = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", self.status, "BOTTOMLEFT", 0, -6)
    self.note:SetWidth(SIDE_W)
    self.note:SetJustifyH("LEFT")

    local moves = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.Skin(moves, C.canvas, C.line)
    moves:SetPoint("TOPLEFT", SIDE_X, -142)
    moves:SetSize(SIDE_W, MOVE_ROWS * 17 + 12)
    moves:EnableMouseWheel(true)
    moves:SetScript("OnMouseWheel", function(_, d) V.moveOffset = (V.moveOffset or 0) - d; V.follow = false; V:RefreshMoves() end)
    UI.Text(f, "GameFontNormalSmall", C.accent, "MOVES", "BOTTOMLEFT", moves, "TOPLEFT", 2, 4)
    self.moveRows = {}
    for i = 1, MOVE_ROWS do
        local y = -6 - (i - 1) * 17
        local r = {}
        r.n = UI.Text(moves, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 8, y)
        r.w = UI.Text(moves, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 40, y)
        r.b = UI.Text(moves, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 40 + (SIDE_W - 48) / 2, y)
        self.moveRows[i] = r
    end
    self.movesBox = moves

    local function btn(label, tip, fn)
        local b = UI.Button(f, SIDE_W, 26, label, tip, fn)
        return b
    end
    self.btnA = btn("", nil, function() V:Action("a") end)
    self.btnB = btn("", nil, function() V:Action("b") end)
    self.btnB:SetPoint("BOTTOMLEFT", SIDE_X, 14)
    self.btnA:SetPoint("BOTTOMLEFT", self.btnB, "TOPLEFT", 0, 6)
end

-- ---------------------------------------------------------------------
-- Showing a game
-- ---------------------------------------------------------------------
function V:OnShow()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    CH.roster = nil
    CH:Hello()
    if not (self.sel and CH:Get(self.sel)) then
        local first = CH:Games()[1]
        self.sel = first and first.id
    end
    self.follow = true
    self:Refresh()
end

function V:Open(id)
    if id then self.sel = id end
    self.pick, self.promoMove = nil, nil
    self:Show()
    if self.frame and self.frame:IsShown() then self.follow = true; self:Refresh() end
end

function V:Select(id)
    if self.sel ~= id then self.pick, self.promoMove, self.confirm = nil, nil, nil end
    self.sel = id
    self.follow = true
    self:Refresh()
end

function V:OnChange(g, what)
    if what == "new" and g and g.by == ns.me then self.sel = g.id end
    if g and g.id == self.sel and what ~= "offer" then self.pick, self.promoMove = nil, nil; self.follow = true end
    if not self:IsShown() then return end
    -- a new move in the game on screen slides into place
    if g and g.id == self.sel and (what == "move" or what == "state") then
        local n = #CH.SplitMoves(g.moves)
        if self.slidN and self.slidN[g.id] and n > self.slidN[g.id] then self:StartSlide(g) end
    end
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- The move slide
-- ---------------------------------------------------------------------
V.SLIDE = CH.SLIDE               -- seconds (the live clock waits for it)

-- top-left of a square on the board, from your side
function V:SquareOffset(sq)
    local file, rank = sq % 8, math.floor(sq / 8)
    local x, y
    if self.flip then x, y = 7 - file, rank else x, y = file, 7 - rank end
    return 2 + x * SQ, -2 - y * SQ
end

function V:StartSlide(g)
    local game = CH:Live(g)
    local m = game.last
    if not m then return end
    self.slide = { from = m.from, to = m.to, tex = texFor(game.pos.b[m.to]), t0 = GetTime() }
    self.slider:SetTexture(self.slide.tex)
    self.board:SetScript("OnUpdate", function() V:Animate() end)
    self:Animate()
end

function V:Animate()
    local sl = self.slide
    if not sl then return end
    local t = (GetTime() - sl.t0) / self.SLIDE
    if t >= 1 then
        self.slide = nil
        self.slider:Hide()
        self.board:SetScript("OnUpdate", nil)
        self:RefreshBoard(self.game)
        return
    end
    t = 1 - (1 - t) * (1 - t)                -- ease out
    local x1, y1 = self:SquareOffset(sl.from)
    local x2, y2 = self:SquareOffset(sl.to)
    self.slider:ClearAllPoints()
    self.slider:SetPoint("TOPLEFT", self.board, "TOPLEFT", x1 + (x2 - x1) * t + 3, y1 + (y2 - y1) * t - 3)
    self.slider:Show()
end

-- Your opponent moved while you're elsewhere in Titan Up: the Chess entry
-- on the rail blinks a few times.
function V:FlashRail()
    local Nav = ns.Nav
    for _, h in pairs(Nav.headers or {}) do
        for _, b in ipairs(h.railButtons or {}) do
            local isChess = false
            for _, k in ipairs(b.item and b.item.keys or {}) do if k == "chess" then isChess = true end end
            if isChess and h.key ~= "chess" then
                local n = 0
                local ticker
                ticker = C_Timer.NewTicker(0.3, function()
                    n = n + 1
                    UI.SetActive(b, n % 2 == 1)
                    if n >= 6 then ticker:Cancel(); Nav:RefreshChrome(h) end
                end)
            end
        end
    end
end

-- board square on screen -> square index, from your side of the board
function V:SquareAt(x, y, flip)
    if flip then return y * 8 + (7 - x) end
    return (7 - y) * 8 + x
end

local function statusLine(g)
    if g.status == "invited" then
        if g.by == ns.me then return col(MUTED, "Waiting for them to accept") end
        return col(WARN, "Challenged you!")
    end
    if g.status == "over" then
        if g.result == "d" then return col(MUTED, "Draw") end
        if g.reason == "declined" or g.reason == "cancelled" then return col(MUTED, g.reason == "declined" and "Declined" or "Taken back") end
        return (g.result == CH:ColorOf(g)) and col(GOOD, "You won") or col(BAD, "You lost")
    end
    if CH:NeedsMe(g) then return col(ACCENT, "Your move") end
    return col(MUTED, "Their move")
end

function V:Refresh()
    if not self.frame then return end
    local games = CH:Games()
    -- the list
    self.listOffset = math.max(0, math.min(#games - ROWS, self.listOffset or 0))
    self.listEmpty:SetShown(#games == 0)
    for i, r in ipairs(self.rows) do
        local g = games[i + self.listOffset]
        r:SetShown(g ~= nil)
        if g then
            r.id = g.id
            local n = #CH.SplitMoves(g.moves)
            r.text:SetText("vs " .. ns.Short(CH:Opponent(g)))
            r.sub:SetText(statusLine(g) .. (n > 0 and col(MUTED, ("  -  move %d"):format(math.floor((n + 1) / 2))) or ""))
            r.hl:SetShown(g.id == self.sel)
        end
    end
    local g = self.sel and CH:Get(self.sel)
    if g and not CH:IsPlayer(g) then g = nil end
    if self.game ~= g then self.slide = nil; self.slider:Hide(); self.board:SetScript("OnUpdate", nil) end
    self.game = g
    self.slidN = self.slidN or {}
    if g then self.slidN[g.id] = #CH.SplitMoves(g.moves) end
    self:RefreshBoard(g)
    self:RefreshSide(g)
    self:RefreshMoves()
end

function V:RefreshBoard(g)
    local game = g and CH:Live(g)
    local pos = game and game.pos or R.New()
    local flip = g and CH:ColorOf(g) == "b"
    self.flip = flip
    -- squares the picked piece can go to
    local targets = {}
    if self.pick and game then
        for _, m in ipairs(game.legal) do
            if m.from == self.pick then targets[m.to] = true end
        end
    end
    self.targets = targets
    local last = game and game.last
    local checkSq = game and R.InCheck(pos) and R.KingSquare(pos.b, pos.side)
    for _, s in ipairs(self.squares) do
        local sq = self:SquareAt(s.x, s.y, flip)
        s.sq = sq
        local light = (sq % 8 + math.floor(sq / 8)) % 2 == 1
        local c = light and LIGHT or DARK
        s.bg:SetColorTexture(c[1], c[2], c[3], 1)
        -- tint: picked piece, last move, king in check
        local tint
        if sq == self.pick then tint = { C.accent[1], C.accent[2], C.accent[3], 0.55 }
        elseif sq == checkSq then tint = { C.bad[1], C.bad[2], C.bad[3], 0.6 }
        elseif last and (sq == last.from or sq == last.to) then tint = { C.accent[1], C.accent[2], C.accent[3], 0.3 } end
        if tint then s.tint:SetColorTexture(tint[1], tint[2], tint[3], tint[4]); s.tint:Show() else s.tint:Hide() end
        local p = pos.b[sq]
        local tex = texFor(p)
        if tex and not (self.slide and self.slide.to == sq) then s.piece:SetTexture(tex); s.piece:Show() else s.piece:Hide() end
        if targets[sq] then
            if p then
                s.dot:SetTexture(ns.MEDIA .. "Shapes\\ring80")
                s.dot:SetSize(SQ - 2, SQ - 2)
                s.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
            else
                s.dot:SetTexture(PIECES .. "dot")
                s.dot:SetSize(SQ * 0.3, SQ * 0.3)
                s.dot:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
            end
            s.dot:Show()
        else
            s.dot:Hide()
        end
        -- coordinates along the bottom and left edges, in the other square colour
        local oc = light and DARK or LIGHT
        s.coordF:SetText(s.y == 7 and R.Name(sq):sub(1, 1) or "")
        s.coordR:SetText(s.x == 0 and R.Name(sq):sub(2, 2) or "")
        s.coordF:SetTextColor(oc[1], oc[2], oc[3])
        s.coordR:SetTextColor(oc[1], oc[2], oc[3])
    end
    -- promotion picker
    local pm = self.promoMove
    self.promo:SetShown(pm ~= nil)
    if pm then
        local white = CH:ColorOf(g) == "w"
        for _, b in ipairs(self.promo.buttons) do
            b.icon:SetTexture(PIECES .. (white and "w" or "b") .. b.kind:upper())
        end
    end
    self:RefreshPlayers(g)
end

-- Names, what each has taken, colours, clocks and whose move it is.
function V:RefreshPlayers(g)
    if not g then
        self.topName:SetText(""); self.topInfo:SetText(""); self.botName:SetText(""); self.botInfo:SetText("")
        return
    end
    local game = CH:Live(g)
    local me, opp = ns.me, CH:Opponent(g)
    local mine = CH:ColorOf(g)
    local theirs = mine == "w" and "b" or "w"
    local turn = g.status == "active" and CH:ToMove(g)
    local kind = CH:Timer(g)
    local online = CH:IsOnline(opp)
    local function strip(name, color)
        local taken, lead = V.Captures(game, color)
        return UI.Named(name) .. "  " .. taken .. (lead and col(MUTED, " +" .. lead) or "")
    end
    local function info(color, isMe)
        local bits = { col(MUTED, color == "w" and "White" or "Black") }
        if kind == "live" then
            local left = CH:ClockLeft(g, color)
            local running = turn == color and online == true
            bits[#bits + 1] = col(left < 60 and BAD or (running and ACCENT or MUTED), clockText(left))
        elseif kind == "days" and turn == color then
            local left = CH:DaysLeft(g)
            bits[#bits + 1] = col(left < 6 * 3600 and WARN or MUTED, daysText(left))
        end
        if turn == color then bits[#bits + 1] = col(ACCENT, isMe and "your move" or "to move") end
        if not isMe then
            bits[#bits + 1] = online == true and col(GOOD, "online") or (online == false and col(MUTED, "offline") or nil)
        end
        return table.concat(bits, "  ")
    end
    self.topName:SetText(strip(opp, theirs))
    self.topInfo:SetText(info(theirs, false))
    self.botName:SetText(strip(me, mine))
    self.botInfo:SetText(info(mine, true))
end

-- Once a second (from the game's own ticker): clocks, and the claim button
-- appearing when your opponent runs out of time.
function V:Tick()
    local g = self.game
    if not (self:IsShown() and g and CH:Timer(g)) then return end
    self:RefreshPlayers(g)
    local can = CH:CanClaimTime(g)
    local key = g.id .. (can and "+" or "-") .. g.status
    if key ~= self.lastTick then
        self.lastTick = key
        self:RefreshSide(g)
    end
end

local function setBtn(b, label, tip, active)
    b:SetShown(label ~= nil)
    if not label then return end
    b.label:SetText(label)
    b.tip = tip
    UI.SetActive(b, active and true or false)
end

function V:RefreshSide(g)
    local status, note
    local a, b = nil, nil                -- { label, tip, active }
    self.actions = {}
    if not g then
        status = "Chess with your guild"
        note = "Pick a game on the left, or challenge a guildmate. Games are saved until they end, and moves reach offline players through any guildmate running Titan Up."
    else
        local opp = ns.Short(CH:Opponent(g))
        local online = CH:IsOnline(CH:Opponent(g))
        local game = CH:Live(g)
        if g.status == "invited" then
            if g.by == ns.me then
                status = ("Waiting for %s to accept."):format(opp)
                note = online == false and ("%s is offline - the challenge reaches them through a guildmate."):format(opp) or ""
                b = { "Take back the challenge", nil, false, "decline" }
            else
                status = ("%s challenged you!"):format(opp)
                note = ("You'd play %s."):format(CH:ColorOf(g) == "w" and "White and move first" or "Black")
                if g.tc then note = note .. "\nTimer: " .. CH.TIMER_LABEL[g.tc] .. "." end
                a = { "Accept", nil, true, "accept" }
                b = { "Decline", nil, false, "decline" }
            end
        elseif g.status == "over" then
            status = CH:EndText(g)
            local n = #CH.SplitMoves(g.moves)
            note = n > 0 and ("%d moves."):format(math.floor((n + 1) / 2)) or ""
            b = { "Remove from list", "Take this finished game off your list", false, "remove" }
        else
            local _, who = CH:ToMove(g)
            if who == ns.me then
                status = R.InCheck(game.pos) and col(WARN, "Check!") .. " Your move." or "Your move."
                note = "Click a piece, then where it goes."
            else
                status = ("Waiting for %s."):format(opp)
                note = online == false and ("%s is offline - your move reaches them through a guildmate."):format(opp) or ""
            end
            if g.offer and g.offer.n == #CH.SplitMoves(g.moves) then
                if g.offer.by == ns.me then
                    note = note .. "\nYou offered a draw."
                    a = { "Draw offered", nil, false, "none" }
                else
                    status = status .. " " .. col(WARN, opp .. " offers a draw.")
                    a = { "Accept the draw", nil, true, "acceptDraw" }
                end
            else
                a = { "Offer a draw", "Offer a draw - it stands until the next move", false, "offerDraw" }
            end
            b = self.confirm == g.id and { "Click again to resign", nil, true, "resign" } or { "Resign", nil, false, "resign" }
            if g.tc then note = note .. "\n" .. col(MUTED, "Timer: " .. CH.TIMER_LABEL[g.tc] .. (CH:Timer(g) == "live" and " (pauses while either of you is offline)" or "") .. ".") end
            if CH:CanClaimTime(g) then
                status = ("%s is out of time."):format(opp)
                a = { "Claim the win on time", nil, true, "claim" }
            end
            -- moves a courier brought that your opponent hasn't confirmed yet
            local by
            for _, name in pairs(g.via or {}) do by = name end
            if by then note = note .. "\n" .. col(MUTED, ("%s's last move was delivered by %s."):format(opp, ns.Short(by))) end
        end
    end
    self.status:SetText(status)
    self.note:SetText(note)
    setBtn(self.btnA, a and a[1], a and a[2], a and a[3])
    setBtn(self.btnB, b and b[1], b and b[2], b and b[3])
    if a then UI.SetDisabled(self.btnA, a[4] == "none") end
    self.actions.a, self.actions.b = a and a[4], b and b[4]
end

function V:RefreshMoves()
    if not self.frame then return end
    local g = self.game
    local san = g and CH:Live(g).san or {}
    local taken = g and CH:Live(g).taken or {}
    local lines = math.ceil(#san / 2)
    if self.follow then self.moveOffset = lines - MOVE_ROWS end
    self.moveOffset = math.max(0, math.min(lines - MOVE_ROWS, self.moveOffset or 0))
    for i, r in ipairs(self.moveRows) do
        local line = i + self.moveOffset
        local w, b = san[line * 2 - 1], san[line * 2]
        -- each capture shows the piece it took
        local tw, tb = taken[line * 2 - 1], taken[line * 2]
        r.n:SetText(w and (line .. ".") or "")
        r.w:SetText(w and (w .. (tw and (" " .. icon(tw, 13)) or "")) or "")
        r.b:SetText(b and (b .. (tb and (" " .. icon(tb, 13)) or "")) or "")
    end
end

-- ---------------------------------------------------------------------
-- Playing
-- ---------------------------------------------------------------------
function V:ClickSquare(sq)
    local g = self.game
    if not g or g.status ~= "active" or select(2, CH:ToMove(g)) ~= ns.me or self.promoMove then return end
    local game = CH:Live(g)
    local p = game.pos.b[sq]
    local mine = p and R.ColorOf(p) == CH:ColorOf(g)
    if self.pick and self.targets and self.targets[sq] then
        local from = self.pick
        local needsPromo = false
        for _, m in ipairs(game.legal) do
            if m.from == from and m.to == sq and m.promo then needsPromo = true end
        end
        if needsPromo then
            self.promoMove = { from = from, to = sq }
            self:Refresh()
            return
        end
        self:Play(R.Name(from) .. R.Name(sq))
        return
    end
    self.pick = (mine and sq ~= self.pick) and sq or nil
    self:Refresh()
end

function V:Promote(kind)
    local pm = self.promoMove
    self.promoMove = nil
    if pm then self:Play(R.Name(pm.from) .. R.Name(pm.to) .. kind) end
end

function V:Play(uci)
    self.pick = nil
    local ok, err = CH:Move(self.sel, uci)
    if not ok and err then ns.Print(err) end
    self.follow = true
    self:Refresh()
end

function V:Action(which)
    local act = self.actions and self.actions[which]
    local id = self.sel
    if not act or not id then return end
    if act ~= "resign" then self.confirm = nil end
    if act == "accept" then CH:Accept(id)
    elseif act == "decline" then CH:Decline(id)
    elseif act == "remove" then CH:Remove(id); self.sel = nil
    elseif act == "offerDraw" then CH:OfferDraw(id)
    elseif act == "acceptDraw" then CH:AcceptDraw(id)
    elseif act == "claim" then CH:ClaimTime(id)
    elseif act == "resign" then
        if self.confirm == id then
            self.confirm = nil
            CH:Resign(id)
        else
            self.confirm = id
            C_Timer.After(4, function() if V.confirm == id then V.confirm = nil; V:Refresh() end end)
        end
    end
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- Challenge window: pick a guildmate who has Chess (or type a name), and a timer
-- ---------------------------------------------------------------------
local DLG_ROWS = 9

function V:BuildChallenge()
    local d = UI.Window("TitanUpChessChallenge", 340, 446, { strata = "DIALOG", border = C.accent, drag = true, y = 60 })
    UI.Text(d, "GameFontNormal", C.accent, "CHALLENGE A GUILDMATE", "TOPLEFT", 14, -12)
    local close = UI.Button(d, 22, 20, "X", "Close", function() d:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    local help = UI.Text(d, "GameFontHighlightSmall", C.muted, "Guildmates with Titan Up Chess. They don't need to be online: the challenge waits for them.", "TOPLEFT", 14, -34)
    help:SetWidth(312); help:SetJustifyH("LEFT")

    local list = CreateFrame("Frame", nil, d, "BackdropTemplate")
    UI.Skin(list, C.canvas, C.line)
    list:SetPoint("TOPLEFT", 12, -66)
    list:SetSize(316, DLG_ROWS * 26 + 6)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) d.offset = (d.offset or 0) - delta; V:RefreshChallenge() end)
    d.rows = {}
    for i = 1, DLG_ROWS do
        local r = UI.Row(list, 24, 0.08, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.8 }, "GameFontHighlight", true)
        r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 26)
        r:SetWidth(310)
        r.text:SetPoint("LEFT", 8, 0)
        r.text:SetWidth(170)
        r.seen = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "RIGHT", -8, 0)
        r:SetScript("OnClick", function(b) d.pick = b.name; d.box:SetText(""); d.box:ClearFocus(); V:RefreshChallenge() end)
        d.rows[i] = r
    end
    d.empty = UI.Text(list, "GameFontHighlightSmall", C.muted,
        "Nobody yet. Guildmates show up here once they've logged in with Titan Up 0.34.0 or newer. You can type a name below.", "TOPLEFT", 10, -10)
    d.empty:SetWidth(296); d.empty:SetJustifyH("LEFT")

    UI.Text(d, "GameFontHighlightSmall", C.muted, "Or type a name:", "TOPLEFT", 14, -(66 + DLG_ROWS * 26 + 18))
    local box = UI.EditBox(d, 200, 24, { inset = 6, max = 64 })
    box:SetPoint("TOPLEFT", 126, -(66 + DLG_ROWS * 26 + 12))
    box:SetScript("OnTextChanged", function(_, user) if user then d.pick = nil; V:RefreshChallenge() end end)
    box:SetScript("OnEnterPressed", function() V:SendChallenge() end)
    d.box = box

    UI.Text(d, "GameFontHighlightSmall", C.muted, "Timer:", "TOPLEFT", 14, -(66 + DLG_ROWS * 26 + 50))
    local timer = UI.Button(d, 200, 24, "", "Optional. Days per move works when you're not online together; a live clock only runs while you're both online.", function(b)
        local items = {}
        for _, t in ipairs(CH.TIMERS) do
            items[#items + 1] = { text = t[2], checked = (d.tc or "") == t[1], onClick = function() d.tc = t[1]; V:RefreshChallenge() end }
        end
        UI.Menu(b, items)
    end)
    timer:SetPoint("TOPLEFT", 126, -(66 + DLG_ROWS * 26 + 44))
    d.timer = timer

    d.go = UI.Button(d, 140, 26, "Challenge", nil, function() V:SendChallenge() end)
    d.go:SetPoint("BOTTOMRIGHT", -12, 12)
    UI.SetActive(d.go, true)
    local cancel = UI.Button(d, 90, 26, "Cancel", nil, function() d:Hide() end)
    cancel:SetPoint("RIGHT", d.go, "LEFT", -8, 0)
    d.err = UI.Text(d, "GameFontHighlightSmall", C.bad, nil, "BOTTOMLEFT", 14, 46)
    d.err:SetWidth(312); d.err:SetJustifyH("LEFT")
    ns.Dock:Add(d)
    self.dlg = d
    return d
end

local function ago(at)
    local s = ns.Now() - (at or 0)
    if s < 3600 then return "seen just now" end
    if s < 86400 then return ("seen %dh ago"):format(math.floor(s / 3600)) end
    local days = math.floor(s / 86400)
    return days == 1 and "seen yesterday" or ("seen %d days ago"):format(days)
end

function V:RefreshChallenge()
    local d = self.dlg
    if not d then return end
    local people = CH:KnownPlayers()
    d.people = people
    d.offset = math.max(0, math.min(#people - DLG_ROWS, d.offset or 0))
    d.empty:SetShown(#people == 0)
    for i, r in ipairs(d.rows) do
        local p = people[i + d.offset]
        r:SetShown(p ~= nil)
        if p then
            r.name = p.name
            local cc = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            r.text:SetText(ns.Short(p.name))
            if cc then r.text:SetTextColor(cc.r, cc.g, cc.b) else r.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end
            r.seen:SetText(p.online and col(GOOD, "online") or ago(p.at))
            r.hl:SetShown(d.pick == p.name)
        end
    end
    d.timer.label:SetText((CH.TIMER_LABEL[d.tc or ""] or "No timer") .. "  v")
    local who = d.pick or (d.box:GetText() ~= "" and d.box:GetText())
    UI.SetDisabled(d.go, not who)
    d.go.label:SetText(who and ("Challenge " .. ns.Short(who)) or "Challenge")
end

function V:AskChallenge()
    local d = self.dlg or self:BuildChallenge()
    d.pick, d.tc, d.offset = nil, "", 0
    d.err:SetText("")
    d.box:SetText("")
    -- your target is picked (or typed) for you
    local target = UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") and not UnitIsUnit("target", "player") and ns.FullName("target")
    if target then
        if (ns.udb.chess.known or {})[target] then d.pick = target else d.box:SetText(target) end
    end
    d:Show()
    self:RefreshChallenge()
end

function V:SendChallenge()
    local d = self.dlg
    local who = d.pick or d.box:GetText()
    if not who or who == "" then return end
    local ok, res = CH:Challenge(who, d.tc)
    if not ok then d.err:SetText(res) return end
    d:Hide()
    self.sel = res.id
    self.follow = true
    if self:IsShown() then self:Refresh() end
end

ns.RegisterModule({
    key = "chess", name = "Chess", icon = ns.MEDIA .. "Chess", group = "games", order = 4,
    desc = "Chess with a guildmate - games are saved until they end, and moves reach offline players.",
    view = V,
    badge = function() return CH:WaitingCount() end,
})
