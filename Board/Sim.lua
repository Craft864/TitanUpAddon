-- TitanBoard - Sim.lua
-- /tb sim : a fake 5-person raid for solo testing. Their messages go
-- through the real receive path (including multi-part reassembly and the
-- permission checks), and after ~30 seconds it prints PASS/FAIL checks.
--
--   Brakk  - granted drawing rights; streams a live stroke, places and moves a stamp
--   Selune - has the addon, opens the board after a few seconds, then points with the laser
--   Vexa   - has the addon but NO rights; tries to draw (must be ignored)
--   Thorn  - goes silent after a few seconds (must time out)
--   Mossy  - doesn't have the addon
local ADDON, ns = ...

local Sim = {}
ns.Sim = Sim
Sim.members = {}

local ROSTER = {   -- name, class, has addon, raid group
    { "Brakk", "WARRIOR", true, 1 }, { "Selune", "PRIEST", true, 1 }, { "Vexa", "MAGE", true, 2 },
    { "Thorn", "HUNTER", true, 2 }, { "Mossy", "DRUID", false, 2 },
}

local run = 0

function Sim:Init() end

function Sim:OnOutgoing()
    self.out = (self.out or 0) + 1
end

function Sim:Start()
    if IsInGroup() then
        ns.Print("Leave your group first - the simulation is for solo testing.")
        return
    end
    if ns.loopback then ns.Comms:ToggleLoopback() end
    run = run + 1
    local myRun = run
    local realm = GetNormalizedRealmName() or "Medivh"
    wipe(self.members)
    for _, r in ipairs(ROSTER) do
        self.members[#self.members + 1] = { name = r[1] .. "-" .. realm, class = r[2], addon = r[3], group = r[4] }
    end
    local brakk, selune, vexa, thorn = self.members[1].name, self.members[2].name, self.members[3].name, self.members[4].name
    self.active = true
    self.out = 0
    self.seluneState = 2
    ns.Sync.rejected = 0
    ns.acl[brakk] = true

    if not ns.Board:IsShown() then ns.Board:Show() end
    local page = ns.Model.plan and ns.Model.plan.page or 1
    local start = GetTime()
    ns.Print("Simulation started. Brakk can draw, Vexa can't. Don't switch encounters for ~30s; checks print at the end.")

    local Model = ns.Model
    local function at(t, fn)
        C_Timer.After(t, function()
            if Sim.active and run == myRun then fn() end
        end)
    end
    local function from(name, kind, payload) ns.Comms:Inject(kind, payload, name) end
    local function presence(name, kind, state) from(name, kind, "sim," .. state) end

    -- Presence
    at(0.5, function() presence(brakk, "H", 1) end)
    at(0.9, function() presence(selune, "H", 2) end)
    at(1.3, function() presence(vexa, "H", 1) end)
    at(1.7, function() presence(thorn, "H", 1) end)
    at(6, function() Sim.seluneState = 1; presence(selune, "P", 1) end)
    self.ticker = C_Timer.NewTicker(5, function()
        if not Sim.active or run ~= myRun then return end
        presence(brakk, "P", 1)
        presence(selune, "P", Sim.seluneState)
        presence(vexa, "P", 1)
        if GetTime() - start < 4 then presence(thorn, "P", 1) end
    end)

    -- Brakk streams a wavy pen stroke in 6 pieces, then sends the final
    -- version (60 points - long enough to need a multi-part message).
    local wave = {}
    for i = 0, 59 do
        wave[#wave + 1] = 600 + i * 47
        wave[#wave + 1] = math.floor(1400 + math.sin(i / 6) * 450)
    end
    local base = { t = "P", c = 5, w = 4, k = 0 }
    for chunk = 0, 5 do
        at(3 + chunk * 0.3, function()
            local s = Model.Serialize(base, "1", Model.PackPoints(wave, chunk * 10 + 1, chunk * 10 + 10))
            from(brakk, "S", page .. ";a" .. s)
        end)
    end
    at(5, function()
        local op = { t = "P", c = 5, w = 4, k = 0, pts = wave }
        from(brakk, "O", page .. ";" .. Model.Serialize(op, "1"))
    end)

    -- A tank stamp labelled "Brakk", then moved twice (same id = update).
    local function stamp(x, y)
        return page .. ";" .. Model.Serialize({ t = "M", c = 1, w = 3, k = 1, pts = { x, y }, text = "Brakk" }, "2")
    end
    at(6.5, function() from(brakk, "O", stamp(1500, 2600)) end)
    at(7.5, function() from(brakk, "O", stamp(2300, 2200)) end)
    at(8.5, function() from(brakk, "O", stamp(2900, 2500)) end)

    -- Vexa has no rights: this line must NOT appear.
    at(9.5, function()
        from(vexa, "O", page .. ";" .. Model.Serialize({ t = "L", c = 1, w = 8, k = 0, pts = { 100, 100, 4000, 4000 } }, "1"))
    end)

    -- Brakk adds an arrow from the stamp.
    at(10.5, function()
        from(brakk, "O", page .. ";" .. Model.Serialize({ t = "A", c = 3, w = 3, k = 0, pts = { 2900, 2500, 2100, 1750 } }, "3"))
    end)

    -- Brakk adds a 60-degree pie slice and a donut with a 40% hole.
    at(11.5, function()
        from(brakk, "O", page .. ";" .. Model.Serialize({ t = "W", c = 2, w = 2, k = 60, pts = { 2000, 700, 2000, 1500 } }, "4"))
    end)
    at(12, function()
        from(brakk, "O", page .. ";" .. Model.Serialize({ t = "D", c = 7, w = 2, k = 40, pts = { 3100, 3100, 3600, 3100 } }, "5"))
    end)

    -- Selune can't draw, so she points with the laser for ~2 seconds.
    for i = 0, 12 do
        at(13 + i * 0.15, function()
            local x, y = 1200 + i * 120, 2000 + math.floor(math.sin(i / 2) * 300)
            ns.Laser:OnMessage(page .. ";" .. Model.PackPoints({ x, y }), selune)
        end)
    end
    at(14.5, function()
        local p = ns.Laser.pointers[selune]
        Sim.laserSeen = p ~= nil and p.x > 1500
    end)
    at(15.2, function() ns.Laser:OnMessage(page .. ";x", selune) end)

    -- Results
    at(30, function()
        local pg = Model.plan and Model.plan.pages[page]
        local function get(id) return pg and pg.byId[id] end
        local results = {}
        local function check(label, ok)
            results[#results + 1] = (ok and "|cff66e08cPASS|r " or "|cffff5a5aFAIL|r ") .. label
        end
        local stroke, marker = get(brakk .. ":1"), get(brakk .. ":2")
        check("Live stroke streamed and finalized (multi-part message)", stroke and not stroke.live and #stroke.pts == 120)
        check("Stamp moved in place, no duplicates", marker and marker.pts[1] == 2900 and marker.pts[2] == 2500)
        check("Arrow received", get(brakk .. ":3") ~= nil)
        local pie, donut = get(brakk .. ":4"), get(brakk .. ":5")
        check("Pie slice and donut received with their settings", pie and pie.k == 60 and donut and donut.k == 40)
        check("Unauthorized drawing ignored (Vexa)", get(vexa .. ":1") == nil and ns.Sync.rejected >= 1)
        local roster = ns.Presence.roster
        check("Selune switched to watching", roster[selune] and roster[selune].state == 1)
        check("Thorn timed out after going silent", roster[thorn] == nil)
        local list, counts = ns.Presence:List()
        check("Mossy and Thorn counted as not responding", counts.none == 2)
        check("Selune's laser pointer showed up", Sim.laserSeen == true)
        local headers = 0
        for _, e in ipairs(list) do if e.header then headers = headers + 1 end end
        check("Whole roster listed in raid groups (6 people, 2 groups)", counts.total == 6 and headers == 2)
        ns.Print("Simulation results:")
        for _, line in ipairs(results) do ns.Print("  " .. line) end
        ns.Print(("Your own drawing produced %d outgoing message(s); %d still queued. /tb sim to stop."):format(Sim.out, ns.Comms:QueueSize()))
    end)
end

function Sim:Stop()
    if not self.active then return end
    self.active = false
    if self.ticker then self.ticker:Cancel() self.ticker = nil end
    for _, m in ipairs(self.members) do
        ns.acl[m.name] = nil
        ns.Presence.roster[m.name] = nil
    end
    wipe(self.members)
    ns.fakeLockdown = nil
    ns.Print("Simulation stopped. Fake raiders' drawings stay on the board (right-click or Clear to remove).")
    if ns.Board then ns.Board:UpdateViewers() end
end
