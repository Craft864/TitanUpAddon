-- TitanBoard - ImportExport.lua
-- Plan strings. Everything is plain text inside, so the raid site can
-- generate the same strings later.
local ADDON, ns = ...

local IE = {}
ns.ImportExport = IE

-- "!TB2!" + print-encoding (ns.Codec, LibDeflate-compatible) of a compressed payload with fields
-- (separated by \31): "2", instance ID, encounter ID, floor map ID,
-- background kind, plan name, slide meta ("name:zoom:cx:cy" joined by ~),
-- then one field per slide with ops joined by "~".
-- "!TB1!" strings from v0.1-0.3 (4 fixed phases) still import.
local Codec = ns.Codec

function IE:Encode()
    local Model = ns.Model
    local plan = Model.plan
    if not plan then return nil end
    local ctx = plan.ctx
    local parts = { "2", ctx.inst or 0, ctx.enc or 0, ctx.map or 0,
        (ns.Board.bg and ns.Board.bg.kind) or "none", Model.CleanName(plan.name), Model:SlideMeta() }
    local count = Model:AddPageFields(parts)
    local payload = table.concat(parts, "\031")
    local packed = Codec.Compress(payload)
    if not packed then return nil, count end
    return "!TB2!" .. Codec.EncodeForPrint(packed), count
end

function IE:Decode(str)
    str = tostring(str or ""):gsub("%s", "")
    local version, body = str:match("^!TB(%d)!(.+)$")
    if not body then return nil, "That isn't a TitanBoard plan string." end
    local compressed = Codec.DecodeForPrint(body)
    local payload = compressed and Codec.Decompress(compressed)
    if not payload then return nil, "The string is damaged or incomplete." end
    local f = ns.Split(payload, "\031")
    local data = { inst = tonumber(f[2]), enc = tonumber(f[3]), map = tonumber(f[4]), bg = f[5] }
    if version == "1" and f[1] == "1" and #f >= 9 then
        local last = 0
        for p = 1, 4 do if f[5 + p] ~= "" then last = p end end
        local meta, opFields = {}, {}
        for p = 1, math.max(1, last) do
            meta[p] = "Phase " .. p .. ":0:0:0"
            opFields[p] = f[5 + p]
        end
        data.name = "Imported"
        data.slides = ns.Model.DecodeSlides(table.concat(meta, "~"), opFields)
    elseif version == "2" and f[1] == "2" and #f >= 8 then
        data.name = (f[6] ~= "" and f[6]) or "Imported"
        data.slides = ns.Model.DecodeSlides(f[7], f, nil, 8)
    else
        return nil, "Unknown plan format - it may be from a newer TitanBoard."
    end
    if not data.slides then return nil, "The plan inside the string couldn't be read." end
    return data
end

function IE:ShowExport()
    if not Codec.Available() then ns.Print("Import/export needs the game's compression API, which isn't available.") return end
    local text, count = self:Encode()
    if not text then ns.Print("Nothing to export yet.") return end
    ns.UI.Prompt({
        title = "Export plan",
        help = ("\"%s\": %d slide(s), %d item(s). Press Ctrl+C to copy, then paste it in Discord or another raid leader's Import box."):format(
            ns.Model.plan.name, ns.Model:SlideCount(), count),
        text = text,
        select = true,
    })
end

function IE:ShowImport()
    if not Codec.Available() then ns.Print("Import/export needs the game's compression API, which isn't available.") return end
    if not ns.IsOwner() then
        ns.Print("Only the group leader can import plans while in a group.")
        return
    end
    ns.UI.Prompt({
        title = "Import plan",
        help = "Paste a TitanBoard plan string, or a Raidstrats.gg string (!raidstrats-addon-...). It's added as a new saved plan for its encounter - nothing gets overwritten.",
        accept = "Import",
        onAccept = function(text) IE:Import(text) end,
    })
end

function IE:Import(text)
    local data, err
    local fromRaidstrats = ns.RaidstratsImport and ns.RaidstratsImport.IsRaidstrats(text)
    if fromRaidstrats then
        data, err = ns.RaidstratsImport:Decode(text)
    else
        data, err = self:Decode(text)
    end
    if not data then ns.Print(err) return end
    if fromRaidstrats then data.found = data.enc ~= nil end
    if fromRaidstrats and not data.enc then
        -- Boss not recognized: put it on the encounter that's open right now.
        local ctx = ns.Model.plan and ns.Model.plan.ctx
        if ctx then data.inst, data.enc, data.map = ctx.inst, ctx.enc, ctx.map end
    end
    local inst = (data.inst and data.inst > 0) and data.inst or nil
    local enc = (data.enc and data.enc > 0) and data.enc or nil
    local map = (data.map and data.map > 0) and data.map or nil
    local Board, Model = ns.Board, ns.Model
    Board:SelectContext(ns.Content:MakeContext(inst, enc, map), 1, true)
    Model:NewPlan(data.name)
    Model.plan.page = 1
    Model:SetSlides(nil, data.slides, true)
    Model:Save()
    local count = 0
    for _, sl in ipairs(Model.plan.pages) do count = count + #sl.ops end
    Board:AfterPlanChange()
    Board:RefreshList(true)
    ns.Print(("Imported \"%s\": %d slide(s), %d item(s)%s."):format(Model.plan.name, Model:SlideCount(), count,
        Model.plan.ctx.name and (" for " .. Model.plan.ctx.name) or ""))
    if fromRaidstrats then self:RaidstratsSummary(data) end
    if data.bg and data.bg ~= "none" and Board.bg and data.bg ~= Board.bg.kind then
        ns.Print("|cffffa340Heads up:|r this plan was drawn on a different background (" .. data.bg .. " vs " .. Board.bg.kind .. "), so positions may be off.")
    end
end

function IE:RaidstratsSummary(data)
    local n = data.notes or {}
    local parts = {}
    if n.moves then parts[#parts + 1] = n.moves .. " movement path(s) drawn as arrows" end
    if n.frontals then parts[#parts + 1] = n.frontals .. " frontal(s) as pie slices" end
    if n.tethers then parts[#parts + 1] = n.tethers .. " tether(s) as lines" end
    if #parts > 0 then ns.Print("From Raidstrats: " .. table.concat(parts, ", ") .. ".") end
    if not data.found then
        ns.Print(("Raidstrats boss \"%s\" wasn't found in the journal, so the plan went on the board you had open."):format(tostring(data.boss or "?")))
    end
    if n.truncated then ns.Print(("Only the first %d scenes fit (%d dropped)."):format(ns.Model.MAX_SLIDES, n.truncated)) end
    if n.skipped then ns.Print(n.skipped .. " item(s) of an unknown type were skipped.") end
    ns.Print("Positions are placed relative to the room image. If Raidstrats used a different picture of the room, things may need nudging.")
end
