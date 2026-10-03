-- TitanBoard - Invite.lua
-- "Invite" does two things:
--   * an addon message, so everyone WITH TitanBoard gets a clickable
--     [Open TitanBoard] link printed locally (servers strip custom links
--     from real chat, but a line an addon prints itself can contain one)
--   * a plain group-chat line, so people WITHOUT it know what to install.
-- Both are blocked during an encounter, so the button refuses then.
local ADDON, ns = ...

local Invite = {}
ns.Invite = Invite

local LINK = "|Haddon:TitanBoard:open|h|cff4fc3f7[Open TitanBoard]|r|h"

local function onLink(link)
    if type(link) == "string" and link:find("^addon:TitanBoard:open") then
        if not ns.Board:IsShown() then ns.Board:Show() end
    end
end

function Invite:Init()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) onLink(link) end, Invite)
    end
    if SetItemRef then
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
        if channel and send then
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
