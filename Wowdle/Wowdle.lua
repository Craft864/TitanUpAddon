-- Titan Up - Wowdle/Wowdle.lua
-- Wowdle: a daily guild word game. Everyone gets the same 5-letter word
-- each day (US daily reset), mixing WoW terms with everyday words.
--   * The word is picked from a fixed shuffled list by the day number, so
--     nothing has to be sent to agree on it.
--   * Guesses must be real words: checked by binary search inside one
--     packed string (Words.lua) - no word table is ever built.
--   * Standings: each player shares only their own totals and today's guess
--     count over the guild channel (never the guesses), out of combat.
-- Nothing is built until the window is first opened.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local WD = {}
ns.Wowdle = WD

local PREFIX = "TitanUpWD"
local LAUNCH = 1791126000          -- the US daily reset that starts Wowdle #1
local DAY = 86400
WD.MAX_GUESSES = 6

local function db() return ns.udb.wowdle end

-- ---------------------------------------------------------------------
-- Days and words
-- ---------------------------------------------------------------------
-- Today's Wowdle number: days since LAUNCH, counted from the US daily reset.
function WD.Today()
    local now = GetServerTime and GetServerTime() or time()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    local dayStart
    if type(untilReset) == "number" and untilReset > 0 then
        dayStart = now + untilReset - DAY
    else
        dayStart = now - ((now - LAUNCH) % DAY)
    end
    return math.floor((dayStart - LAUNCH) / DAY + 0.5) + 1      -- rounding absorbs small clock/DST offsets
end

local function decode(s, i)
    local out = {}
    for j = 1, 5 do
        local c = s:byte(j) - 65
        out[j] = string.char((c - 7 - ((i * 3 + (j - 1) * 5) % 26)) % 26 + 65)
    end
    return table.concat(out)
end

function WD.Answer(day)
    local A = ns.WowdleWords.ANSWERS
    local n = #A / 5
    local i = (day - 1) % n                         -- 0-based position in the list
    return decode(A:sub(i * 5 + 1, i * 5 + 5), i)
end

-- Real-word check: binary search in the packed, sorted string.
function WD.IsValid(word)
    if type(word) ~= "string" or #word ~= 5 then return false end
    word = word:upper()
    local V = ns.WowdleWords.VALID
    local lo, hi = 0, #V / 5 - 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local w = V:sub(mid * 5 + 1, mid * 5 + 5)
        if w == word then return true elseif w < word then lo = mid + 1 else hi = mid - 1 end
    end
    return false
end

-- Colors for a guess: "g" right spot, "y" in the word elsewhere, "b" not in
-- it. Repeated letters are only marked as often as they appear.
function WD.Score(guess, answer)
    local res, left = {}, {}
    for i = 1, 5 do
        local g, a = guess:sub(i, i), answer:sub(i, i)
        if g == a then res[i] = "g" else left[a] = (left[a] or 0) + 1 end
    end
    for i = 1, 5 do
        if not res[i] then
            local g = guess:sub(i, i)
            if (left[g] or 0) > 0 then res[i] = "y"; left[g] = left[g] - 1 else res[i] = "b" end
        end
    end
    return res
end

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------
-- Guild standings: players who haven't played in 30 days drop off.
WD.PRUNE_DAYS = 30
function WD:Prune()
    local today = WD.Today and WD.Today()
    if not today then return end
    for name, r in pairs(db().standings) do
        if name ~= ns.me and (r.day or 0) < today - WD.PRUNE_DAYS then db().standings[name] = nil end
    end
end

