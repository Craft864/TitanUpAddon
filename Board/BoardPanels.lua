-- Titan Up - Board/BoardPanels.lua
-- TitanBoard's side panels: the encounter list (left), live viewers (right),
-- header / status, slides, saved plans and the room picker. Split out of
-- Board.lua to keep that file manageable; these only use the shared tables
-- below (the view and undo history), never Board.lua's canvas sizes.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C
local Model = ns.Model
local Board = ns.Board
local view = Board._view
local undo = Board._undo

-- ---------------------------------------------------------------------
-- Encounter list (left)
-- ---------------------------------------------------------------------
function Board:BuildEntries()
    local e = {}
    local function header(text) e[#e + 1] = { kind = "header", text = text } end
    local function inst(i)
        e[#e + 1] = { kind = "inst", text = i.name, inst = i.id, missing = i.missing }
        if i.id and self.expanded == i.id then
            for _, b in ipairs(ns.Content:Encounters(i.id)) do
                e[#e + 1] = { kind = "boss", text = b.name, inst = i.id, enc = b.id }
            end
        end
    end
    local here = ns.Content:CurrentContext()
    if here and here.inst then
        header("YOU ARE HERE")
        inst({ id = here.inst, name = here.instName or "Current instance" })
    end
    header("RAIDS")
    for _, i in ipairs(ns.Content:Raids()) do inst(i) end
    header("MYTHIC+ POOL")
    local d = ns.Content:Dungeons()
    if #d == 0 then e[#e + 1] = { kind = "note", text = "Loading keystone pool..." } end
    for _, i in ipairs(d) do inst(i) end
    local world = ns.Content:WorldBosses()
    if #world > 0 then
        header("WORLD BOSSES")
        for _, i in ipairs(world) do inst(i) end
    end
    header("OTHER")
    e[#e + 1] = { kind = "free", text = "Blank board" }
    self.entries = e
end

function Board:RefreshList(rebuild)
    if not self.frame then return end
    if rebuild or not self.entries then self:BuildEntries() end
    local e = self.entries
    local rows = self.listRows
    local maxOff = math.max(0, #e - #rows)
    self.listOffset = math.max(0, math.min(maxOff, self.listOffset or 0))
    local ctx = Model.plan and Model.plan.ctx
    for i, row in ipairs(rows) do
        local item = e[i + self.listOffset]
        row.item = item
        if not item then
            row:Hide()
        else
            row:Show()
            local text, col, indent = item.text, C.text, 6
            row.hl:Hide()
            if item.kind == "header" then
                col, text = C.accent, item.text
            elseif item.kind == "note" then
                col = C.muted
            elseif item.kind == "inst" then
                text = ((self.expanded == item.inst) and "- " or "+ ") .. item.text
                if item.missing then col = C.muted end
            elseif item.kind == "boss" then
                indent = 20
                if ctx and ctx.enc == item.enc then
                    row.hl:Show()
                    col = C.accent
                end
            elseif item.kind == "free" then
                if ctx and ctx.key == "free" then row.hl:Show(); col = C.accent end
            end
            row.text:SetPoint("LEFT", indent, 0)
            row.text:SetText(text)
            row.text:SetFontObject(item.kind == "header" and "GameFontNormalSmall" or "GameFontHighlightSmall")
            row.text:SetTextColor(col[1], col[2], col[3])
        end
    end
end

function Board:_listClick(item)
    if not item then return end
    if item.kind == "inst" then
        if item.missing then
            ns.Print("No Encounter Journal match for this dungeon yet (see Content.lua NAME_OVERRIDES).")
            return
        end
        if self.expanded == item.inst then self.expanded = nil else self.expanded = item.inst end   -- click again to collapse
        self:RefreshList(true)
        return
    end
    if item.kind ~= "boss" and item.kind ~= "free" then return end
    if IsInGroup() and not ns.CanDraw() then
        ns.Print("You're following the leader's board - they choose the encounter.")
        return
    end
    local ctx = (item.kind == "boss") and ns.Content:MakeContext(item.inst, item.enc) or ns.Content:MakeContext()
    self:SelectContext(ctx, 1)
end

-- ---------------------------------------------------------------------
-- Viewers (right)
-- ---------------------------------------------------------------------
local STATUS_TEXT = {
    watching = { "watching", C.good },
    mini = { "mini view", C.good },
    closed = { "board closed", C.warn },
    none = { "no response", C.muted },
    offline = { "offline", C.muted },
}

function Board:UpdateViewers()
    if not self.frame or not self.frame:IsShown() then return end
    local list, counts = ns.Presence:List()
    self.countText:SetText(("|cff66e08c%d|r / %d watching   |cffffa340%d closed|r   |cff8a8f9c%d other|r"):format(
        counts.watching, counts.total, counts.closed, counts.none))
    local rows = self.viewerRows
    local maxOff = math.max(0, #list - #rows)
    self.viewerOffset = math.max(0, math.min(maxOff, self.viewerOffset or 0))
    for i, row in ipairs(rows) do
        local v = list[i + self.viewerOffset]
        row.entry = v
        if not v then
            row:Hide()
        elseif v.header then
            row:Show()
            row.dot:Hide()
            row.name:SetText(v.text)
            row.name:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
            row.status:SetText("")
            row.hl:Hide()
        else
            row:Show()
            row.dot:Show()
            local st = STATUS_TEXT[v.status]
            local active = v.status == "watching" or v.status == "mini"
            row.dot:SetVertexColor(st[2][1], st[2][2], st[2][3], active and 1 or 0.6)
            local class = ns.ClassOf(v.name)
            local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            local name = ns.Short(v.name) .. ((v.name == ns.me) and " (you)" or "")
            row.name:SetText(name)
            local r, g, b = C.text[1], C.text[2], C.text[3]
            if cc then r, g, b = cc.r, cc.g, cc.b end
            row.name:SetTextColor(r, g, b, active and 1 or 0.45)
            local status = st[1]
            if v.recent then status = "|cff4fc3f7tuned in|r" end
            if v.canDraw then status = "|cff4fc3f7draw|r  " .. status end
            row.status:SetText(status)
            row.status:SetTextColor(C.muted[1], C.muted[2], C.muted[3], active and 1 or 0.7)
            row.hl:SetShown(v.recent and true or false)
        end
    end
end

function Board:_viewerClick(entry)
    if not entry or entry.header or entry.name == ns.me then return end
    local leader = IsInGroup() and UnitIsGroupLeader("player")
    if not leader and IsInGroup() then
        ns.Print("Only the group leader can grant drawing rights.")
        return
    end
    if not IsInGroup() then return end
    ns.acl[entry.name] = (not ns.acl[entry.name]) or nil
    ns.Print(ns.Short(entry.name) .. (ns.acl[entry.name] and " can now draw." or " can no longer draw."))
    ns.Sync:SendACL()
    self:UpdateViewers()
end

-- ---------------------------------------------------------------------
-- Header, phases, status
-- ---------------------------------------------------------------------
function Board:UpdateHeader()
    local ctx = Model.plan and Model.plan.ctx
    local text = "Blank board"
    if ctx then
        if ctx.name then
            text = ctx.name .. (ctx.instName and ("  |cff8a8f9c" .. ctx.instName .. "|r") or "")
        elseif ctx.instName then
            text = ctx.instName
        end
    end
    self.ctxText:SetText(text)
end

-- ---------------------------------------------------------------------
-- Slides (left panel)
-- ---------------------------------------------------------------------
function Board:RefreshSlides(keepOffset)
    if not self.slideRows then return end
    local plan = Model.plan
    local count = plan and #plan.pages or 0
    local page = plan and plan.page or 1
    local rows = self.slideRows
    local maxOff = math.max(0, count - #rows)
    local off = self.slideOffset or 0
    if not keepOffset and page <= off then off = page - 1 end
    if not keepOffset and page > off + #rows then off = page - #rows end
    self.slideOffset = math.max(0, math.min(maxOff, off))
    for i, row in ipairs(rows) do
        local idx = i + self.slideOffset
        local sl = plan and plan.pages[idx]
        row.index = idx
        if not sl then
            row:Hide()
        else
            row:Show()
            local current = idx == page
            row.hl:SetShown(current)
            row.num:SetText(idx)
            row.text:SetText(sl.name)
            local c = current and C.accent or C.text
            row.text:SetTextColor(c[1], c[2], c[3])
            local n = #sl.ops
            row.count:SetText(n > 0 and n or "")
        end
    end
    self.slideCountText:SetText(("%d / %d"):format(count > 0 and page or 0, Model.MAX_SLIDES))
    self.miniSlideText:SetText(plan and ("Slide %d/%d"):format(page, count) or "")
end

local function ownerOnly()
    if ns.IsOwner() then return true end
    ns.Print("Only the group leader can manage plans and slides.")
    return false
end

function Board:AfterPlanChange()
    wipe(undo)
    self:_openZoomedOut()
    self:RenderAll()
    ns.Sync:SendAll()
end

-- a new slide (i, or nil when the plan is full): show it and share it
function Board:_slideAdded(i, applyView)
    if not i then ns.Print("A plan can have up to " .. Model.MAX_SLIDES .. " slides.") return end
    wipe(undo)
    Model.plan.page = i
    if applyView then self:ApplySlideView() end
    self:RenderAll()
    ns.Sync:SendSnapshot()
end

function Board:AddSlide()
    if Model.plan and ownerOnly() then self:_slideAdded(Model:AddSlide({ z = view.zoom, cx = view.cx, cy = view.cy })) end
end

function Board:DuplicateSlide()
    if Model.plan and ownerOnly() then self:_slideAdded(Model:DuplicateSlide(Model.plan.page), true) end
end

function Board:RenameSlide()
    if not Model.plan or not ownerOnly() then return end
    UI.Prompt({
        title = "Rename slide", help = "Up to 24 characters, e.g. \"Pull\", \"P2 soaks\", \"Intermission\".",
        text = Model:Page().name, accept = "Rename", select = true,
        onAccept = function(text)
            if Model:RenameSlide(Model.plan.page, text) then
                Board:RefreshSlides()
                ns.Sync:SendSnapshot()
            end
        end,
    })
end

function Board:DeleteSlide()
    if not Model.plan or not ownerOnly() then return end
    if Model:SlideCount() <= 1 then
        ns.Print("A plan needs at least one slide - use Clear to empty it.")
        return
    end
    local function doDelete()
        Model:DeleteSlide(Model.plan.page)
        wipe(undo)
        Board:ApplySlideView()
        Board:RenderAll()
        ns.Sync:SendAll()
    end
    if Model:CountOps() == 0 then doDelete() return end
    UI.Prompt({
        title = "Delete slide", noInput = true, accept = "Delete",
        help = ("Delete \"%s\" and its %d drawing(s)? This can't be undone."):format(Model:Page().name, Model:CountOps()),
        onAccept = doDelete,
    })
end

function Board:MoveSlide(delta)
    if not Model.plan or not ownerOnly() then return end
    if Model:MoveSlide(Model.plan.page, delta) then
        wipe(undo)
        self:RefreshSlides()
        ns.Sync:SendAll()
    end
end

-- ---------------------------------------------------------------------
-- Saved plans (left panel)
-- ---------------------------------------------------------------------
function Board:RefreshPlanUI()
    if not self.planBtn then return end
    local plan = Model.plan
    local owner = ns.IsOwner()
    self.planBtn.label:SetText(plan and plan.name or "")
    local n = plan and #Model:PlanNames() or 0
    self.planCount:SetText(n > 1 and (n .. " plans") or "")
    for _, b in ipairs(self.ownerButtons) do UI.SetDisabled(b, not owner) end
    UI.SetDisabled(self.planBtn, not owner)
end

function Board:ShowPlanMenu()
    if not Model.plan or not ownerOnly() then return end
    local items = {}
    for _, name in ipairs(Model:PlanNames()) do
        items[#items + 1] = {
            text = name, checked = name == Model.plan.name,
            onClick = function()
                Model:SwitchPlan(name)
                Board:AfterPlanChange()
            end,
        }
    end
    items[#items + 1] = { text = "+ New plan...", muted = true, onClick = function() Board:NewPlan() end }
    UI.Menu(self.planBtn, items)
end

function Board:NewPlan()
    if not Model.plan or not ownerOnly() then return end
    UI.Prompt({
        title = "New plan", help = "A blank plan for this encounter. Your current plan is already saved.",
        text = Model:UniquePlanName("New plan"), accept = "Create", select = true,
        onAccept = function(text)
            Model:NewPlan(text)
            Board:AfterPlanChange()
        end,
    })
end

function Board:SavePlanAs()
    if not Model.plan or not ownerOnly() then return end
    UI.Prompt({
        title = "Save plan as", help = "Saves a copy under a new name and keeps working on the copy. Plans also save automatically as you draw.",
        text = Model:UniquePlanName(Model.plan.name .. " copy"), accept = "Save", select = true,
        onAccept = function(text)
            Model:SaveAs(text)
            Board:RefreshPlanUI()
            ns.Print("Saved as \"" .. Model.plan.name .. "\".")
            ns.Sync:SendSnapshot()
        end,
    })
end

function Board:DeletePlan()
    if not Model.plan or not ownerOnly() then return end
    local name = Model.plan.name
    UI.Prompt({
        title = "Delete plan", noInput = true, accept = "Delete",
        help = ("Delete \"%s\" and all %d of its slides? This can't be undone. (Export it first if you might want it back.)"):format(name, Model:SlideCount()),
        onAccept = function()
            Model:DeletePlan(name)
            Board:AfterPlanChange()
            ns.Print("Deleted \"" .. name .. "\".")
        end,
    })
end

function Board:UpdateStatus()
    if self.FitOptionsBar then self:FitOptionsBar() end
    if not self.frame then return end
    local mode = ns.Comms:Mode()
    local queued = ns.Comms:QueueSize()
    local locked = ns.InLockdown()
    local pill, pc
    if locked then
        pill, pc = "LOCKDOWN", C.warn
    elseif mode == "group" then
        pill, pc = "LIVE", C.good
    else
        pill, pc = "LOCAL", C.muted
    end
    self.pill.text:SetText(pill)
    self.pill.text:SetTextColor(pc[1], pc[2], pc[3])
    self.pill:SetBackdropBorderColor(pc[1], pc[2], pc[3], 1)

    local banner
    if locked then
        banner = ("|cffffa340Encounter lockdown|r - nothing can be sent right now. %d change(s) queued."):format(queued)
    elseif IsInGroup() and not ns.CanDraw() then
        local leader = ns.LeaderName()
        local synced = ns.Sync:InSync()
        banner = "Following " .. ns.Short(leader or "the leader") .. "  |cff8a8f9c- hold the left mouse button to point|r"
        if synced == false then banner = banner .. "  |cffffa340(resyncing...)|r" end
    end
    self.banner:SetText(banner or "")
    self.bannerBg:SetShown(banner ~= nil)

    local st = ns.Comms.stats
    self.footRight:SetText(("%s  |  sent %d  recv %d  queued %d  throttled %d"):format(
        mode, st.sent, st.recv, queued, st.throttled))

    self.emptyText:SetShown(Model.plan ~= nil and Model:CountOps() == 0 and not self.mini)
    local canDraw = ns.CanDraw()
    for m, b in pairs(self.toolBtns) do b:SetAlpha((canDraw or m == "R") and 1 or 0.4) end
    for _, b in pairs(self.stampBtns) do b:SetAlpha(canDraw and 1 or 0.4) end
    self.syncBtn.label:SetText(ns.IsOwner() and "Send full plan" or "Request resync")
    self:UpdateViewers()
end

-- ---------------------------------------------------------------------
-- Room picker (options bar): which background this slide uses
-- ---------------------------------------------------------------------
function Board:RefreshRoomUI()
    local b = self.roomBtn
    if not b then return end
    local ctx = Model.plan and Model.plan.ctx
    local list = ctx and ns.Rooms:List(ctx) or {}
    if #list == 0 or ns.testRoom then
        b:Hide()
        return
    end
    b:Show()
    local room = ns.Rooms:Get(ctx, Model:Page().bg)
    b.label:SetText("Room: " .. (room and room.label or "Blizzard map"))
    UI.SetDisabled(b, not ns.CanDraw())
end

function Board:ShowRoomMenu()
    if not Model.plan then return end
    if not ns.CanDraw() then
        ns.Print("You're following the leader - they choose the room.")
        return
    end
    local ctx = Model.plan.ctx
    local current = ns.Rooms:Get(ctx, Model:Page().bg)
    local items = {}
    for _, r in ipairs(ns.Rooms:List(ctx)) do
        items[#items + 1] = { text = r.label, checked = current == r, onClick = function() Board:SetRoom(r.key) end }
    end
    items[#items + 1] = { text = "Blizzard map", checked = current == nil, onClick = function() Board:SetRoom("map") end }
    UI.Menu(self.roomBtn, items)
end

function Board:SetRoom(key)
    local sl = Model:Page()
    if not sl or not ns.CanDraw() then return end
    if sl.bg == key then return end
    if #sl.ops > 0 then
        ns.Print("Room changed. Drawings keep their positions on the board, so re-place anything that no longer lines up.")
    end
    sl.bg = key
    Model.plan.keep = true
    self:ResetView()
    self:RenderAll()
    Model:Touch()
    ns.Sync:SendRoom()
    self:_viewChanged()
end

function Board:PrintIds(all)
    local ctx = Model.plan and Model.plan.ctx
    if all then
        local inst = ctx and ctx.inst
        if not inst then
            local here = ns.Content:CurrentContext()
            inst = here and here.inst
        end
        if not inst then ns.Print("Open the board on a boss (or stand in the instance) first.") return end
        ns.Print(("%s - instance %d:"):format(ns.Content:InstanceName(inst) or "?", inst))
        for _, e in ipairs(ns.Content:Encounters(inst)) do
            ns.Print(("  [%d] = %s"):format(e.id or 0, e.name or "?"))
        end
        return
    end
    if not ctx then ns.Print("Open the board on an encounter first.") return end
    local room = ns.Rooms:Get(ctx, Model:Page().bg)
    ns.Print(("Instance %s  |  encounter %s  |  floor map %s  |  background: %s"):format(
        tostring(ctx.inst), tostring(ctx.enc), tostring(ctx.map), room and ("room \"" .. room.label .. "\"") or (self.bg and self.bg.kind or "?")))
    ns.Print("Tip: /tb ids all lists every boss in this instance.")
end
