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

-- get/set: where the switch lives; page: its settings page (shown in Settings)
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
      desc = "The group's battle-rez charges on screen while you're in combat in Mythic+ or a raid boss fight - grey at zero, with a countdown to the next.",
      get = function() return ns.udb.brez.enabled end,
      set = function(on) ns.udb.brez.enabled = on; ns.BattleRez:Check() end,
      page = function() return ns.BattleRez end, title = "BATTLE REZ TRACKER" },
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

TW.InRaidInstance = ns.InRaidInstance

-- The visible death dialog's Release button, if any.
local function releaseButton()
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("DEATH")
    if not dialog then return nil end
    local b = (dialog.GetButton1 and dialog:GetButton1()) or dialog.button1 or _G[(dialog:GetName() or "") .. "Button1"]
    return b, dialog
end

function TW:GuardRelease()
    if not db().releaseGuard or not TW.InRaidInstance() then return end
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
    g.held = 0
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
    g.text:SetText(g.held > 0 and ("Keep holding Alt... %.1f"):format(left) or "Hold Alt (3s) to release")
    if g.held >= HOLD_SECONDS then
        -- step aside: the real Release button works normally now
        g:Hide()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    end
end

function TW:ReleaseGuardOff()
    if self.guard then self.guard:Hide() end
end

-- ---------------------------------------------------------------------
-- Settings window (the module's page)
-- ---------------------------------------------------------------------
local V = {}
ns.TweaksUI = V
local W = 460

function V:Create()
    local rowH = 64
    self.listH = 50 + #TW.LIST * rowH + 20
    local f = ns.Nav:Window(self, "TitanUpTweaks", "tweaks", "UI TWEAKS", W, self.listH, { mark = { 260, 0.05, -10 },
        cog = { "UI Tweaks settings", function() ns.Settings:Open("tweak:" .. TW.LIST[1].key, V.frame) end } })

    -- the list of tweaks
    local list = CreateFrame("Frame", nil, f)
    list:SetAllPoints()
    self.list = list
    self.intro = UI.Text(list, "GameFontHighlightSmall", C.muted, "Small changes to the game's own UI - each is off until you turn it on.", "TOPLEFT", 18, -12)
    self.intro:SetPoint("RIGHT", -100, 0)              -- clear of the cog and X
    self.intro:SetJustifyH("LEFT")
    self.rows = {}
    for i, t in ipairs(TW.LIST) do
        local y = -40 - (i - 1) * rowH
        local name = UI.Text(list, "GameFontNormal", C.text, t.name, "TOPLEFT", 18, y)
        local desc = UI.Text(list, "GameFontHighlightSmall", C.muted, t.desc, "TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        desc:SetWidth(W - 190); desc:SetJustifyH("LEFT")
        local b = UI.Button(list, 70, 24, "", nil, function()
            t.set(not t.get())
            ns.SettingsChanged()                  -- updates this list and an open Settings page
        end)
        b:SetPoint("TOPRIGHT", -18, y - 2)
        self.rows[t.key] = b
        -- its settings live in the Settings window: the cog goes straight to its page
        if t.page then
            local s = UI.IconButton(list, 24, ns.MEDIA .. "Cog", "Open " .. t.name .. " settings", function() ns.Settings:Open("tweak:" .. t.key, V.frame) end)
            s:SetPoint("RIGHT", b, "LEFT", -8, 0)
            self.settingsBtns = self.settingsBtns or {}
            self.settingsBtns[t.key] = s
        end
    end
end

function V:Refresh()
    if not self.frame then return end
    for _, t in ipairs(TW.LIST) do
        local b = self.rows[t.key]
        local on = t.get()
        b.label:SetText(on and "|cff66e08cOn|r" or "Off")
        UI.SetActive(b, on)
    end
end

ns.RegisterModule({
    key = "tweaks", name = "UI Tweaks", icon = ns.MEDIA .. "Tweaks", group = "uitweaks", order = 1,
    desc = "Small changes to the game's UI, like Release protection in raids.",
    view = V,
})
