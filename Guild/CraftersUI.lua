-- Titan Up - Guild/CraftersUI.lua
-- The Crafters window: search (type, or shift-click an item into the box)
-- and a profession filter on top; what the guild can make on the left; who
-- can make the picked one on the right (online first, a Whisper button),
-- plus outside crafters guildmates added (and an "Add outside crafter" box).
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local CR

local V = {}
ns.CraftersUI = V

local W, H = ns.Nav.STD_W, ns.Nav.STD_H
local LEFT_W = 380
local ROW_H = 26
local WHO_H = 34


function V:Init() CR = ns.Crafters end

local function profText(base) return CR.ProfName(base) end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpCrafters", "crafters", "CRAFTERS", W, H, { mark = { 420, 0.04, -40 },
        cog = { "Crafters settings", function() ns.Settings:Open("crafters") end },
        onShow = function()
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
            CR.sync:CatchUp()
            V:Refresh()
        end })

    -- top: search, profession filter, add
    local search = UI.EditBox(f, 300, 24, { inset = 8 })
    search:SetPoint("TOPLEFT", 12, -10)
    search:SetScript("OnTextChanged", function() V.offset = 0; V:Refresh() end)
    ns.AcceptLinks(search, function(link)
        local _, name = CR.ItemFrom(link)
        search:SetText(name or "")
    end)
    self.search = search
    self.searchHint = UI.Text(search, "GameFontHighlightSmall", C.muted, "Search, or shift-click an item", "LEFT", 8, 0)
    search:SetScript("OnEditFocusGained", function() V.searchHint:Hide() end)
    search:SetScript("OnEditFocusLost", function() V.searchHint:SetShown((search:GetText() or "") == "") end)
    self.profBtn = UI.Button(f, 170, 24, "All professions", "Show one profession only", function() V:ProfMenu() end)
    self.profBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
    self.addBtn = UI.Button(f, 160, 24, "Add outside crafter", "Someone outside the guild (another guild or server) who crafts something the guild can't. Everyone with Titan Up will see it.", function() V:ShowAdd() end)
    self.addBtn:SetPoint("TOPRIGHT", -12, -10)

    -- left: what the guild can make
    local left = UI.Panel(f)
    left:SetPoint("TOPLEFT", 12, -42)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(LEFT_W)
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", function(_, d) V.offset = (V.offset or 0) - d * 4; V:Refresh() end)
    self.count = UI.Text(left, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -8)
    self.rows = {}
    for i = 1, math.floor((H - 84) / ROW_H) do
        local row = UI.Row(left, ROW_H, 0.05, { C.accentDim[1], C.accentDim[2], C.accentDim[3], 0.6 })
        row:SetPoint("TOPLEFT", 4, -26 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -4, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", -60, 0)
        row.n = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "RIGHT", -6, 0)
        row:SetScript("OnClick", function(s) if s.entry then V.sel = s.entry; V:Refresh() end end)
        self.rows[i] = row
    end
    self.empty = UI.Text(left, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 12, -30)
    self.empty:SetWidth(LEFT_W - 24)
    self.empty:SetJustifyH("LEFT")

    -- right: who can make it
    local right = UI.Panel(f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -12, 12)
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, d) V.whoOffset = (V.whoOffset or 0) - d * 2; V:RefreshWho() end)
    self.right = right
    local rw = W - LEFT_W - 44
    self.whoTitle = UI.Text(right, "GameFontNormal", C.text, nil, "TOPLEFT", 10, -8)
    self.whoTitle:SetWidth(rw - 20); self.whoTitle:SetJustifyH("LEFT"); self.whoTitle:SetWordWrap(false)
    self.whoSub = UI.Text(right, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -26)
    self.whoSub:SetWidth(rw - 20); self.whoSub:SetJustifyH("LEFT")
    self.who = {}
    for i = 1, math.floor((H - 110) / WHO_H) do
        local r = CreateFrame("Frame", nil, right)
        r:SetSize(rw - 12, WHO_H)
        r:SetPoint("TOPLEFT", 6, -48 - (i - 1) * WHO_H)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("TOPLEFT", 4, -7)
        r.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        r.name = UI.Text(r, "GameFontHighlight", C.text, nil, "TOPLEFT", 18, -3)
        r.name:SetWidth(rw - 140); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.sub = UI.Text(r, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 18, -18)
        r.sub:SetWidth(rw - 140); r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
        r.btn = UI.Button(r, 74, 22, "Whisper", nil, function(b)
            local e = b:GetParent().entry
            if not e then return end
            if b.remove then
                if CR:RemoveOutside(e) then V:Refresh() end
            else
                CR.Whisper(e.whisper)
            end
        end)
        r.btn:SetPoint("RIGHT", -4, 0)
        self.who[i] = r
    end
    self.whoEmpty = UI.Text(right, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 10, -50)
    self.whoEmpty:SetWidth(rw - 20); self.whoEmpty:SetJustifyH("LEFT")
