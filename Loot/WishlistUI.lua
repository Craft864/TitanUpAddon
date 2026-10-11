-- Titan Up - Loot/WishlistUI.lua
-- The Wishlist tab of the Loot window: pick an expansion, an instance, a
-- boss (or every drop) and a difficulty; narrow it down with the search box,
-- a slot and the stats (Both = items with all the ticked stats, Either =
-- any of them); click BIS / Sidegrade / Want on a row to put it on your
-- wishlist. The right side shows who in the guild wants the picked item.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local WL

local V = {}
ns.WishlistUI = V

local W, H = ns.Nav.STD_W, ns.Nav.STD_H
local RIGHT_W = 250
local ROW_H = 34

function V:Init() WL = ns.Wishlist end

local function dropdown(parent, w, tip, fn)
    local b = UI.Button(parent, w, 24, "", tip, fn)
    UI.Caret(b, "RIGHT", -6, 0)
    return b
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpWishlist", "wishlist", "LOOT WISHLIST", W, H, { mark = { 420, 0.04, -40 },
        cog = { "Loot settings", function() ns.Settings:Open("loot") end },
        onShow = function() WL.sync:CatchUp(); V:Reload() end })
    self.filter = { stats = {}, both = false }
    self.mySpec = true

    -- row 1: where
    self.tierBtn = dropdown(f, 150, "Expansion", function() V:TierMenu() end)
    self.tierBtn:SetPoint("TOPLEFT", 12, -10)
    self.instBtn = dropdown(f, 200, "Raid or dungeon", function() V:InstanceMenu() end)
    self.instBtn:SetPoint("LEFT", self.tierBtn, "RIGHT", 6, 0)
    self.bossBtn = dropdown(f, 180, "One boss, or every drop in the instance", function() V:BossMenu() end)
    self.bossBtn:SetPoint("LEFT", self.instBtn, "RIGHT", 6, 0)
    self.diffBtn = dropdown(f, 110, "Difficulty (item levels follow it)", function() V:DiffMenu() end)
    self.diffBtn:SetPoint("LEFT", self.bossBtn, "RIGHT", 6, 0)
    self.mineBtn = UI.Button(f, 170, 24, "", "Show only what's on your wishlist (from this instance)", function()
        V.filter.onlyMine = not V.filter.onlyMine; V.offset = 0; V:Refresh()
    end)
    self.mineBtn:SetPoint("TOPRIGHT", -12, -10)

    -- row 2: narrow it down
    local search = UI.EditBox(f, 170, 24, { inset = 8 })
    search:SetPoint("TOPLEFT", 12, -40)
    search:SetScript("OnTextChanged", function() V.offset = 0; V:Refresh() end)
    ns.AcceptLinks(search, function(link) local _, name = ns.Crafters.ItemFrom(link); search:SetText(name or "") end)
    self.search = search
    self.searchHint = UI.Text(search, "GameFontHighlightSmall", C.muted, "Search items", "LEFT", 8, 0)
    search:SetScript("OnEditFocusGained", function() V.searchHint:Hide() end)
    search:SetScript("OnEditFocusLost", function() V.searchHint:SetShown((search:GetText() or "") == "") end)
    self.slotBtn = dropdown(f, 120, "Only one slot", function() V:SlotMenu() end)
    self.slotBtn:SetPoint("LEFT", search, "RIGHT", 6, 0)
    self.statBtns = {}
    local x = nil
    for _, s in ipairs(WL.STATS) do
        local key = s.key
        local b = UI.Button(f, 74, 24, s.name, "Only items with " .. s.name, function() V:ToggleStat(key) end)
        if x then b:SetPoint("LEFT", x, "RIGHT", 4, 0) else b:SetPoint("LEFT", self.slotBtn, "RIGHT", 10, 0) end
        x = b
        self.statBtns[key] = b
    end
    self.bothBtn = UI.Button(f, 54, 24, "Both", "Both: only items that have every stat you ticked", function() V:SetBoth(true) end)
    self.bothBtn:SetPoint("LEFT", x, "RIGHT", 10, 0)
    self.eitherBtn = UI.Button(f, 54, 24, "Either", "Either: items with any of the stats you ticked", function() V:SetBoth(false) end)
    self.eitherBtn:SetPoint("LEFT", self.bothBtn, "RIGHT", 2, 0)
    self.specBtn = UI.Button(f, 74, 24, "My spec", "Only items your current specialization can use", function()
        V.mySpec = not V.mySpec; V:Reload()
    end)
    self.specBtn:SetPoint("TOPRIGHT", -12, -40)

    -- the items
    local list = UI.Panel(f)
    list:SetPoint("TOPLEFT", 12, -72)
    list:SetPoint("BOTTOMRIGHT", -(RIGHT_W + 20), 12)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d) V.offset = (V.offset or 0) - d * 3; V:Refresh() end)
    self.status = UI.Text(list, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -8)
    self.status:SetWidth(W - RIGHT_W - 60); self.status:SetJustifyH("LEFT")
    self.rows = {}
    local lw = W - RIGHT_W - 44
    for i = 1, math.floor((H - 112) / ROW_H) do
        local row = UI.Row(list, ROW_H, 0.04, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.6 })
        row:SetPoint("TOPLEFT", 4, -26 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -4, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 3, 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
        row.text:SetWidth(lw - 250)
        row.sub = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
        row.sub:SetWidth(lw - 250); row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false)
        row.tags = {}
        local prev
        for j = #WL.TAGS, 1, -1 do
            local t = WL.TAGS[j]
            local code = t[1]
            local b = UI.Button(row, t[1] == "S" and 72 or 46, 22, t[2], t[3] .. " (click again to take it off your wishlist)", function()
                local item = row.item
                if not item then return end
                WL:Set(item.itemID, WL:Tag(item.itemID) ~= code and code or nil)
                V:Refresh()
            end)
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -3, 0) else b:SetPoint("RIGHT", -4, 0) end
            prev = b
            row.tags[code] = b
        end
        row:SetScript("OnClick", function(s) if s.item then V.sel = s.item.itemID; V:Refresh() end end)
        row:SetScript("OnEnter", function(s)
            if not (s.item and s.item.link) then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, s.item.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.rows[i] = row
    end

    -- who wants it
    local right = UI.Panel(f)
    right:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 12)
    self.whoTitle = UI.Text(right, "GameFontNormal", C.accent, "WHO WANTS IT", "TOPLEFT", 10, -8)
    self.whoItem = UI.Text(right, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 10, -26)
    self.whoItem:SetWidth(RIGHT_W - 20); self.whoItem:SetJustifyH("LEFT"); self.whoItem:SetWordWrap(false)
    self.whoText = UI.Text(right, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 10, -46)
    self.whoText:SetWidth(RIGHT_W - 20); self.whoText:SetJustifyH("LEFT"); self.whoText:SetSpacing(3)
