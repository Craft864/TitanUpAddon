-- Titan Up - Consumables/ConsumablesUI.lua
-- The Consumables window (Tools): a summary on top ("Stocked for raid" /
-- "Short on 3"), My list / All items, Copy from another character, an Add
-- box (shift-click, drag or type an item); then one line per item and rank:
-- Have (bags only), Want (type a number), Short.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local CO

local V = {}
ns.ConsumablesUI = V

local W, H = ns.Nav.STD_W, ns.Nav.STD_H
local ROW_H = 26
local LIST_TOP = -76
local COL_HAVE, COL_WANT, COL_SHORT = -190, -112, -40       -- column centres from the right edge

function V:Init() CO = ns.Consumables end

local function hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

function V:Open()
    self:Show()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function V:Create()
    local f = ns.Nav:Window(self, "TitanUpConsumables", "consumables", "CONSUMABLES", W, H, { mark = { 420, 0.04, -40 },
        cog = { "Consumables settings", function() ns.Settings:Open("consumables") end },
        onShow = function() CO:Learn(); V:Refresh() end })

    -- top line: summary, My list / All items, Copy from
    self.summary = UI.Text(f, "GameFontNormalLarge", C.text, nil, "TOPLEFT", 14, -14)
    self.summary:SetWidth(380); self.summary:SetJustifyH("LEFT"); self.summary:SetWordWrap(false)
    self.copyBtn = UI.Button(f, 130, 24, "Copy from...", "Copy the list from another of your characters onto this one", function() V:CopyMenu() end)
    self.copyBtn:SetPoint("TOPRIGHT", -12, -10)
    self.allBtn = UI.Button(f, 90, 24, "All items", "Every consumable Titan Up knows, so you can set a Want on the ones you bring", function() V.all = true; V.offset = 0; V:Refresh() end)
    self.allBtn:SetPoint("RIGHT", self.copyBtn, "LEFT", -16, 0)
    self.listBtn = UI.Button(f, 90, 24, "My list", "Only what you've set a Want on", function() V.all = false; V.offset = 0; V:Refresh() end)
    self.listBtn:SetPoint("RIGHT", self.allBtn, "LEFT", -4, 0)

    -- second line: add your own
    local add = UI.EditBox(f, 330, 24, { inset = 8, max = 200 })
    add:SetPoint("TOPLEFT", 12, -42)
    add:SetScript("OnTextChanged", function() V.addErr:SetText("") end)
    add:SetScript("OnEnterPressed", function() V:AddTyped() end)
    add:SetScript("OnReceiveDrag", function() V:TakeCursor() end)
    add:HookScript("OnMouseDown", function() V:TakeCursor() end)
    ns.AcceptLinks(add, function(link) add:SetText(link); V:AddTyped() end)
    self.add = add
    self.addHint = UI.Text(add, "GameFontHighlightSmall", C.muted, "Add an item: shift-click, drag, or type its name", "LEFT", 8, 0)
    add:SetScript("OnEditFocusGained", function() V.addHint:Hide() end)
    add:SetScript("OnEditFocusLost", function() V.addHint:SetShown((add:GetText() or "") == "") end)
    self.groupBtn = UI.Button(f, 130, 24, CO.GROUP_NAME.mine, "Which group a new item goes in", function() V:GroupMenu() end)
    self.groupBtn:SetPoint("LEFT", add, "RIGHT", 6, 0)
    self.addBtn = UI.Button(f, 60, 24, "Add", nil, function() V:AddTyped() end)
    self.addBtn:SetPoint("LEFT", self.groupBtn, "RIGHT", 6, 0)
    self.addErr = UI.Text(f, "GameFontHighlightSmall", C.warn, nil, "LEFT", self.addBtn, "RIGHT", 10, 0)
    self.addErr:SetPoint("RIGHT", f, "RIGHT", -12, 0); self.addErr:SetJustifyH("LEFT"); self.addErr:SetWordWrap(false)

    -- the list
    local panel = UI.Panel(f)
    panel:SetPoint("TOPLEFT", 12, LIST_TOP)
    panel:SetPoint("BOTTOMRIGHT", -12, 12)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, d) V.offset = (V.offset or 0) - d * 3; V:Refresh() end)
    panel:SetScript("OnReceiveDrag", function() V:TakeCursor() end)
    self.panel = panel
    local head = CreateFrame("Frame", nil, panel)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", 4, -4)
    head:SetPoint("RIGHT", -4, 0)
    local function col(text, x)
        local t = UI.Text(head, "GameFontHighlightSmall", C.muted, text, "CENTER", head, "RIGHT", x, 0)
        return t
    end
    UI.Text(head, "GameFontHighlightSmall", C.muted, "ITEM", "LEFT", 6, 0)
    col("HAVE", COL_HAVE); col("WANT", COL_WANT); col("SHORT", COL_SHORT)
    self.rows = {}
    for i = 1, math.floor((H + LIST_TOP - 40) / ROW_H) do
        local row = UI.Row(panel, ROW_H, 0.04)
        row:SetPoint("TOPLEFT", 4, -26 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -4, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", COL_HAVE - 40, 0)
        row.have = UI.Text(row, "GameFontHighlight", C.text, nil, "CENTER", row, "RIGHT", COL_HAVE, 0)
        row.note = UI.Text(row, "GameFontHighlightSmall", C.muted, nil, "RIGHT", row, "RIGHT", -12, 0)
        local want = UI.EditBox(row, 46, 20, { center = true, numeric = true, max = 3, keys = false })
        want:SetPoint("CENTER", row, "RIGHT", COL_WANT, 0)
        want:SetScript("OnEscapePressed", function(e) e.cancel = true; e:ClearFocus() end)
        want:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
        want:SetScript("OnEditFocusLost", function(e)
            if e.cancel then e.cancel = nil; V:Refresh() return end
            local en = e:GetParent().entry
            if en and en.id then CO:SetWant(en.id, e:GetText()); V:Refresh() end
        end)
        row.want = want
        row.short = UI.Text(row, "GameFontHighlight", C.text, nil, "CENTER", row, "RIGHT", COL_SHORT, 0)
        row.remove = UI.Button(row, 20, 18, "x", "Take this item off your list", function(b)
            local en = b:GetParent().entry
            if en and en.mine and CO:Remove(en.id) then V:Refresh() end
        end)
        row.remove:SetPoint("RIGHT", row, "RIGHT", COL_HAVE - 22, 0)
        row:SetScript("OnEnter", function(s)
            if s.entry and s.entry.id and GameTooltip then
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, s.entry.id) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:SetScript("OnReceiveDrag", function() V:TakeCursor() end)
        self.rows[i] = row
    end
    self.empty = UI.Text(panel, "GameFontHighlightSmall", C.muted, nil, "TOPLEFT", 12, -34)
    self.empty:SetWidth(W - 60); self.empty:SetJustifyH("LEFT")
end

-- ---------------------------------------------------------------------
-- Adding
-- ---------------------------------------------------------------------
function V:AddTyped()
    local ok, res = CO:Add(self.add:GetText(), self.group)
    if ok then
        self.add:SetText("")
        self.add:ClearFocus()
        self.addErr:SetText("")
        self.all = true                                 -- show it (its Want is still 0)
        self:Refresh()
        self:ScrollToItem(res)
    else
        self.addErr:SetText(res or "")
    end
end

-- an item dragged from your bags
function V:TakeCursor()
    if not GetCursorInfo then return false end
    local kind, id = GetCursorInfo()
    id = ns.Safe.Num(id)
    if kind ~= "item" or not id then return false end
    ClearCursor()
    self.add:SetText(tostring(id))
    self:AddTyped()
    return true
end

function V:ScrollToItem(id)
    for i, r in ipairs(self.list or {}) do
        if r.id == id then
            self.offset = math.max(0, i - 3)
            self:Refresh()
            return
        end
    end
end

function V:GroupMenu()
    local items = {}
    for _, g in ipairs(CO.GROUPS) do
        items[#items + 1] = { text = g.name, checked = (self.group or "mine") == g.key,
                              onClick = function() V.group = g.key; V.groupBtn.label:SetText(g.name) end }
    end
    UI.Menu(self.groupBtn, items)
end

function V:CopyMenu()
    local others = CO:OtherChars()
    local items = {}
    if #others == 0 then
        items[1] = { text = "No other character has a list yet", muted = true }
    end
    for _, name in ipairs(others) do
        items[#items + 1] = { text = UI.Named(name), onClick = function()
            UI.Prompt({ title = "Copy consumables list", noInput = true, accept = "Copy",
                help = ("Replace this character's list with %s's (what you want and the items you added)?"):format(ns.Short(name)),
                onAccept = function() CO:CopyFrom(name); V.all = false; V.offset = 0; V:Refresh() end })
        end }
    end
    UI.Menu(self.copyBtn, items)
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------
function V:Refresh()
    if not self.frame then return end
    self.dirty = nil
    local tracked = CO:Tracked()
    if self.all == nil then self.all = tracked == 0 end
    UI.SetActive(self.listBtn, not self.all)
    UI.SetActive(self.allBtn, self.all)
    UI.SetDisabled(self.copyBtn, #CO:OtherChars() == 0)
    self.groupBtn.label:SetText(CO.GROUP_NAME[self.group or "mine"])
    self.addHint:SetShown((self.add:GetText() or "") == "" and not self.add:HasFocus())

    local short = CO:Short()
    if tracked == 0 then
        self.summary:SetText(hex(C.muted) .. "Nothing on your list yet|r")
    elseif #short == 0 then
        self.summary:SetText(hex(C.good) .. "Stocked for raid|r")
    else
        self.summary:SetText(hex(C.bad) .. ("Short on %d %s|r"):format(#short, #short == 1 and "thing" or "things"))
    end

    local rows = CO:Rows(self.all)
    self.list = rows
    self.offset = math.max(0, math.min(math.max(0, #rows - #self.rows), self.offset or 0))
    for i, row in ipairs(self.rows) do
        local e = rows[i + self.offset]
        row.entry = e
        row:SetShown(e ~= nil)
        if e then self:DrawRow(row, e) end
    end
    self.empty:SetShown(#rows == 0)
    if #rows == 0 then
        self.empty:SetText("Nothing on your list yet. Press \"All items\" and type how many of each consumable you want to carry - or add your own above.")
    end
end

function V:DrawRow(row, e)
    if e.header then
        row.icon:Hide()
        row.text:SetPoint("LEFT", row.icon, "LEFT", 0, 0)
        row.text:SetText(hex(C.accent) .. e.name:upper() .. "|r")
        row.have:SetText(""); row.short:SetText(""); row.note:SetText("")
        row.want:Hide(); row.remove:Hide()
        row:EnableMouse(false)
        return
    end
    row:EnableMouse(true)
    row.icon:Show()
    row.icon:SetTexture(e.icon)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    local rank = e.rank and ("  " .. hex(C.muted) .. "Rank " .. e.rank .. "|r") or ""
    local mine = e.mine and e.group ~= "mine" and ("  " .. hex(C.muted) .. "(added)|r") or ""
    row.text:SetText(e.name .. rank .. mine)
    row.remove:SetShown(e.mine == true)
    if e.pending then
        row.have:SetText(""); row.short:SetText("")
        row.want:Hide()
        row.note:SetText("Have one in your bags once to track it")
        return
    end
    row.note:SetText("")
    row.want:Show()
    if not row.want:HasFocus() then row.want:SetText(e.want > 0 and tostring(e.want) or "") end
    local dim = e.want == 0
    row.have:SetText((dim and hex(C.muted) or "") .. e.have .. (dim and "|r" or ""))
    if e.want == 0 then
        row.short:SetText("")
    elseif e.short > 0 then
        row.short:SetText(hex(C.bad) .. e.short .. "|r")
    else
        row.short:SetText(hex(C.good) .. "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t|r")
    end
end

ns.RegisterModule({
    key = "consumables", name = "Consumables", icon = ns.MEDIA .. "Consumables", group = "uitweaks", order = 8,
    desc = "Your raid shopping list: how many flasks, potions and food you have in your bags, how many you want, and what you're short on.",
    view = V,
})
