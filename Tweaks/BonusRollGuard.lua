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
--
-- Docked in the Loot Rolls window (0.30.1): while that window is open (out
-- of combat), Blizzard's real bonus roll frame is moved into a "Bonus roll"
-- strip along the window's bottom - only its position changes (no reparent,
-- no scripts). Closing the window puts it back in its place in Blizzard's
-- loot column. It's never moved in combat (any move waits for combat to
-- end). With protection on, the covers and confirm panels work the same there.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local BG = {}
ns.BonusRollGuard = BG

BG.ARM_SECONDS = 15
local BONUS_ROLL_PROMPT = (Enum and Enum.SpellConfirmationPromptType and Enum.SpellConfirmationPromptType.BonusRoll)
    or LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL or 1

local function db() return ns.udb.tweaks end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
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
    ns.On("PLAYER_REGEN_ENABLED", function() BG:Dock() end)
    self:Watch()
end

-- the frame itself: watched, never changed (hooked once it exists)
function BG:Watch()
    if self.watching or not (BonusRollFrame and BonusRollFrame.HookScript) then return end
    self.watching = true
    BonusRollFrame:HookScript("OnShow", function() BG:Dock(); BG:Check() end)
    BonusRollFrame:HookScript("OnHide", function() BG:Off(); BG:Undock() end)
    -- Blizzard lays the frame out again when its loot container changes:
    -- note its new place (to go back to), then put it back in the strip
    if hooksecurefunc then
        for _, fn in ipairs({ "GroupLootContainer_Update", "GroupLootContainer_AddFrame" }) do
            if _G[fn] then hooksecurefunc(fn, function() if BG.docked then BG:NoteHome(); BG:Place() end end) end
        end
    end
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

-- the spec functions moved to C_SpecializationInfo (11.2); old globals as fallback
local function spec(fn, ...)
    local f = (C_SpecializationInfo and C_SpecializationInfo[fn]) or _G[fn]
    if f then return f(...) end
end

-- "Holy (current spec)": the spec the roll's loot is for
function BG.LootSpec()
    local specID = ns.Safe.Num(spec("GetLootSpecialization"))
    if specID and specID > 0 then
        local _, name = spec("GetSpecializationInfoByID", specID)
        if ns.Safe.Text(name) then return name end
    end
    local index = ns.Safe.Num(spec("GetSpecialization"))
    if index then
        local _, name = spec("GetSpecializationInfo", index)
        if ns.Safe.Text(name) then return name .. " (current spec)" end
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
    self:Watch()
    if not self:Enabled() then return self:Off() end
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

-- ---------------------------------------------------------------------
-- Docked in the Loot Rolls window
-- ---------------------------------------------------------------------
BG.STRIP_H = 72

-- the strip: its own frame under the window, skinned to look like part of
-- it, on a low layer so Blizzard's frame always draws on top
function BG:Strip()
    local win = ns.LootRolls and ns.LootRolls.V.frame
    if not win then return nil end
    local st = self.strip
    if not st then
        st = CreateFrame("Frame", nil, win, "BackdropTemplate")
        UI.Skin(st, C.bg, C.accent)
        st:SetFrameStrata("LOW")
        st:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, 1)
        st:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", 0, 1)
        st:SetHeight(BG.STRIP_H)
        UI.Text(st, "GameFontNormalSmall", C.accent, "BONUS ROLL", "TOPLEFT", 14, -12)
        st.hint = UI.Text(st, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 14, -30)
        st.hint:SetWidth(220); st.hint:SetJustifyH("LEFT")
        st.slot = CreateFrame("Frame", nil, st)
        st.slot:SetPoint("TOPLEFT", 250, -6)
        st.slot:SetPoint("BOTTOMRIGHT", -14, 6)
        st:Hide()
        self.strip = st
    end
    return st
end

-- Move Blizzard's frame into the strip: the Loot Rolls window is open, a
-- bonus roll is showing, and we're out of combat.
function BG:Dock()
    local f = BonusRollFrame
    local win = ns.LootRolls and ns.LootRolls.V.frame
    if not (f and f:IsShown() and win and win:IsShown()) then return self:Undock() end
    if self.docked then self.strip:Show(); return self:Place() end
    if inCombat() then return end                                   -- after combat (PLAYER_REGEN_ENABLED)
    local st = self:Strip()
    if not st then return end
    self:NoteHome()                                                  -- to put it back
    self.docked = true
    st.hint:SetText(self:Enabled() and "Roll or pass here - Titan Up asks first." or "Roll or pass here.")
    st:Show()
    self:Place()
end

function BG:Place()
    local f, st = BonusRollFrame, self.strip
    if not (f and st and self.docked) or inCombat() then return end    -- (re-placed after combat)
    f:ClearAllPoints()
    f:SetPoint("LEFT", st.slot, "LEFT", 0, 0)
end

-- Where Blizzard has the frame: noted when docking and again each time
-- Blizzard lays its loot column out while it's docked (its slot moves as
-- rolls end or are handed back), so undocking puts it in its current slot.
function BG:NoteHome()
    local f, st = BonusRollFrame, self.strip
    if not (f and f.GetNumPoints) then return end
    local _, rel = f:GetPoint(1)
    if self.docked and st and rel == st.slot then return end         -- that's our strip, not Blizzard's place
    self.home = {}
    for i = 1, f:GetNumPoints() do self.home[i] = { f:GetPoint(i) } end
end

-- back in its place in Blizzard's loot column; in combat, once combat ends
function BG:Undock()
    if self.strip then self.strip:Hide() end
    if not self.docked or inCombat() then return end
    self.docked = nil
    local f = BonusRollFrame
    if f and self.home and #self.home > 0 then
        f:ClearAllPoints()
        for _, pt in ipairs(self.home) do f:SetPoint(unpack(pt)) end
    end
    self.home = nil
end