end

-- ---------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------
function V:TierMenu()
    local tiers = WL:Tiers() or {}
    local items = {}
    for i = #tiers, 1, -1 do
        local t = tiers[i]
        items[#items + 1] = { text = t.name, checked = V.tier == t.tier, onClick = function() V:PickTier(t.tier, t.name) end }
    end
    if #items == 0 then items[1] = { text = select(2, WL:CanBrowse()) or "Nothing to show", muted = true } end
    UI.Menu(self.tierBtn, items)
end

function V:PickTier(tier, name)
    self.tier, self.tierName = tier, name
    self.instances = WL:Instances(tier) or {}
    local first = self.instances[1]
    if first then self:PickInstance(first) else self.inst = nil; self:Reload() end
end

function V:InstanceMenu()
    local items = {}
    local raid
    for _, inst in ipairs(self.instances or {}) do
        if inst.raid ~= raid then
            raid = inst.raid
            items[#items + 1] = { text = raid and "RAIDS" or "DUNGEONS", muted = true }
        end
        items[#items + 1] = { text = "  " .. inst.name, checked = V.inst and V.inst.id == inst.id, onClick = function() V:PickInstance(inst) end }
    end
    if #items == 0 then items[1] = { text = "Pick an expansion first", muted = true } end
    UI.Menu(self.instBtn, items)
end

function V:PickInstance(inst)
    self.inst = inst
    self.boss = nil
    self.bosses = WL:Encounters(inst.id) or {}
    self.diffs = WL:Difficulties(inst.id, inst.raid)
    local keep
    for _, d in ipairs(self.diffs) do if d[1] == self.diff then keep = true end end
    if not keep then
        -- default: the highest difficulty for raids (Heroic if there's no Mythic), Mythic+ for dungeons
        local best = self.diffs[#self.diffs]
        self.diff = best and best[1]
    end
    self.offset = 0
    self:Reload()
end

function V:BossMenu()
    local items = { { text = "All drops", checked = V.boss == nil, onClick = function() V.boss = nil; V.offset = 0; V:Reload() end } }
    for _, b in ipairs(self.bosses or {}) do
        items[#items + 1] = { text = b.name, checked = V.boss and V.boss.id == b.id, onClick = function() V.boss = b; V.offset = 0; V:Reload() end }
    end
    UI.Menu(self.bossBtn, items)
end

function V:DiffMenu()
    local items = {}
    for _, d in ipairs(self.diffs or {}) do
        items[#items + 1] = { text = d[2], checked = V.diff == d[1], onClick = function() V.diff = d[1]; V:Reload() end }
    end
    if #items == 0 then items[1] = { text = "Pick an instance first", muted = true } end
    UI.Menu(self.diffBtn, items)
end

function V:SlotMenu()
    local items = { { text = "Any slot", checked = V.filter.slot == nil, onClick = function() V.filter.slot = nil; V.offset = 0; V:Refresh() end } }
    for _, s in ipairs(WL.SLOTS) do
        items[#items + 1] = { text = s[2], checked = V.filter.slot == s[1], onClick = function() V.filter.slot = s[1]; V.offset = 0; V:Refresh() end }
    end
    UI.Menu(self.slotBtn, items)
end

function V:ToggleStat(key)
    local st = self.filter.stats
    if st[key] then st[key] = nil
    else
        -- gear has at most two secondary stats: Both keeps the last two ticked
        if self.filter.both then
            local n = 0
            for _ in pairs(st) do n = n + 1 end
            if n >= 2 then
                for k in pairs(st) do if k ~= self.lastStat then st[k] = nil end end
            end
        end
        st[key] = true
        self.lastStat = key
    end
    self.offset = 0
    self:Refresh()
end

function V:SetBoth(on)
    self.filter.both = on
    if on then
        local keys = {}
        for k in pairs(self.filter.stats) do keys[#keys + 1] = k end
        if #keys > 2 then
            for _, k in ipairs(keys) do if k ~= self.lastStat then self.filter.stats[k] = nil; break end end
            local n = 0
            for _ in pairs(self.filter.stats) do n = n + 1 end
            while n > 2 do
                for k in pairs(self.filter.stats) do if k ~= self.lastStat then self.filter.stats[k] = nil; n = n - 1; break end end
            end
        end
    end
    self.offset = 0
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- Loading and drawing
-- ---------------------------------------------------------------------
-- Re-read the loot for the current picks (the first time: the newest expansion)
function V:Reload()
    if not self.frame then return end
    local ok, why = WL:CanBrowse()
    self.why = not ok and why or nil
    if ok and not self.tier then
        local tiers = WL:Tiers() or {}
        local t = tiers[#tiers]
        if t then
            self.tier, self.tierName = t.tier, t.name
            self.instances = WL:Instances(t.tier) or {}
            if self.instances[1] then
                self.inst = self.instances[1]
                self.bosses = WL:Encounters(self.inst.id) or {}
                self.diffs = WL:Difficulties(self.inst.id, self.inst.raid)
                local best = self.diffs[#self.diffs]
                self.diff = best and best[1]
            end
        end
    end
    self.loot = nil
    if ok and self.inst then
        local loot, err = WL:Loot(self.inst.id, self.boss and self.boss.id, self.diff, self.mySpec)
        self.loot = loot or {}
        if err then self.why = err end
        if loot and loot.missing then self.waitingLoot = true end
    end
    self:Refresh()
end

local function slotName(key)
    for _, s in ipairs(WL.SLOTS) do if s[1] == key then return s[2] end end
    return "Other"
end

local function statsText(stats)
    local out = {}
    for _, s in ipairs(WL.STATS) do if stats[s.key] then out[#out + 1] = s.name end end
    return table.concat(out, " / ")
end

local function bossName(id)
    for _, b in ipairs(V.bosses or {}) do if b.id == id then return b.name end end
    return nil
end

function V:Refresh()
    if not self.frame then return end
    local f = self.filter
    f.search = (self.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    self.searchHint:SetShown(f.search == "" and not self.search:HasFocus())
    self.tierBtn.label:SetText(self.tierName or "Expansion")
    self.instBtn.label:SetText(self.inst and self.inst.name or "Instance")
    self.bossBtn.label:SetText(self.boss and self.boss.name or "All drops")
    local dname
    for _, d in ipairs(self.diffs or {}) do if d[1] == self.diff then dname = d[2] end end
    self.diffBtn.label:SetText(dname or "Difficulty")
    self.slotBtn.label:SetText(f.slot and slotName(f.slot) or "Any slot")
    for key, b in pairs(self.statBtns) do UI.SetActive(b, f.stats[key] == true) end
    UI.SetActive(self.bothBtn, f.both)
    UI.SetActive(self.eitherBtn, not f.both)
    UI.SetActive(self.specBtn, self.mySpec)
    local n = 0
    for _ in pairs(WL:Mine()) do n = n + 1 end
    self.mineBtn.label:SetText(("My wishlist (%d)"):format(n))
    UI.SetActive(self.mineBtn, f.onlyMine == true)

    local shown = {}
    for _, item in ipairs(self.loot or {}) do if WL.Passes(item, f) then shown[#shown + 1] = item end end
    if self.why then
        self.status:SetText("|cffffa340" .. self.why .. "|r")
    elseif not self.inst then
        self.status:SetText("Pick an expansion and an instance.")
    else
        local total = #(self.loot or {})
        self.status:SetText(("%d of %d items%s%s"):format(#shown, total, self.mySpec and "  -  for your spec" or "",
            not WL:Enabled() and "  -  |cffffa340your wishlist isn't shared (Loot settings)|r" or ""))
    end
    self.offset = math.max(0, math.min(math.max(0, #shown - #self.rows), self.offset or 0))
    for i, row in ipairs(self.rows) do
        local item = shown[i + self.offset]
        row.item = item
        row:SetShown(item ~= nil)
        if item then
            row.icon:SetTexture(item.icon or 134400)
            row.text:SetText(item.link or item.name)
            local bits = { slotName(item.slot) }
            local st = statsText(item.stats)
            if st ~= "" then bits[#bits + 1] = st end
            if not self.boss then bits[#bits + 1] = bossName(item.encounterID) end
            local wants = #WL:Wanters(item.itemID)
            if wants > 0 then bits[#bits + 1] = "|cff4fc3f7" .. wants .. " want" .. (wants == 1 and "s" or "") .. " it|r" end
            row.sub:SetText(table.concat(bits, "  -  "))
            local tag = WL:Tag(item.itemID)
            for code, b in pairs(row.tags) do UI.SetActive(b, tag == code) end
            row.hl:SetShown(self.sel == item.itemID)
        end
    end
    self:RefreshWho(shown)
end

function V:RefreshWho(shown)
    local id = self.sel
    if not id then
        self.whoItem:SetText("")
        self.whoText:SetText("|cff8a8f9cClick an item to see who in the guild has it on their wishlist. BIS names are gold.|r")
        return
    end
    local link
    for _, item in ipairs(shown or self.loot or {}) do if item.itemID == id then link = item.link or item.name end end
    self.whoItem:SetText(link or "")
    self.whoText:SetText(V.WantersText(id))
end

-- the "who wants it" lines, shared with the Loot window's drops
function V.WantersText(itemID, groupOnly)
    local list = WL:Wanters(itemID)
    local lines = {}
    for _, w in ipairs(list) do
        if not groupOnly or w.group then
            lines[#lines + 1] = WL.NameText(w.name, w.tag) .. (w.name == ns.me and " |cff8a8f9c(you)|r" or "") .. "  |cff8a8f9c" .. (WL.TAG_NAME[w.tag] or "") .. "|r"
                .. (w.group and "" or "  |cff5a5f6anot in your group|r")
        end
    end
    if #lines == 0 then return "|cff8a8f9cNobody has it on their wishlist yet.|r" end
    return table.concat(lines, "\n")
end

ns.RegisterModule({
    key = "wishlist", name = "Loot Wishlist", icon = ns.MEDIA .. "Loot", group = "tools", order = 2.5,
    desc = "Pick what you want from any raid or dungeon in the Adventure Guide - BIS, Sidegrade or just want - and see who else wants it.",
    rail = "loot", railName = "Loot", tab = "Wishlist",
    view = V,
})
