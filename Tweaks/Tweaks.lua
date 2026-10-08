-- Titan Up - Tweaks/Tweaks.lua
-- UI Tweaks: small quality-of-life changes to the game's own UI, each with
-- an on/off switch. New tweaks add an entry to TW.LIST.
--
-- Release protection (raid instances only): when you die, the Release
-- Spirit button is covered by a small click-catcher that says "Hold Alt".
-- Hold Alt for 3 seconds and it steps aside; let go early and it resets.
-- Blizzard's own dialog and button are never modified (no taint), and a
-- combat res / soulstone works as normal.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local TW = {}
ns.Tweaks = TW

local HOLD_SECONDS = 3

local function db() return ns.udb.tweaks end

-- get/set: where the switch lives; page: its options (shown beside it in UI Tweaks)
TW.LIST = {
    { key = "releaseGuard", name = "Release protection",
      desc = "In raid instances, the Release Spirit button only works after holding Alt for 3 seconds - no more accidental releases mid-fight.",
      get = function() return ns.udb.tweaks.releaseGuard end,
      set = function(on) ns.udb.tweaks.releaseGuard = on end },
    { key = "deathAlerts", name = "Death alerts",
      desc = "A banner when someone in your group dies - role icon, class color and fight time - with sounds, and one \"Wipe likely\" banner instead of spam.",
      get = function() return ns.udb.deathAlerts.enabled end,
      set = function(on) ns.udb.deathAlerts.enabled = on end,
      page = function() return ns.DeathAlerts end, title = "DEATH ALERTS" },
    { key = "stackSplitter", name = "Stack splitter",
      desc = "Shift-click a stack for a better split: take some, split it all into stacks of N or into K equal stacks, or combine partial stacks - in bags, bank and guild bank.",
      get = function() return ns.udb.splitter.enabled end,
      set = function(on) ns.udb.splitter.enabled = on end,
      page = function() return ns.StackSplitter end, title = "STACK SPLITTER" },
    { key = "brez", name = "Battle rez tracker",
      desc = "The group's battle-rez charges on screen during Mythic+ keys and raid boss fights (even while you're dead) - grey at zero, with a countdown to the next.",
      get = function() return ns.udb.brez.enabled end,
      set = function(on) ns.udb.brez.enabled = on; ns.BattleRez:Check() end,
      page = function() return ns.BattleRez end, title = "BATTLE REZ TRACKER" },
    { key = "bonusGuard", name = "Bonus roll protection",
      desc = "Blizzard's bonus roll Roll and Pass buttons ask first - a green \"Spend a bonus roll?\" or a red \"Give up this bonus roll?\" - so a misclick can't waste one.",
      get = function() return ns.udb.tweaks.bonusGuard end,
      set = function(on) ns.udb.tweaks.bonusGuard = on; ns.BonusRollGuard:Check() end },
}

