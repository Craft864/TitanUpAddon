-- Titan Up - Chess/ChessToast.lua
-- The "your move" pop-up (0.45.0, off until you turn it on in Settings >
-- Chess): a small box when it becomes your move in a chess game, or a
-- guildmate challenges you, while the Chess window is closed. Click it to
-- open that game; it fades after a few seconds. Never in combat, encounter
-- lockdown or an instance. It has its own anchor (separate from Death
-- alerts) and an optional sound, picked like the Death alerts sounds.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local CH = ns.Chess

local CT = {}
ns.ChessToast = CT

CT.SHOW = 8                     -- seconds on screen
CT.FADE = 0.6                   -- seconds to fade out

local function db() return ns.udb.chess.toast end
function CT:Enabled() return db().on and true or false end

-- ---------------------------------------------------------------------
-- The pop-up
-- ---------------------------------------------------------------------
function CT:Ensure()
    if self.frame then return self.frame end
    local f = CreateFrame("Button", "TitanUpChessToast", UIParent, "BackdropTemplate")
    f:SetSize(250, 50)
    f:SetFrameStrata("HIGH")
    UI.Skin(f, C.panel, C.accent)
    UI.Draggable(f, db, { "TOP", "TOP", 0, -140 }, "Drag to move - click the anchor again to lock", nil, function() return CT.unlocked end)
    f:RegisterForClicks("LeftButtonUp")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(ns.MEDIA .. "Chess")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("LEFT", 10, 0)
    f.title = UI.Text(f, "GameFontNormal", C.accent, "YOUR MOVE", "TOPLEFT", 50, -9)
    f.text = UI.Text(f, "GameFontHighlight", C.text, nil, "TOPLEFT", 50, -27)
    f.text:SetPoint("RIGHT", -10, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f:SetScript("OnClick", function() CT:OnClick() end)
    f:SetScript("OnUpdate", function() CT:Animate() end)
    f:Hide()
    f:Place()
    self.frame = f
    return f
end

function CT:ResetPosition() self:Ensure():ResetPlace() end

-- (shared with the tests) can a pop-up show right now?
function CT:CanShow()
    if not self:Enabled() then return false end
    if ns.ChessUI and ns.ChessUI:IsShown() then return false end
    if ns.Busy() then return false end
    if IsInInstance and IsInInstance() then return false end
    return true
end

-- It became your move in g (or g is a challenge to you).
function CT:YourTurn(g, challenged)
    if not g or not self:CanShow() then return false end
    local opp = ns.Short(CH:Opponent(g))
    self:Show(challenged and "CHALLENGE" or "YOUR MOVE",
        challenged and (opp .. " challenged you to chess") or ("vs " .. opp), g.id)
    if db().sound and db().sound ~= "None" and ns.DeathAlerts then ns.DeathAlerts.Play(db().sound) end
    return true
end

function CT:Show(title, text, id)
    local f = self:Ensure()
    f.title:SetText(title)
    f.text:SetText(text)
    self.id = id
    self.hideAt = GetTime() + self.SHOW
    f:SetAlpha(1)
    f:Show()
end

function CT:Animate()
    local f = self.frame
    if self.unlocked or not self.hideAt then return end
    local left = self.hideAt - GetTime()
    if left <= 0 then
        self.hideAt = nil
        f:Hide()
    elseif left < self.FADE then
        f:SetAlpha(left / self.FADE)
    end
end

function CT:OnClick()
    if self.unlocked then return end
    local id = self.id
    self.hideAt = nil
    self.frame:Hide()
    if id and ns.ChessUI then ns.ChessUI:Open(id) end
end

-- the anchor button: show a sample to drag around
function CT:SetUnlocked(on)
    self.unlocked = on and true or false
    local f = self:Ensure()
    f.hint:SetShown(self.unlocked)
    if self.unlocked then
        f.title:SetText("YOUR MOVE")
        f.text:SetText("vs Kev")
        self.hideAt = nil
        f:SetAlpha(1)
        f:Show()
    else
        f:Hide()
    end
end

function CT:Test()
    self:Show("YOUR MOVE", "vs Kev", nil)
    if db().sound and db().sound ~= "None" and ns.DeathAlerts then ns.DeathAlerts.Play(db().sound) end
end

-- ---------------------------------------------------------------------
-- Settings > Chess
-- ---------------------------------------------------------------------
function CT:BuildPage(parent)
    local pg = CreateFrame("Frame", nil, parent)
    pg:SetAllPoints()
    self.page = pg
    local RIGHT = -18
    local y = -8
    local function label(text, yy) return UI.Text(pg, "GameFontHighlight", C.text, text, "TOPLEFT", 18, yy - 5) end
    local function tag(text, tip, t) ns.Search.Tag(CT, text, tip, t, y, 440) end

    local onTip = "A small pop-up when it becomes your move in a chess game, or a guildmate challenges you, while the Chess window is closed. Click it to open the game. Never in combat or inside an instance."
    tag("Your-move pop-up", onTip, label("Your-move pop-up", y))
    self.onBtn = UI.Button(pg, 170, 24, "", onTip, function() db().on = not db().on; CT:RefreshPage() end)
    self.onBtn:SetPoint("TOPRIGHT", RIGHT, y)
    y = y - 32

    local soundTip = "Play a sound with the pop-up (None = silent)"
    tag("Pop-up sound", soundTip, label("Pop-up sound", y))
    local play = UI.Button(pg, 24, 24, ">", "Preview", function() if ns.DeathAlerts then ns.DeathAlerts.Play(db().sound) end end)
    play:SetPoint("TOPRIGHT", RIGHT, y)
    local b = UI.Button(pg, 170, 24, "", soundTip, nil)
    b:SetPoint("RIGHT", play, "LEFT", -4, 0)
    b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 8, 0); b.label:SetPoint("RIGHT", -20, 0); b.label:SetJustifyH("LEFT")
    UI.Caret(b, "RIGHT", -6, 0)
    b:SetScript("OnClick", function()
        ns.DeathAlerts:PickSound(b, db().sound, function(name) db().sound = name; CT:RefreshPage() end)
    end)
    self.soundBtn = b
    y = y - 38

    local test = UI.Button(pg, 90, 24, "Test", "Show the pop-up (and play its sound)", function() CT:Test() end)
    test:SetPoint("TOPLEFT", 18, y)
    local reset
    self.anchorBtn, reset = ns.Tweaks.MoveControls(pg, CT, { after = function() CT:RefreshPage() end,
        tip = "Move the pop-up: click to unlock and drag, click again to lock. Separate from the Death alerts anchor." })
    self.anchorBtn:SetPoint("LEFT", test, "RIGHT", 8, 0)
    reset:SetPoint("LEFT", self.anchorBtn, "RIGHT", 8, 0)
    y = y - 40
    local note = UI.Text(pg, "GameFontHighlightSmall", C.muted,
        "Watch other guild games from the Watch tab in the Chess window.", "TOPLEFT", 18, y)
    note:SetWidth(420); note:SetJustifyH("LEFT")
    self.pageHeight = -y + 30
    return pg
end

function CT:RefreshPage()
    if not self.page then return end
    local on = self:Enabled()
    self.onBtn.label:SetText(on and "|cff66e08cOn|r" or "Off")
    UI.SetActive(self.onBtn, on)
    self.soundBtn.label:SetText(db().sound or "None")
    UI.SetActive(self.anchorBtn, self.unlocked)
end
