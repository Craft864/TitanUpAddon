-- Eternal Table - Loot/LootBars.lua
-- Dungeon roll bars (Loot settings, off by default; 0.50.0): in a party
-- (not a raid), each roll gets a small bar where Blizzard's pop-ups sit
-- instead of the big Loot Rolls window, with a "Rolls" breakdown docked
-- beside them.
--   * The bar shows the same buttons Blizzard's pop-up would (Transmog in
--     Greed's place when the game offers it), with the game's reason on a
--     greyed one. Rolling goes through LootRolls (LR:Roll), so the "will
--     bind" question and sharing work the same.
--   * Pass shrinks the bar to one line with a red "Pass". While the group
--     is still choosing, the bar pulses and says who it's waiting on; the
--     winner flashes green, and the bar fades a few seconds later.
--   * The breakdown (click a bar to pick it): waiting on, Need, Greed (with
--     the roll numbers once they're in) and a collapsed Passed line. It
--     reads the game's loot history, or on WoW Forever the roll lines in
--     chat, so everyone in the group shows, addon or not.
--   * Blizzard's pop-ups stay hidden while the bars show a roll (the same
--     hiding as the window); drag the Rolls panel to move them.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local LR = ns.LootRolls

local B = {}
LR.Bars = B

local BAR_W, BAR_H, SMALL_H, GAP = 318, 50, 24, 4
local SIDE_W, LINE_H, LINES = 200, 14, 18
local MAX_BARS = 4                 -- like Blizzard's pop-ups
B.LINGER = 8                       -- seconds a finished bar stays
local YELLOW, PURPLE = { 1, 0.85, 0.30 }, { 0.78, 0.61, 1 }
local NEED_HEX, GREED_HEX, PASS_HEX, WAIT_HEX = "|cff66e08c", "|cffffd94d", "|cfff25959", "|cffffa340"

B.list = {}                        -- the rolls on screen, oldest first

local function store()
    local l = ns.udb.loot
    l.bars = l.bars or {}
    return l.bars
end

function B:Showing() return self.frame and self.frame:IsShown() and #self.list > 0 end

local function passedOn(e) return e.rolled == LR.PASS end
local function heightOf(e) return passedOn(e) and SMALL_H or BAR_H end

