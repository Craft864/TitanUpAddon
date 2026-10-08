-- Titan Up - Tweaks/StackSplitter.lua
-- Stack Splitter (a UI Tweak): Shift-clicking a stack opens a Titan Up
-- dialog instead of Blizzard's little box.
--   * Take N: put N on your cursor (the normal split).
--   * Stacks of N: split the whole stack into stacks of N.
--   * Equal stacks: split it into K stacks as even as possible.
--   * Combine: merge this item's partial stacks back together.
-- New stacks go to empty slots in the same storage: your bags (and reagent
-- bag), the bank, one Warband bank tab, or one guild bank tab. A preview
-- shows what will happen and whether there's room; a progress bar and Stop
-- button show while it works. Each move waits for the game to finish
-- (its "item moved" events, plus a light check that only runs mid-job).
-- At a vendor, or anywhere the slot can't be identified, Blizzard's own box
-- is left alone. Nothing is built until the first Shift-click with it on.
local ADDON, ns = ...

local UI = ns.UI
local C = UI.C

local SS = {}
ns.StackSplitter = SS

local GUILD_SLOTS = 98
local MOVE_TIMEOUT, GUILD_TIMEOUT = 3, 6
-- A move is done when the SOURCE stack has dropped by the amount moved -
-- that's all we wait for (the new slot's count and lock flags can update
-- late, especially in the guild bank). Checked every frame while a split
-- runs; nothing runs otherwise. If a split didn't pick anything up (the
-- server wasn't ready), it's retried a moment later; a move that times out
-- is re-checked and retried before giving up.
-- Guild bank pacing: the source can report "unlocked" a moment before the
-- server will take another split, and a split asked for too soon is quietly
-- ignored. So: a short settle pause after each move; a split counts as
-- ignored if the source never locks within LOCK_WAIT (nothing in flight, so
-- asking again is safe); each ignored split lengthens the pause a little.
local GUILD_SETTLE, GUILD_SETTLE_MAX, SETTLE_STEP = 0.4, 1.5, 0.2
local LOCK_WAIT = 1.0
local IGNORE_RETRIES = 5       -- per move
local SPLIT_RETRIES = 6        -- split didn't pick anything up: try again shortly
local SPLIT_BACKOFF = 0.1      -- seconds, times the attempt number
local MOVE_RETRIES = 3         -- a move timed out: re-check, then retry
SS.MODES = { { "take", "Take" }, { "stacks", "Stacks of N" }, { "equal", "Equal stacks" } }

local function db() return ns.udb.splitter end

function SS:Init()
    -- add onto Blizzard's split box opening (never replace it)
    local function hook(...) SS:OnBlizzardOpen(...) end
    if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame and hooksecurefunc then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", function(_, ...) hook(...) end)
    elseif OpenStackSplitFrame and hooksecurefunc then
        hooksecurefunc("OpenStackSplitFrame", hook)
    end
    ns.On("GUILDBANKFRAME_OPENED", function() SS.guildOpen = true end)
    ns.On("GUILDBANKFRAME_CLOSED", function() SS.guildOpen = false; SS:Stop("The guild bank closed.") end)
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "GUILDBANKBAGSLOTS_CHANGED" }) do
        ns.On(ev, function() if SS.job then SS:Step() end end)
    end
end

-- ---------------------------------------------------------------------
-- Where things are
-- ---------------------------------------------------------------------
local BI = Enum and Enum.BagIndex or {}
local REAGENT_BAG = BI.ReagentBag or 5
local NUM_BAGS = NUM_BAG_SLOTS or 4