end

function V:ProfMenu()
    local cat = CR:Catalog()
    local items = { { text = "All professions", checked = V.prof == nil, onClick = function() V.prof = nil; V.offset = 0; V:Refresh() end } }
    local list = {}
    for base in pairs(cat.profs) do list[#list + 1] = base end
    table.sort(list, function(a, b) return profText(a) < profText(b) end)
    for _, base in ipairs(list) do
        items[#items + 1] = { text = profText(base), checked = V.prof == base, onClick = function() V.prof = base; V.offset = 0; V:Refresh() end }
    end
    UI.Menu(self.profBtn, items)
end

-- ---------------------------------------------------------------------
-- Add an outside crafter: item (shift-click or type), Name-Server, note
-- ---------------------------------------------------------------------
function V:ShowAdd()
    local d = self.addDialog
    if not d then
        d = UI.Window("TitanUpCraftersAdd", 420, 230, { y = 120, strata = "DIALOG", border = C.accent, drag = true })
        UI.Text(d, "GameFontNormal", C.accent, "ADD AN OUTSIDE CRAFTER", "TOPLEFT", 14, -12)
        local help = UI.Text(d, "GameFontHighlightSmall", C.muted, "Someone outside the guild who crafts something nobody here can. Everyone in the guild with Titan Up will see it.", "TOPLEFT", 14, -32)
        help:SetPoint("RIGHT", -14, 0); help:SetJustifyH("LEFT")
        local function field(label, y, max)
            UI.Text(d, "GameFontHighlightSmall", C.text, label, "TOPLEFT", 14, y)
            local e = UI.EditBox(d, 270, 24, { inset = 8, max = max })
            e:SetPoint("TOPLEFT", 136, y + 6)
            return e
        end
        d.item = field("Item (shift-click)", -70, 200)
        ns.AcceptLinks(d.item, function(link) d.item:SetText(link) end)
        d.who = field("Crafter (Name-Server)", -102, 40)
        d.note = field("Note (optional)", -134, 60)
        d.err = UI.Text(d, "GameFontHighlightSmall", C.warn, nil, "BOTTOMLEFT", 14, 44)
        d.err:SetPoint("RIGHT", -14, 0); d.err:SetJustifyH("LEFT")
        d.ok = UI.Button(d, 100, 24, "Add", nil, function()
            local ok, err = CR:AddOutside(d.item:GetText(), d.who:GetText(), d.note:GetText())
            if ok then d:Hide(); V:Refresh() else d.err:SetText(err or "") end
        end)
        d.ok:SetPoint("BOTTOMRIGHT", -14, 12)
        d.cancel = UI.Button(d, 100, 24, "Close", nil, function() d:Hide() end)
        d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
        self.addDialog = d
    end
    d.item:SetText(""); d.who:SetText(""); d.note:SetText(""); d.err:SetText("")
    d:Show()
    d.item:SetFocus()
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------
function V:Refresh()
    if not self.frame then return end
    local text = self.search:GetText() or ""
    self.searchHint:SetShown(text == "" and not self.search:HasFocus())
    self.profBtn.label:SetText(V.prof and profText(V.prof) or "All professions")
    local rows = CR:Search(text, V.prof)
    self.list = rows
    local people = CR:Counts()
    self.count:SetText(("%d %s  -  %d guildmate%s sharing"):format(#rows, #rows == 1 and "result" or "results", people, people == 1 and "" or "s"))
    self.offset = math.max(0, math.min(math.max(0, #rows - #self.rows), self.offset or 0))
    -- keep the selection if it's still listed
    if self.sel then
        local still
        for _, r in ipairs(rows) do
            if (r.kind == self.sel.kind) and ((r.id and r.id == self.sel.id) or (not r.id and r.name == self.sel.name)) then still = r end
        end
        self.sel = still
    end
    for i, row in ipairs(self.rows) do
        local e = rows[i + self.offset]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then
            if e.kind == "recipe" then
                row.icon:SetTexture(CR.RecipeIcon(e.id))
                row.text:SetText(e.name)
                row.n:SetText(#e.crafters + #(e.outside or {}))
            else
                local icon = e.item and e.item ~= 0 and C_Item and C_Item.GetItemIconByID and ns.Safe.Call(C_Item.GetItemIconByID, e.item)
                row.icon:SetTexture(icon or 134400)
                row.text:SetText(e.name .. "  |cff8a8f9coutside the guild|r")
                row.n:SetText(#e.entries)
            end
            row.hl:SetShown(self.sel == e)
        end
    end
    self.empty:SetShown(#rows == 0)
    if #rows == 0 then
        if text ~= "" or V.prof then
            self.empty:SetText("Nobody in the guild has shared that yet. You can add a crafter from outside the guild with \"Add outside crafter\".")
        elseif not CR:Enabled() then
            self.empty:SetText("Recipe sharing is off for you (Crafters settings). Other guildmates' recipes show here as they share them.")
        else
            self.empty:SetText("No crafters known yet. Recipes appear as guildmates running Titan Up open their profession windows - open yours to add your own.")
        end
    end
    self:RefreshWho()
end

local function onlineFirst(a, b)
    if a.online ~= b.online then return a.online end
    if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) > (b.skill or 0) end
    return a.name < b.name
end

function V:RefreshWho()
    local e = self.sel
    for _, r in ipairs(self.who) do r:Hide() end
    if not e then
        self.whoTitle:SetText("")
        self.whoSub:SetText("")
        self.whoEmpty:SetText("Pick something on the left to see who can make it.")
        return
    end
    self.whoEmpty:SetText("")
    local roster = ns.GuildRoster()
    local list = {}
    if e.kind == "recipe" then
        self.whoTitle:SetText(e.name)
        self.whoSub:SetText(profText(e.base))
        for _, c in ipairs(e.crafters) do
            list[#list + 1] = { name = c.name, whisper = c.name, online = roster.online[c.name] == true, skill = c.skill, max = c.max, base = c.base,
                                class = roster.class[c.name] }
        end
    else
        self.whoTitle:SetText(e.name)
        self.whoSub:SetText("Crafters outside the guild, added by guildmates")
    end
    table.sort(list, onlineFirst)
    for _, o in ipairs(e.kind == "recipe" and (e.outside or {}) or e.entries) do
        list[#list + 1] = { name = o.crafter, whisper = o.crafter, outside = o, online = false }
    end
    self.whoOffset = math.max(0, math.min(math.max(0, #list - #self.who), self.whoOffset or 0))
    for i, r in ipairs(self.who) do
        local x = list[i + self.whoOffset]
        r.entry = x and (x.outside or x)
        if x then
            r:Show()
            if x.outside then
                local o = x.outside
                r.dot:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.6)
                r.name:SetText(o.crafter .. "  |cff8a8f9coutside the guild|r")
                r.sub:SetText("added by " .. UI.ClassName(o.by, roster.class[o.by]) .. ((o.note or "") ~= "" and (": \"" .. o.note .. "\"") or ""))
                local canRemove = CR:CanRemove(o)
                r.btn.remove = canRemove
                r.btn.label:SetText(canRemove and "Remove" or "Whisper")
                r.btn.tip = canRemove and (o.by == ns.me and "Take your entry back out" or "Officer: hide this entry for the whole guild") or ("Whisper " .. o.crafter)
                r.entry = canRemove and o or { whisper = o.crafter }
            else
                local col = x.online and C.good or C.muted
                r.dot:SetVertexColor(col[1], col[2], col[3], 1)
                r.name:SetText(UI.ClassName(x.name, x.class or ns.ClassOf(x.name)) .. (x.name == ns.me and " |cff8a8f9c(you)|r" or "") .. (x.online and "" or "  |cff8a8f9coffline|r"))
                r.sub:SetText(("%s  %s"):format(profText(x.base), (x.max or 0) > 0 and (x.skill .. " / " .. x.max) or ""))
                r.btn.remove = nil
                r.btn.label:SetText("Whisper")
                r.btn.tip = "Whisper " .. ns.Short(x.name) .. " (works when they're online)"
            end
            UI.SetDisabled(r.btn, not r.btn.remove and x.name == ns.me)
        end
    end
end

ns.RegisterModule({
    key = "crafters", name = "Crafters", icon = ns.MEDIA .. "Crafters", group = "guild", order = 10,
    desc = "Who in the guild can make what - search any recipe or shift-click an item, then whisper the crafter.",
    view = V,
})
