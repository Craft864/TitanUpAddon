-- Titan Up - Settings.lua
-- Every module's settings, shown in the Titan Up window: a list of pages on
-- the left, the page on the right. The cog in a module's title bar opens
-- its page directly, with a button back to the module (Home's cog opens the
-- Titan Up page). UI Tweaks keep their options in the UI Tweaks module.
-- (The Combat Timer's window is its settings; Keystone Roulette's and Death
-- Roll's choices are per-game, in their windows.)
-- Pages follow the tools' own order.
-- Pages are built the first time they're opened; tall pages scroll.
--
-- S.Pager is the scrolling page area itself, shared with UI Tweaks.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local S = {}
ns.Settings = S

local NAV_W = 200
local W, H = ns.Nav.STD_W, ns.Nav.STD_H     -- the standard module size
local PAGE_W = W - NAV_W - 40
local ROW_H = 30

-- ---------------------------------------------------------------------
-- The pages
--   simple pages: rows of { toggle = label, get, set, tip }
--                          { cycle = label, options = { {v, text}, ... }, get, set }
--                          { button = label, run, tip }
--                          { text = "a line of help" }
--   tweak pages:  { tweak = TW.LIST entry } - its On/Off, then its own page
--                 (shown by UI Tweaks)
-- ---------------------------------------------------------------------
function S:Pages()
    local u = ns.udb
    local pages = {}
    pages[#pages + 1] = { key = "titanup", title = "Titan Up", group = "TITAN UP", rows = {
        { text = "Titan Up " .. ns.VERSION .. " - the guild toolkit." },
        { button = "Check raid versions", tip = "See which Titan Up version everyone in your group runs - the list fills in as they answer", run = function() ns.Updates:Check() end },
        { button = "Reset alert position", tip = "Put the stack of pop-ups (pull alert, death summary, key vote, What's new) back at the top of the screen", run = function() ns.Dock:Reset() end },
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
-- The page area: pages built on first use, a scroll bar when one is tall
-- ---------------------------------------------------------------------
local Pager = {}
Pager.__index = Pager

-- parent: the window; x, y: top-left of the page area; pageW: page width;
-- viewH: visible height
function S.Pager(parent, x, y, pageW, viewH)
    local pg = setmetatable({ pageW = pageW, viewH = viewH, built = {} }, Pager)
    pg.scroll = UI.ScrollArea(parent, pageW, viewH, 40)
    pg.scroll.view:SetPoint("TOPLEFT", x, y)
    pg.view = pg.scroll.view
    return pg
end

-- build one page the first time it's opened
function Pager:Build(p)
    local PW = self.pageW
    local content = CreateFrame("Frame", nil, self.view)
    content:SetWidth(PW)
    content:SetPoint("TOPLEFT", 0, 0)
    content.rows = {}
    content.mod = false
    local y = -4
    local function row(entry)
        local r = CreateFrame("Frame", nil, content)
        r:SetSize(PW - 16, ROW_H - 4)
        r:SetPoint("TOPLEFT", 4, y)
        r.entry = entry
        r.y = -y                                -- (how far down the page: search scrolls to it)
        if entry.notes then
            r:SetHeight(10)
            UI.Text(r, "GameFontNormalSmall", C.accent, "WHAT'S NEW", "TOPLEFT", 4, -6)
            r.label = UI.Text(r, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 4, -26)
            r.label:SetWidth(PW - 30); r.label:SetJustifyH("LEFT"); r.label:SetSpacing(2)
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
        desc:SetWidth(PW - 24); desc:SetJustifyH("LEFT")
        desc:SetText(t.desc)
        y = y - 40
        if not p.noToggle then
            row({ toggle = "Turned on", get = t.get, set = function(on) t.set(on) end })
            y = y - 6
        end
        local mod = t.page and t.page()
        if mod and mod.BuildPage then
            local host = CreateFrame("Frame", nil, content)
            host:SetPoint("TOPLEFT", 0, y)
            content.hostY = -y
            host:SetSize(PW, 10)
            mod:BuildPage(host)
            local h = mod.pageHeight or 400
            host:SetHeight(h)
            content.mod = mod
            y = y - h
        elseif not t.page then
            UI.Text(content, "GameFontHighlightSmall", C.muted, "Nothing else to set - just turn it on or off.", "TOPLEFT", 8, y - 4)
            y = y - 24
        end
    else
        for _, e in ipairs(p.rows or {}) do row(e) end
    end
    content.height = -y + 10
    content:SetHeight(content.height)
    return content
end

-- build page p without showing it (search reads the rows it tags)
function Pager:Prebuild(p)
    if not self.built[p.key] then
        self.built[p.key] = self:Build(p)
        if self.current ~= p.key then self.built[p.key]:Hide() end
    end
    return self.built[p.key]
end

-- show page p (building it if needed), scrolled to the top
function Pager:Show(p)
    if not self.built[p.key] then self.built[p.key] = self:Build(p) end
    self.current = p.key
    for k, c in pairs(self.built) do c:SetShown(k == p.key) end
    local c = self:Content()
    self.scroll:SetContent(c, c.height)
    self:Refresh()
end

function Pager:Content() return self.built[self.current or ""] end
function Pager:MaxScroll() return self.scroll:MaxScroll() end
function Pager:ScrollTo(v) self.scroll:ScrollTo(v) end
function Pager:ScrollBy(d) self.scroll:ScrollBy(d) end

-- redraw the shown page's buttons from the saved settings
function Pager:Refresh()
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
    self:ScrollTo(self.scroll.offset)
end

-- ---------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------
-- key: the page. Opened from a module's cog, Settings shows a button back
-- to that module.
function S:Open(key)
    local from = ns.Nav:ShellKey()
    self:EnsureFrame()
    if from ~= "settings" then self.back = from end
    self.frame:Show()
    ns.Nav:Activate("settings")
    self:Select(key or self.current or "titanup")
end

function S:Toggle()
    local f = self:EnsureFrame()
    if f:IsShown() then f:Hide() else self:Open(self.current or "titanup") end
end

function S:Show() self:Open(self.current or "titanup") end

-- ---------------------------------------------------------------------
-- Window: page list | page (scrolls when tall)
-- ---------------------------------------------------------------------
function S:EnsureFrame()
    if self.frame then return self.frame end
    local f = ns.Nav:Window(self, "TitanUpSettings", "settings", "SETTINGS", W, H, { mark = { 360, 0.04, -20 },
        onShow = function() S:Refresh() end })
    self.pageTitle = UI.Text(f, "GameFontNormal", C.text, nil, "TOPLEFT", NAV_W + 16, -14)
    self.backBtn = UI.Button(f, 150, 22, "", "Back to the module you came from", function()
        local key = S.back
        S.back = nil
        if key then ns.Nav:Switch(key, "settings") else f:Hide() end
    end)
    self.backBtn:SetPoint("TOPRIGHT", -14, -10)
    -- the page list
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    sep:SetPoint("TOPLEFT", NAV_W, -12); sep:SetPoint("BOTTOMLEFT", NAV_W, 12); sep:SetWidth(1)
    self.pages = self:Pages()
    self.navBtns = {}
    local y, group = -12, nil
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
    self.pager = S.Pager(f, NAV_W + 8, -40, PAGE_W, H - 52)
    self.frame = f
    return f
end

function S:Refresh()
    if not self.backBtn then return end
    local m = self.back and (self.back == "home" and { name = "Home" } or ns.Nav.byKey[self.back])
    self.backBtn:SetShown(m ~= nil)
    if m then self.backBtn.label:SetText("< Back to " .. ((m.rail and m.railName) or m.name)) end
    self:RefreshPage()
end

function S:Select(key)
    local p
    for _, q in ipairs(self.pages) do if q.key == key then p = q end end
    if not p then p = self.pages[1] end
    self.current = p.key
    for k, b in pairs(self.navBtns) do UI.SetActive(b, k == p.key) end
    self.pageTitle:SetText(p.title:upper())
    self.pager:Show(p)
end

function S:RefreshPage()
    if self.pager then self.pager:Refresh() end
end

ns.RegisterModule({
    key = "settings", name = "Settings", icon = ns.MEDIA .. "Cog", group = "suite",
    desc = "Every module's options, and what's new.",
    view = S, show = function() S:Show() end,
})