function TW:Init()
    -- watch for the death dialog (nothing is built until it's needed)
    if StaticPopup_Show and hooksecurefunc then
        hooksecurefunc("StaticPopup_Show", function(which)
            if which == "DEATH" then C_Timer.After(0, function() TW:GuardRelease() end)
            else TW:CheckGuardStillValid() end                -- e.g. a battle rez offer reusing the same pop-up
        end)
    end
    ns.On("PLAYER_DEAD", function() C_Timer.After(0.2, function() TW:GuardRelease() end) end)
    ns.On("PLAYER_ALIVE", function() TW:ReleaseGuardOff() end)
    ns.On("PLAYER_UNGHOST", function() TW:ReleaseGuardOff() end)
end

-- The visible death dialog's Release button, if any.
local function releaseButton()
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("DEATH")
    if not dialog then return nil end
    local b = (dialog.GetButton1 and dialog:GetButton1()) or dialog.button1 or _G[(dialog:GetName() or "") .. "Button1"]
    return b, dialog
end

function TW:GuardRelease()
    if not db().releaseGuard or not ns.InRaidInstance() then return end
    local button, dialog = releaseButton()
    if not button then return end
    local g = self.guard
    if not g then
        g = CreateFrame("Button", "TitanUpReleaseGuard", UIParent, "BackdropTemplate")
        UI.Skin(g, { 0.08, 0.05, 0.05, 0.92 }, C.warn)
        g:SetFrameStrata("FULLSCREEN_DIALOG")
        g:EnableMouse(true)
        g:RegisterForClicks("AnyUp")
        g:SetScript("OnClick", function() if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end end)
        g.fill = g:CreateTexture(nil, "ARTWORK")
        g.fill:SetPoint("TOPLEFT", 2, -2)
        g.fill:SetPoint("BOTTOMLEFT", 2, 2)
        g.fill:SetColorTexture(C.warn[1], C.warn[2], C.warn[3], 0.45)
        g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        g.text:SetPoint("CENTER")
        g:SetScript("OnUpdate", function(s, elapsed) TW:OnGuardUpdate(elapsed) end)
        self.guard = g
    end
    g.button, g.dialog = button, dialog
    g:ClearAllPoints()
    g:SetAllPoints(button)
    g.held, g.shown = 0, nil
    g:Show()
    self:OnGuardUpdate(0)
end

-- The cover belongs only on the Release Spirit dialog. The game reuses the
-- same pop-up for other things (a battle rez offer, a soulstone prompt), so
-- the moment it shows anything else, the cover goes.
function TW.IsDeathDialog(dialog)
    return dialog and dialog:IsShown() and dialog.which == "DEATH"
end

function TW:CheckGuardStillValid()
    local g = self.guard
    if g and g:IsShown() and not TW.IsDeathDialog(g.dialog) then self:ReleaseGuardOff() end
end

function TW:OnGuardUpdate(elapsed)
    local g = self.guard
    if not g then return end
    if not TW.IsDeathDialog(g.dialog) then return self:ReleaseGuardOff() end
    if IsAltKeyDown() then g.held = (g.held or 0) + (elapsed or 0) else g.held = 0 end
    local left = math.max(0, HOLD_SECONDS - g.held)
    local w = g:GetWidth()
    if type(w) == "number" and w > 4 then g.fill:SetWidth(math.max(0.01, (w - 4) * (g.held / HOLD_SECONDS))) end
    local tenths = g.held > 0 and math.floor(left * 10 + 0.5) or -1      -- the text only changes with the tenths
    if tenths ~= g.shown then
        g.shown = tenths
        g.text:SetText(tenths >= 0 and ("Keep holding Alt... %.1f"):format(tenths / 10) or "Hold Alt (3s) to release")
    end
    if g.held >= HOLD_SECONDS then
        -- step aside: the real Release button works normally now
        g:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    end
end

function TW:ReleaseGuardOff()
    if self.guard then self.guard:Hide() end
end

-- The "move it" controls of an on-screen display (Combat Timer, Death
-- alerts, Battle rez tracker): the anchor button (click to unlock and
-- drag, again to lock) and "Reset position"; leaving the page locks it
-- again. target has unlocked, SetUnlocked(on) and ResetPosition();
-- o = { size, tip, resetW, resetH, after (run after a click) }.
function TW.MoveControls(parent, target, o)
    local anchor = UI.IconButton(parent, o.size or 24, ns.MEDIA .. "Anchor", o.tip, function()
        target:SetUnlocked(not target.unlocked)
        if o.after then o.after() end
    end)
    local reset = UI.Button(parent, o.resetW or 92, o.resetH or 22, "Reset position", o.resetTip, function() target:ResetPosition() end)
    parent:HookScript("OnHide", function() if target.unlocked then target:SetUnlocked(false) end end)
    return anchor, reset
end

-- ---------------------------------------------------------------------
-- Window: every tweak with its On/Off switch on the left; the selected
-- tweak's options on the right (the same pages Settings used to show)
-- ---------------------------------------------------------------------
local V = {}
ns.TweaksUI = V
local W, H = 880, 570
local LIST_W = 380
local PAGE_W = 460                 -- the tweak pages are laid out for this width
local ROW_H = 92

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpTweaks", "tweaks", "UI TWEAKS", W, H, { mark = { 360, 0.04, -20 } })

    -- the list of tweaks
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT")
    list:SetSize(LIST_W, H)
    self.list = list
    self.intro = UI.Text(list, "GameFontHighlightSmall", C.muted, "Small changes to the game's own UI - each is off until you turn it on.", "TOPLEFT", 16, -14)
    self.intro:SetWidth(LIST_W - 28)
    self.intro:SetJustifyH("LEFT")
    self.rows = {}
    self.cards = {}
    for i, t in ipairs(TW.LIST) do
        local card = CreateFrame("Button", nil, list, "BackdropTemplate")
        UI.Skin(card, C.panel, C.line)
        card:SetSize(LIST_W - 28, ROW_H - 8)
        card:SetPoint("TOPLEFT", 16, -40 - (i - 1) * ROW_H)
        card:SetScript("OnClick", function() V:Select(t.key) end)
        local hl = card:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)
        local name = UI.Text(card, "GameFontNormal", C.text, t.name, "TOPLEFT", 12, -10)
        local desc = UI.Text(card, "GameFontHighlightSmall", C.muted, t.desc, "TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        desc:SetWidth(LIST_W - 130); desc:SetJustifyH("LEFT")
        desc:SetHeight(ROW_H - 36); desc:SetJustifyV("TOP")
        local b = UI.Button(card, 64, 24, "", nil, function()
            t.set(not t.get())
            V:Select(t.key)
            ns.SettingsChanged()                  -- updates this list and the page beside it
        end)
        b:SetPoint("TOPRIGHT", -10, -10)
        self.rows[t.key] = b
        self.cards[t.key] = card
    end

    -- the selected tweak's options
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", LIST_W, -12); sep:SetPoint("BOTTOMLEFT", LIST_W, 12); sep:SetWidth(1)
    self.pageTitle = UI.Text(f, "GameFontNormal", C.text, nil, "TOPLEFT", LIST_W + 18, -14)
    self.pager = ns.Settings.Pager(f, LIST_W + 10, -40, PAGE_W, H - 52)
    self:Select(TW.LIST[1].key)
end

-- show tweak `key`'s options beside the list
function V:Select(key)
    local t
    for _, x in ipairs(TW.LIST) do if x.key == key then t = x end end
    if not t then return end
    self.current = key
    self.pageTitle:SetText(t.name:upper() .. " OPTIONS")
    for k, card in pairs(self.cards) do
        local c = (k == key) and C.accent or C.line
        card:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    self.pager:Show({ key = "tweak:" .. key, tweak = t, noToggle = true })
end

-- (old callers: open a tweak's options)
function V:Open(key)
    self:Show()
    ns.Nav:Activate("tweaks")
    if key then self:Select(key) end
end

function V:Refresh()
    if not self.frame then return end
    for _, t in ipairs(TW.LIST) do
        local b = self.rows[t.key]
        local on = t.get()
        b.label:SetText(on and "|cff66e08cOn|r" or "Off")
        UI.SetActive(b, on)
    end
    self.pager:Refresh()
end

ns.RegisterModule({
    key = "tweaks", name = "UI Tweaks", icon = ns.MEDIA .. "Tweaks", group = "uitweaks", order = 1,
    desc = "Small changes to the game's UI, like Release protection in raids.",
    view = V,
})
