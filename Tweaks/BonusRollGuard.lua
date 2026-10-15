-- Titan Up - Tweaks/BonusRollGuard.lua
-- Bonus roll protection (a UI Tweak, off until turned on): no more spending
-- or passing a bonus roll by accident.
--   * Blizzard's bonus roll Roll and Pass buttons get a cover each. Clicking
--     Roll opens a green "Spend your bonus roll?" panel (boss, loot spec,
--     coins now and after); clicking Pass opens a red "Pass on your bonus
--     roll?" panel ("Nevermind, I'm still thinking" backs out).
--   * (0.42.0) The panel's own big Yes button does it: a secure "click"
--     button (SecureActionButtonTemplate, type "click") that clicks
--     Blizzard's real Roll / Pass button, exactly like a /click macro - the
--     game only lets its own button spend or pass a bonus roll, and this way
--     its own button still does. Blizzard's frame and buttons are never
--     modified (no taint).
--   * In combat a secure button can't be shown or set up, and if the click
--     ever doesn't go through, the panel falls back to the old way: the real
--     button's cover steps aside, it glows, and the panel says to click it.
--   * Nothing clicked within 30 seconds: the covers come back.
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

BG.ARM_SECONDS = 30
BG.CHECK_AFTER = 1.5              -- a Yes that did nothing by then: fall back to the glowing button
local BONUS_ROLL_PROMPT = (Enum and Enum.SpellConfirmationPromptType and Enum.SpellConfirmationPromptType.BonusRoll)
    or LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL or 1

local function db() return ns.udb.tweaks end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
function BG:Enabled() return db().bonusGuard and true or false end

function BG:Init()
    ns.On("SPELL_CONFIRMATION_PROMPT", function(_, confirmType, _, _, currencyID, currencyCost)
        if ns.IsSecret(confirmType) or confirmType ~= BONUS_ROLL_PROMPT then return end
        BG.currencyID = not ns.IsSecret(currencyID) and currencyID or nil
        BG.cost = ns.Safe.Num(currencyCost)
        if C_Timer then C_Timer.After(0, function() BG:Check() end) end
    end)
    ns.On("SPELL_CONFIRMATION_TIMEOUT", function() BG:Check() end)
    ns.On("BONUS_ROLL_STARTED", function() BG:Off() end)
    ns.On("BONUS_ROLL_RESULT", function() BG:Off() end)
    -- the secure Yes can't be hidden once combat starts: hide it just before
    ns.On("PLAYER_REGEN_DISABLED", function() BG:CombatStarts() end)
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