function WD:Init()
    self:Prune()
    ns.Listen(PREFIX, "guild", function(msg, sender) WD:OnMessage(msg, sender) end)
    ns.On("PLAYER_REGEN_ENABLED", function() if WD.pendingShare then C_Timer.After(2, function() WD:ShareMine() end) end end)
    -- tell the guild our standing once after login (if we've ever played)
    C_Timer.After(25, function() if (db().stats.played or 0) > 0 then WD:ShareMine() end end)
    self:CheckDay()
end

-- A new day: clear yesterday's board.
function WD:CheckDay()
    local d, today = db(), WD.Today()
    if d.day ~= today then
        d.day, d.guesses, d.done, d.won = today, {}, nil, nil
    end
    return today
end

function WD:Submit(word)
    self:CheckDay()
    local d = db()
    if d.done then return false, "You've finished today's Wowdle - come back after the daily reset." end
    word = (word or ""):upper()
    if #word ~= 5 then return false, "Not enough letters." end
    if not WD.IsValid(word) then return false, "Not in the word list." end
    local answer = WD.Answer(d.day)
    table.insert(d.guesses, word)
    if word == answer or #d.guesses >= WD.MAX_GUESSES then
        d.done, d.won = true, (word == answer)
        local s = d.stats
        s.played = s.played + 1
        if d.won then
            s.wins = s.wins + 1
            s.sum = s.sum + #d.guesses
            s.dist[#d.guesses] = (s.dist[#d.guesses] or 0) + 1
            s.streak = (s.lastWonDay == d.day - 1) and (s.streak + 1) or 1
            s.lastWonDay = d.day
            s.best = math.max(s.best, s.streak)
        else
            s.streak = 0
        end
        self:ShareMine()
    end
    return true
end

-- ---------------------------------------------------------------------
-- Standings sync (guild channel, out of combat, own results only)
-- ---------------------------------------------------------------------
local quiet = ns.Busy

function WD:MyRecord()
    local d, s = db(), db().stats
    local n = d.done and (d.won and #d.guesses or 0) or -1          -- -1: not finished today
    return { day = d.day, n = n, played = s.played, wins = s.wins, streak = s.streak, best = s.best, sum = s.sum }
end

function WD:ShareMine()
    self:CheckDay()
    local ch = ns.DataChannel()
    if not ch then return end
    if quiet() then self.pendingShare = true return end
    self.pendingShare = nil
    local r = self:MyRecord()
    db().standings[ns.me] = r
    ns.Send(PREFIX, ("R^%d^%d^%d^%d^%d^%d^%d"):format(r.day, r.n, r.played, r.wins, r.streak, r.best, r.sum), ch)
end

function WD:RequestStandings()
    local ch = ns.DataChannel()
    if not ch or quiet() then return end
    if self.lastRequest and GetTime() - self.lastRequest < 60 then return end
    self.lastRequest = GetTime()
    ns.Send(PREFIX, "Q", ch)
end

-- a whole number from a message within lo..hi, else nil (nan / inf too)
local function int(v, lo, hi)
    local n = tonumber(v)
    if n and n == n and n % 1 == 0 and n >= lo and n <= hi then return n end
end

function WD:OnMessage(msg, sender)
    local f = ns.Split(msg, "^")
    if f[1] == "R" then
        -- every number checked: a day near today (so it's pruned in time), counts that add up
        local today = WD.Today()
        local r = { day = int(f[2], today - WD.PRUNE_DAYS, today + 1), n = int(f[3], -1, WD.MAX_GUESSES), played = int(f[4], 0, 100000) }
        if not (r.day and r.n and r.played) then return end
        r.wins = int(f[5], 0, r.played)
        if not r.wins then return end
        r.streak, r.best, r.sum = int(f[6], 0, r.played) or 0, int(f[7], 0, r.played) or 0, int(f[8], 0, r.wins * WD.MAX_GUESSES) or 0
        db().standings[sender] = r
        self:Prune()
        -- a request brings a burst of answers: one redraw for them all
        ns.Debounce("wowdle-standings", 0.3, function() if ns.WowdleUI then ns.WowdleUI:Refresh() end end)
    elseif f[1] == "Q" then
        -- answer after a short random wait so a guild doesn't reply all at once
        if (db().stats.played or 0) == 0 or self.replyQueued then return end
        self.replyQueued = true
        C_Timer.After(1 + math.random() * 4, function() WD.replyQueued = nil; WD:ShareMine() end)
    end
end

-- Standings rows, best first: today's solvers by fewest guesses, then everyone by wins.
function WD:Standings()
    local today, rows = WD.Today(), {}
    db().standings[ns.me] = (db().stats.played or 0) > 0 and self:MyRecord() or nil
    for name, r in pairs(db().standings) do
        local t = (r.day == today) and r.n or -1
        rows[#rows + 1] = { name = name, today = t, played = r.played or 0, wins = r.wins or 0,
            streak = (r.day == today or r.day == today - 1) and (r.streak or 0) or 0, best = r.best or 0,
            avg = (r.wins or 0) > 0 and (r.sum or 0) / r.wins or nil }
    end
    local function key(r) return (r.today > 0) and r.today or ((r.today == 0) and 8 or 9) end
    table.sort(rows, function(a, b)
        if key(a) ~= key(b) then return key(a) < key(b) end
        if a.wins ~= b.wins then return a.wins > b.wins end
        return a.name < b.name
    end)
    return rows
end

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------
local V = {}
ns.WowdleUI = V
local W, H = 880, 570          -- the standard module size
local PLAY_W = 420             -- the board and keyboard; the guild standings sit to the right
local TILE, TGAP = 46, 6
local COLORS = {
    g = { 0.33, 0.62, 0.31 },
    y = { 0.77, 0.66, 0.22 },
    b = { 0.23, 0.25, 0.30 },
}
local ROWS_KB = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpWowdle", "wowdle", "WOWDLE", W, H, { mark = { 300, 0.04, -40 },
        onShow = function() WD:CheckDay(); V.typed = ""; WD:RequestStandings(); V:Refresh() end })
    f:SetScript("OnHide", function() if V.input then V.input:ClearFocus() end end)
    self.dayText = UI.Text(f, "GameFontNormal", C.accent, nil, "TOPLEFT", 18, -12)
    self.viewBtn = UI.Button(f, 96, 22, "Refresh", "Ask the guild for their latest results", function() WD.lastRequest = nil; V:ToggleView() end)
    self.viewBtn:SetPoint("RIGHT", self.header.close, "LEFT", -8, 0)

    -- the board
    local board = CreateFrame("Button", nil, f)
    local bw = 5 * TILE + 4 * TGAP
    board:SetSize(bw, 6 * TILE + 5 * TGAP)
    board:SetPoint("TOP", f, "TOPLEFT", PLAY_W / 2, -44)
    board:SetScript("OnClick", function() V:FocusTyping() end)
    self.board = board
    self.tiles = {}
    for r = 1, WD.MAX_GUESSES do
        self.tiles[r] = {}
        for c = 1, 5 do
            local t = CreateFrame("Frame", nil, board, "BackdropTemplate")
            t:SetSize(TILE, TILE)
            t:SetPoint("TOPLEFT", (c - 1) * (TILE + TGAP), -(r - 1) * (TILE + TGAP))
            UI.Skin(t, C.canvas, C.line)
            t:EnableMouse(false)
            t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            t.text:SetPoint("CENTER")
            self.tiles[r][c] = t
        end
    end
    self.message = UI.Text(f, "GameFontHighlight", C.text, nil, "TOP", board, "BOTTOM", 0, -10)

    -- typing: a hidden edit box that only takes keys after you click the board
    local input = CreateFrame("EditBox", nil, f)
    input:SetSize(1, 1)
    input:SetPoint("TOPLEFT", -100, 100)
    input:SetAutoFocus(false)
    input:SetFontObject("ChatFontNormal")
    input:SetAlpha(0)
    input:SetScript("OnTextChanged", function(s, user)
        if not user then return end
        local txt = s:GetText():upper():gsub("[^A-Z]", "")
        s:SetText("")
        for i = 1, #txt do V:Type(txt:sub(i, i)) end
    end)
    input:SetScript("OnKeyDown", function(_, key) if key == "BACKSPACE" then V:Back() end end)
    input:SetScript("OnEnterPressed", function() V:Enter() end)
    input:SetScript("OnEscapePressed", function(s) s:ClearFocus(); V:Refresh() end)
    input:SetScript("OnEditFocusLost", function() V:Refresh() end)
    input:SetScript("OnEditFocusGained", function() V:Refresh() end)
    self.input = input

    -- on-screen keyboard
    self.keys = {}
    local KW, KH, KG = 32, 36, 4
    local ky = -(44 + 6 * TILE + 5 * TGAP + 36)
    for ri, row in ipairs(ROWS_KB) do
        local n = #row + (ri == 3 and 2 or 0)
        local extra = (ri == 3) and 2 * 22 or 0
        local rowW = n * KW + (n - 1) * KG + extra
        local x = -rowW / 2
        local function add(label, w, onClick, key)
            local b = UI.Button(f, w, KH, label, nil, onClick)
            b:SetPoint("TOP", f, "TOPLEFT", PLAY_W / 2 + x + w / 2, ky - (ri - 1) * (KH + KG))
            x = x + w + KG
            if key then self.keys[key] = b end
            return b
        end
        if ri == 3 then add("ENTER", KW + 22, function() V:Enter() end) end
        for i = 1, #row do
            local ch = row:sub(i, i)
            add(ch, KW, function() V:Type(ch) end, ch)
        end
        if ri == 3 then add("DEL", KW + 22, function() V:Back() end) end
    end

    -- the guild standings, always beside the board
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", PLAY_W, -12); sep:SetPoint("BOTTOMLEFT", PLAY_W, 12); sep:SetWidth(1)
    UI.Text(f, "GameFontNormalSmall", C.accent, "GUILD STANDINGS", "TOPLEFT", PLAY_W + 20, -16)
    local st = CreateFrame("Frame", nil, f)
    st:SetPoint("TOPLEFT", PLAY_W + 12, -40)
    st:SetPoint("BOTTOMRIGHT", -12, 12)
    self.standings = st
    local heads = { { "Player", 8 }, { "Today", 170 }, { "Won", 230 }, { "Streak", 290 }, { "Avg", 356 } }
    for _, h in ipairs(heads) do
        UI.Text(st, "GameFontNormalSmall", C.muted, h[1], "TOPLEFT", h[2], -4)
    end
    self.stRows = {}
    for i = 1, 18 do
        local y = -24 - (i - 1) * 24
        local r = {}
        r.name = UI.Text(st, "GameFontHighlight", nil, nil, "TOPLEFT", 8, y); r.name:SetWidth(156); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.today = UI.Text(st, "GameFontHighlight", nil, nil, "TOPLEFT", 170, y)
        r.won = UI.Text(st, "GameFontHighlight", nil, nil, "TOPLEFT", 230, y)
        r.streak = UI.Text(st, "GameFontHighlight", nil, nil, "TOPLEFT", 290, y)
        r.avg = UI.Text(st, "GameFontHighlight", nil, nil, "TOPLEFT", 356, y)
        self.stRows[i] = r
    end
    self.stEmpty = UI.Text(st, "GameFontHighlightSmall", C.muted, "No results yet. Standings fill in as guildmates play.", "TOPLEFT", 8, -30)
    -- more players than rows: the mouse wheel scrolls
    self.stOffset = 0
    st:EnableMouseWheel(true)
    st:SetScript("OnMouseWheel", function(_, d) V.stOffset = V.stOffset - d; V:Refresh() end)
    self.typed = ""
end

function V:FocusTyping()
    if db().done then return end
    self.input:SetFocus()
end

function V:Type(ch)
    if db().done then return end
    if #self.typed < 5 then self.typed = self.typed .. ch; self.flash = nil; self:Refresh() end
end

function V:Back()
    if #self.typed > 0 then self.typed = self.typed:sub(1, -2); self.flash = nil; self:Refresh() end
end

function V:Enter()
    local ok, err = WD:Submit(self.typed)
    if ok then self.typed = "" else self.flash = err end
    if db().done then self.input:ClearFocus() end
    self:Refresh()
end

-- (the standings are always shown now: this just asks for fresh ones)
function V:ToggleView()
    WD:RequestStandings()
    self:Refresh()
end

function V:Refresh()
    if not self.frame then return end
    local d = db()
    local day = WD:CheckDay()
    self.dayText:SetText(("Wowdle #%d"):format(day))
    local answer = WD.Answer(day)
    -- board
    local best = {}
    for r = 1, WD.MAX_GUESSES do
        local guess = d.guesses[r]
        local res = guess and WD.Score(guess, answer)
        local typing = (not guess) and (r == #d.guesses + 1) and not d.done
        for c = 1, 5 do
            local t = self.tiles[r][c]
            local ch = guess and guess:sub(c, c) or (typing and self.typed:sub(c, c)) or ""
            t.text:SetText(ch)
            if res then
                local col = COLORS[res[c]]
                t:SetBackdropColor(col[1], col[2], col[3], 1)
                t:SetBackdropBorderColor(col[1], col[2], col[3], 1)
                local prev = best[ch]
                if res[c] == "g" or (res[c] == "y" and prev ~= "g") or not prev then best[ch] = res[c] end
            else
                t:SetBackdropColor(C.canvas[1], C.canvas[2], C.canvas[3], C.canvas[4] or 1)
                local active = typing and ch ~= ""
                t:SetBackdropBorderColor(active and C.accent[1] or C.line[1], active and C.accent[2] or C.line[2], active and C.accent[3] or C.line[3], 1)
            end
        end
    end
    -- keyboard colors
    for ch, b in pairs(self.keys) do
        local st = best[ch]
        if st then
            local col = COLORS[st]
            b:SetBackdropColor(col[1], col[2], col[3], 1)
        else
            UI.Paint(b)
        end
    end
    -- message
    local msg
    if self.flash then msg = "|cffffa340" .. self.flash .. "|r"
    elseif d.done and d.won then msg = ("|cff66e08cSolved in %d!|r  Next Wowdle after the daily reset."):format(#d.guesses)
    elseif d.done then msg = ("The word was |cffffd94d%s|r. Next Wowdle after the daily reset."):format(answer)
    elseif self.input:HasFocus() then msg = "|cff8a8f9cTyping... (Esc to stop)|r"
    else msg = "|cff8a8f9cClick the board to type, or use the keys below.|r" end
    self.message:SetText(msg)
    -- standings
    if self.standings:IsShown() then
        local rows = WD:Standings()
        self.stEmpty:SetShown(#rows == 0)
        self.stOffset = math.max(0, math.min(#rows - #self.stRows, self.stOffset or 0))
        for i, r in ipairs(self.stRows) do
            local e = rows[i + self.stOffset]
            r.name:SetText(e and (ns.Short and ns.Short(e.name) or e.name) or "")
            r.today:SetText(e and ((e.today > 0 and ("%d/6"):format(e.today)) or (e.today == 0 and "|cffff5a5aX/6|r") or "|cff8a8f9c-|r") or "")
            r.won:SetText(e and ("%d/%d"):format(e.wins, e.played) or "")
            r.streak:SetText(e and tostring(e.streak) or "")
            r.avg:SetText(e and (e.avg and ("%.1f"):format(e.avg) or "-") or "")
        end
    end
end

ns.RegisterModule({
    key = "wowdle", name = "Wowdle", icon = ns.MEDIA .. "Wowdle", group = "games", order = 3,
    desc = "The daily guild word game - WoW terms and everyday words.",
    view = V,
})
