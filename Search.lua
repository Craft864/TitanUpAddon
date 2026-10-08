-- Titan Up - Search.lua
-- The settings search box in the middle of every Titan Up title bar.
-- Type a few letters and a list of matching settings drops down under the
-- box; pick one (click, or arrows + Enter) and Titan Up opens the window
-- or page it lives on, scrolls to it and flashes it. Esc clears the box.
--
-- Nothing is kept by hand: the index is read from what already describes
-- each setting - the Settings pages' rows (S:Pages), the UI Tweaks list
-- (TW.LIST) and the rows the hand-built pages tag as they build
-- (SR.Tag, used by the tweak pages and the Combat Timer window). It's
-- built the first time someone types, so it costs nothing until then.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local SR = {}
ns.Search = SR

local MAX = 10             -- results shown
local ROW_H = 34
local DROP_W = 320
SR.BOX_W = 200

-- ---------------------------------------------------------------------
-- Tags: a hand-built page marks a setting's row as it builds it.
--   mod: the module that owns the page; label / tip: what search reads;
--   region: what gets flashed; y: the row's top on its page (negative);
--   w: how wide the flash is (default: the region's own size)
-- ---------------------------------------------------------------------
function SR.Tag(mod, label, tip, region, y, w)
    mod.searchTags = mod.searchTags or {}
    mod.searchTags[#mod.searchTags + 1] = { label = label, tip = tip, region = region, y = y or 0, w = w }
end

local function clean(s)
    s = tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------
-- The index: { label, tip, where, go } - go() opens the setting and
-- returns the pager it's on (or nil), the region to flash, its offset
-- from the top of the page (for scrolling) and the flash width.
-- ---------------------------------------------------------------------
function SR:BuildIndex()
    local out = {}
    local function add(label, tip, where, go)
        label = clean(label)
        if label == "" then return end
        tip = clean(tip)
        out[#out + 1] = { label = label, tip = tip, where = where, go = go,
            low = label:lower(), all = (label .. "\n" .. tip .. "\n" .. where):lower() }
    end

    -- Settings pages
    local S = ns.Settings
    if S then
        S:EnsureFrame()
        for _, p in ipairs(S.pages) do
            for i, e in ipairs(p.rows or {}) do
                local label = e.toggle or e.cycle or e.button
                if label then
                    add(label, e.tip, "Settings > " .. p.title, function()
                        S:Open(p.key)
                        local c = S.pager:Content()
                        local r = c and c.rows[i]
                        return S.pager, r, r and r.y
                    end)
                end
            end
        end
    end

    -- UI Tweaks: each tweak (its on/off), then the options on its page
    local TW, V = ns.Tweaks, ns.TweaksUI
    if TW and V then
        V:EnsureFrame()
        for _, t in ipairs(TW.LIST) do
            add(t.name, t.desc, "UI Tweaks", function()
                V:Open(t.key)
                return nil, V.cards[t.key]
            end)
            local mod = t.page and t.page()
            if mod then
                local content = V.pager:Prebuild({ key = "tweak:" .. t.key, tweak = t, noToggle = true })
                for _, tag in ipairs(mod.searchTags or {}) do
                    add(tag.label, tag.tip, "UI Tweaks > " .. t.name, function()
                        V:Open(t.key)
                        return V.pager, tag.region, (content.hostY or 0) - tag.y, tag.w
                    end)
                end
            end
        end
    end

    -- the Combat Timer's window is its settings
    local TV = ns.TimerUI
    if TV then
        TV:EnsureFrame()
        for _, tag in ipairs(TV.searchTags or {}) do
            add(tag.label, tag.tip, "Combat Timer", function()
                ns.Nav:Switch("timer", ns.Nav:ShellKey())
                return nil, tag.region, nil, tag.w
            end)
        end
    end

    self.index = out
    return out
end

-- The best matches for q: every word must be in the name, tooltip or
-- place. Names holding every word come first (those starting with the
-- first word ahead), then names starting with it, then the rest; each
-- group in the order the settings appear.
function SR:Find(q)
    q = clean(q):lower()
    if q == "" then return {} end
    local words = {}
    for w in q:gmatch("%S+") do words[#words + 1] = w end
    local idx = self.index or self:BuildIndex()
    local hits = {}
    for n, e in ipairs(idx) do
        local ok, inLabel = true, true
        for _, w in ipairs(words) do
            if not e.all:find(w, 1, true) then ok = false break end
            if not e.low:find(w, 1, true) then inLabel = false end
        end
        if ok then
            local starts = e.low:sub(1, #words[1]) == words[1]
            local score = (inLabel and (starts and 0 or 1)) or (starts and 2) or 3
            hits[#hits + 1] = { e = e, score = score, n = n }
        end
    end
    table.sort(hits, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.n < b.n end)
    local out = {}
    for i = 1, math.min(MAX, #hits) do out[i] = hits[i].e end
    return out
end

-- ---------------------------------------------------------------------
-- The box (one per title bar) and the list under it (one, shared)
-- ---------------------------------------------------------------------
function SR:Attach(h)
    local box = UI.EditBox(h.bar, SR.BOX_W, 20, { inset = { 22, 20, 0, 0 }, max = 40, keys = false })
    box:SetFontObject("GameFontHighlightSmall")
    box:SetPoint("CENTER", h.bar, "CENTER", 0, 0)
    local glass = box:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(13, 13)
    glass:SetPoint("LEFT", 6, -1)
    glass:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 1)
    box.hint = UI.Text(box, "GameFontHighlightSmall", C.muted, "Search settings", "LEFT", 22, 0)
    box.clear = UI.Button(box, 16, 16, "x", "Clear", function() SR:Clear(box) end)
    box.clear:SetPoint("RIGHT", -2, 0)
    box.clear:Hide()
    local function looks()
        local empty = box:GetText() == ""
        box.hint:SetShown(empty and not box:HasFocus())
        box.clear:SetShown(not empty)
    end
    box.Looks = looks
    box:SetScript("OnTextChanged", function() looks(); SR:Update(box) end)
    box:SetScript("OnEditFocusGained", looks)
    box:SetScript("OnEditFocusLost", looks)
    box:SetScript("OnEscapePressed", function() SR:Clear(box); box:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() if SR.hits and SR.hits[1] then SR:Pick(SR.sel or 1) else box:ClearFocus() end end)
    box:SetScript("OnArrowPressed", function(_, key)
        if key == "DOWN" then SR:Move(1) elseif key == "UP" then SR:Move(-1) end
    end)
    box:SetScript("OnTabPressed", function() SR:Move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1) end)
    -- the window closing (or its title bar hiding) takes the list with it
    local function gone() if SR.box == box then SR:Close() end end
    h.tab:HookScript("OnHide", gone)
    h.frame:HookScript("OnHide", gone)
    h.search = box
    return box
end

function SR:EnsureDrop()
    if self.drop then return self.drop end
    local d = CreateFrame("Frame", "TitanUpSearchResults", UIParent, "BackdropTemplate")
    UI.Skin(d, C.panel, C.accent)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetWidth(DROP_W)
    d:EnableMouse(true)
    d.rows = {}
    for i = 1, MAX do
        local r = UI.Row(d, ROW_H, 0.06, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.9 }, "GameFontHighlight")
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
        r.text:SetPoint("TOPLEFT", 8, -4)
        r.text:SetPoint("RIGHT", -8, 0)
        r.where = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 8, -19)
        r.where:SetPoint("RIGHT", -8, 0)
        r.where:SetJustifyH("LEFT")
        r.where:SetWordWrap(false)
        r:SetScript("OnClick", function() SR:Pick(i) end)
        r:SetScript("OnEnter", function(s)
            SR.sel = i
            SR:Paint()
            local e = SR.hits and SR.hits[i]
            if e and e.tip ~= "" then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:SetText(e.label, 1, 1, 1)
                GameTooltip:AddLine(e.tip, 0.8, 0.82, 0.86, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.rows[i] = r
    end
    d.none = UI.Text(d, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 12, -10)
    d.none:SetWidth(DROP_W - 24)
    d.none:SetJustifyH("LEFT")
    d:Hide()
    self.drop = d
    return d
end

-- the matched part of a name, in the accent colour
local function lit(label, q)
    local w = q:match("%S+")
    if not w then return label end
    local s, e = label:lower():find(w, 1, true)
    if not s then return label end
    return label:sub(1, s - 1) .. "|cff4fc2f7" .. label:sub(s, e) .. "|r" .. label:sub(e + 1)
end

-- the box's text changed: refresh the list under it
function SR:Update(box)
    local q = clean(box:GetText()):lower()
    if q == "" then
        if self.box == box then self:Close() end
        return
    end
    self.box = box
    local ok, hits = pcall(self.Find, self, q)
    hits = ok and hits or {}
    self.hits, self.sel = hits, 1
    local d = self:EnsureDrop()
    for i, r in ipairs(d.rows) do
        local e = hits[i]
        r:SetShown(e ~= nil)
        if e then
            r.text:SetText(lit(e.label, q))
            r.where:SetText(e.where)
        end
    end
    d.none:SetShown(#hits == 0)
    d.none:SetText("No settings match \"" .. box:GetText() .. "\". Try a shorter word.")
    d:SetHeight(#hits > 0 and (#hits * ROW_H + 8) or 34)
    d:ClearAllPoints()
    d:SetPoint("TOP", box, "BOTTOM", 0, -6)
    d:Show()
    self:Paint()
end

function SR:Paint()
    if not self.drop then return end
    for i, r in ipairs(self.drop.rows) do r.hl:SetShown(i == self.sel) end
end

function SR:Move(d)
    local n = self.hits and #self.hits or 0
    if n == 0 then return end
    self.sel = ((self.sel or 1) - 1 + d) % n + 1
    self:Paint()
end

function SR:Close()
    if self.drop then self.drop:Hide() end
    self.box, self.hits, self.sel = nil, nil, nil
end

function SR:Clear(box)
    box:SetText("")
    if box.Looks then box.Looks() end
    if self.box == box then self:Close() end
end

-- open result i: its window / page, scrolled to it, flashed
function SR:Pick(i)
    local e = self.hits and self.hits[i]
    local box = self.box
    if box then box:ClearFocus(); self:Clear(box) end
    self:Close()
    if not e then return end
    local ok, pager, region, offset, w = pcall(e.go)
    if not ok then return end
    if pager and offset then pager:ScrollTo(math.max(0, offset - 60)) end
    if region then self:Flash(region, w) end
    self.last = e                        -- (for tests)
end

-- a short glow around the setting you jumped to
function SR:Flash(region, w)
    local f = self.flash
    if not f then
        f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        UI.Skin(f, { C.accent[1], C.accent[2], C.accent[3], 0.14 }, C.accent)
        f:SetScript("OnUpdate", function(s, elapsed)
            s.t = s.t + (elapsed or 0)
            if s.t >= 1.6 then s:Hide()
            elseif s.t > 0.9 then s:SetAlpha(1 - (s.t - 0.9) / 0.7) end
        end)
        self.flash = f
    end
    local parent = region.GetParent and region:GetParent() or UIParent
    if region.CreateTexture then parent = region end          -- a frame: glow inside it
    f:SetParent(parent)
    f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
    f:ClearAllPoints()
    if w then
        f:SetPoint("TOPLEFT", region, "TOPLEFT", -8, 8)
        f:SetSize(w, 34)
    else
        f:SetPoint("TOPLEFT", region, "TOPLEFT", -3, 3)
        f:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 3, -3)
    end
    f.t, f.region = 0, region
    f:SetAlpha(1)
    f:Show()
end

-- /tu set <words>: Settings, with the search typed in
function SR:OpenWith(text)
    ns.Settings:Open()
    local h = ns.Settings.header
    local box = h and h.search
    if not box then return end
    box:SetFocus()
    box:SetText(text or "")
    if box.Looks then box.Looks() end
    self:Update(box)
end
