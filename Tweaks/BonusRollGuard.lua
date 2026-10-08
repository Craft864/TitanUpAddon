-- Titan Up - Tweaks/BonusRollGuard.lua
-- Bonus roll protection (a UI Tweak, off until turned on): no more spending
-- or passing a bonus roll by accident.
--   * Blizzard's bonus roll Roll and Pass buttons get a cover each. Clicking
--     Roll opens a green "Spend a bonus roll?" panel (with your loot spec and
--     how many coins you have); clicking Pass opens a red "Give up this bonus
--     roll?" panel with a big "Keep my roll" button.
--   * Confirming means clicking the real button: its cover steps aside and
--     the button glows. The game only lets its own buttons spend or pass a
--     bonus roll (an addon's click is blocked), so the real button is always
--     the one that does it - Blizzard's frame and buttons are never modified
--     (no taint), same as Release protection.
--   * Nothing clicked within 15 seconds: the covers come back.
--   * The roll result goes to the Loot list ("Bonus roll") - see Loot.lua.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local BG = {}
ns.BonusRollGuard = BG

BG.ARM_SECONDS = 15
local BONUS_ROLL_PROMPT = (Enum and Enum.SpellConfirmationPromptType and Enum.SpellConfirmationPromptType.BonusRoll)
    or LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL or 1

local function db() return ns.udb.tweaks end
function BG:Enabled() return db().bonusGuard and true or false end

function BG:Init()
    ns.On("SPELL_CONFIRMATION_PROMPT", function(_, confirmType, _, _, currencyID)
        if ns.IsSecret(confirmType) or confirmType ~= BONUS_ROLL_PROMPT then return end
        BG.currencyID = not ns.IsSecret(currencyID) and currencyID or nil
        if C_Timer then C_Timer.After(0, function() BG:Check() end) end
    end)
    ns.On("SPELL_CONFIRMATION_TIMEOUT", function() BG:Check() end)
    ns.On("BONUS_ROLL_STARTED", function() BG:Off() end)
    ns.On("BONUS_ROLL_RESULT", function() BG:Off() end)
    self:Watch()
end

-- the frame itself: watched, never changed (hooked once it exists)
function BG:Watch()
    if self.watching or not (BonusRollFrame and BonusRollFrame.HookScript) then return end
    self.watching = true
    BonusRollFrame:HookScript("OnShow", function() BG:Check() end)
    BonusRollFrame:HookScript("OnHide", function() BG:Off() end)
end

-- Blizzard's Roll and Pass buttons (nil if the frame's layout is unknown)
function BG.Buttons()
    local f = BonusRollFrame
    if not f then return nil end
    local p = f.PromptFrame or f
    local roll = p.RollButton or f.RollButton
    local pass = p.PassButton or f.PassButton
    if type(roll) == "table" and type(pass) == "table" then return roll, pass end
end

-- "Holy (current spec)": the spec the roll's loot is for
function BG.LootSpec()
    local specID = GetLootSpecialization and GetLootSpecialization()
    if specID and not ns.IsSecret(specID) and specID > 0 and GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(specID)
        if name then return name end
    end
    local index = GetSpecialization and GetSpecialization()
    if index and GetSpecializationInfo then
        local _, name = GetSpecializationInfo(index)
        if name then return name .. " (current spec)" end
    end
    return "unknown"
end

function BG.Coins()
    if not (BG.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, BG.currencyID)
    if ok and type(info) == "table" and not ns.IsSecret(info.quantity) then return info.quantity, info.name end
end

