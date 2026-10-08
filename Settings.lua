-- Titan Up - Settings.lua
-- Every module's settings in one window: a list of modules on the left,
-- each module's options on its own page. The cog on each module opens its
-- page directly (the hub's cog opens the Titan Up page). UI Tweaks keep all
-- their detailed options here; the UI Tweaks window is just the on/off list.
-- (The Combat Timer keeps its own window - that window is its settings;
-- Keystone Roulette's and Death Roll's choices are per-game, in their windows.)
-- Pages follow the tools' own order.
-- Pages are built the first time they're opened; tall pages scroll.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local S = {}
ns.Settings = S

local NAV_W = 180
local PAGE_W = 460                -- the UI Tweak pages were laid out for this width
local W, H = NAV_W + PAGE_W + 40, 520
local ROW_H = 30

-- ---------------------------------------------------------------------
-- The pages
--   simple pages: rows of { toggle = label, get, set, tip }
--                          { cycle = label, options = { {v, text}, ... }, get, set }
--                          { button = label, run, tip }
--                          { text = "a line of help" }
--   tweak pages:  { tweak = TW.LIST entry } - its On/Off, then its own page
-- ---------------------------------------------------------------------
function S:Pages()
    local u = ns.udb
    local pages = {}
    pages[#pages + 1] = { key = "titanup", title = "Titan Up", group = "TITAN UP", rows = {
        { text = "Titan Up " .. ns.VERSION .. " - the guild toolkit." },
        { button = "Check raid versions", tip = "See which Titan Up version everyone in your group runs - the list fills in as they answer", run = function() ns.Updates:Check() end },
        { notes = true },                       -- what's new, every version, newest first
    } }
    -- the raid tools' pages, keyed by module (shown in the tools' own order)
    local TOOL_PAGES = {
        loot = u.loot and { title = "Loot", rows = {
            { cycle = "Track items of", options = { { 4, "Epic and up" }, { 3, "Rare and up" } },
              get = function() return u.loot.minQuality end, set = function(v) u.loot.minQuality = v end },
            { toggle = "Titan Up loot roll window", tip = "One window for every loot roll instead of Blizzard's pop-ups: tag items BIS / Sidegrade / 2pc / 4pc, add a note, and see what the rest of the raid chose (Titan Up users) before you roll",
              get = function() return u.loot.rollWindow end,
              set = function(on) u.loot.rollWindow = on; if not on and ns.LootRolls then ns.LootRolls.V:Hide() end end },
            { button = "Preview the roll window", tip = "Open it with sample items and raiders - nothing is rolled or sent", run = function() ns.LootRolls:Preview() end },
            { text = "/tu rolls opens it again after you close it (rolls stay listed for 2 hours, the trade window)." },
        } },
        raidcheck = u.raidcheck and { title = "Raid Check", rows = {
            { toggle = "Check before /pull", tip = "When you (leader / assist) type /pull in a Heroic or Mythic raid, check everyone first",
              get = function() return u.raidcheck.pullCheck end, set = function(on) u.raidcheck.pullCheck = on end },
        } },
        pullreport = u.pullReport and { title = "Pull Report", rows = {
            { cycle = "Opens after a raid pull", options = { { "leader", "When I'm raid leader" }, { "always", "After every pull" }, { "never", "Never" } },
              get = function() return u.pullReport.popup end, set = function(v) u.pullReport.popup = v end },
            { toggle = "My death summary", tip = "A small box when you die in a raid: what hit you, your health, what you had ready",
              get = function() return u.pullReport.personal end, set = function(on) u.pullReport.personal = on end },
        } },
    }
    local order = (ns.Nav and ns.Nav.Ordered) and ns.Nav:Ordered() or {}
    local added = {}
    for _, m in ipairs(order) do
        local pg = TOOL_PAGES[m.key]
        if pg and m.group == "tools" then
            pages[#pages + 1] = { key = m.key, title = pg.title, group = "RAID TOOLS", rows = pg.rows }
            added[m.key] = true
        end
    end
    for key, pg in pairs(TOOL_PAGES) do                       -- (anything not in the nav yet)
        if pg and not added[key] then pages[#pages + 1] = { key = key, title = pg.title, group = "RAID TOOLS", rows = pg.rows } end
    end
    -- UI tweaks: one page each, in the UI Tweaks window's order
    for _, t in ipairs(ns.Tweaks and ns.Tweaks.LIST or {}) do
        pages[#pages + 1] = { key = "tweak:" .. t.key, title = t.name, group = "UI TWEAKS", tweak = t }
    end
    return pages
end

-- Something changed a setting: redraw every open window that shows one,
-- so a change in one place shows everywhere at once.
function ns.SettingsChanged()
    if S.frame and S.frame:IsShown() then S:RefreshPage() end
    for _, name in ipairs({ "TweaksUI", "LootUI", "RaidCheckUI", "PullReportUI", "DeathRollUI" }) do
        local v = ns[name]
        if v and v.frame and v.frame:IsShown() and v.Refresh then pcall(v.Refresh, v) end
    end
    local dr = ns.DeathRollUI
    if dr and dr.announceCheck then dr.announceCheck:Refresh() end
end

-- ---------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------
-- anchor: the Titan Up window it was opened from. Settings docks to its
-- left (top edges lined up), or its right if there's no room on the left;
-- with no window it opens centred. It docks again each time it opens, and
-- can be dragged anywhere while open.
function S:Open(key, anchor)
    self:EnsureFrame()
    self:Dock(anchor)
    self.frame:Show()
    self:Select(key or self.current or "titanup")
end

function S:Dock(anchor)
    local f = self.frame
    if not (anchor and anchor.IsShown and anchor:IsShown()) then
        local hub = ns.Hub and ns.Hub.frame
        anchor = (hub and hub:IsShown()) and hub or nil
    end
    f:ClearAllPoints()
    if not anchor then f:SetPoint("CENTER", 0, 40) return end
    local left = anchor.GetLeft and anchor:GetLeft()
    if type(left) == "number" and left < W + 12 then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)        -- no room on the left
    else
        f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    end
end

function S:Toggle(anchor)
    local f = self:EnsureFrame()
    if f:IsShown() then f:Hide() else self:Open(self.current or "titanup", anchor) end
end

function S:Show() self:Open(self.current or "titanup") end

-- ---------------------------------------------------------------------
-- Window: module list | page (scrolls when tall)
-- ---------------------------------------------------------------------
function S:EnsureFrame()
    if self.frame then return self.frame end
    local f = UI.Window("TitanUpSettings", W, H, { border = C.accent, drag = true })     -- placed by Dock
    UI.Text(f, "GameFontNormal", C.accent, "TITAN UP SETTINGS", "TOPLEFT", 16, -14)
    local x = UI.Button(f, 22, 20, "X", "Close", function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -8, -8)
    self.pageTitle = UI.Text(f, "GameFontNormal", C.text, nil, "TOPLEFT", NAV_W + 16, -14)
    -- the module list
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", NAV_W, -40); sep:SetPoint("BOTTOMLEFT", NAV_W, 12); sep:SetWidth(1)
    self.pages = self:Pages()
    self.navBtns = {}
    local y, group = -44, nil
    for _, p in ipairs(self.pages) do
        if p.group ~= group then
            group = p.group
            UI.Text(f, "GameFontNormalSmall", C.muted, group, "TOPLEFT", 16, y - 6)
            y = y - 22
        end
        local b = UI.Button(f, NAV_W - 24, 22, p.title, nil, function() S:Select(p.key) end)
        b:SetPoint("TOPLEFT", 12, y)
        self.navBtns[p.key] = b
        y = y - 25
    end
    -- the page area (clips its content) + scroll bar
    local view = CreateFrame("Frame", nil, f)
    view:SetPoint("TOPLEFT", NAV_W + 8, -40)
    view:SetSize(PAGE_W, H - 52)
    if view.SetClipsChildren then view:SetClipsChildren(true) end
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * 40) end)
    self.view = view
    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("TOPLEFT", view, "TOPRIGHT", 8, 0)
    track:SetSize(8, H - 52)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.06)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function()
        local _, cy = GetCursorPosition()
        S.dragFrom, S.dragOffset = cy / (UIParent:GetEffectiveScale() or 1), S.offset or 0
        thumb:SetScript("OnUpdate", function()
            local _, ny = GetCursorPosition()
            ny = ny / (UIParent:GetEffectiveScale() or 1)
            local span = (track:GetHeight() or 1) - (thumb:GetHeight() or 1)
            if span > 0 then S:ScrollTo(S.dragOffset + (S.dragFrom - ny) / span * S:MaxScroll()) end
        end)
    end)
    thumb:SetScript("OnDragStop", function() thumb:SetScript("OnUpdate", nil) end)
    self.track, self.thumb = track, thumb
    self.built = {}
    self.frame = f
    return f
