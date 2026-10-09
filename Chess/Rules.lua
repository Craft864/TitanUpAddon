-- Titan Up - Chess/Rules.lua
-- The full rules of chess, with no game or window code: every client runs
-- this on every move it receives, so nobody can make an illegal move (the
-- same idea as Death Roll's strict roll check).
--
-- Squares are 0..63, a1 = 0, b1 = 1 ... h8 = 63 (index = rank * 8 + file).
-- Pieces are letters: white "PNBRQK", black "pnbrqk"; an empty square is nil.
-- A position: { b = board, side = "w"|"b", castle = { K=, Q=, k=, q= },
--               ep = en passant target square or nil, half = 50-move clock,
--               full = move number }.
-- Moves travel as UCI text: "e2e4", "e7e8q" (promotion letter lowercase).
-- Draws by threefold repetition and the 50-move rule are automatic.
local ADDON, ns = ...

local R = {}
ns.ChessRules = R

local floor = math.floor

-- ---------------------------------------------------------------------
-- Squares
-- ---------------------------------------------------------------------
local FILES = "abcdefgh"
function R.Name(i) return FILES:sub(i % 8 + 1, i % 8 + 1) .. (floor(i / 8) + 1) end

function R.Square(s)
    if type(s) ~= "string" or #s ~= 2 then return nil end
    local f = FILES:find(s:sub(1, 1), 1, true)
    local r = tonumber(s:sub(2, 2))
    if not f or not r or r < 1 or r > 8 then return nil end
    return (r - 1) * 8 + (f - 1)
end

local function colorOf(p)
    if not p then return nil end
    return (p == p:upper()) and "w" or "b"
end
R.ColorOf = colorOf

local function other(side) return side == "w" and "b" or "w" end
R.Other = other

-- ---------------------------------------------------------------------
-- Positions
-- ---------------------------------------------------------------------
local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
R.START = START

function R.FromFEN(fen)
    local placement, side, castle, ep, half, full = (fen or ""):match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)")
    if not placement then return nil end
    local b = {}
    local rank, file = 7, 0
    for c in placement:gmatch(".") do
        if c == "/" then
            rank, file = rank - 1, 0
        elseif c:match("%d") then
            file = file + tonumber(c)
        elseif c:match("[pnbrqkPNBRQK]") then
            if rank < 0 or file > 7 then return nil end
            b[rank * 8 + file] = c
            file = file + 1
        else
            return nil
        end
    end
    local st = { b = b, side = (side == "b") and "b" or "w", castle = {}, ep = nil,
                 half = tonumber(half) or 0, full = tonumber(full) or 1 }
    for c in castle:gmatch("[KQkq]") do st.castle[c] = true end
    if ep ~= "-" then st.ep = R.Square(ep) end
    return st
end

function R.New() return R.FromFEN(START) end

local function copy(st)
    local b = {}
    for i = 0, 63 do b[i] = st.b[i] end
    return { b = b, side = st.side, castle = { K = st.castle.K, Q = st.castle.Q, k = st.castle.k, q = st.castle.q },
             ep = st.ep, half = st.half, full = st.full }
end
R.Copy = copy

-- ---------------------------------------------------------------------
-- Attacks
-- ---------------------------------------------------------------------
local KNIGHT = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local ROOK = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local BISHOP = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function at(b, f, r)
    if f < 0 or f > 7 or r < 0 or r > 7 then return false end
    return b[r * 8 + f]
end

-- Is square sq attacked by any piece of side `by`?
function R.Attacked(b, sq, by)
    local f, r = sq % 8, floor(sq / 8)
    local white = by == "w"
    -- pawns
    local pr = white and r - 1 or r + 1
    local pawn = white and "P" or "p"
    if at(b, f - 1, pr) == pawn or at(b, f + 1, pr) == pawn then return true end
    -- knights and king
    local knight, king = white and "N" or "n", white and "K" or "k"
    for _, d in ipairs(KNIGHT) do if at(b, f + d[1], r + d[2]) == knight then return true end end
    for _, d in ipairs(KING) do if at(b, f + d[1], r + d[2]) == king then return true end end
    -- sliders
    local rook, bishop, queen = white and "R" or "r", white and "B" or "b", white and "Q" or "q"
    for _, d in ipairs(ROOK) do
        local x, y = f + d[1], r + d[2]
        while x >= 0 and x <= 7 and y >= 0 and y <= 7 do
            local p = b[y * 8 + x]
            if p then
                if p == rook or p == queen then return true end
                break
            end
            x, y = x + d[1], y + d[2]
        end
    end
    for _, d in ipairs(BISHOP) do
        local x, y = f + d[1], r + d[2]
        while x >= 0 and x <= 7 and y >= 0 and y <= 7 do
            local p = b[y * 8 + x]
            if p then
                if p == bishop or p == queen then return true end
                break
            end
            x, y = x + d[1], y + d[2]
        end
    end
    return false
