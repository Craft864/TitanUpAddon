-- Titan Up - RaidCheck/RaidCheckUI.lua
-- Results window (raid buffs + personal checks as x/y, hover for names)
-- and the /pull alert ("Pull anyway" / "Cancel").
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local RC

local V = {}
ns.RaidCheckUI = V

local W, H = 640, 500

local function colored(name)
    local class = ns.ClassOf(name)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return ("|cff%02x%02x%02x%s|r"):format(cc.r * 255, cc.g * 255, cc.b * 255, ns.Short(name)) end
    return ns.Short(name)
end

local function nameList(list, max)
    local out = {}
    for i, n in ipairs(list) do
        if max and i > max then out[#out + 1] = ("+%d more"):format(#list - max) break end
        out[#out + 1] = colored(n)
    end
    return table.concat(out, ", ")
end

function V:Init() RC = ns.RaidCheck end
function V:EnsureFrame() if not self.frame then self:Create() end return self.frame end
function V:IsShown() return self.frame and self.frame:IsShown() or false end
function V:Show() self:EnsureFrame():Show() end
function V:ShowResults() self:Show(); self:Refresh() end
function V:OnReport()
    if self:IsShown() then self:Refresh() end
end

local function makeRow(parent, y, x)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(290, 24)
    row:SetPoint("TOPLEFT", x, y)
    row:EnableMouse(true)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.label = UI.Text(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.count = UI.Text(row, "GameFontNormal")
    row.count:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", function(s)
        local r = s.data
        if not r then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(r.def.label or r.def.name, 1, 1, 1)
        if #r.missing == 0 then
            GameTooltip:AddLine("Everyone's covered.", 0.4, 0.9, 0.55)
        else
            GameTooltip:AddLine("Missing (" .. #r.missing .. "):", 1, 0.6, 0.3)
            for _, n in ipairs(r.missing) do GameTooltip:AddLine("  " .. colored(n), 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function checkIcon(key) return ns.MEDIA .. "Check\\" .. key end

function V:Create()
    local f = CreateFrame("Frame", "TitanUpRaidCheck", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    UI.Skin(f, C.bg, C.line)
    f:Hide()
    tinsert(UISpecialFrames, "TitanUpRaidCheck")
    f:SetScript("OnShow", function() V:Refresh() end)
    UI.Watermark(f, 400, 0.05, -20)
    self.header = ns.Nav:CreateHeader(f, "raidcheck", { title = "RAID CHECK", icon = ns.MEDIA .. "RaidCheck" })

    self.info = UI.Text(f, "GameFontHighlight")
    self.info:SetPoint("TOPLEFT", 16, -44)
    self.info:SetPoint("RIGHT", -16, 0)
    self.info:SetJustifyH("LEFT")

    local lh = UI.Text(f, "GameFontNormalSmall", C.accent); lh:SetPoint("TOPLEFT", 16, -72); lh:SetText("RAID BUFFS")
    local rh = UI.Text(f, "GameFontNormalSmall", C.accent); rh:SetPoint("TOPLEFT", 330, -72); rh:SetText("PERSONAL")
    self.buffRows, self.checkRows = {}, {}
    for i = 1, #RC.RAID_BUFFS do self.buffRows[i] = makeRow(f, -92 - (i - 1) * 28, 14) end
    for i = 1, #RC.CHECKS do self.checkRows[i] = makeRow(f, -92 - (i - 1) * 28, 328) end
    self.noBuffs = UI.Text(f, "GameFontHighlightSmall", C.muted)
    self.noBuffs:SetPoint("TOPLEFT", 18, -96)

    self.noReply = UI.Text(f, "GameFontHighlightSmall", C.warn)
    self.noReply:SetPoint("TOPLEFT", 16, -330)
    self.noReply:SetPoint("RIGHT", -16, 0)
    self.noReply:SetJustifyH("LEFT")

    -- buttons
    local check = UI.Button(f, 120, 26, "Check now", "Ask everyone for a fresh report (leader/assist, Heroic/Mythic raid)", function()
        if not RC:Active() then ns.Print("Raid Check runs in Heroic and Mythic raids.") return end
        if not RC:CanLead() then ns.Print("Only the raid leader or assists can run a check.") return end
        RC:RequestCheck("manual")
        V:Refresh()
    end)
    check:SetPoint("BOTTOMLEFT", 16, 16)
    UI.SetActive(check, true)
    local learn = UI.Button(f, 170, 26, "Learn approved buffs", "Eat the Hearty feast and take an approved flask (high quality and/or cauldron), then click. Only those exact buffs will count as flask/food. Learn adds to the list.", function()
        RC:LearnApproved()
        V:Refresh()
    end)
    learn:SetPoint("LEFT", check, "RIGHT", 8, 0)
    local reset = UI.Button(f, 70, 26, "Reset", "Forget the approved flask/food list", function()
        RC:ResetApproved()
        V:Refresh()
    end)
    reset:SetPoint("LEFT", learn, "RIGHT", 6, 0)
    self.pullBtn = UI.Button(f, 170, 26, "", "When you (leader/assist) type /pull in a Heroic or Mythic raid, check everyone first", function()
        ns.udb.raidcheck.pullCheck = not ns.udb.raidcheck.pullCheck
        V:Refresh()
    end)
    self.pullBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    self.approvedText = UI.Text(f, "GameFontHighlightSmall", C.muted)
    self.approvedText:SetPoint("BOTTOMLEFT", check, "TOPLEFT", 0, 8)
end

local function fill(row, r, icon, name)
    row.data = r
    row:SetShown(r ~= nil)
    if not r then return end
    row.icon:SetTexture(icon)
    row.label:SetText(name)
    local col = (#r.missing == 0) and "|cff66e08c" or "|cffffa340"
    row.count:SetText(("%s%d / %d|r"):format(col, r.have, r.have + #r.missing))
end

function V:Refresh()
    if not self.frame then return end
    local s = ns.udb.raidcheck
    self.pullBtn.label:SetText("Check before /pull: " .. (s.pullCheck and "ON" or "OFF"))
    UI.SetActive(self.pullBtn, s.pullCheck)
    local nf, nfd = 0, 0
    for _ in pairs(s.approved.flask) do nf = nf + 1 end
    for _ in pairs(s.approved.food) do nfd = nfd + 1 end
    self.approvedText:SetText(("Approved: %s flask%s, %s food buff%s%s"):format(
        nf == 0 and "any" or nf, nf == 1 and "" or "s", nfd == 0 and "any" or nfd, nfd == 1 and "" or "s",
        (nf == 0 or nfd == 0) and "  |cffffa340(Learn to restrict to the feast / approved flasks)|r" or ""))

    local check = RC.current
    if not check then
        self.info:SetText(RC:Active() and "No check yet - start a ready check, type /pull, or click Check now."
            or "|cff8a8f9cRaid Check runs in Heroic and Mythic raids (not Normal or LFR).|r")
        for _, r in ipairs(self.buffRows) do r:Hide() end
        for _, r in ipairs(self.checkRows) do r:Hide() end
        self.noBuffs:SetText("")
        self.noReply:SetText("")
        return
    end
    local result = RC:Evaluate(check)
    local reported = 0
    for _ in pairs(check.reports) do reported = reported + 1 end
    local kind = (check.kind == "ready" and "Ready check") or (check.kind == "pull" and "Pull check") or "Check"
    local _, _, _, diffName = GetInstanceInfo()
    self.info:SetText(("%s by %s  |cff8a8f9c%s  -  %s  -  %d/%d reported|r"):format(
        kind, colored(check.by), date("%H:%M", check.t), diffName or "", reported, result.total))
    for i, row in ipairs(self.buffRows) do
        local r = result.buffs[i]
        if r then
            local b = r.def
            local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spell)) or 136243
            fill(row, r, icon, b.name)
        else
            fill(row, nil)
        end
    end
    self.noBuffs:SetText(#result.buffs == 0 and "No raid-buff classes in the raid." or "")
    for i, row in ipairs(self.checkRows) do
        local r = result.checks[i]
        fill(row, r, r and checkIcon(r.def.key), r and r.def.label)
    end
    self.noReply:SetText(#result.noReply > 0 and ("No report (no Titan Up, offline, or still loading): " .. nameList(result.noReply, 12)) or "")
end

-- ---------------------------------------------------------------------
-- /pull alert
-- ---------------------------------------------------------------------
function V:EnsureAlert()
    if self.alert then return self.alert end
    local a = CreateFrame("Frame", "TitanUpPullAlert", UIParent, "BackdropTemplate")
    UI.Skin(a, C.bg, C.warn)
    a:SetSize(520, 340)
    a:SetPoint("CENTER", 0, 120)
    a:SetFrameStrata("FULLSCREEN_DIALOG")
    a:SetToplevel(true)
    a:EnableMouse(true)
    a:SetMovable(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", a.StartMoving)
    a:SetScript("OnDragStop", a.StopMovingOrSizing)
    a:Hide()
    tinsert(UISpecialFrames, "TitanUpPullAlert")
    local t = UI.Text(a, "GameFontNormalLarge", C.warn)
    t:SetPoint("TOPLEFT", 16, -14)
    t:SetText("Not everyone is ready to pull")
    a.body = UI.Text(a, "GameFontHighlight")
    a.body:SetPoint("TOPLEFT", 16, -44)
    a.body:SetPoint("RIGHT", -16, 0)
    a.body:SetJustifyH("LEFT")
    a.body:SetJustifyV("TOP")
    a.body:SetHeight(240)
    a.pull = UI.Button(a, 150, 30, "Pull anyway", nil, function()
        local fn = a.doPull
        a.doPull = nil
        a:Hide()
        if fn then fn() end
    end)
    a.pull:SetPoint("BOTTOMRIGHT", -16, 14)
    a.cancel = UI.Button(a, 110, 30, "Cancel", nil, function() a.doPull = nil; a:Hide() end)
    a.cancel:SetPoint("RIGHT", a.pull, "LEFT", -8, 0)
    UI.SetActive(a.cancel, true)
    a:SetScript("OnHide", function() a.doPull = nil end)
    self.alert = a
    return a
end

function V:ShowPullAlert(result, msg, doPull)
    local a = self:EnsureAlert()
    local lines = {}
    for _, list in ipairs({ result.buffs, result.checks }) do
        for _, r in ipairs(list) do
            if #r.missing > 0 then
                lines[#lines + 1] = ("|cffffa340%s (%d):|r %s"):format(r.def.label or r.def.name, #r.missing, nameList(r.missing, 8))
            end
        end
    end
    if #result.noReply > 0 then
        lines[#lines + 1] = ("|cff8a8f9cNo report (%d):|r %s"):format(#result.noReply, nameList(result.noReply, 8))
    end
    a.body:SetText(table.concat(lines, "\n"))
    a.pull.label:SetText(("Pull anyway%s"):format((msg and msg:match("%d+")) and (" (" .. msg:match("%d+") .. "s)") or ""))
    a.doPull = doPull
    a:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    -- the leader also gets the full results window
    self:ShowResults()
end

ns.RegisterModule({
    key = "raidcheck", name = "Raid Check", icon = ns.MEDIA .. "RaidCheck", order = 2,
    desc = "Raid buffs, flasks, food, oils, potions, healthstones and durability - on ready check and /pull.",
    show = function() V:Show() end,
    hide = function() if V.frame then V.frame:Hide() end end,
    isShown = function() return V:IsShown() end,
    frame = function() return V.frame end,
})