-- ---------------------------------------------------------------------
-- Adding and dropping rolls
-- ---------------------------------------------------------------------
function B:Add(e)
    self:Create()
    for _, x in ipairs(self.list) do if x == e then return end end
    self.list[#self.list + 1] = e
    if not self.sel or self.sel.closed then self.sel = e end
    self.frame:Show()
    self:Refresh()
    self:Tick()
end

-- finished (a winner, everyone passed, or out of time) for a few seconds: gone
function B:Prune(now)
    for i = #self.list, 1, -1 do
        local e = self.list[i]
        if e.closed or now > e.expires + 10 then
            e.doneAt = e.doneAt or now
            if now - e.doneAt >= B.LINGER then table.remove(self.list, i) end
        end
    end
    if self.sel and not tContains(self.list, self.sel) then self.sel = self.list[#self.list] end
end

function B:Tick()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(0.5, function()
        B:Refresh()
        if #B.list == 0 and B.ticker then B.ticker:Cancel(); B.ticker = nil end
    end)
end

-- ---------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------
local function rollButton(bar, label, kind, w, color)
    local b = UI.Button(bar, w, 20, label, nil, function(s) if s.entry and not s.disabled then LR:Roll(s.entry, kind) end end)
    b.textColor = color
    b.edge = { color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 1 }
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end   -- a greyed button still shows why
    UI.Paint(b)
    return b
end

local function newBar(parent)
    local bar = CreateFrame("Button", nil, parent, "BackdropTemplate")
    bar:SetSize(BAR_W, BAR_H)
    UI.Skin(bar, C.bg, C.line)
    bar:RegisterForClicks("LeftButtonUp")
    bar:SetScript("OnClick", function(s) if s.entry then B.sel = s.entry; B:Refresh() end end)
    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")    -- the item's quality around its icon
    bar.icon = bar.border:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("TOPLEFT", 2, -2)
    bar.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    bar.border:EnableMouse(true)
    bar.border:SetScript("OnEnter", function() if bar.entry then LR.V:ItemTip(bar.border, bar.entry) end end)
    bar.border:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.border:SetScript("OnMouseUp", function() if bar.entry then B.sel = bar.entry; B:Refresh() end end)
    bar.name = UI.Text(bar, "GameFontNormal", C.text, nil, "TOPLEFT", bar.border, "TOPRIGHT", 8, -1)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.sub = UI.Text(bar, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", -8, -8)
    bar.sub:SetJustifyH("RIGHT")
    bar.status = UI.Text(bar, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", bar.border, "BOTTOMRIGHT", 8, 1)
    bar.status:SetJustifyH("LEFT")
    bar.status:SetWordWrap(false)
    -- Need, then Greed or Transmog (one slot - Blizzard shows one or the other), then Pass
    bar.pass = rollButton(bar, "Pass", LR.PASS, 42, C.bad)
    bar.pass:SetPoint("BOTTOMRIGHT", -6, 7)
    bar.greed = rollButton(bar, "Greed", LR.GREED, 62, YELLOW)
    bar.greed:SetPoint("RIGHT", bar.pass, "LEFT", -4, 0)
    bar.tmog = rollButton(bar, "Transmog", LR.TRANSMOG, 62, PURPLE)
    bar.tmog:SetPoint("RIGHT", bar.pass, "LEFT", -4, 0)
    bar.need = rollButton(bar, "Need", LR.NEED, 48, C.good)
    bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -4, 0)
    bar.result = UI.Text(bar, "GameFontHighlightSmall", C.text, nil, "RIGHT", -10, 0)
    bar.result:SetJustifyH("RIGHT")
    -- time left
    bar.time = bar:CreateTexture(nil, "ARTWORK")
    bar.time:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    bar.time:SetPoint("BOTTOMLEFT", 1, 1)
    bar.time:SetHeight(2)
    -- a pulsing border while the group is still choosing, a green flash for the winner
    local p = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    p:SetAllPoints()
    p:EnableMouse(false)
    UI.Skin(p, { 0, 0, 0, 0 }, C.accent)
    local ag = p:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15); a:SetToAlpha(1); a:SetDuration(0.8)
    p.anim = ag
    p:Hide()
    bar.pulse = p
    local fl = CreateFrame("Frame", nil, bar)
    fl:SetAllPoints()
    fl:EnableMouse(false)
    local t = fl:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(C.good[1], C.good[2], C.good[3], 0.4)
    local fg = fl:CreateAnimationGroup()
    local fa = fg:CreateAnimation("Alpha")
    fa:SetFromAlpha(1); fa:SetToAlpha(0); fa:SetDuration(1.2)
    fg:SetScript("OnFinished", function() fl:Hide() end)
    fl.anim = fg
    fl:Hide()
    bar.flash = fl
    return bar
end

function B:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "TitanUpLootBars", UIParent)
    f:SetSize(SIDE_W + 6 + BAR_W, MAX_BARS * (BAR_H + GAP))
    f:SetFrameStrata("MEDIUM")
    UI.Draggable(f, store, { "BOTTOM", "BOTTOM", 0, 250 })
    f:Place()
    f:Hide()
    self.frame = f

    self.bars = {}
    for i = 1, MAX_BARS do self.bars[i] = newBar(f) end

    -- the breakdown, docked on the left (drag it to move everything)
    local s = CreateFrame("Frame", nil, f, "BackdropTemplate")
    s:SetWidth(SIDE_W)
    s:SetPoint("BOTTOMLEFT", 0, 0)
    UI.Skin(s, C.bg, C.line)
    s:EnableMouse(true)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", function() f:StartMoving() end)
    s:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
    s.head = UI.Text(s, "GameFontNormalSmall", C.accent, "ROLLS", "TOPLEFT", 8, -7)
    s.hint = UI.Text(s, "GameFontDisableSmall", nil, "drag to move", "TOPRIGHT", -8, -8)
    s.item = UI.Text(s, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 8, -22)
    s.item:SetWidth(SIDE_W - 16)
    s.item:SetJustifyH("LEFT")
    s.item:SetWordWrap(false)
    s.lines = {}
    for i = 1, LINES do
        local l = {}
        l.left = UI.Text(s, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 8, 0)
        l.left:SetJustifyH("LEFT")
        l.left:SetWidth(SIDE_W - 60)
        l.left:SetWordWrap(false)
        l.right = UI.Text(s, "GameFontHighlightSmall", C.muted, nil, "TOPRIGHT", -8, 0)
        l.right:SetJustifyH("RIGHT")
        s.lines[i] = l
    end
    s.passBtn = UI.Button(s, SIDE_W - 16, 18, "", "Show or hide who passed", function()
        if B.sel then B.sel.showPassed = not B.sel.showPassed; B:Refresh() end
    end)
    s.passBtn.textColor = C.bad
    s.passBtn:Hide()
    s.foot = UI.Text(s, "GameFontDisableSmall", nil, nil, "BOTTOMLEFT", 8, 6)
    s.foot:SetWidth(SIDE_W - 16)
    s.foot:SetJustifyH("LEFT")
    self.side = s
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------
local function qualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return { c.r, c.g, c.b, 1 } end
    return C.line
end

local function slotText(e)
    local bits = {}
    if e.ilvl then bits[#bits + 1] = "ilvl " .. e.ilvl end
    if e.bop then bits[#bits + 1] = "BoP" end
    return table.concat(bits, "  ")
end

function B:DrawBar(bar, e, now)
    bar.entry = e
    local collapsed = passedOn(e)
    local h = heightOf(e)
    bar:SetHeight(h)
    local size = collapsed and 16 or 38
    bar.border:SetSize(size, size)
    bar.border:ClearAllPoints()
    bar.border:SetPoint(collapsed and "LEFT" or "TOPLEFT", 6, collapsed and 0 or -6)
    UI.Skin(bar.border, { 0, 0, 0, 1 }, qualityColor(e.quality))
    bar.icon:SetTexture(e.icon or 134400)
    bar.name:ClearAllPoints()
    if collapsed then bar.name:SetPoint("LEFT", bar.border, "RIGHT", 8, 0) else bar.name:SetPoint("TOPLEFT", bar.border, "TOPRIGHT", 8, -1) end
    bar.name:SetWidth(collapsed and (BAR_W - 90) or (BAR_W - 110))
    bar.name:SetText((e.link or e.name or "?") .. (e.count and e.count > 1 and (" x" .. e.count) or ""))
    bar:SetBackdropBorderColor(unpack(self.sel == e and C.accent or C.line))
    local open = not e.rolled and not e.closed
    for _, def in ipairs({ { bar.need, true, e.canNeed, LR.Reason(e.reasonNeed, "You can't Need this") },
                           { bar.greed, not e.canTransmog, e.canGreed, LR.Reason(e.reasonGreed, "You can't Greed this") },
                           { bar.tmog, e.canTransmog, true },
                           { bar.pass, true, true } }) do
        local b = def[1]
        b.entry = e
        b:SetShown(open and def[2] and not collapsed)
        UI.SetDisabled(b, not def[3])
        b.tip = not def[3] and def[4] or nil
    end
    local waiting = e.rolled and not collapsed and not e.closed
    bar.pulse:SetShown(waiting)
    if waiting then if not bar.pulse.anim:IsPlaying() then bar.pulse.anim:Play() end else bar.pulse.anim:Stop() end
    if e.flashAt and not e.barFlashed and not collapsed then
        e.barFlashed = true
        bar.flash:Show()
        bar.flash.anim:Play()
    end
    bar.sub:SetShown(not collapsed and open)
    bar.sub:SetText(slotText(e))
    bar.status:SetShown(not collapsed)
    if collapsed then
        bar.result:SetText(PASS_HEX .. "Pass|r")
        bar.result:Show()
        bar.time:Hide()
        bar.flash:Hide()
        return h
    end
    local list = LR:Raiders(e)
    local wait, done, total = LR:Waiting(e, list)
    local st
    if e.closed then
        st = LR.Status(e) or "|cff8a8f9cRolls finished|r"
    elseif e.pending then
        st = LR.Status(e)
    elseif e.rolled then
        st = "You: " .. GREED_HEX .. (LR.ROLL_LABEL[e.rolled] or "?") .. "|r"
        if #wait > 0 then st = st .. "  " .. WAIT_HEX .. "waiting on|r " .. LR.NameList(wait, 2) end
    else
        st = total > 0 and (done .. " / " .. total .. " picked") or ""
    end
    bar.status:SetWidth(open and (BAR_W - 56 - 168) or (BAR_W - 60))
    bar.status:SetText(st or "")
    bar.result:Hide()
    local left = e.expires - now
    bar.time:SetShown(not e.closed and left > 0)
    if not e.closed then bar.time:SetWidth(math.max(1, (BAR_W - 2) * math.min(1, math.max(0, left) / (e.total or 60)))) end
    return h
end

-- one line of the breakdown
local function line(s, i, y, left, right, color)
    local l = s.lines[i]
    if not l then return y end
    l.left:ClearAllPoints(); l.left:SetPoint("TOPLEFT", 8, y)
    l.right:ClearAllPoints(); l.right:SetPoint("TOPRIGHT", -8, y)
    l.left:SetText(left or "")
    l.right:SetText(right or "")
    local c = color or C.text
    l.left:SetTextColor(c[1], c[2], c[3])
    return y - LINE_H
end

function B:DrawSide()
    local s, e = self.side, self.sel
    for _, l in ipairs(s.lines) do l.left:SetText(""); l.right:SetText("") end
    s.passBtn:Hide()
    if not e then
        s.item:SetText("")
        s.foot:SetText("")
        s:SetHeight(60)
        return
    end
    s.item:SetText(e.link or e.name or "?")
    local list = LR:Raiders(e)
    local need, greed, passed, wait = {}, {}, {}, {}
    for _, x in ipairs(list) do
        if x.passed then passed[#passed + 1] = x
        elseif x.wait then wait[#wait + 1] = x
        elseif x.state == 0 or x.state == 1 or (not x.state and x.roll == LR.NEED) then need[#need + 1] = x
        elseif x.state or x.roll then greed[#greed + 1] = x end
    end
    local function who(x)
        return x.name == ns.me and "You" or UI.ClassName(x.name, x.class or ns.ClassOf(x.name))
    end
    local i, y = 1, -40
    local function group(title, people, color, value)
        if #people == 0 or i > LINES then return end
        y = line(s, i, y - 3, title .. " (" .. #people .. ")", nil, color); i = i + 1
        for _, x in ipairs(people) do
            if i > LINES then break end
            y = line(s, i, y, (x.won and NEED_HEX .. "> |r" or "") .. who(x), value(x)); i = i + 1
        end
    end
    if not e.closed then group("WAITING ON", wait, C.warn, function() return "..." end) end
    local function num(x) return x.won and (NEED_HEX .. (x.num or "won") .. "|r") or (x.num and tostring(x.num) or (e.closed and "" or "picked")) end
    group("NEED", need, C.good, num)
    group("GREED", greed, YELLOW, num)
    if #passed > 0 then
        s.passBtn:ClearAllPoints()
        s.passBtn:SetPoint("TOPLEFT", 8, y - 4)
        s.passBtn.label:SetText((e.showPassed and "v  " or ">  ") .. "Passed (" .. #passed .. ")")
        s.passBtn:Show()
        y = y - 26
        if e.showPassed then
            for _, x in ipairs(passed) do
                if i > LINES then break end
                y = line(s, i, y, who(x), x.state == nil and x.roll == nil and "no roll" or nil); i = i + 1
            end
        end
    end
    local _, _, total, fromGame = LR:Waiting(e, list)
    s.foot:SetText(total > 0 and not fromGame and "Eternal Table users only so far" or "")
    s:SetHeight(-y + (s.foot:GetText() ~= "" and 24 or 10))
end

function B:Refresh()
    if not self.frame then return end
    local now = GetTime()
    self:Prune(now)
    if #self.list == 0 then
        if self.frame:IsShown() then self.frame:Hide() end
        return
    end
    if not self.frame:IsShown() then self.frame:Show() end
    -- the newest rolls at the bottom, like Blizzard's pop-ups stacking up
    local y, shown = 0, 0
    for i = 1, MAX_BARS do
        local e = self.list[#self.list - MAX_BARS + i]
        local bar = self.bars[i]
        bar:SetShown(e ~= nil)
        if e then shown = shown + 1 end
    end
    for i = MAX_BARS, 1, -1 do
        local bar = self.bars[i]
        local e = self.list[#self.list - MAX_BARS + i]
        if e then
            local h = self:DrawBar(bar, e, now)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, y)
            y = y + h + GAP
        end
    end
    self:DrawSide()
    LR:HideBlizzard()
end

-- ---------------------------------------------------------------------
-- Preview (Loot settings): sample items and a sample party rolling;
-- nothing is rolled or sent
-- ---------------------------------------------------------------------
local PARTY = { { "Mossy", "DRUID" }, { "Kev", "MAGE" }, { "Lyra", "PRIEST" }, { "Thorn", "ROGUE" } }
local SAMPLE = {
    { "Hand of Justice", "Interface\\Icons\\INV_Jewelry_Talisman_01", 3, 58, { "need", "greed", "pass", "need" } },
    { "Robe of the Archmage", "Interface\\Icons\\INV_Chest_Cloth_25", 4, 62, { "greed", "need", "need", "greed" }, true },
    { "Runeblade of Baron Rivendare", "Interface\\Icons\\INV_Sword_17", 3, 63, { "pass", "pass", "pass", "greed" } },
}

function B:Preview()
    self.previewToken = {}
    local token = self.previewToken
    for i = #self.list, 1, -1 do if self.list[i].sim then table.remove(self.list, i) end end
    for i = #LR.items, 1, -1 do if LR.items[i].barSim then table.remove(LR.items, i) end end
    local now = GetTime()
    for i, s in ipairs(SAMPLE) do
        local e = { rollID = -100 - i, sim = true, barSim = true, chat = true, t = time(), name = s[1], icon = s[2], quality = s[3], ilvl = s[4],
                    link = "|cff" .. (s[3] == 4 and "a335ee" or "0070dd") .. "[" .. s[1] .. "]|r", item = -100 - i,
                    canNeed = not s[6], canGreed = true, canTransmog = false, reasonNeed = s[6] and 1 or nil, bop = true,
                    expires = now + 40, total = 40, tags = "", note = "", picks = {}, rolls = {}, bar = true }
        e.rolls[ns.me] = { s = 4, c = select(2, UnitClass("player")) }
        local roster = {}
        for k, p in ipairs(PARTY) do
            local full = p[1] .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or "Realm")
            e.rolls[full] = { s = 4, c = p[2] }
            roster[k] = full
        end
        LR.items[#LR.items + 1] = e
        self:Add(e)
        local state = { need = 0, greed = 3, pass = 5 }
        for k, choice in ipairs(s[5]) do
            C_Timer.After(1 + k * 1.3 + i * 0.4, function()
                if B.previewToken ~= token then return end
                e.rolls[roster[k]].s = state[choice]
                B:Refresh()
            end)
        end
        C_Timer.After(9 + i * 2, function()
            if B.previewToken ~= token or e.closed then return end
            local best, bestN, tier = nil, -1, nil
            for _, st in ipairs({ 0, 3 }) do
                for name, r in pairs(e.rolls) do
                    if r.s == st or (name == ns.me and ((st == 0 and e.rolled == LR.NEED) or (st == 3 and e.rolled == LR.GREED))) then
                        tier = tier or st
                        if tier == st then
                            r.s, r.r = st, math.random(1, 100)
                            if r.r > bestN then best, bestN = name, r.r end
                        end
                    end
                end
                if tier then break end
            end
            if best then e.winner, e.wstate, e.wroll, e.flashAt = best, tier, bestN, GetTime() else e.allPassed = true end
            e.closed = true
            B:Refresh()
        end)
    end
end