local function listOf(prefix, n)
    local out = {}
    for i = 1, n do local v = BI[prefix .. i] if v then out[#out + 1] = v end end
    return out
end
local CHAR_TABS = listOf("CharacterBankTab_", 6)
local ACCOUNT_TABS = listOf("AccountBankTab_", 5)
local LEGACY_BANK = { BANK_CONTAINER or -1 }
for i = 1, (NUM_BANKBAGSLOTS or 7) do LEGACY_BANK[#LEGACY_BANK + 1] = NUM_BAGS + 1 + i end   -- 6..12 (5 is the reagent bag)

local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

-- The bags new stacks may go to, for an item in `bag`.
function SS.ScopeFor(bag)
    if bag >= 0 and bag <= NUM_BAGS then
        local t = {} for b = 0, NUM_BAGS do t[#t + 1] = b end return t
    end
    if bag == REAGENT_BAG then
        local t = { REAGENT_BAG } for b = 0, NUM_BAGS do t[#t + 1] = b end return t
    end
    if has(ACCOUNT_TABS, bag) then return { bag } end
    if has(CHAR_TABS, bag) then return CHAR_TABS end
    if has(LEGACY_BANK, bag) or bag == (REAGENTBANK_CONTAINER or -3) then
        local t = {} for _, b in ipairs(LEGACY_BANK) do t[#t + 1] = b end
        if bag == (REAGENTBANK_CONTAINER or -3) then table.insert(t, 1, bag) end
        return t
    end
    return { bag }
end

-- One slot: { count, locked, itemID, link, icon } or nil when empty.
function SS.Slot(loc, bag, slot)
    if loc.guild then
        local icon, count, locked = GetGuildBankItemInfo(bag, slot)
        if not icon then return nil end
        local link = GetGuildBankItemLink and GetGuildBankItemLink(bag, slot)
        local id = link and tonumber(link:match("item:(%d+)"))
        return { count = count or 1, locked = locked, itemID = id, link = link, icon = icon }
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return { count = info.stackCount or 1, locked = info.isLocked, itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID }
end

local function slotsIn(loc, bag)
    if loc.guild then return GUILD_SLOTS end
    return C_Container.GetContainerNumSlots(bag) or 0
end

-- Empty slots in the item's storage (guild bank: its tab), in the game's
-- own slot order starting right after the source slot and wrapping around -
-- so new stacks fill in neatly after the original (in the guild bank: down
-- each column, then the next column).
function SS:EmptySlots(loc, exclude)
    local all, start = {}, 0
    for _, bag in ipairs(loc.scope) do
        for slot = 1, slotsIn(loc, bag) do
            all[#all + 1] = { bag, slot }
            if bag == loc.bag and slot == loc.slot then start = #all end
        end
    end
    local out, n = {}, #all
    for k = 1, n do
        local p = all[((start + k - 1) % n) + 1]
        local key = p[1] .. ":" .. p[2]
        if not (exclude and exclude[key]) and not SS.Slot(loc, p[1], p[2]) then out[#out + 1] = p end
    end
    return out
end

local function isInside(frame, ancestor)
    local f = frame
    for _ = 1, 12 do
        if not f then return false end
        if f == ancestor then return true end
        f = f.GetParent and f:GetParent()
    end
    return false
end

local function nameHas(frame, text)
    local f = frame
    for _ = 1, 8 do
        if not f then return false end
        local n = f.GetName and f:GetName()
        if type(n) == "string" and n:find(text, 1, true) then return true end
        f = f.GetParent and f:GetParent()
    end
    return false
end

-- Which slot was Shift-clicked: item-location info first, then bag/slot
-- methods, the Warband bank's own methods, and the guild bank.
function SS.Locate(button)
    if not button then return nil end
    -- guild bank (Blizzard's, or a bag addon's guild view while it's open)
    local guildView = (GuildBankFrame and GuildBankFrame.IsShown and GuildBankFrame:IsShown() and isInside(button, GuildBankFrame))
        or (SS.guildOpen and nameHas(button, "Guild"))
    if guildView and GetCurrentGuildBankTab then
        local slot = button.GetID and button:GetID()
        if slot and slot > 0 then return { guild = true, bag = GetCurrentGuildBankTab(), slot = slot } end
    end
    local bag, slot
    if button.GetBankTabID and button.GetContainerSlotID then
        bag, slot = button:GetBankTabID(), button:GetContainerSlotID()
    end
    if not (bag and slot) and button.GetItemLocation then
        local loc = button:GetItemLocation()
        if loc and loc.GetBagAndSlot then bag, slot = loc:GetBagAndSlot() end
    end
    if not (bag and slot) and button.GetBagID then
        bag, slot = button:GetBagID(), button.GetID and button:GetID()
    end
    if not (bag and slot) then
        local p = button.GetParent and button:GetParent()
        bag, slot = p and p.GetID and p:GetID(), button.GetID and button:GetID()
    end
    if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
    return { bag = bag, slot = slot }
end

-- ---------------------------------------------------------------------
-- Opening: replace Blizzard's box when we can
-- ---------------------------------------------------------------------
function SS:OnBlizzardOpen(maxStack, parent)
    if not db().enabled or self.job then return end
    if MerchantFrame and MerchantFrame:IsShown() then return end         -- vendors: Blizzard's box
    local loc = SS.Locate(parent)
    if not loc then return end
    loc.scope = loc.guild and { loc.bag } or SS.ScopeFor(loc.bag)
    local item = SS.Slot(loc, loc.bag, loc.slot)
    if not item or (item.count or 0) < 2 then return end
    if StackSplitFrame then StackSplitFrame:Hide() end
    self:Open(loc, item, parent)
end

-- ---------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------
-- The stacks to move off the source for a mode; the source keeps the rest.
function SS.Plan(mode, count, n)
    local moves = {}
    if mode == "stacks" then
        if n < 1 or n >= count then return moves end
        local left = count
        while left > n do moves[#moves + 1] = n; left = left - n end
    elseif mode == "equal" then
        if n < 2 then return moves end
        n = math.min(n, count)
        local base, extra = math.floor(count / n), count % n
        for i = 2, n do moves[#moves + 1] = base + ((i <= extra) and 1 or 0) end   -- the source keeps a base(+1) share
    end
    return moves
end

-- Partial stacks of the same item in this storage, for Combine.
function SS:Partials(loc, itemID, maxStack)
    local out = {}
    for _, bag in ipairs(loc.scope) do
        for slot = 1, slotsIn(loc, bag) do
            local s = SS.Slot(loc, bag, slot)
            if s and s.itemID == itemID and s.count < maxStack then out[#out + 1] = { bag = bag, slot = slot, count = s.count, locked = s.locked } end
        end
    end
    return out
end

local function maxStackOf(itemID, fallback)
    local m = itemID and C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)
    return (type(m) == "number" and m > 0) and m or fallback or 1
end

function SS:Preview()
    local o = self.open
    if not o then return "" end
    local item = SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    if not item then return "|cffff5a5aThat stack is gone.|r" end
    local n, mode = o.amount, o.mode
    if mode == "take" then return ("Puts %d on your cursor."):format(math.min(n, item.count)) end
    local moves = SS.Plan(mode, item.count, n)
    if #moves == 0 then return "|cff8a8f9cNothing to split with these numbers.|r" end
    local free = #self:EmptySlots(o.loc)
    local desc
    if mode == "stacks" then
        local full, rest = math.floor(item.count / n), item.count % n
        desc = ("Makes %d stack%s of %d%s"):format(full, full == 1 and "" or "s", n, rest > 0 and (" + 1 of " .. rest) or "")
    else
        local sizes = { item.count - (function() local t = 0 for _, m in ipairs(moves) do t = t + m end return t end)() }
        for _, m in ipairs(moves) do sizes[#sizes + 1] = m end
        desc = ("Makes %d stacks (%s)"):format(#sizes, table.concat(sizes, ", "))
    end
    local need = #moves
    local room = free >= need and ("|cff66e08cneeds %d free slot%s (you have %d)|r"):format(need, need == 1 and "" or "s", free)
        or ("|cffffa340needs %d free slots - only %d free, it'll do %d|r"):format(need, free, free)
    return desc .. "\n" .. room
end

-- ---------------------------------------------------------------------
-- Doing it
-- ---------------------------------------------------------------------
local function pickup(loc, bag, slot)
    if loc.guild then PickupGuildBankItem(bag, slot) else C_Container.PickupContainerItem(bag, slot) end
end
local function split(loc, bag, slot, n)
    if loc.guild then SplitGuildBankItem(bag, slot, n) else C_Container.SplitContainerItem(bag, slot, n) end
end

function SS:Take()
    local o = self.open
    if not o then return end
    local item = SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    if item then
        ClearCursor()
        split(o.loc, o.loc.bag, o.loc.slot, math.max(1, math.min(o.amount, item.count)))
    end
    self:Close()
end

function SS:Start(kind, leftover)
    local o = self.open
    if not o or self.job then return end
    local item = SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    if not item then return end
    local job = { loc = o.loc, kind = kind, done = 0, used = {}, itemID = item.itemID, retries = 0, splitFails = 0,
                  startedAt = GetTime(), ignored = 0, pace = o.loc.guild and GUILD_SETTLE or 0, ignoreTries = 0 }
    if kind == "combine" then
        job.max = maxStackOf(item.itemID, item.count)
        job.total = math.max(1, #self:Partials(o.loc, item.itemID, job.max) - 1)
    else
        job.moves = leftover or SS.Plan(o.mode, item.count, o.amount)
        local free = #self:EmptySlots(o.loc)
        while #job.moves > free do table.remove(job.moves) end
        job.total = #job.moves
        if job.total == 0 then return end
    end
    if db().remember then db().amount = o.amount end
    self.leftover = nil
    self.message = nil
    ClearCursor()
    self.job = job
    if not self.driver then self.driver = CreateFrame("Frame") end
    self.driver:SetScript("OnUpdate", function() SS:Step() end)      -- every frame, only while splitting
    self:Refresh()
    self:Step()
end

-- Continue a split that stopped part-way (the moves it hadn't done yet).
function SS:Continue()
    local rest = self.leftover
    if rest and #rest > 0 then self:Start("split", rest) end
end

local function refreshGuild(loc)
    if loc.guild and QueryGuildBankTab then QueryGuildBankTab(loc.bag) end
end

-- A move timed out: did it land anyway? If not, retry a few times (each
-- with a longer pause) before stopping with an honest reason.
function SS:MoveTimedOut(job, w)
    local loc = job.loc
    local src = SS.Slot(loc, w.sb, w.ss)
    local landed = (not src) or src.count <= w.srcAfter
    if landed then
        job.waiting = nil
        job.done, job.retries = job.done + 1, 0
        return
    end
    if loc.guild then
        -- guild bank: never ask for the split again (a late one would make
        -- two). Refresh the tab and wait once more, then stop honestly.
        if not w.extended then
            w.extended = true
            w.deadline = GetTime() + GUILD_TIMEOUT
            refreshGuild(loc)
            return
        end
        ClearCursor()
        job.waiting = nil
        return self:GiveUp(job)
    end
    ClearCursor()
    job.waiting = nil
    job.retries = job.retries + 1
    if job.retries > MOVE_RETRIES then return self:GiveUp(job) end
    job.nextAt = GetTime() + 0.3 * job.retries
end

function SS:GiveUp(job)
    local loc = job.loc
    if loc.guild and job.done == 0 then
        return self:Stop("The guild bank refused the move - check your permissions or withdraw limit.")
    end
    if loc.guild then
        return self:Stop(("Guild bank is slow - stopped at %d of %d. Continue resumes."):format(job.done, job.total))
    end
    return self:Stop(("A move didn't finish - stopped at %d of %d."):format(job.done, job.total))
end

-- One move at a time. The game can fire its bag / guild bank events
-- *instantly* inside a split or drop, which would run Step again in the
-- middle of a step (and fire extra splits) - so a step never re-enters;
-- the per-frame check picks things up right after.
function SS:Step()
    if self.stepping then return end
    self.stepping = true
    local ok, err = pcall(self.StepInner, self)
    self.stepping = false
    if not ok then
        self:Stop("Stopped: something went wrong.")
        if geterrorhandler then geterrorhandler()(err) end
    end
end

-- wait until the last move finished, pause if needed, then do the next
function SS:StepInner()
    local job = self.job
    if not job then return end
    local loc = job.loc
    if job.waiting then
        local w = job.waiting
        local src = SS.Slot(loc, w.sb, w.ss)
        local now = GetTime()
        if src and src.locked and not w.lockAt then w.lockAt = now end
        if (not src) or src.count <= w.srcAfter then          -- the source dropped by (at least) the amount
            job.waiting = nil
            job.done, job.retries, job.ignoreTries = job.done + 1, 0, 0
            if loc.guild then job.nextAt = now + job.pace end
            self:Refresh()
        elseif loc.guild and not w.lockAt and now - w.asked > LOCK_WAIT and src.count == w.srcAfter + w.amount
            and not (GetCursorInfo and GetCursorInfo()) then
            -- the server ignored the split (never locked, nothing moved): safe to ask again
            job.waiting = nil
            job.ignored, job.ignoreTries = job.ignored + 1, job.ignoreTries + 1
            job.pace = math.min(GUILD_SETTLE_MAX, job.pace + SETTLE_STEP)
            if job.ignoreTries > IGNORE_RETRIES then return self:GiveUp(job) end
            job.nextAt = now + job.pace
            return
        elseif now > w.deadline then
            self:MoveTimedOut(job, w)
            if not self.job or job.waiting then return end      -- stopped, or still waiting (guild bank: extended)
            self:Refresh()
        else
            return
        end
    end
    if job.nextAt and GetTime() < job.nextAt then return end      -- pacing / backoff
    -- what to move next
    local sb, ss, db_, ds, amount, key, srcCount, dstCount
    if job.kind == "combine" then
        local parts = self:Partials(loc, job.itemID, job.max)
        if #parts < 2 then return self:Finish() end
        table.sort(parts, function(a, b) return a.count > b.count end)
        local target, source = parts[1], parts[#parts]
        if target.locked or source.locked then return end
        sb, ss, db_, ds = source.bag, source.slot, target.bag, target.slot
        amount, srcCount, dstCount = math.min(source.count, job.max - target.count), source.count, target.count
    else
        amount = job.moves[job.done + 1]
        if not amount then return self:Finish() end
        local src = SS.Slot(loc, loc.bag, loc.slot)
        if not src or src.locked then return end
        local empty = self:EmptySlots(loc, job.used)[1]
        if not empty then return self:Stop("Stopped: no more free slots.") end
        sb, ss, db_, ds = loc.bag, loc.slot, empty[1], empty[2]
        key, srcCount, dstCount = empty[1] .. ":" .. empty[2], src.count, 0
        job.used[key] = true
    end
    -- split, then drop. In the guild bank the server fills the cursor a
    -- moment later, so drop straight away (like the game expects) - checking
    -- the cursor there would wrongly look like a failure. Bags fill it at once.
    -- record the pending move first: anything that runs while the game
    -- handles the split/drop sees "already waiting"
    local w = { sb = sb, ss = ss, srcAfter = srcCount - amount, db = db_, ds = ds, dstAfter = dstCount + amount, key = key,
                amount = amount, asked = GetTime(), deadline = GetTime() + (loc.guild and GUILD_TIMEOUT or MOVE_TIMEOUT) }
    job.waiting = w
    split(loc, sb, ss, amount)
    if not loc.guild and GetCursorInfo and not GetCursorInfo() then
        job.waiting = nil
        if key then job.used[key] = nil end
        job.splitFails = job.splitFails + 1
        if job.splitFails > SPLIT_RETRIES then return self:GiveUp(job) end
        job.nextAt = GetTime() + SPLIT_BACKOFF * job.splitFails     -- not ready yet: try again shortly
        return
    end
    job.splitFails = 0
    pickup(loc, db_, ds)
end

function SS:Finish()
    local job = self.job
    self:EndJob()
    self.leftover = nil
    self.message = job and (job.kind == "combine" and "|cff66e08cCombined.|r" or ("|cff66e08cDone - %d new stack%s.|r"):format(job.done, job.done == 1 and "" or "s"))
    self:Refresh()
end

function SS:Stop(reason)
    local job = self.job
    if not job then return end
    -- remember what's left so Continue can finish it
    if job.kind ~= "combine" and job.moves then
        local rest = {}
        for i = job.done + 1, #job.moves do rest[#rest + 1] = job.moves[i] end
        self.leftover = #rest > 0 and rest or nil
    end
    self:EndJob()
    ClearCursor()
    self.message = "|cffffa340" .. (reason or "Stopped.") .. "|r"
    self:Refresh()
end

function SS:EndJob()
    self.job = nil
    if self.driver then self.driver:SetScript("OnUpdate", nil) end
end

-- ---------------------------------------------------------------------
-- Dialog
-- ---------------------------------------------------------------------
local W, H = 340, 262          -- room for a two-line status message

function SS:Build()
    local f = UI.Window("TitanUpStackSplitter", W, H, { strata = "DIALOG", border = C.accent, drag = true })   -- placed by Open
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) SS:SetAmount(SS.open.amount + delta) end)
    f:SetScript("OnHide", function() if not SS.job then SS.open = nil end end)
    local close = UI.Button(f, 22, 20, "X", "Close", function() SS:Close() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", 12, -10)
    f.name = UI.Text(f, "GameFontNormal", C.text, nil, "TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
    f.name:SetWidth(W - 90); f.name:SetJustifyH("LEFT"); f.name:SetWordWrap(false)
    f.count = UI.Text(f, "GameFontHighlightSmall", C.muted, nil, "BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 1)
    -- modes
    f.modeBtns = {}
    for i, m in ipairs(SS.MODES) do
        local b = UI.Button(f, 102, 24, m[2], nil, function() SS.open.mode = m[1]; SS:Refresh() end)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 106, -54)
        f.modeBtns[m[1]] = b
    end
    -- amount: [-] [ 20 ] [v] [+]
    f.amountLabel = UI.Text(f, "GameFontHighlight", C.text, nil, "TOPLEFT", 14, -94)
    local plus = UI.Button(f, 24, 24, "+", nil, function() SS:SetAmount(SS.open.amount + 1) end)
    plus:SetPoint("TOPRIGHT", -14, -88)
    local list = UI.Button(f, 22, 24, "", "Presets", function() SS:PresetMenu(f.box) end)
    list:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    UI.Caret(list, "CENTER")
    local box = UI.EditBox(f, 60, 24, { center = true, numeric = true, max = 5, keys = false })
    box:SetPoint("RIGHT", list, "LEFT", -2, 0)
    box:SetScript("OnTextChanged", function(s, user) if user then SS:SetAmount(tonumber(s:GetText()) or 0, true) end end)
    box:SetScript("OnEnterPressed", function(s) s:ClearFocus(); SS:Primary() end)
    box:SetScript("OnEscapePressed", function() SS:Close() end)
    local minus = UI.Button(f, 24, 24, "-", nil, function() SS:SetAmount(SS.open.amount - 1) end)
    minus:SetPoint("RIGHT", box, "LEFT", -4, 0)
    f.box = box
    -- preview
    f.preview = UI.Text(f, "GameFontHighlightSmall", C.text, nil, "TOPLEFT", 14, -124)
    f.preview:SetWidth(W - 28); f.preview:SetJustifyH("LEFT")
    -- actions
    f.primary = UI.Button(f, 150, 30, "", nil, function() SS:Primary() end)
    f.primary:SetPoint("BOTTOMLEFT", 14, 14)
    UI.SetActive(f.primary, true)
    f.combine = UI.Button(f, 150, 30, "Combine", "Merge this item's partial stacks back together (same storage)", function() SS:Start("combine") end)
    f.combine:SetPoint("BOTTOMRIGHT", -14, 14)
    -- progress (while working)
    f.bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.Skin(f.bar, C.canvas, C.line)
    f.bar:SetSize(W - 120, 22)
    f.bar:SetPoint("BOTTOMLEFT", 14, 18)
    f.bar.fill = f.bar:CreateTexture(nil, "ARTWORK")
    f.bar.fill:SetPoint("TOPLEFT", 2, -2); f.bar.fill:SetPoint("BOTTOMLEFT", 2, 2)
    f.bar.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    f.bar.text = UI.Text(f.bar, "GameFontHighlightSmall", C.text, nil, "CENTER")
    f.stop = UI.Button(f, 84, 26, "Stop", nil, function() SS:Stop("Stopped.") end)
    f.stop:SetPoint("BOTTOMRIGHT", -14, 16)
    f.continue = UI.Button(f, 150, 30, "Continue", "Finish the split that stopped part-way", function() SS:Continue() end)
    f.continue:SetPoint("BOTTOMLEFT", 14, 14)
    UI.SetActive(f.continue, true)
    -- status message: its own band between the preview and the buttons,
    -- wrapped to the dialog's width (two lines at most)
    f.message = UI.Text(f, "GameFontHighlightSmall", C.text, nil, "BOTTOMLEFT", 14, 52)
    f.message:SetPoint("BOTTOMRIGHT", -14, 52)
    f.message:SetHeight(26)
    f.message:SetJustifyH("CENTER")
    f.message:SetJustifyV("MIDDLE")
    f.message:SetWordWrap(true)
    if f.message.SetMaxLines then f.message:SetMaxLines(2) end
    self.frame = f
    return f
end

function SS:Open(loc, item, anchor)
    local f = self.frame or self:Build()
    local d = db()
    self.message = nil
    self.leftover = nil                 -- a Continue belongs to the stack it came from
    self.open = { loc = loc, mode = d.mode, amount = (d.remember and d.amount) or math.floor(item.count / 2) }
    self.open.amount = math.max(1, math.min(self.open.amount, item.count))
    local name = item.link and item.link:match("%[(.-)%]") or "Item"
    local color = item.link and item.link:match("|c%x%x%x%x%x%x%x%x") or "|cffffffff"
    f.icon:SetTexture(item.icon)
    f.name:SetText(color .. name .. "|r")
    f:ClearAllPoints()
    if anchor and anchor.GetCenter then f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4) else f:SetPoint("CENTER") end
    f:Show()
    self:Refresh()
    f.box:SetFocus()
    f.box:HighlightText()
end

function SS:Close()
    if self.job then return end
    if self.frame then self.frame:Hide() end
    self.open = nil
end

function SS:SetAmount(v, typing)
    local o = self.open
    if not o then return end
    local item = SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    local top = item and item.count or 1
    v = math.floor(tonumber(v) or 0)
    if not typing then v = math.max(1, math.min(v, top)) end
    o.amount = v
    self:Refresh(typing)
end

function SS:Primary()
    local o = self.open
    if not o or self.job then return end
    if o.mode == "take" then self:Take() else self:Start("split") end
end

function SS:PresetMenu(anchor)
    local o = self.open
    local item = o and SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    if not item then return end
    local items = {}
    for _, n in ipairs(db().presets) do
        if n >= 1 and n <= item.count then items[#items + 1] = { text = tostring(n), onClick = function() SS:SetAmount(n) end } end
    end
    local half = math.floor(item.count / 2)
    if half >= 1 then items[#items + 1] = { text = ("Half (%d)"):format(half), onClick = function() SS:SetAmount(half) end } end
    UI.Menu(anchor, items)
end

function SS:Refresh(typing)
    local f, o = self.frame, self.open
    if not (f and o) then return end
    local item = SS.Slot(o.loc, o.loc.bag, o.loc.slot)
    f.count:SetText(item and ("Stack of %d%s"):format(item.count, o.loc.guild and "  -  guild bank" or "") or "")
    for key, b in pairs(f.modeBtns) do UI.SetActive(b, key == o.mode) end
    f.amountLabel:SetText(o.mode == "equal" and "Number of stacks" or (o.mode == "stacks" and "Stack size" or "Amount"))
    if not typing then f.box:SetText(tostring(o.amount)) end
    f.preview:SetText(self:Preview())
    local working = self.job ~= nil
    local canContinue = not working and self.leftover ~= nil
    f.continue:SetShown(canContinue)
    f.primary:SetShown(not working and not canContinue)
    f.combine:SetShown(not working)
    f.bar:SetShown(working)
    f.stop:SetShown(working)
    f.primary.label:SetText(o.mode == "take" and ("Take %d"):format(o.amount) or "Split")
    if working then
        local job = self.job
        local frac = job.total > 0 and job.done / job.total or 0
        f.bar.fill:SetWidth(math.max(0.01, (W - 124) * frac))
        f.bar.text:SetText(job.kind == "combine" and ("Combining... %d"):format(job.done) or ("Splitting %d of %d..."):format(math.min(job.done + 1, job.total), job.total))
    end
    f.message:SetText(self.message or "")
end

-- ---------------------------------------------------------------------
-- Settings page (inside UI Tweaks)
-- ---------------------------------------------------------------------
function SS:BuildPage(parent)
    local pg = CreateFrame("Frame", nil, parent)
    pg:SetAllPoints()
    self.page = pg
    local y = -8
    local function label(text) local t = UI.Text(pg, "GameFontHighlight", C.text) t:SetPoint("TOPLEFT", 18, y - 5) t:SetText(text) end
    label("Opens in")
    self.pageMode = UI.Button(pg, 170, 24, "", "Which tab the dialog starts on", function()
        local i = 1
        for k, m in ipairs(SS.MODES) do if m[1] == db().mode then i = k end end
        db().mode = SS.MODES[(i % #SS.MODES) + 1][1]
        SS:RefreshPage()
    end)
    self.pageMode:SetPoint("TOPRIGHT", -18, y)
    y = y - 32
    label("Remember the last amount")
    self.pageRemember = UI.Button(pg, 170, 24, "", nil, function() db().remember = not db().remember; SS:RefreshPage() end)
    self.pageRemember:SetPoint("TOPRIGHT", -18, y)
    y = y - 32
    label("Presets (the dropdown)")
    self.presetBoxes = {}
    for i = 4, 1, -1 do
        local b = UI.EditBox(pg, 38, 24, { center = true, numeric = true, max = 4, keys = false })
        b:SetPoint("TOPRIGHT", -18 - (4 - i) * 44, y)
        local function commit()
            local v = tonumber(b:GetText())
            if v and v > 0 then db().presets[i] = v end
            SS:RefreshPage()
        end
        b:SetScript("OnEnterPressed", function(s) commit(); s:ClearFocus() end)
        b:SetScript("OnEditFocusLost", commit)
        self.presetBoxes[i] = b
    end
    y = y - 40
    local help = UI.Text(pg, "GameFontHighlightSmall", C.muted, "Shift-click any stack in your bags, bank, Warband bank or guild bank. At vendors the game's own box is used.", "TOPLEFT", 18, y)
    help:SetWidth(400); help:SetJustifyH("LEFT")
    self.pageHeight = -y + 40
    return pg
end

function SS:RefreshPage()
    if not self.page then return end
    for _, m in ipairs(SS.MODES) do if m[1] == db().mode then self.pageMode.label:SetText(m[2]) end end
    self.pageRemember.label:SetText(db().remember and "|cff66e08cOn|r" or "Off")
    UI.SetActive(self.pageRemember, db().remember)
    for i, b in ipairs(self.presetBoxes) do b:SetText(tostring(db().presets[i] or "")) end
end
