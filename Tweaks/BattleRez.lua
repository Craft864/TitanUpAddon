-- Titan Up - Tweaks/BattleRez.lua
-- Battle rez tracker (a UI Tweak, off until turned on): the Rebirth icon with
-- the number of battle-rez charges the group has. At zero it greys out, with
-- a cooldown sweep and a countdown to the next charge.
--   * Shows for the whole of a raid boss encounter or a Mythic+ key - the
--     times the game keeps a shared battle-rez pool (which it reports
--     through Rebirth's charges, for every class) - including while you're
--     dead (dying takes you out of combat, just when a rez matters most).
--   * Move it with the anchor on its settings page.
--   * Updates only while it's showing: when the charges change, plus a
--     once-a-second tick for the countdown.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local BR = {}
ns.BattleRez = BR

local REBIRTH = 20484
local FALLBACK_ICON = "Interface\\Icons\\Spell_Nature_Reincarnation"
BR.SIZES = { { "small", "Small", 32 }, { "medium", "Medium", 44 }, { "large", "Large", 60 } }

local function db() return ns.udb.brez end

function BR:Init()
    -- a finished key can still report itself active until you leave
    ns.On("CHALLENGE_MODE_START", function() BR.keyDone = nil; BR:Check() end)
    for _, ev in ipairs({ "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" }) do
        ns.On(ev, function() BR.keyDone = true; BR:Check() end)
    end
    ns.On("ZONE_CHANGED_NEW_AREA", function() BR:Check() end)
    ns.On("ENCOUNTER_START", function() BR.encounter = true; BR:Check() end)
    ns.On("ENCOUNTER_END", function() BR.encounter = false; BR:Check() end)
    ns.On("SPELL_UPDATE_CHARGES", function() if BR.shown then BR:Update() end end)
end

local function inKey()
    if BR.keyDone then return false end
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() or false
end

local function inRaidEncounter() return BR.encounter and ns.InRaidInstance() end

-- Should it be on screen right now? The whole encounter or key - in or out
-- of combat, alive or dead.
function BR:Wanted()
    if self.unlocked then return true end
    if not db().enabled then return false end
    return (inRaidEncounter() or inKey()) and true or false
end

function BR:Check()
    local want = self:Wanted()
    if want and not self.shown then
        local f = self:EnsureFrame()
        f:Show()
        self.shown = true
        self.ticker = C_Timer.NewTicker(1, function() BR:Update() end)
        self:Update()
    elseif not want and self.shown then
        self.shown = false
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        if self.frame then self.frame:Hide() end
    end
end

-- ---------------------------------------------------------------------
-- The icon
-- ---------------------------------------------------------------------
function BR:EnsureFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "TitanUpBattleRez", UIParent)
    f:SetFrameStrata("MEDIUM")
    UI.Draggable(f, db, { "CENTER", "CENTER", -260, 120 }, "Drag to move", nil, function() return BR.unlocked end)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(REBIRTH)
    f.icon:SetTexture(tex or FALLBACK_ICON)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -2, 2); f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(0, 0, 0, 0.8)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    f.count = f:CreateFontString(nil, "OVERLAY")
    f.count:SetPoint("CENTER", 0, 0)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f:Hide()
    self.frame = f
    self:ApplyStyle()
    return f
end

function BR:ApplyStyle()
    local f = self.frame
    if not f then return end
    local px = 44
    for _, s in ipairs(BR.SIZES) do if s[1] == db().size then px = s[3] end end
    f:SetSize(px, px)
    f.count:SetFont(STANDARD_TEXT_FONT, math.floor(px * 0.55), "THICKOUTLINE")
    f.timer:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(px * 0.28)), "OUTLINE")
    f:Place()
end

-- Read the shared pool: charges now, max, and when the next one arrives.
function BR.Charges()
    local ch = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(REBIRTH)
    if type(ch) ~= "table" then return nil end
    return ch.currentCharges, ch.maxCharges, ch.cooldownStartTime, ch.cooldownDuration
end

function BR:Update()
    local f = self.frame
    if not f then return end
    local cur, max, start, dur = BR.Charges()
    if self.unlocked and cur == nil then cur, max = 1, 2 end         -- placing it outside a fight: show a sample
    if cur == nil then
        f.count:SetText("?")
        f.timer:SetText("")
        f.icon:SetDesaturated(false)
        return
    end
    if ns.IsSecret(cur) then
        -- hidden mid-fight: the game still lets us show it, just not compare it
        pcall(f.count.SetText, f.count, cur)
        f.icon:SetDesaturated(false)
    else
        f.count:SetText(tostring(cur))
        f.icon:SetDesaturated(cur <= 0)
        local c = cur <= 0 and { 1, 0.35, 0.35 } or { 1, 1, 1 }
        f.count:SetTextColor(c[1], c[2], c[3])
    end
    -- the next charge: cooldown sweep + countdown
    local recharging = type(start) == "number" and type(dur) == "number" and not ns.IsSecret(start) and not ns.IsSecret(dur)
        and dur > 0 and (ns.IsSecret(cur) or not max or ns.IsSecret(max) or cur < max)
    if recharging then
        f.cd:SetCooldown(start, dur)
        local left = math.max(0, start + dur - GetTime())
        f.timer:SetText(("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60)))
    else
        if f.cd.Clear then f.cd:Clear() end
        f.timer:SetText("")
    end
end

function BR:SetUnlocked(on)
    self.unlocked = on and true or false
    local f = self:EnsureFrame()
    f:EnableMouse(self.unlocked)
    f.hint:SetShown(self.unlocked)
    self:Check()
    if self.shown then self:Update() end
end

function BR:ResetPosition() self:EnsureFrame():ResetPlace() end

-- ---------------------------------------------------------------------
-- Settings page (inside UI Tweaks)
-- ---------------------------------------------------------------------
function BR:BuildPage(parent)
    local pg = CreateFrame("Frame", nil, parent)
    pg:SetAllPoints()
    self.page = pg
    local y = -8
    -- (its description is shown once, at the top of its Settings page)
    UI.Text(pg, "GameFontHighlight", C.text, "Size", "TOPLEFT", 18, y - 5)
    self.sizeBtn = UI.Button(pg, 140, 24, "", nil, function()
        local i = 1
        for k, s in ipairs(BR.SIZES) do if s[1] == db().size then i = k end end
        db().size = BR.SIZES[(i % #BR.SIZES) + 1][1]
        BR:ApplyStyle(); BR:RefreshPage()
    end)
    self.sizeBtn:SetPoint("TOPRIGHT", -18, y)
    y = y - 34
    UI.Text(pg, "GameFontHighlight", C.text, "Move it", "TOPLEFT", 18, y - 5)
    self.anchorBtn, self.resetBtn = ns.Tweaks.MoveControls(pg, BR, { resetW = 100, after = function() BR:RefreshPage() end,
        tip = "Click to show it and drag it anywhere; click again to lock it in place" })
    self.anchorBtn:SetPoint("TOPRIGHT", -18, y)
    self.resetBtn:SetPoint("RIGHT", self.anchorBtn, "LEFT", -8, 0)
    self.pageHeight = -(y - 24) + 20
    return pg
end

function BR:RefreshPage()
    if not self.page then return end
    for _, s in ipairs(BR.SIZES) do if s[1] == db().size then self.sizeBtn.label:SetText(s[2]) end end
    UI.SetActive(self.anchorBtn, self.unlocked)
end
