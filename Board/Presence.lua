-- TitanBoard - Presence.lua
-- Who has the addon and who is looking at the board.
-- H = hello (sent when joining; others answer with P), P = ping/state.
-- Payload "version,state": 1 watching, 2 board closed, 3 mini view.
-- Anyone silent longer than the timeout drops off the list.
local ADDON, ns = ...

local P = {}
ns.Presence = P
P.roster = {}

local lastPing = 0
P.tunedIn = {}   -- [name] = time they opened the board (for the "tuned in" highlight)

local function timeout()
    return (ns.Sim and ns.Sim.active) and 15 or 45
end

function P:MyState()
    local B = ns.Board
    if B and B:IsShown() then return B.mini and 3 or 1 end
    return 2
end

function P:Announce(kind)
    if ns.Comms:Mode() == "local" then return end
    lastPing = GetTime()
    ns.Comms:Send(kind or "P", ns.VERSION .. "," .. self:MyState(), "presence")
end

function P:OnMessage(kind, payload, sender)
    local ver, state = payload:match("^([^,]*),(%d)$")
    if not ver then return end
    local known = self.roster[sender]
    state = tonumber(state)
    local wasWatching = known and (known.state == 1 or known.state == 3)
    if (state == 1 or state == 3) and not wasWatching then self.tunedIn[sender] = GetTime() end
    self.roster[sender] = { ver = ver, state = state, last = GetTime() }
    if kind == "H" and not known then
        C_Timer.After(math.random() * 2, function() P:Announce("P") end)
    end
    if ns.Board then ns.Board:UpdateViewers() end
end

function P:Prune()
    local now, members = GetTime(), {}
    for _, n in ipairs(ns.GroupNames()) do members[n] = true end
    for name, e in pairs(self.roster) do
        if not members[name] or now - e.last > timeout() then self.roster[name] = nil end
    end
end

-- The whole roster in a stable order (raid group, then name) so people
-- light up in place as they tune in. Group headers are included in raids.
-- Status: watching, mini, closed (has the addon, board shut), none (no
-- reply - no addon or not loaded), offline.
function P:List()
    self:Prune()
    local members = ns.GroupRoster()
    table.sort(members, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    local multiGroup = members[1] and members[#members].group ~= members[1].group
    local list, lastGroup = {}, nil
    local counts = { watching = 0, closed = 0, none = 0, total = #members }
    local now = GetTime()
    for _, m in ipairs(members) do
        if multiGroup and m.group ~= lastGroup then
            list[#list + 1] = { header = true, text = "GROUP " .. m.group }
            lastGroup = m.group
        end
        local st
        if m.name == ns.me then
            st = self:MyState()
        else
            local e = self.roster[m.name]
            st = e and e.state
        end
        local status = (not m.online and "offline") or (st == 1 and "watching") or (st == 3 and "mini")
            or (st == 2 and "closed") or "none"
        if status == "watching" or status == "mini" then
            counts.watching = counts.watching + 1
        elseif status == "closed" then
            counts.closed = counts.closed + 1
        else
            counts.none = counts.none + 1
        end
        local t = self.tunedIn[m.name]
        list[#list + 1] = {
            name = m.name, group = m.group, status = status, canDraw = ns.CanDraw(m.name),
            recent = t and (status == "watching" or status == "mini") and now - t < 6,
            ver = (m.name == ns.me) and ns.VERSION or (self.roster[m.name] and self.roster[m.name].ver),
        }
    end
    return list, counts
end

function P:OnRoster()
    if IsInGroup() and ns.Sim and ns.Sim.active then ns.Sim:Stop() end
    if IsInGroup() and ns.loopback then ns.Comms:ToggleLoopback() end
    local leader = ns.LeaderName()
    if leader ~= self._leader then
        self._leader = leader
        wipe(ns.acl)   -- new leader, new permissions
    end
    if IsInGroup() then
        if not self._grouped then
            self._grouped = true
            self:Announce("H")
            if ns.Board:IsShown() and not ns.IsOwner() then ns.Sync:RequestSnapshot() end
        end
    else
        self._grouped = false
        wipe(self.roster)
    end
    ns.Board:UpdateViewers()
end

function P:Init()
    ns.Comms:On("H", function(p, s) P:OnMessage("H", p, s) end)
    ns.Comms:On("P", function(p, s) P:OnMessage("P", p, s) end)
    C_Timer.NewTicker(5, function()
        if ns.Comms:Mode() == "local" then
            if next(P.roster) then wipe(P.roster) end
            return                      -- solo: nothing to announce or prune
        end
        if GetTime() - lastPing >= 20 then P:Announce("P") end
        P:Prune()
    end)
    ns.On("GROUP_ROSTER_UPDATE", function()
        if P._rosterTimer then return end
        P._rosterTimer = true
        C_Timer.After(2, function()
            P._rosterTimer = nil
            P:OnRoster()
        end)
    end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(3, function()
            if IsInGroup() then
                P._grouped = true
                P:Announce("H")
            end
        end)
    end)
end
