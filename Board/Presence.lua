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

local TIMEOUT = 45      -- seconds of silence before someone drops off the list

function P:MyState()
    local B = ns.Board
    if B and B:IsShown() then return B.mini and 3 or 1 end
    return 2
end

function P:Announce(kind)
    if ns.Comms:Mode() == "local" then return end
    lastPing = GetTime()
    kind = kind or "P"
    -- (H and P coalesce separately: a queued hello must not turn into a ping)
    ns.Comms:Send(kind, ns.VERSION .. "," .. self:MyState(), "presence:" .. kind)
end

function P:OnMessage(kind, payload, sender)
    local ver, state = payload:match("^([^,]*),(%d)$")
    if not ver then return end
    local known = self.roster[sender]
    state = tonumber(state)
    local wasWatching = known and (known.state == 1 or known.state == 3)
    if (state == 1 or state == 3) and not wasWatching then
        self.tunedIn[sender] = GetTime()
        C_Timer.After(6.1, function() if ns.Board then ns.Board:UpdateViewers() end end)   -- "tuned in" fades
    end
    self.roster[sender] = { ver = ver, state = state, last = GetTime() }
    if kind == "H" and not known then
        C_Timer.After(math.random() * 2, function() P:Announce("P") end)
    end
    if ns.Board then ns.Board:UpdateViewers() end
end

function P:Prune()
    local now = GetTime()
    for name, e in pairs(self.roster) do
        if not ns.InMyGroup(name) or now - e.last > TIMEOUT then self.roster[name] = nil end
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
        ns.Model:PruneLive(10)          -- strokes whose author stopped mid-draw (left, reloaded)
        if InCombatLockdown() then return end   -- no check-ins mid-fight; resumes after the pull
        if GetTime() - lastPing >= 20 then P:Announce("P") end
        P:Prune()
        ns.Board:UpdateViewers()
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

-- =====================================================================
-- Invite: ping the group to open the board (formerly Board/Invite.lua)
-- =====================================================================
do
-- "Invite" does two things:
--   * an addon message, so everyone WITH TitanBoard gets a clickable
--     [Open TitanBoard] link printed locally (servers strip custom links
--     from real chat, but a line an addon prints itself can contain one)
--   * a plain group-chat line, so people WITHOUT it know what to install.
-- Both are blocked during an encounter, so the button refuses then.

local Invite = {}
ns.Invite = Invite

local LINK = "|Haddon:TitanBoard:open|h|cff4fc3f7[Open TitanBoard]|r|h"

local function onLink(link)
    if type(link) == "string" and link:find("^addon:TitanBoard:open") then
        if not ns.Board:IsShown() then ns.Board:Show() end
    end
end

function Invite:Init()
    -- the game hands "addon:" links to EventRegistry; older clients only to SetItemRef
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, Invite)
    elseif SetItemRef then
        hooksecurefunc("SetItemRef", function(link) onLink(link) end)
    end
end

local function describe()
    local ctx = ns.Model.plan and ns.Model.plan.ctx
    local what = ctx and (ctx.name or ctx.instName) or "a plan"
    return (what:gsub("[%^|~]", ""))
end

function Invite:Send()
    if ns.InLockdown() then
        ns.Print("Can't send invites during an encounter - try again after the pull.")
        return
    end
    local what = describe()
    if ns.Comms:Mode() == "group" then
        ns.Comms:Send("I", what, "invite")
        local channel = ns.GroupChannel()
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        if channel and send and ns.GroupIsAllGuild() then
            pcall(send, ("[TitanBoard] %s is sharing a plan for %s. Install TitanBoard to watch it live."):format(
                ns.Short(ns.me), what), channel)
        end
        ns.Print("Invite sent.")
    else
        ns.Print("Solo preview - raiders with TitanBoard would see the line below, and everyone gets a note in group chat:")
        self:OnInvite(ns.me, what, true)
    end
end

function Invite:OnInvite(sender, what, force)
    if ns.Board:IsShown() and not force then return end
    ns.Print(("%s is sharing a plan for %s  %s"):format(ns.Short(sender), what or "an encounter", LINK))
    if SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
end
end