-- the boss the bonus roll is for ("this boss" if the journal doesn't say)
function BG.Boss()
    local id = BonusRollFrame and ns.Safe.Num(BonusRollFrame.encounterID)
    if id and EJ_GetEncounterInfo then
        local ok, name = pcall(EJ_GetEncounterInfo, id)
        if ok and ns.Safe.Text(name) then return name end
    end
    return "this boss"
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

    local p = UI.Window("TitanUpBonusRollGuard", 380, 236, { strata = "FULLSCREEN_DIALOG", noTop = true, noEsc = true })
    p.title = UI.Text(p, "GameFontNormalLarge", C.good, nil, "TOP", 0, -14)
    p.what = UI.Text(p, "GameFontHighlight", C.text, nil, "TOP", p.title, "BOTTOM", 0, -10)
    p.facts = UI.Text(p, "GameFontHighlightSmall", C.text, nil, "TOP", p.what, "BOTTOM", 0, -10)
    for _, t in ipairs({ p.what, p.facts }) do t:SetWidth(344); t:SetJustifyH("CENTER") end
    -- (where the Yes goes; this one only shows when the secure one can't)
    p.yes = UI.Button(p, 344, 32, "", nil, nil)
    p.yes:SetPoint("BOTTOM", 0, 60)
    p.yes.label:SetFontObject("GameFontNormal")
    p.no = UI.Button(p, 344, 26, "", nil, function() BG:Cover() end)
    p.no:SetPoint("BOTTOM", 0, 28)
    p.fine = UI.Text(p, "GameFontHighlightSmall", C.muted, nil, "BOTTOM", 0, 10)
    p.fine:SetWidth(344)
    p:ClearAllPoints()
    p:SetPoint("BOTTOM", BonusRollFrame, "TOP", 0, 8)             -- just above Blizzard's frame
    self.panel = p

    -- The real Yes: a secure button that clicks Blizzard's own Roll / Pass
    -- button (like a /click macro). Its own frame, not the panel's child:
    -- a secure child would lock the panel in combat.
    local y = CreateFrame("Button", "TitanUpBonusRollYes", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    y:SetFrameStrata("FULLSCREEN_DIALOG")
    y:SetFrameLevel((p:GetFrameLevel() or 1) + 10)
    y:RegisterForClicks("AnyUp")
    y:SetAttribute("type", "click")
    y:SetAttribute("useOnKeyDown", false)
    -- (anchored to p.yes only while shown: a protected button anchored to
    -- the panel would lock the panel in combat too)
    y:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    y.label = y:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    y.label:SetPoint("CENTER")
    y:HookScript("OnEnter", function(s) s:SetBackdropColor(s.color[1] * 0.45, s.color[2] * 0.45, s.color[3] * 0.45, 1) end)
    y:HookScript("OnLeave", function(s) s:SetBackdropColor(s.color[1] * 0.25, s.color[2] * 0.25, s.color[3] * 0.25, 1) end)
    y:HookScript("OnClick", function() BG:Clicked() end)
    y.color = C.good
    y:Hide()
    self.yes = y
end

-- the secure Yes can only be shown, hidden or pointed at a button out of combat
local function hideYes()
    if BG.yes and not inCombat() then BG.yes:Hide(); BG.yes:ClearAllPoints() end
end

-- Show the covers (the safe state)
function BG:Cover()
    self.armed, self.armedUntil, self.glowing = nil, nil, nil
    local roll, pass = BG.Buttons()
    if not roll or not self:Enabled() or not (BonusRollFrame and BonusRollFrame:IsShown()) then return self:Off() end
    self:Build()
    self.covers.roll:ClearAllPoints(); self.covers.roll:SetAllPoints(roll)
    self.covers.pass:ClearAllPoints(); self.covers.pass:SetAllPoints(pass)
    self.covers.roll:SetShown(roll:IsVisible())
    self.covers.pass:SetShown(pass:IsVisible())
    self.glow:Hide()
    hideYes()
    self.panel:Hide()
end

-- the words on the panel, spelled out
local TEXT = {
    roll = function()
        local coins, coinName = BG.Coins()
        local cost = BG.cost or 1
        local coin = cost == 1 and "coin" or "coins"
        return {
            title = "SPEND YOUR BONUS ROLL?",
            what = ("This uses |cffffd94d%d %s|r for a chance at extra loot from |cffffffff%s|r."):format(cost, coinName or coin, BG.Boss()),
            facts = "Loot spec: |cffffd94d" .. BG.LootSpec() .. "|r"
                .. (coins and ("\nCoins: |cffffd94d" .. coins .. " now, " .. math.max(0, coins - cost) .. " after this roll|r") or ""),
            yes = ("YES - SPEND %d %s AND ROLL"):format(cost, coin:upper()),
            no = "No, go back",
            fine = "Nothing is spent until you click the green button.",
            button = "Roll",
        }
    end,
    pass = function()
        local coins = BG.Coins()
        return {
            title = "PASS ON YOUR BONUS ROLL?",
            what = ("You will |cfff25959NOT|r roll for extra loot from |cffffffff%s|r.\nThis can't be undone."):format(BG.Boss()),
            facts = (coins and ("Coins: |cffffd94d" .. coins .. " - none spent if you pass|r\n") or "") .. "Loot spec: |cffffd94d" .. BG.LootSpec() .. "|r",
            yes = "YES - PASS, NO BONUS ROLL",
            no = "|cff66e08cNevermind, I'm still thinking|r",
            fine = "Your roll is safe until you click the red button.",
            button = "Pass",
        }
    end,
}

-- Clicked a cover: the panel, with its own Yes
function BG:Ask(kind)
    local roll, pass = BG.Buttons()
    if not roll then return self:Off() end
    self:Build()
    self.armed, self.glowing = kind, nil
    self.armedUntil = GetTime() + BG.ARM_SECONDS
    local token = {}
    self.token = token
    C_Timer.After(BG.ARM_SECONDS, function() if BG.token == token and BG.armed then BG:Check() end end)
    local p, real = self.panel, kind == "roll" and roll or pass
    local t = TEXT[kind]()
    self.text = t
    -- both stay covered: the Yes clicks the real button
    self.covers.roll:Show(); self.covers.pass:Show()
    self.glow:Hide()
    local color = kind == "roll" and C.good or C.bad
    UI.Skin(p, C.bg, color)
    p.title:SetTextColor(color[1], color[2], color[3])
    p.title:SetText(t.title)
    p.what:SetText(t.what)
    p.facts:SetText(t.facts)
    p.no.label:SetText(t.no)
    p.fine:SetText(t.fine)
    p.yes.textColor, p.yes.edge = color, color
    p:Show()
    if inCombat() then
        self:Glow(kind)
    else
        local y = self.yes
        y:SetAttribute("clickbutton", real)
        y.color = color
        y:SetBackdropColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 1)
        y:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        y.label:SetText(t.yes)
        y.label:SetTextColor(color[1], color[2], color[3])
        y:ClearAllPoints(); y:SetAllPoints(p.yes)
        y:Show()
        p.yes:Hide()
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
end

-- The old way (in combat, or a Yes that didn't go through): lift the real
-- button's cover and make it glow; the panel says to click it.
function BG:Glow(kind, why)
    local roll, pass = BG.Buttons()
    if not roll or not self.panel then return end
    local p, real, t = self.panel, kind == "roll" and roll or pass, self.text or TEXT[kind]()
    local color = kind == "roll" and C.good or C.bad
    self.glowing = true
    hideYes()
    self.covers[kind]:Hide()
    self.covers[kind == "roll" and "pass" or "roll"]:Show()
    p.yes.label:SetText("CLICK THE GLOWING " .. t.button:upper() .. " BUTTON")
    p.yes.textColor, p.yes.edge = color, color
    UI.Paint(p.yes)
    p.yes:Show()
    p.fine:SetText(why or ("In combat only Blizzard's own button can do this - click its glowing " .. t.button .. " button."))
    self.glow:ClearAllPoints()
    self.glow:SetPoint("TOPLEFT", real, "TOPLEFT", -4, 4)
    self.glow:SetPoint("BOTTOMRIGHT", real, "BOTTOMRIGHT", 4, -4)
    UI.Skin(self.glow, { 0, 0, 0, 0 }, color)
    self.glow.color = color
    self.glow:Show()
end

-- The secure Yes was clicked: if the bonus roll is still waiting a moment
-- later, the click didn't go through - fall back to the glowing button.
function BG:Clicked()
    local kind, token = self.armed, self.token
    if not kind then return end
    self.armedUntil = GetTime() + BG.ARM_SECONDS
    C_Timer.After(BG.CHECK_AFTER, function()
        if BG.token ~= token or BG.armed ~= kind or BG.glowing then return end
        local f = BonusRollFrame
        local state = f and ns.Safe.Text(f.state)
        if f and f:IsShown() and (state == nil or state == "prompt") then
            BG:Glow(kind, "That didn't go through - click Blizzard's glowing " .. (BG.text and BG.text.button or "") .. " button instead.")
        end
    end)
end

function BG:CombatStarts()
    if not self.yes then return end
    -- (PLAYER_REGEN_DISABLED comes just before the lockdown: still allowed)
    local was = self.yes:IsShown()
    self.yes:Hide(); self.yes:ClearAllPoints()
    if was and self.armed then self:Glow(self.armed) end
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
    self.armed, self.armedUntil, self.glowing = nil, nil, nil
    if not self.panel then return end
    self.covers.roll:Hide()
    self.covers.pass:Hide()
    self.glow:Hide()
    hideYes()
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
