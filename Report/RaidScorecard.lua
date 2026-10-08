-- Titan Up - Report/RaidScorecard.lua
-- Raid Scorecard (Raid Tools): over a raid week (or all kept weeks), per
-- player - how often they died first, were in the first 3 dead, and died
-- with a defensive available, with counts and percentages. Click a number
-- for the pulls it happened on; click a pull for its full death order.
--   * Built from the Pull Report's Heroic / Mythic raid pulls (never test
--     pulls). Deaths after the raid leader's wipe-call mark don't count;
--     close calls never count. Percentages are over the pulls they were in.
--   * Kept by raid week (Tuesday reset), 4 weeks; clear a week or all.
--   * Sync from raid leader: asks the leader's Titan Up for their (most
--     complete) copy of the week, out of combat; merged without duplicates.
--   * Export CSV: one row per death, for Google Sheets / Excel.
-- Nothing runs in combat; the numbers are worked out when you open it.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local RS = {}
ns.RaidScorecard = RS

local PREFIX = "TitanUpRS"
local WEEK = 7 * 86400
local KEEP_WEEKS = 4
local CHUNK = 230
local DIFF = { [15] = "Heroic", [16] = "Mythic" }

local function db() return ns.udb.raidHistory end

function RS:Init()
    ns.Listen(PREFIX, "guild", function(msg, sender) RS:OnMessage(msg, sender) end)
    ns.On("PLAYER_REGEN_ENABLED", function() if RS.pendingReply then C_Timer.After(2, function() RS:SendReply() end) end end)
end

-- ---------------------------------------------------------------------
-- Weeks (Tuesday reset)
-- ---------------------------------------------------------------------
function RS.CurrentWeekStart()
    local now = GetServerTime and GetServerTime() or time()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    local start
    if type(untilReset) == "number" and untilReset > 0 then
        start = now + untilReset - WEEK
    else
        -- US: Tuesday 15:00 UTC (a known Tuesday reset, stepped in whole weeks)
        local ref = 1791126000 - 5 * 86400               -- Tue 2026-09-29 15:00 UTC
        start = ref + math.floor((now - ref) / WEEK) * WEEK
    end
    return math.floor(start / 3600 + 0.5) * 3600
end

function RS.WeekOf(ts)
    local w = RS.CurrentWeekStart()
    while ts < w do w = w - WEEK end
    while ts >= w + WEEK do w = w + WEEK end
    return w
end

-- a week's record (made when first needed)
function RS:Week(wk)
    local w = db().weeks[wk] or { start = wk, pulls = {} }
    db().weeks[wk] = w
    return w
end

function RS:WeekKeys()
    local keys = {}
    for k in pairs(db().weeks) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a > b end)       -- newest first
    return keys
end

-- ---------------------------------------------------------------------
-- Storing pulls (called by the Pull Report)
-- ---------------------------------------------------------------------
local function cleanText(s) return (tostring(s or ""):gsub("[%c;|,\t]", " ")) end

