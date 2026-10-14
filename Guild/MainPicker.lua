-- Titan Up - Guild/MainPicker.lua
-- "Pick your main" (0.41.0, Ryan asked for it forced): a pop-up after login
-- that asks which character is your main, until you answer (once per
-- account). Later closes it until the next login. Never shown in combat,
-- an encounter or an instance (raids, dungeons, M+).
--
-- It lists every character this account has logged into with Titan Up in
-- this guild (they're already linked). If your main isn't there yet (you're
-- on a bank alt, say), "My main isn't listed" lets you pick it from the
-- guild roster; it becomes your main when you next log into it (Alts:Seen).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local MP = {}
ns.MainPicker = MP

local W, ROWS, ROW_H = 380, 8, 22
local RETRY, MAX_TRIES = 30, 120          -- check every 30 s for an hour after login

function MP:Init()
    local tries = 0
    local function try()
        tries = tries + 1
        local AL = ns.Alts
        if not (AL and AL:NeedsMain()) or (self.frame and self.frame:IsShown()) then return end
        if ns.guildName and not ns.Busy() and not IsInInstance() then
            AL:Seen()
            self:Show()
        elseif tries < MAX_TRIES then
            C_Timer.After(RETRY, try)
        end
    end
    C_Timer.After(15, try)
    ns.On("GUILD_ROSTER_UPDATE", function()
        if MP.frame and MP.frame:IsShown() and MP.mode == "roster" then ns.Debounce("mainpicker-roster", 0.5, function() MP:Refresh() end) end
    end)
end

local function build()
    local f = UI.Window("TitanUpMainPicker", W, 120, { point = { "TOP", 0, -160 }, strata = "DIALOG", border = C.accent, drag = true })
    f.title = UI.Text(f, "GameFontNormal", C.accent, "PICK YOUR MAIN", "TOPLEFT", 14, -12)
    f.body = UI.Text(f, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 14, -34)
    f.body:SetWidth(W - 28); f.body:SetJustifyH("LEFT"); f.body:SetSpacing(2)

    f.search = UI.EditBox(f, W - 28, 24, { inset = 8, max = 60 })
    f.search:SetScript("OnTextChanged", function() MP.offset = 0; MP:Refresh() end)
    f.search.hint = UI.Text(f.search, "GameFontHighlightSmall", C.muted, "Type a name...", "LEFT", 8, 0)
    f.search:SetScript("OnEditFocusGained", function(s) s.hint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function(s) s.hint:SetShown(s:GetText() == "") end)

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetSize(W - 28, ROWS * ROW_H)
    f.list:EnableMouseWheel(true)
    f.list:SetScript("OnMouseWheel", function(_, d) MP.offset = math.max(0, (MP.offset or 0) - d); MP:Refresh() end)
    f.rows = {}
    for i = 1, ROWS do
        local r = UI.Row(f.list, ROW_H - 2, 0.1, nil, "GameFontHighlight")
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT")
        r.text:SetPoint("LEFT", 8, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r:SetScript("OnClick", function(s) if s.name then MP:Choose(s.name) end end)
        f.rows[i] = r
    end
    f.empty = UI.Text(f.list, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 8, -4)
    f.empty:SetWidth(W - 44); f.empty:SetJustifyH("LEFT")

    f.other = UI.Button(f, 170, 24, "My main isn't listed", "Pick your main from the guild roster", function()
        MP:SetMode(MP.mode == "roster" and "mine" or "roster")
    end)
    f.other:SetPoint("BOTTOMLEFT", 14, 12)
    f.later = UI.Button(f, 90, 24, "Later", "Ask again next time you log in", function() f:Hide() end)
    f.later:SetPoint("BOTTOMRIGHT", -14, 12)
    return f
end

function MP:Show()
    self.frame = self.frame or build()
    self:SetMode("mine")
    self.frame:Show()
end

function MP:SetMode(mode)
    local f = self.frame
    self.mode, self.offset = mode, 0
    if mode == "roster" then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        f.body:SetText("Find your main in the guild roster and click it. It becomes your main the first time you log into it with Titan Up.")
        f.other.label:SetText("Back to my characters")
        f.search:SetText("")
        f.search.hint:Show()
        f.search:Show()
    else
        f.body:SetText("Titan Up lists each player once in the guild games, under their main. These are the characters you've logged into with Titan Up - which one is your main?")
        f.other.label:SetText("My main isn't listed")
        f.search:ClearFocus()
        f.search:Hide()
    end
    self:Layout()
    self:Refresh()
    if mode == "roster" then f.search:SetFocus() end
end

-- body text, then the search box (roster only), the list and the buttons
function MP:Layout()
    local f = self.frame
    local h = f.body:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = 28 end
    local y = 34 + h + 10
    if self.mode == "roster" then
        f.search:ClearAllPoints()
        f.search:SetPoint("TOPLEFT", 14, -y)
        y = y + 24 + 8
    end
    -- your characters: only as tall as the list; the roster: always full height
    local rows = self.mode == "roster" and ROWS or math.max(1, math.min(ROWS, #self:Names()))
    f.list:ClearAllPoints()
    f.list:SetPoint("TOPLEFT", 14, -y)
    f.list:SetHeight(rows * ROW_H)
    f:SetHeight(y + rows * ROW_H + 8 + 24 + 12)
end

-- the names to list: your characters, or guildmates matching the search
function MP:Names()
    local AL, out = ns.Alts, {}
    if self.mode ~= "roster" then return AL:MyChars() end
    local roster = ns.GuildRoster()
    local typed = (self.frame.search:GetText() or ""):lower()
    for name in pairs(roster.inGuild) do
        if not AL:IsMine(name) and (typed == "" or ns.Short(name):lower():find(typed, 1, true)) then out[#out + 1] = name end
    end
    table.sort(out)
    return out, roster
end

function MP:Refresh()
    local f = self.frame
    if not f then return end
    local names, roster = self:Names()
    local chars = ns.udb.alts.chars
    self.offset = math.max(0, math.min(math.max(0, #names - ROWS), self.offset or 0))
    for i, r in ipairs(f.rows) do
        local name = names[i + self.offset]
        r.name = name
        if name then
            local class = roster and roster.class[name] or (chars[name] and chars[name].class)
            local tag = ""
            if name == ns.me then tag = "  |cff8a8f9c(this character)|r"
            elseif roster and roster.online[name] then tag = "  |cff8a8f9conline|r" end
            r.text:SetText(UI.ClassName(name, class) .. tag)
            r:Show()
        else
            r:Hide()
        end
    end
    if #names > 0 then f.empty:SetText("")
    elseif self.mode == "roster" then
        f.empty:SetText(roster and roster.loaded and "No guildmate by that name." or "Loading the guild roster...")
    else f.empty:SetText("") end
end

function MP:Choose(name)
    local AL = ns.Alts
    self.frame:Hide()
    if self.mode == "roster" then
        AL:PickPending(name)
        ns.Print(("%s will be your main once you log into it with Titan Up."):format(ns.Short(name)))
    else
        AL:PickMain(name)
        ns.Print(("Your main is %s. Change it any time in Settings > Titan Up."):format(ns.Short(name)))
    end
end