end

local function kingSquare(b, side)
    local k = side == "w" and "K" or "k"
    for i = 0, 63 do if b[i] == k then return i end end
end
R.KingSquare = kingSquare

function R.InCheck(st, side)
    side = side or st.side
    local k = kingSquare(st.b, side)
    return k ~= nil and R.Attacked(st.b, k, other(side))
end

-- ---------------------------------------------------------------------
-- Moves
-- ---------------------------------------------------------------------
-- A move: { from, to, promo = "q"|"r"|"b"|"n"|nil, ep = true, castle = "K"|"Q" }
local function add(list, from, to, promo, flag, val)
    local m = { from = from, to = to, promo = promo }
    if flag then m[flag] = val end
    list[#list + 1] = m
end

local function pseudo(st)
    local b, side, list = st.b, st.side, {}
    local white = side == "w"
    for sq = 0, 63 do
        local p = b[sq]
        if p and colorOf(p) == side then
            local f, r = sq % 8, floor(sq / 8)
            local kind = p:lower()
            if kind == "p" then
                local dir = white and 1 or -1
                local last = white and 7 or 0
                local startRank = white and 1 or 6
                local r1 = r + dir
                if r1 >= 0 and r1 <= 7 then
                    local fwd = r1 * 8 + f
                    if not b[fwd] then
                        if r1 == last then
                            for _, pr in ipairs({ "q", "r", "b", "n" }) do add(list, sq, fwd, pr) end
                        else
                            add(list, sq, fwd)
                            local r2 = r + 2 * dir
                            if r == startRank and not b[r2 * 8 + f] then add(list, sq, r2 * 8 + f) end
                        end
                    end
                    for _, df in ipairs({ -1, 1 }) do
                        local x = f + df
                        if x >= 0 and x <= 7 then
                            local to = r1 * 8 + x
                            local t = b[to]
                            if t and colorOf(t) ~= side then
                                if r1 == last then
                                    for _, pr in ipairs({ "q", "r", "b", "n" }) do add(list, sq, to, pr) end
                                else
                                    add(list, sq, to)
                                end
                            elseif not t and st.ep == to then
                                add(list, sq, to, nil, "ep", true)
                            end
                        end
                    end
                end
            elseif kind == "n" or kind == "k" then
                for _, d in ipairs(kind == "n" and KNIGHT or KING) do
                    local x, y = f + d[1], r + d[2]
                    if x >= 0 and x <= 7 and y >= 0 and y <= 7 then
                        local t = b[y * 8 + x]
                        if not t or colorOf(t) ~= side then add(list, sq, y * 8 + x) end
                    end
                end
                if kind == "k" then
                    -- castling: rights, empty squares between, rook in place, and the
                    -- king doesn't start in, cross or land on an attacked square
                    local home = white and 4 or 60
                    local enemy = other(side)
                    local K, Q = white and "K" or "k", white and "Q" or "q"
                    local rook = white and "R" or "r"
                    if sq == home and not R.Attacked(b, home, enemy) then
                        if st.castle[K] and b[home + 3] == rook and not b[home + 1] and not b[home + 2]
                                and not R.Attacked(b, home + 1, enemy) and not R.Attacked(b, home + 2, enemy) then
                            add(list, sq, home + 2, nil, "castle", "K")
                        end
                        if st.castle[Q] and b[home - 4] == rook and not b[home - 1] and not b[home - 2] and not b[home - 3]
                                and not R.Attacked(b, home - 1, enemy) and not R.Attacked(b, home - 2, enemy) then
                            add(list, sq, home - 2, nil, "castle", "Q")
                        end
                    end
                end
            else
                local dirs = (kind == "r") and ROOK or (kind == "b") and BISHOP or nil
                local function slide(ds)
                    for _, d in ipairs(ds) do
                        local x, y = f + d[1], r + d[2]
                        while x >= 0 and x <= 7 and y >= 0 and y <= 7 do
                            local to = y * 8 + x
                            local t = b[to]
                            if t then
                                if colorOf(t) ~= side then add(list, sq, to) end
                                break
                            end
                            add(list, sq, to)
                            x, y = x + d[1], y + d[2]
                        end
                    end
                end
                if dirs then slide(dirs) else slide(ROOK); slide(BISHOP) end
            end
        end
    end
    return list
end

-- Castling rights lost when a piece leaves or is captured on these squares.
local RIGHTS = { [0] = "Q", [7] = "K", [4] = "KQ", [56] = "q", [63] = "k", [60] = "kq" }

-- A new position with move m made (m is assumed pseudo-legal).
function R.Apply(st, m)
    local n = copy(st)
    local b = n.b
    local p = b[m.from]
    local captured = b[m.to]
    b[m.to], b[m.from] = p, nil
    if m.ep then
        local behind = (st.side == "w") and m.to - 8 or m.to + 8
        captured = b[behind]
        b[behind] = nil
    end
    if m.castle then
        local home = (st.side == "w") and 0 or 56
        if m.castle == "K" then b[home + 5], b[home + 7] = b[home + 7], nil
        else b[home + 3], b[home] = b[home], nil end
    end
    if m.promo then b[m.to] = (st.side == "w") and m.promo:upper() or m.promo end
    for _, sq in ipairs({ m.from, m.to }) do
        local lost = RIGHTS[sq]
        if lost then for c in lost:gmatch(".") do n.castle[c] = nil end end
    end
    n.ep = nil
    if p:lower() == "p" and math.abs(m.to - m.from) == 16 then n.ep = (m.from + m.to) / 2 end
    n.half = (p:lower() == "p" or captured) and 0 or st.half + 1
    if st.side == "b" then n.full = st.full + 1 end
    n.side = other(st.side)
    return n
end

function R.Legal(st)
    local out = {}
    local side = st.side
    for _, m in ipairs(pseudo(st)) do
        local n = R.Apply(st, m)
        if not R.InCheck(n, side) then out[#out + 1] = m end
    end
    return out
end

function R.UCI(m) return R.Name(m.from) .. R.Name(m.to) .. (m.promo or "") end

-- The legal move this UCI text names, or nil.
function R.Find(st, uci, legal)
    if type(uci) ~= "string" then return nil end
    for _, m in ipairs(legal or R.Legal(st)) do
        if R.UCI(m) == uci then return m end
    end
end

-- Move count to depth (for testing the move generator against known numbers).
function R.Perft(st, depth)
    if depth == 0 then return 1 end
    local moves = R.Legal(st)
    if depth == 1 then return #moves end
    local n = 0
    for _, m in ipairs(moves) do n = n + R.Perft(R.Apply(st, m), depth - 1) end
    return n
end

-- ---------------------------------------------------------------------
-- Notation (the move list shows standard algebraic notation: Nf3, exd5, O-O)
-- ---------------------------------------------------------------------
-- (noCheck: leave off the + / # suffix; the caller adds it)
function R.SAN(st, m, legal, noCheck)
    legal = legal or R.Legal(st)
    local b = st.b
    local p = b[m.from]
    local kind = p:upper()
    local s
    if m.castle then
        s = (m.castle == "K") and "O-O" or "O-O-O"
    elseif kind == "P" then
        local capture = b[m.to] or m.ep
        s = (capture and (FILES:sub(m.from % 8 + 1, m.from % 8 + 1) .. "x") or "") .. R.Name(m.to)
        if m.promo then s = s .. "=" .. m.promo:upper() end
    else
        -- another piece of the same kind that can reach the same square
        local sameFile, sameRank, ambiguous = false, false, false
        for _, o in ipairs(legal) do
            if o.to == m.to and o.from ~= m.from and b[o.from] == p then
                ambiguous = true
                if o.from % 8 == m.from % 8 then sameFile = true end
                if floor(o.from / 8) == floor(m.from / 8) then sameRank = true end
            end
        end
        local from = R.Name(m.from)
        local dis = ""
        if ambiguous then
            if not sameFile then dis = from:sub(1, 1)
            elseif not sameRank then dis = from:sub(2, 2)
            else dis = from end
        end
        s = kind .. dis .. (b[m.to] and "x" or "") .. R.Name(m.to)
    end
    if noCheck then return s end
    local n = R.Apply(st, m)
    if R.InCheck(n) then s = s .. ((#R.Legal(n) == 0) and "#" or "+") end
    return s
end

-- ---------------------------------------------------------------------
-- Game end
-- ---------------------------------------------------------------------
-- A key for repetition: pieces, side, castling, and the en passant square
-- only when a pawn could actually take there.
function R.Key(st)
    local t = {}
    for i = 0, 63 do t[i + 1] = st.b[i] or "." end
    local ep = "-"
    if st.ep then
        local pawn = st.side == "w" and "P" or "p"
        local from = st.side == "w" and st.ep - 8 or st.ep + 8
        local f = st.ep % 8
        if (f > 0 and st.b[from - 1] == pawn) or (f < 7 and st.b[from + 1] == pawn) then ep = R.Name(st.ep) end
    end
    local c = (st.castle.K and "K" or "") .. (st.castle.Q and "Q" or "") .. (st.castle.k and "k" or "") .. (st.castle.q and "q" or "")
    return table.concat(t) .. st.side .. c .. ep
end

-- Neither side can ever mate: K v K, K+minor v K, K+B v K+B on same-colour squares.
function R.Insufficient(b)
    local minors, bishops = {}, {}
    for i = 0, 63 do
        local p = b[i]
        if p then
            local k = p:lower()
            if k == "p" or k == "r" or k == "q" then return false end
            if k == "n" or k == "b" then minors[#minors + 1] = p end
            if k == "b" then bishops[#bishops + 1] = (i % 8 + floor(i / 8)) % 2 end
        end
    end
    if #minors <= 1 then return true end
    if #minors == #bishops then
        for _, c in ipairs(bishops) do if c ~= bishops[1] then return false end end
        return true
    end
    return false
end

-- Piece values for the material count (+3 beside a name).
R.VALUE = { p = 1, n = 3, b = 3, r = 5, q = 9, k = 0 }

-- White's material minus Black's on a board.
function R.Material(b)
    local d = 0
    for i = 0, 63 do
        local p = b[i]
        if p then
            local v = R.VALUE[p:lower()]
            d = d + ((p == p:upper()) and v or -v)
        end
    end
    return d
end

-- ---------------------------------------------------------------------
-- A whole game from its move list
-- ---------------------------------------------------------------------
-- A game grows one move at a time (R.Step), so a new move costs one
-- position, not a replay of the whole game.
-- game = { pos = current position, legal = its legal moves, san = { ... },
--          taken = { [ply] = piece captured on that move, or false },
--          moves = { move tables }, uci = { ... }, last = last move,
--          over = reason|nil, winner = "w"|"b"|nil, seen = repetition counts }
-- reason: "mate", "stalemate", "repetition", "fifty", "material".
function R.Begin()
    local st = R.New()
    return { pos = st, legal = R.Legal(st), san = {}, moves = {}, uci = {}, taken = {}, seen = { [R.Key(st)] = 1 } }
end

-- Add one move (UCI); false when it's illegal or the game is already over.
function R.Step(g, uci)
    if g.over then return false end
    local st = g.pos
    local m = R.Find(st, uci, g.legal)
    if not m then return false end
    local san = R.SAN(st, m, g.legal, true)
    -- the piece taken (en passant: the pawn beside, not the empty square)
    local taken = st.b[m.to]
    if m.ep then taken = (st.side == "w") and "p" or "P" end
    local n = R.Apply(st, m)
    local legal = R.Legal(n)
    if R.InCheck(n) then san = san .. ((#legal == 0) and "#" or "+") end
    local i = #g.moves + 1
    g.moves[i], g.uci[i], g.san[i] = m, uci, san
    g.taken[i] = taken or false
    g.pos, g.legal, g.last = n, legal, m
    local k = R.Key(n)
    g.seen[k] = (g.seen[k] or 0) + 1
    g.over, g.winner = R.Ended(n, g.seen[k], legal)
    return true
end

-- R.Play(list of UCI) -> game, or nil + the ply that was illegal.
function R.Play(moves)
    local g = R.Begin()
    for i, uci in ipairs(moves or {}) do
        if not R.Step(g, uci) then return nil, i end
    end
    return g
end

-- reason, winner for a position (reps = how often it has occurred).
function R.Ended(st, reps, legal)
    if #(legal or R.Legal(st)) == 0 then
        if R.InCheck(st) then return "mate", other(st.side) end
        return "stalemate"
    end
    if (reps or 1) >= 3 then return "repetition" end
    if st.half >= 100 then return "fifty" end
    if R.Insufficient(st.b) then return "material" end
end