function RS:Compact(pull)
    local deaths = {}
    for _, d in ipairs(pull.deaths or {}) do
        local dflag = d.nodata and -1 or ((#(d.major or {}) > 0) and 2 or ((#(d.minor or {}) > 0) and 1 or 0))
        local killer = d.hits and d.hits[1] and d.hits[1].spell or ""
        deaths[#deaths + 1] = { o = d.owner, c = d.class, t = d.ft or 0, k = cleanText(killer), d = dflag,
                                p = d.pr and true or false, h = d.hr and true or false, s = d.kind == "save" or nil }
    end
    local roster = {}
    for _, n in ipairs(pull.roster or {}) do roster[#roster + 1] = n end
    return { key = pull.enc .. ":" .. pull.start, enc = pull.enc, name = pull.name, diff = pull.diff, start = pull.start, n = pull.n,
             result = pull.result, dur = pull.dur, leader = pull.leader, wipeAt = pull.wipeAt, roster = roster, deaths = deaths }
end

function RS:Store(pull)
    if not (pull and (pull.diff == 15 or pull.diff == 16)) then return end
    local week = self:Week(RS.WeekOf(pull.start))
    local c = self:Compact(pull)
    week.pulls[c.key] = c
    self:Trim()
    if ns.RaidScorecardUI then ns.RaidScorecardUI:Refresh() end
end

-- a pull under 20 seconds (not a kill): not counted, only tallied per boss
function RS:CountShort(pull)
    if not (pull and pull.start) then return end
    local week = self:Week(RS.WeekOf(pull.start))
    week.short = week.short or {}
    local name = pull.name or "Encounter"
    week.short[name] = (week.short[name] or 0) + 1
    if ns.RaidScorecardUI then ns.RaidScorecardUI:Refresh() end
end

function RS:ShortCount(wk, boss)
    local n = 0
    for k, w in pairs(db().weeks) do
        if not wk or k == wk then
            for name, c in pairs(w.short or {}) do if not boss or name == boss then n = n + c end end
        end
    end
    return n
end

function RS:Trim()
    local keys = self:WeekKeys()
    for i = KEEP_WEEKS + 1, #keys do db().weeks[keys[i]] = nil end
end

function RS:Clear(wk)
    if wk then db().weeks[wk] = nil else db().weeks = {} end
    if ns.RaidScorecardUI then ns.RaidScorecardUI.drill, ns.RaidScorecardUI.drillPull = nil, nil; ns.RaidScorecardUI:Refresh() end
end

-- ---------------------------------------------------------------------
-- The numbers
-- ---------------------------------------------------------------------
-- Deaths that count in a pull: real deaths (not close calls), not after the
-- wipe call, in order.
function RS.Counted(p)
    local out = {}
    for _, d in ipairs(p.deaths or {}) do
        if not d.s and not (p.wipeAt and (d.t or 0) > p.wipeAt) then out[#out + 1] = d end
    end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

-- every death (not close calls) in time order, and each counted one's place
function RS.DeathOrder(p)
    local order, all = {}, {}
    for i, d in ipairs(RS.Counted(p)) do order[d] = i end
    for _, d in ipairs(p.deaths or {}) do if not d.s then all[#all + 1] = d end end
    table.sort(all, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return all, order
end

function RS:Pulls(wk, boss)
    local list = {}
    local weeks = wk and { db().weeks[wk] } or {}
    if not wk then for _, w in pairs(db().weeks) do weeks[#weeks + 1] = w end end
    for _, w in ipairs(weeks) do
        for _, p in pairs(w.pulls or {}) do
            if not boss or p.name == boss then list[#list + 1] = p end
        end
    end
    table.sort(list, function(a, b) return a.start < b.start end)
    return list
end

-- bosses with pulls in that week (for the boss filter)
function RS:Bosses(wk)
    local seen, list = {}, {}
    for _, p in ipairs(self:Pulls(wk)) do if p.name and not seen[p.name] then seen[p.name] = true; list[#list + 1] = p.name end end
    table.sort(list)
    return list
end

function RS:Stats(wk, boss)
    local by = {}
    local function row(name, class)
        local r = by[name]
        if not r then
            r = { name = name, class = class, pulls = 0, first = {}, top3 = {}, defDeaths = {}, potDeaths = {}, hsDeaths = {}, deaths = 0, withData = 0 }
            by[name] = r
        end
        r.class = r.class or class
        return r
    end
    for _, p in ipairs(self:Pulls(wk, boss)) do
        local present = {}
        for _, n in ipairs(p.roster or {}) do present[n] = true end
        for _, d in ipairs(p.deaths or {}) do present[d.o] = true end
        for n in pairs(present) do row(n).pulls = row(n).pulls + 1 end
        local counted = RS.Counted(p)
        for i, d in ipairs(counted) do
            local r = row(d.o, d.c)
            r.deaths = r.deaths + 1
            if i == 1 then r.first[#r.first + 1] = p end
            if i <= 3 then r.top3[#r.top3 + 1] = p end
            if d.d >= 0 then
                r.withData = r.withData + 1
                if d.d >= 1 then r.defDeaths[#r.defDeaths + 1] = p end
                if d.p then r.potDeaths[#r.potDeaths + 1] = p end
                if d.h then r.hsDeaths[#r.hsDeaths + 1] = p end
            end
        end
    end
    local rows = {}
    for _, r in pairs(by) do rows[#rows + 1] = r end
    table.sort(rows, function(a, b)
        if #a.first ~= #b.first then return #a.first > #b.first end
        if #a.top3 ~= #b.top3 then return #a.top3 > #b.top3 end
        return a.name < b.name
    end)
    return rows
end

local function pct(n, d) return d > 0 and math.floor(n / d * 100 + 0.5) or 0 end

-- ---------------------------------------------------------------------
-- CSV export: one row per death
-- ---------------------------------------------------------------------
local function csv(v)
    v = tostring(v or "")
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

function RS:CSV(wk, boss)
    local lines = { "Week,Date,Boss,Difficulty,Pull,Result,Player,Time of death,Death order,Killed by,Defensive available,Potion available,Healthstone available,After wipe call" }
    for _, p in ipairs(self:Pulls(wk, boss)) do
        local all, order = RS.DeathOrder(p)
        for _, d in ipairs(all) do
            local t = math.floor(d.t or 0)
            lines[#lines + 1] = table.concat({
                csv(date("%Y-%m-%d", RS.WeekOf(p.start))), csv(date("%Y-%m-%d %H:%M", p.start)), csv(p.name), csv(DIFF[p.diff] or p.diff),
                csv(p.n or ""), csv(p.result == "kill" and "Kill" or "Wipe"), csv((d.o or ""):match("^[^-]+") or d.o),
                csv(("%d:%02d"):format(math.floor(t / 60), t % 60)), csv(order[d] or ""), csv(d.k),
                csv(d.d == -1 and "no data" or (d.d == 2 and "yes" or (d.d == 1 and "minor only" or "no"))),
                csv(d.d == -1 and "" or (d.p and "yes" or "no")), csv(d.d == -1 and "" or (d.h and "yes" or "no")),
                csv((p.wipeAt and (d.t or 0) > p.wipeAt) and "yes" or "no"),
            }, ",")
        end
    end
    return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------
-- Sync from raid leader (guild channel, out of combat)
-- ---------------------------------------------------------------------
--   Q wk leader reqID          please send me your week
--   D reqID part count chunk   a piece of the answer
function RS.Serialize(week)
    local out = {}
    for _, p in pairs(week.pulls or {}) do
        local ds = {}
        for _, d in ipairs(p.deaths or {}) do
            ds[#ds + 1] = table.concat({ d.o or "", d.c or "", ("%.1f"):format(d.t or 0), d.k or "", d.d or 0, d.p and 1 or 0, d.h and 1 or 0, d.s and 1 or 0 }, "|")
        end
        out[#out + 1] = table.concat({ p.key, p.enc or 0, cleanText(p.name), p.diff or 0, p.start or 0, p.result or "", p.dur and ("%.0f"):format(p.dur) or "",
            p.leader or "", p.wipeAt and ("%.1f"):format(p.wipeAt) or "", table.concat(p.roster or {}, ","), table.concat(ds, ";"), p.n or "" }, "\t")
    end
    return tostring(week.start) .. "\n" .. table.concat(out, "\n")
end

function RS.Deserialize(text)
    local lines = ns.Split(text, "\n")
    local week = { start = tonumber(lines[1]), pulls = {} }
    if not week.start then return nil end
    for i = 2, #lines do
        local f = ns.Split(lines[i], "\t")
        if #f >= 11 and f[1] ~= "" then
            local p = { key = f[1], enc = tonumber(f[2]), name = f[3], diff = tonumber(f[4]), start = tonumber(f[5]), result = f[6] ~= "" and f[6] or nil,
                        dur = tonumber(f[7]), leader = f[8] ~= "" and f[8] or nil, wipeAt = tonumber(f[9]), roster = {}, deaths = {}, n = tonumber(f[12] or "") }
            for n in (f[10] or ""):gmatch("[^,]+") do p.roster[#p.roster + 1] = n end
            for ds in (f[11] or ""):gmatch("[^;]+") do
                local x = ns.Split(ds, "|")
                if #x >= 8 then
                    p.deaths[#p.deaths + 1] = { o = x[1], c = x[2] ~= "" and x[2] or nil, t = tonumber(x[3]) or 0, k = x[4], d = tonumber(x[5]) or 0,
                                                p = x[6] == "1", h = x[7] == "1", s = x[8] == "1" or nil }
                end
            end
            if p.start and (p.diff == 15 or p.diff == 16) then week.pulls[p.key] = p end
        end
    end
    return week
end

local function dataCount(p) local n = 0 for _, d in ipairs(p.deaths or {}) do if (d.d or -1) >= 0 then n = n + 1 end end return n end

-- Merge a week from the raid leader: new pulls are added; a pull keeps
-- whichever copy has more data; the leader's wipe-call mark wins.
function RS:Merge(week, from)
    if not week or not week.start then return 0 end
    local mine = self:Week(RS.WeekOf(week.start))
    local added = 0
    for key, p in pairs(week.pulls) do
        local have = mine.pulls[key]
        if not have then
            mine.pulls[key] = p
            added = added + 1
        else
            if dataCount(p) > dataCount(have) or #(p.deaths or {}) > #(have.deaths or {}) then
                p.wipeAt = (p.leader == from) and p.wipeAt or have.wipeAt or p.wipeAt
                mine.pulls[key] = p
                added = added + 1
            elseif p.leader == from and p.wipeAt ~= have.wipeAt then
                have.wipeAt = p.wipeAt
            end
            local seen = {}
            for _, n in ipairs(mine.pulls[key].roster or {}) do seen[n] = true end
            for _, n in ipairs((mine.pulls[key] == p and have or p).roster or {}) do
                if not seen[n] then table.insert(mine.pulls[key].roster, n) end
            end
        end
    end
    self:Trim()
    return added
end

-- the week's raid leader (most pulls led), or your group's leader
function RS:LeaderFor(wk)
    local count, best, bestN = {}, nil, 0
    for _, p in ipairs(self:Pulls(wk)) do
        if p.leader then
            count[p.leader] = (count[p.leader] or 0) + 1
            if count[p.leader] > bestN then best, bestN = p.leader, count[p.leader] end
        end
    end
    return best or (IsInGroup() and ns.LeaderName() or nil)
end

function RS:RequestSync(wk)
    local ch = ns.DataChannel()
    if not ch then ns.Print("Syncing needs a guild.") return end
    if InCombatLockdown() then ns.Print("Try again out of combat.") return end
    wk = wk or RS.CurrentWeekStart()
    local leader = self:LeaderFor(wk)
    if not leader then ns.Print("No raid leader known for that week yet - join their group, or run a pull with them first.") return end
    if leader == ns.me then ns.Print("You're the raid leader for that week - your copy is the full one.") return end
    self.request = { id = tostring(GetServerTime and GetServerTime() or time()), from = leader, parts = {}, got = 0 }
    ns.Send(PREFIX, ("Q^%d^%s^%s"):format(wk, leader, self.request.id), ch)
    ns.Print(("Asking %s for that week's raid data..."):format(ns.Short and ns.Short(leader) or leader))
    C_Timer.After(30, function()
        if RS.request and RS.request.got == 0 then ns.Print("No answer - the raid leader may be offline or busy."); RS.request = nil end
    end)
end

function RS:SendReply()
    local r = self.pendingReply
    if not r or InCombatLockdown() then return end
    self.pendingReply = nil
    local ch = ns.DataChannel()
    local week = db().weeks[r.wk]
    if not ch or not week then return end
    local packed = ns.Codec.Compress(RS.Serialize(week))
    if not packed then return end
    local text = ns.Codec.EncodeForPrint(packed)
    local n = math.ceil(#text / CHUNK)
    for i = 1, n do
        -- spaced out so the guild channel isn't flooded
        C_Timer.After((i - 1) * 0.15, function()
            ns.Send(PREFIX, ("D^%s^%d^%d^%s"):format(r.id, i, n, text:sub((i - 1) * CHUNK + 1, i * CHUNK)), ch)
        end)
    end
end

function RS:OnMessage(msg, sender)
    local wk, leader, id = msg:match("^Q%^(%d+)%^([^%^]+)%^(%d+)$")
    if wk then
        if leader ~= ns.me then return end                                   -- only the named leader answers
        self.pendingReply = { wk = tonumber(wk), id = id, to = sender }
        if not InCombatLockdown() then C_Timer.After(0.5, function() RS:SendReply() end) end
        return
    end
    local rid, part, n, chunk = msg:match("^D%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    local req = self.request
    if not (rid and req and req.id == rid and req.from == sender) then return end
    part, n = tonumber(part), tonumber(n)
    if not req.parts[part] then req.parts[part] = chunk; req.got = req.got + 1 end
    if req.got < n then return end
    self.request = nil
    local raw = ns.Codec.DecodeForPrint(table.concat(req.parts))
    local text = raw and ns.Codec.Decompress(raw)
    local week = text and RS.Deserialize(text)
    if not week then ns.Print("The raid data didn't arrive intact - try again.") return end
    local added = self:Merge(week, sender)
    ns.Print(("Synced from %s: %d pull%s added or updated."):format(ns.Short and ns.Short(sender) or sender, added, added == 1 and "" or "s"))
    if ns.RaidScorecardUI then ns.RaidScorecardUI:Refresh() end
end

-- ---------------------------------------------------------------------
-- Window: the table | pulls for a clicked number | that pull's death order
-- ---------------------------------------------------------------------
local V = {}
ns.RaidScorecardUI = V
local COL1, COL2, COL3, H = 740, 300, 320, 470
local ROWS = 14

local function resize(f, w) UI.ResizeKeepTab(f, w, H) end

local function weekLabel(wk)
    if not wk then return "All weeks" end
    if wk == RS.CurrentWeekStart() then return "This week" end
    return "Week of " .. date("%b %d", wk)
end

local classed = UI.ClassName

local STATS = { { "first", "First to die" }, { "top3", "Top 3 dead" }, { "def", "Died w/ defensive" },
                { "pot", "Died w/ potion" }, { "hs", "Died w/ healthstone" } }
local PR_Clock = UI.Clock

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpRaidScorecard", "raidscore", "RAID SCORECARD", COL1, H)
    self.week = RS.CurrentWeekStart()

    local c1 = CreateFrame("Frame", nil, f)
    c1:SetPoint("TOPLEFT"); c1:SetSize(COL1, H)
    self.weekBtn = UI.Button(c1, 150, 22, "", "Which raid week", function() V:WeekMenu() end)
    self.weekBtn:SetPoint("TOPLEFT", 16, -10)
    local sync = UI.Button(c1, 150, 22, "Sync from raid leader", "Get the raid leader's full copy of this week (out of combat)", function() RS:RequestSync(V.week) end)
    sync:SetPoint("LEFT", self.weekBtn, "RIGHT", 6, 0)
    local export = UI.Button(c1, 92, 22, "Export CSV", "One row per death - paste into a .csv file, Google Sheets or Excel", function()
        UI.Prompt({ title = "Raid Scorecard - CSV", help = "Press Ctrl+C to copy, then paste into a text file saved as .csv, or straight into Google Sheets / Excel.",
                    text = RS:CSV(V.week, V.boss), select = true })
    end)
    export:SetPoint("LEFT", sync, "RIGHT", 6, 0)
    local clear = UI.Button(c1, 70, 22, "Clear", "Clear this week, or all kept weeks", function() V:ClearMenu() end)
    clear:SetPoint("LEFT", export, "RIGHT", 6, 0)
    self.bossBtn = UI.Button(c1, 160, 22, "", "Show one boss, or all of them", function() V:BossMenu() end)
    self.bossBtn:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    self.clearBtn = clear
    self.shortText = UI.Text(c1, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", 16, 14)
    -- table
    -- headers: Player / Pulls on the bottom line; the stats on two lines,
    -- centred over their columns so none crowd or run off the edge
    self.heads = {}
    UI.Text(c1, "GameFontNormalSmall", C.muted, "Player", "TOPLEFT", 16, -48)
    UI.Text(c1, "GameFontNormalSmall", C.muted, "Pulls", "TOPLEFT", 170, -48)
    local STAT_HEADS = { "First\nto die", "Top 3\ndead", "Died w/\ndefensive", "Died w/\npotion", "Died w/\nhealthstone" }
    for k, text in ipairs(STAT_HEADS) do
        self.heads[k] = UI.Text(c1, "GameFontNormalSmall", C.muted, text, "TOP", c1, "TOPLEFT", 226 + (k - 1) * 100 + 46, -34)
        self.heads[k]:SetJustifyH("CENTER")
    end
    self.rows = {}
    for i = 1, ROWS do
        local y = -62 - (i - 1) * 26
        local r = {}
        r.name = UI.Text(c1, "GameFontHighlight", nil, nil, "TOPLEFT", 16, y - 4); r.name:SetWidth(150); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.pulls = UI.Text(c1, "GameFontHighlight", C.muted, nil, "TOPLEFT", 170, y - 4)
        r.cells = {}
        for k, s in ipairs(STATS) do
            local b = UI.Button(c1, 92, 22, "", "Click to see which pulls", nil)
            b:SetPoint("TOPLEFT", 226 + (k - 1) * 100, y)
            b:SetScript("OnClick", function()
                if not b.row then return end
                if V.drill and V.drill.name == b.row.name and V.drill.stat == s[1] then V.drill = nil else V.drill = { name = b.row.name, class = b.row.class, stat = s[1], label = s[2], pulls = b.pulls } end
                V.drillPull = nil
                V:Refresh()
            end)
            r.cells[s[1]] = b
        end
        self.rows[i] = r
    end
    -- nothing recorded: a short note, bold white outlined, bottom-right
    self.empty = c1:CreateFontString(nil, "OVERLAY")
    self.empty:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    self.empty:SetTextColor(1, 1, 1)
    self.empty:SetPoint("BOTTOMRIGHT", -16, 10)
    self.empty:SetJustifyH("RIGHT")
    self.note = UI.Text(c1, "GameFontHighlightSmall", C.muted, "Heroic & Mythic only. Close calls and deaths after the wipe call don't count.", "BOTTOMLEFT", 16, 10)

    -- column 2: the pulls behind a number
    local c2 = CreateFrame("Frame", nil, f)
    c2:SetPoint("TOPLEFT", COL1, 0); c2:SetSize(COL2, H)
    local sep = c2:CreateTexture(nil, "ARTWORK"); sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", 0, -10); sep:SetPoint("BOTTOMLEFT", 0, 10); sep:SetWidth(1)
    self.c2 = c2
    self.h2 = UI.Text(c2, "GameFontNormalSmall", C.accent, nil, "TOPLEFT", 14, -14)
    self.h2:SetWidth(COL2 - 28); self.h2:SetJustifyH("LEFT")
    self.pullRows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, c2, "BackdropTemplate")
        r:SetSize(COL2 - 28, 24)
        r:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 26)
        UI.Skin(r, C.panel, C.line)
        r.text = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "LEFT", 8, 0)
        r:SetScript("OnClick", function()
            if V.drillPull == r.pull then V.drillPull = nil else V.drillPull = r.pull end
            V:Refresh()
        end)
        r:Hide()
        self.pullRows[i] = r
    end

    -- column 3: that pull's death order
    local c3 = CreateFrame("Frame", nil, f)
    c3:SetPoint("TOPLEFT", COL1 + COL2, 0); c3:SetSize(COL3, H)
    local sep3 = c3:CreateTexture(nil, "ARTWORK"); sep3:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep3:SetPoint("TOPLEFT", 0, -10); sep3:SetPoint("BOTTOMLEFT", 0, 10); sep3:SetWidth(1)
    self.c3 = c3
    self.detail = UI.Text(c3, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 14, -14)
    self.detail:SetWidth(COL3 - 28); self.detail:SetJustifyH("LEFT"); self.detail:SetSpacing(3)
end

function V:WeekMenu()
    local items = {}
    local keys = RS:WeekKeys()
    local cur = RS.CurrentWeekStart()
    local seen = false
    for _, k in ipairs(keys) do if k == cur then seen = true end end
    if not seen then table.insert(keys, 1, cur) end
    for _, k in ipairs(keys) do
        items[#items + 1] = { text = weekLabel(k), checked = V.week == k, onClick = function() V.week = k; V.drill, V.drillPull = nil, nil; V:Refresh() end }
    end
    items[#items + 1] = { text = "All weeks", checked = V.week == nil, onClick = function() V.week = nil; V.drill, V.drillPull = nil, nil; V:Refresh() end }
    UI.Menu(self.weekBtn, items)
end

function V:BossMenu()
    local items = { { text = "All bosses", checked = V.boss == nil, onClick = function() V.boss = nil; V.drill, V.drillPull = nil, nil; V:Refresh() end } }
    for _, b in ipairs(RS:Bosses(V.week)) do
        items[#items + 1] = { text = b, checked = V.boss == b, onClick = function() V.boss = b; V.drill, V.drillPull = nil, nil; V:Refresh() end }
    end
    UI.Menu(self.bossBtn, items)
end

function V:ClearMenu()
    local wk = V.week or RS.CurrentWeekStart()
    local function confirm(text, fn)
        UI.Prompt({ title = "Clear raid data", help = text .. " This can't be undone.", accept = "Clear", onAccept = function() fn() end })
    end
    UI.Menu(self.clearBtn, {
        { text = "Clear " .. weekLabel(wk):lower(), onClick = function() confirm("Clear " .. weekLabel(wk):lower() .. "?", function() RS:Clear(wk) end) end },
        { text = "Clear all weeks", onClick = function() confirm("Clear all kept raid weeks?", function() RS:Clear(nil) end) end },
    })
end

local function pullLine(p)
    return ("%s  %s (%s)  %s"):format(date("%a %b %d", p.start), p.name, (DIFF[p.diff] or ""):sub(1, 1), p.n and ("pull " .. p.n) or "")
end

function V:Refresh()
    if not self.frame then return end
    self.weekBtn.label:SetText(weekLabel(V.week) .. "  v")
    self.bossBtn.label:SetText((V.boss or "All bosses") .. "  v")
    local rows = RS:Stats(V.week, V.boss)
    local short = RS:ShortCount(V.week, V.boss)
    self.shortText:SetText(short > 0 and ("%d short pull%s (under %d seconds, not a kill) not counted"):format(short, short == 1 and "" or "s", ns.PullReport and ns.PullReport.MIN_PULL or 20) or "")
    self.empty:SetShown(#rows == 0)
    if #rows == 0 then
        local when = (V.week == nil) and "" or ((V.week == RS.CurrentWeekStart()) and " this week" or " that week")
        self.empty:SetText(V.boss and ("No data for this boss" .. when) or (V.week == nil and "No data yet" or ("No data for" .. when)))
    end
    for i, r in ipairs(self.rows) do
        local e = rows[i]
        r.name:SetText(e and classed(e.name, e.class) or "")
        r.pulls:SetText(e and tostring(e.pulls) or "")
        for _, s in ipairs(STATS) do
            local b = r.cells[s[1]]
            b:SetShown(e ~= nil)
            if e then
                local list, denom = e.first, e.pulls
                if s[1] == "top3" then list = e.top3
                elseif s[1] == "def" then list, denom = e.defDeaths, e.withData
                elseif s[1] == "pot" then list, denom = e.potDeaths, e.withData
                elseif s[1] == "hs" then list, denom = e.hsDeaths, e.withData end
                b.row, b.pulls = e, list
                b.label:SetText(("%d  (%d%%)"):format(#list, pct(#list, denom)))
                UI.SetActive(b, V.drill and V.drill.name == e.name and V.drill.stat == s[1] or false)
            end
        end
    end
    -- drill: the pulls
    local show2 = V.drill ~= nil
    self.c2:SetShown(show2)
    if show2 then
        self.h2:SetText(("%s - %s (%d)"):format(classed(V.drill.name, V.drill.class), V.drill.label:lower(), #V.drill.pulls))
        for i, r in ipairs(self.pullRows) do
            local p = V.drill.pulls[i]
            r.pull = p
            r:SetShown(p ~= nil)
            if p then
                r.text:SetText(pullLine(p))
                local c = (V.drillPull == p) and C.accent or C.line
                r:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            end
        end
    end
    -- drill: that pull's death order
    local show3 = show2 and V.drillPull ~= nil
    self.c3:SetShown(show3)
    if show3 then
        local p = V.drillPull
        local lines = { ("|cffffffff%s|r"):format(pullLine(p)), UI.ResultTag(p.result == "kill" and "kill" or "wipe") .. (p.dur and ("  " .. PR_Clock(p.dur)) or ""), "" }
        local all, order = RS.DeathOrder(p)
        for _, d in ipairs(all) do
            local after = p.wipeAt and (d.t or 0) > p.wipeAt
            local who = after and ("|cff8a8f9c" .. ((d.o or ""):match("^[^-]+") or d.o) .. "|r") or classed(d.o, d.c)
            if d.o == V.drill.name then who = "> " .. who end
            lines[#lines + 1] = ("%s  %s  %s%s%s"):format(order[d] and (order[d] .. ".") or "  ", PR_Clock(d.t), who,
                (d.k and d.k ~= "") and ("  |cff8a8f9c" .. d.k .. "|r") or "", after and "  |cff8a8f9c(after wipe)|r" or "")
        end
        if #all == 0 then lines[#lines + 1] = "|cff8a8f9cNobody died.|r" end
        self.detail:SetText(table.concat(lines, "\n"))
    end
    resize(self.frame, COL1 + (show2 and COL2 or 0) + (show3 and COL3 or 0))
end

ns.RegisterModule({
    key = "raidscore", name = "Raid Scorecard", icon = ns.MEDIA .. "RaidScore", group = "tools", order = 6,
    desc = "Over the raid week: who died first, in the first 3, or with a defensive up - click any number for the pulls.",
    view = V,
})