-- ---------------------------------------------------------------------
-- Covers, the glow and the panel (built the first time they're needed)
-- ---------------------------------------------------------------------
local function cover(kind)
    local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    UI.Skin(b, { 0, 0, 0, 0.25 }, kind == "roll" and C.good or C.bad)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function() BG:Ask(kind) end)
    b:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(kind == "roll" and "Titan Up: click to roll - you'll confirm first" or "Titan Up: click to pass - you'll confirm first", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

function BG:Build()
    if self.panel then return end
    self.covers = { roll = cover("roll"), pass = cover("pass") }
    -- the glow round the real button once you've said yes
    local g = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    g:SetFrameStrata("FULLSCREEN_DIALOG")
    g:EnableMouse(false)
    g:Hide()
    g:SetScript("OnUpdate", function(s)
        local a = 0.55 + 0.45 * math.abs(math.sin(GetTime() * 4))
        local c = s.color or C.good
        s:SetBackdropBorderColor(c[1], c[2], c[3], a)
    end)
    self.glow = g

    local p = UI.Window("TitanUpBonusRollGuard", 320, 112, { strata = "FULLSCREEN_DIALOG", noTop = true, noEsc = true })
    p.title = UI.Text(p, "GameFontNormalLarge", C.good, nil, "TOP", 0, -12)
    p.line1 = UI.Text(p, "GameFontHighlight", C.text, nil, "TOP", p.title, "BOTTOM", 0, -6)
    p.line2 = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "TOP", p.line1, "BOTTOM", 0, -4)
    p.line1:SetWidth(296); p.line2:SetWidth(296)
    p.keep = UI.Button(p, 200, 28, "", nil, function() BG:Cover() end)
    p.keep:SetPoint("BOTTOM", 0, 10)
    p:ClearAllPoints()
    p:SetPoint("BOTTOM", BonusRollFrame, "TOP", 0, 8)             -- just above Blizzard's frame
    self.panel = p
end

-- Show the covers (the safe state)
function BG:Cover()
    self.armed, self.armedUntil = nil, nil
    local roll, pass = BG.Buttons()
    if not roll or not self:Enabled() or not (BonusRollFrame and BonusRollFrame:IsShown()) then return self:Off() end
    self:Build()
    self.covers.roll:ClearAllPoints(); self.covers.roll:SetAllPoints(roll)
    self.covers.pass:ClearAllPoints(); self.covers.pass:SetAllPoints(pass)
    self.covers.roll:SetShown(roll:IsVisible())
    self.covers.pass:SetShown(pass:IsVisible())
    self.glow:Hide()
    self.panel:Hide()
end

-- Clicked a cover: explain, lift that cover, make the real button glow
function BG:Ask(kind)
    local roll, pass = BG.Buttons()
    if not roll then return self:Off() end
    self:Build()
    self.armed = kind
    self.armedUntil = GetTime() + BG.ARM_SECONDS
    local token = {}
    self.token = token
    C_Timer.After(BG.ARM_SECONDS, function() if BG.token == token and BG.armed then BG:Check() end end)
    local p, real = self.panel, kind == "roll" and roll or pass
    self.covers[kind]:Hide()
    self.covers[kind == "roll" and "pass" or "roll"]:Show()
    local color = kind == "roll" and C.good or C.bad
    UI.Skin(p, C.bg, color)
    p.title:SetTextColor(color[1], color[2], color[3])
    if kind == "roll" then
        local coins, coinName = BG.Coins()
        p.title:SetText("Spend a bonus roll?")
        p.line1:SetText("Loot spec: |cffffd94d" .. BG.LootSpec() .. "|r" .. (coins and ("   " .. (coinName or "Coins") .. " left: " .. coins) or ""))
        p.line2:SetText("Click the glowing Roll button to spend it.")
        p.keep.label:SetText("Cancel")
    else
        p.title:SetText("Give up this bonus roll?")
        p.line1:SetText("You won't get it back.")
        p.line2:SetText("Click the glowing Pass button to give it up.")
        p.keep.label:SetText("|cff66e08cKeep my roll|r")
    end
    p.keep.tip = nil
    self.glow:ClearAllPoints()
    self.glow:SetPoint("TOPLEFT", real, "TOPLEFT", -4, 4)
    self.glow:SetPoint("BOTTOMRIGHT", real, "BOTTOMRIGHT", 4, -4)
    UI.Skin(self.glow, { 0, 0, 0, 0 }, color)
    self.glow.color = color
    self.glow:Show()
    p:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end

function BG:Check()
    if not self:Enabled() then return self:Off() end
    self:Watch()
    if BonusRollFrame and BonusRollFrame:IsShown() and BG.Buttons() then
        if not self.armed or (self.armedUntil and GetTime() >= self.armedUntil) then self:Cover() end
    else
        self:Off()
    end
end

function BG:Off()
    self.armed, self.armedUntil = nil, nil
    if not self.panel then return end
    self.covers.roll:Hide()
    self.covers.pass:Hide()
    self.glow:Hide()
    self.panel:Hide()
end
