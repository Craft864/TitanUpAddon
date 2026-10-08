-- Titan Up - RaidCheck/RaidCheckUI.lua
-- Results window (raid buffs + personal checks as x/y, hover for names)
-- and the /pull alert ("Pull anyway" / "Cancel").
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local RC

local V = {}
ns.RaidCheckUI = V

local W, H = 880, 570          -- the standard module size
local COL_W = 410

local colored = UI.Named

local function nameList(list, max)
    local out = {}
    for i, n in ipairs(list) do
        if max and i > max then out[#out + 1] = ("+%d more"):format(#list - max) break end
        out[#out + 1] = colored(n)
    end
    return table.concat(out, ", ")
end

function V:Init() RC = ns.RaidCheck end
-- auto: opened by a ready check / pull rather than by you - if another
-- module is open in the Titan Up window, offer the results instead
function V:ShowResults(auto)
    if auto and not ns.Nav:ShellFree("raidcheck") then
        ns.Dock:Notice("Raid Check results are in.", "Open", function() V:ShowResults() end)
        return
    end
    self:Show(); self:Refresh()
end

-- The pull is happening: close the alert and the results window.
function V:CloseAll()
    if self.alert and self.alert:IsShown() then self.alert.doPull = nil; self.alert:Hide() end
    if self.frame and self.frame:IsShown() then self.frame:Hide() end
end
-- reports arrive in a burst on a ready check: redraw once for the lot
function V:OnReport()
    ns.Debounce("raidcheck-report", 0.2, function() if V:IsShown() then V:Refresh() end end)
end

local function makeRow(parent, y, x)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COL_W, 24)
    row:SetPoint("TOPLEFT", x, y)
    row:EnableMouse(true)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.label = UI.Text(row, "GameFontHighlight", nil, nil, "LEFT", row.icon, "RIGHT", 8, 0)
    row.count = UI.Text(row, "GameFontNormal", nil, nil, "RIGHT", -4, 0)
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
    local f = ns.Nav:Window(self, "TitanUpRaidCheck", "raidcheck", "RAID CHECK", W, H, { mark = { 400, 0.05, -20 },
        cog = { "Raid Check settings", function() ns.Settings:Open("raidcheck") end } })

    self.info = UI.Text(f, "GameFontHighlight", nil, nil, "TOPLEFT", 16, -14)
    self.info:SetPoint("RIGHT", -40, 0)              -- clear of the X
    self.info:SetJustifyH("LEFT")

    UI.Text(f, "GameFontNormalSmall", C.accent, "RAID BUFFS", "TOPLEFT", 16, -42)
    UI.Text(f, "GameFontNormalSmall", C.accent, "PERSONAL", "TOPLEFT", 30 + COL_W, -42)
    self.buffRows, self.checkRows = {}, {}
    for i = 1, #RC.RAID_BUFFS do self.buffRows[i] = makeRow(f, -62 - (i - 1) * 28, 14) end
    for i = 1, #RC.CHECKS do self.checkRows[i] = makeRow(f, -62 - (i - 1) * 28, 28 + COL_W) end
    self.noBuffs = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 18, -66)

    self.noReply = UI.Text(f, "GameFontHighlightSmall", C.warn, nil, "TOPLEFT", 16, -400)
    self.noReply:SetPoint("RIGHT", -16, 0)
    self.noReply:SetJustifyH("LEFT")

    -- buttons
    local check = UI.Button(f, 120, 26, "Check now", "Ask everyone for a fresh report (leader/assist, Heroic/Mythic raid)", function()
        if not ns.DataChannel() then ns.Print("Raid Check needs a guild - reports travel over your guild's private addon channel.") return end
        if not RC:Active() then ns.Print("Raid Check runs in Heroic and Mythic raids.") return end
        if not RC:CanLead() then ns.Print("Only the raid leader or assists can run a check.") return end
        RC:RequestCheck("manual")
        V:Refresh()
    end)
    check:SetPoint("BOTTOM", 0, 24)                  -- centered
    UI.SetActive(check, true)

    -- help text: small and grey in the bottom-left corner
    self.helpText = UI.Text(f, "GameFontDisableSmall", nil, nil, "BOTTOMLEFT", 12, 7)
    self.helpText:SetTextColor(0.55, 0.57, 0.62)
    self.helpText:SetJustifyH("LEFT")
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
    local info = "|T" .. ns.MEDIA .. "Info:12:12:0:0|t "
    self.helpText:SetText(info .. (ns.DataChannel() and "Raid Check runs in Heroic and Mythic raids (not Normal or LFR)."
        or "Raid Check needs a guild: everyone's reports travel over your guild's private addon channel."))

    local check = RC.current
    if not check then
        self.info:SetText("No check yet - start a ready check, type /pull, or click Check now.")
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
    local a = UI.Window("TitanUpPullAlert", 520, 340, { y = 120, strata = "FULLSCREEN_DIALOG", border = C.warn, drag = true, noClamp = true })
    UI.Text(a, "GameFontNormalLarge", C.warn, "Not everyone is ready to pull", "TOPLEFT", 16, -14)
    a.body = UI.Text(a, "GameFontHighlight", nil, nil, "TOPLEFT", 16, -44)
    a.body:SetPoint("RIGHT", -16, 0)
    a.body:SetJustifyH("LEFT")
    a.body:SetJustifyV("TOP")
    a.body:SetHeight(240)
    a.pull = UI.Button(a, 150, 30, "Pull anyway", nil, function()
        local fn = a.doPull
        V:CloseAll()
        if fn then fn() end
    end)
    a.pull:SetPoint("BOTTOMRIGHT", -16, 14)
    a.cancel = UI.Button(a, 110, 30, "Cancel", nil, function() a.doPull = nil; a:Hide() end)
    a.cancel:SetPoint("RIGHT", a.pull, "LEFT", -8, 0)
    UI.SetActive(a.cancel, true)
    a:SetScript("OnHide", function() a.doPull = nil end)
    self.alert = a
    ns.Dock:Add(a)                      -- stacks with the other pop-ups
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
    -- the raid leader also gets the full results window
    if RC:IsLeader() then self:ShowResults(true) end
end

ns.RegisterModule({
    key = "raidcheck", name = "Raid Check", icon = ns.MEDIA .. "RaidCheck", group = "tools", order = 4,
    desc = "Buffs, consumables and gear on ready check and /pull.",
    view = V,
})