end

-- build one page the first time it's opened
function S:Build(p)
    local content = CreateFrame("Frame", nil, self.view)
    content:SetWidth(PAGE_W)
    content:SetPoint("TOPLEFT", 0, 0)
    content.rows = {}
    content.mod = false
    local y = -4
    local function row(entry)
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(PAGE_W - 16, ROW_H - 4)
        r:SetPoint("TOPLEFT", 4, y)
        r.entry = entry
        if entry.notes then
            r:SetHeight(10)
            UI.Text(r, "GameFontNormalSmall", C.accent, "WHAT'S NEW", "TOPLEFT", 4, -6)
            r.label = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 4, -26)
            r.label:SetWidth(PAGE_W - 30); r.label:SetJustifyH("LEFT"); r.label:SetSpacing(2)
            r.label:SetText(ns.Updates.NotesText())
            local h = r.label:GetStringHeight()
            if type(h) ~= "number" or h <= 0 then
                h = 0
                for _ in (r.label:GetText() .. "\n"):gmatch("[^\n]*\n") do h = h + 14 end
            end
            r:SetHeight(h + 30)
            content.rows[#content.rows + 1] = r
            y = y - (h + 40)
            return r
        elseif entry.text then
            r.label = UI.Text(r, "GameFontHighlightSmall", C.muted, entry.text, "LEFT", 4, 0)
        elseif entry.button then
            r.btn = UI.Button(r, 240, 24, entry.button, entry.tip, function() entry.run(); ns.SettingsChanged() end)
            r.btn:SetPoint("LEFT", 4, 0)
        else
            r.label = UI.Text(r, "GameFontHighlight", C.text, entry.toggle or entry.cycle, "LEFT", 4, 0)
            r.btn = UI.Button(r, 190, 24, "", entry.tip, function()
                if entry.toggle then entry.set(not entry.get())
                else
                    local cur, i = entry.get(), 1
                    for k, o in ipairs(entry.options) do if o[1] == cur then i = k end end
                    entry.set(entry.options[(i % #entry.options) + 1][1])
                end
                ns.SettingsChanged()
            end)
            r.btn:SetPoint("RIGHT", -4, 0)
        end
        content.rows[#content.rows + 1] = r
        y = y - ROW_H
        return r
    end
    if p.tweak then
        local t = p.tweak
        local desc = UI.Text(content, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 8, y - 2)
        desc:SetWidth(PAGE_W - 24); desc:SetJustifyH("LEFT")
        desc:SetText(t.desc)
        y = y - 40
        row({ toggle = "Turned on", get = t.get, set = function(on) t.set(on) end })
        y = y - 6
        local mod = t.page and t.page()
        if mod and mod.BuildPage then
            local host = CreateFrame("Frame", nil, content)
            host:SetPoint("TOPLEFT", 0, y)
            host:SetSize(PAGE_W, 10)
            mod:BuildPage(host)
            local h = mod.pageHeight or 400
            host:SetHeight(h)
            content.mod = mod
            y = y - h
        end
    else
        for _, e in ipairs(p.rows or {}) do row(e) end
    end
    content.height = -y + 10
    content:SetHeight(content.height)
    return content
end

function S:Select(key)
    local p
    for _, q in ipairs(self.pages) do if q.key == key then p = q end end
    if not p then p = self.pages[1] end
    self.current = p.key
    if not self.built[p.key] then self.built[p.key] = self:Build(p) end
    for k, c in pairs(self.built) do c:SetShown(k == p.key) end
    for k, b in pairs(self.navBtns) do UI.SetActive(b, k == p.key) end
    self.pageTitle:SetText(p.title:upper())
    self.offset = 0
    self:RefreshPage()
end

function S:Content() return self.built and self.built[self.current or ""] end

function S:MaxScroll()
    local c = self:Content()
    local viewH = H - 52
    return math.max(0, ((c and c.height) or 0) - viewH)
end

function S:ScrollTo(v)
    self.offset = math.max(0, math.min(self:MaxScroll(), v or 0))
    local c = self:Content()
    if c then c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, self.offset) end
    self:LayoutScrollbar()
end

function S:ScrollBy(d) self:ScrollTo((self.offset or 0) + d) end

-- a visible scroll bar whenever the page is taller than the window
function S:LayoutScrollbar()
    local max = self:MaxScroll()
    local show = max > 0
    self.track:SetShown(show)
    if not show then return end
    local c = self:Content()
    local viewH = H - 52
    local thumbH = math.max(30, viewH * viewH / c.height)
    self.thumb:SetHeight(thumbH)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.track, "TOP", 0, -((viewH - thumbH) * (self.offset or 0) / max))
end

function S:RefreshPage()
    local c = self:Content()
    if not c then return end
    for _, r in ipairs(c.rows) do
        local e = r.entry
        if e.toggle then
            local on = e.get() and true or false
            r.btn.label:SetText(on and "|cff66e08cOn|r" or "Off")
            UI.SetActive(r.btn, on)
        elseif e.cycle then
            local cur, txt = e.get(), nil
            for _, o in ipairs(e.options) do if o[1] == cur then txt = o[2] end end
            r.btn.label:SetText(txt or tostring(cur or ""))
        end
    end
    local mod = c.mod
    if type(mod) == "table" and mod.RefreshPage then mod:RefreshPage() end
    self:ScrollTo(self.offset or 0)
end
