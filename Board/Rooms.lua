-- TitanBoard - Rooms.lua
-- CUSTOM BOSS ROOM IMAGES
--
-- By default the board shows Blizzard's own map art for the boss's floor.
-- An encounter can instead have one or more custom images; when it has
-- several (phases, different rooms), each SLIDE picks which one it shows
-- with the "Room" button above the map.
--
-- To add your own:
--   1. Put the image in  Interface\AddOns\TitanBoard\Media\Rooms\
--      The bundled rooms are .blp (WoW's compressed format, ~1.4 MB each);
--      an uncompressed .tga also works, it's just ~4x bigger. Make the FILE
--      2048x1024 (or another power of two), put the art in the top-left
--      corner, and give the real art size as width/height below. Paths
--      have no extension - the game finds the .blp or .tga itself.
--   2. Open the board on that boss and type /tb ids for its encounter ID.
--   3. Add an entry below, then /reload.
--
-- Each image: key (short, letters/digits only - it's saved in plans),
-- label (shown in the Room menu), file, width, height, texWidth, texHeight.
--
-- Drawings are stored relative to the background they were drawn on, so
-- changing a slide's room means re-placing what's on it.
local ADDON, ns = ...

local PATH = ns.MEDIA .. "Rooms\\"
local function img(key, label, file, w, h)
    return { key = key, label = label, file = PATH .. file, width = w, height = h, texWidth = 2048, texHeight = 1024 }
end

local ROOMS = {
    -- The Venomous Abyss
    [2871] = { img("arena", "Arena", "Sszorak", 1794, 1006) },              -- Sszorak
    [2887] = { img("arena", "Arena", "TwinFangs", 1798, 1005) },            -- The Twin Fangs
    [2883] = { img("arena", "Arena", "CoiledAltar", 1752, 1009) },          -- The Coiled Altar
    [2895] = {                                                              -- Ula'tek
        img("p1", "P1", "Ulatek_P1", 1797, 1009),
        img("p2left", "P2 Left", "Ulatek_P2Left", 1798, 1002),
        img("p2right", "P2 Right", "Ulatek_P2Right", 1801, 1011),
        img("p3", "P3", "Ulatek_P3", 1801, 1005),
    },
}

-- Sample image used by /tb testroom so you can try custom rooms anywhere.
local TEST_ROOM = { key = "test", label = "Test arena", file = PATH .. "TestArena", width = 512, height = 512, texWidth = 512, texHeight = 512 }

local Rooms = {}
ns.Rooms = Rooms

-- Images available for this encounter (may be empty).
function Rooms:List(ctx)
    local list = ctx and ((ctx.enc and ROOMS[ctx.enc]) or (ctx.map and ROOMS["map:" .. ctx.map]))
    if not list then return {} end
    if list.file then list = { list } end   -- single image written as one table
    for i, r in ipairs(list) do
        r.key = r.key or ("img" .. i)
        r.label = r.label or ("Image " .. i)
        r.texWidth = r.texWidth or r.width
        r.texHeight = r.texHeight or r.height
    end
    return list
end

-- The image a slide shows. bg: a room key, "map" for Blizzard's map, or
-- nil for the encounter's default (its first custom image, if any).
function Rooms:Get(ctx, bg)
    if ns.testRoom then return TEST_ROOM end
    if bg == "map" then return nil end
    local list = self:List(ctx)
    for _, r in ipairs(list) do
        if r.key == bg then return r end
    end
    return list[1]
end
