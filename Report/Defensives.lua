-- Titan Up - Report/Defensives.lua
-- The personal defensives the Pull Report checks, by class (reviewed list:
-- the guild's Class Info sheet cross-checked against Open Raid Library's
-- Midnight data and Wowhead). Each entry: spell IDs (alternatives - talent
-- replacements and spec versions - in one entry, counted once), a name for
-- the report, and a tier: "major" drives the green light, "minor" the
-- yellow. Spells a player doesn't know are simply skipped - no errors.
-- "requires" = a talent that must be known too for the entry to count.
-- Spell IDs checked against the 12.1.5 game data for 0.29.2.
-- Tanks are skipped entirely.
local ADDON, ns = ...

ns.ReportData = {}
local D = ns.ReportData

D.DEFENSIVES = {
    DEATHKNIGHT = {
        { ids = { 48792 }, name = "Icebound Fortitude", tier = "major" },
        { ids = { 48707 }, name = "Anti-Magic Shell", tier = "major" },
        { ids = { 48743 }, name = "Death Pact", tier = "major" },
        { ids = { 49039 }, name = "Lichborne", tier = "minor" },
    },
    DEMONHUNTER = {
        { ids = { 198589 }, name = "Blur", tier = "major" },                  -- Havoc and Devourer
    },
    DRUID = {
        { ids = { 22812 }, name = "Barkskin", tier = "major" },
        { ids = { 61336 }, name = "Survival Instincts", tier = "major" },
        { ids = { 102342 }, name = "Ironbark", tier = "major" },              -- Restoration, cast on yourself
        { ids = { 22842 }, name = "Frenzied Regeneration", tier = "minor" },
    },
    EVOKER = {
        { ids = { 363916 }, name = "Obsidian Scales", tier = "major" },       -- Renewing Blaze is a passive on it now
    },
    HUNTER = {
        { ids = { 186265 }, name = "Aspect of the Turtle", tier = "major" },
        { ids = { 264735 }, name = "Survival of the Fittest", tier = "major" },
        { ids = { 109304 }, name = "Exhilaration", tier = "major" },
    },
    MAGE = {
        { ids = { 45438, 414658 }, name = "Ice Block / Ice Cold", tier = "major" },   -- Ice Cold replaces Ice Block
        { ids = { 235450, 235313, 11426 }, name = "Barrier", tier = "minor" },        -- Prismatic / Blazing / Ice
        { ids = { 55342 }, name = "Mirror Image", tier = "minor" },
        { ids = { 235219 }, name = "Cold Snap", tier = "minor" },
        { ids = { 342245 }, name = "Alter Time", tier = "minor" },
    },
    MONK = {
        { ids = { 115203 }, name = "Fortifying Brew", tier = "major" },       -- Diffuse Magic is a passive on it now
        { ids = { 122470 }, name = "Touch of Karma", tier = "major" },
        { ids = { 116849 }, name = "Life Cocoon", tier = "major" },           -- Mistweaver, cast on yourself
    },
    PALADIN = {
        { ids = { 642 }, name = "Divine Shield", tier = "major" },
        { ids = { 498, 403876 }, name = "Divine Protection", tier = "major" },        -- Holy / Ret versions
        { ids = { 1022 }, name = "Blessing of Protection", tier = "major" },
        { ids = { 633 }, name = "Lay on Hands", tier = "major" },
    },
    PRIEST = {
        { ids = { 47585 }, name = "Dispersion", tier = "major" },
        { ids = { 19236 }, name = "Desperate Prayer", tier = "major" },
        { ids = { 33206 }, name = "Pain Suppression", tier = "major" },       -- Discipline, cast on yourself
        { ids = { 47788 }, name = "Guardian Spirit", tier = "major" },        -- Holy, cast on yourself
        { ids = { 586 }, name = "Fade", tier = "minor" },
    },
    ROGUE = {
        { ids = { 31224 }, name = "Cloak of Shadows", tier = "major" },
        { ids = { 5277 }, name = "Evasion", tier = "major" },
        { ids = { 1966 }, name = "Feint", tier = "minor" },
        { ids = { 185311 }, name = "Crimson Vial", tier = "minor" },
    },
    SHAMAN = {
        { ids = { 108271 }, name = "Astral Shift", tier = "major" },
        { ids = { 198103 }, name = "Earth Elemental", tier = "minor", requires = 1279819 },   -- only with Primordial Bond (+max health)
    },
    WARLOCK = {
        { ids = { 104773 }, name = "Unending Resolve", tier = "major" },
        { ids = { 108416 }, name = "Dark Pact", tier = "major" },
        { ids = { 6789 }, name = "Mortal Coil", tier = "minor" },
    },
    WARRIOR = {
        { ids = { 118038 }, name = "Die by the Sword", tier = "major" },
        { ids = { 184364 }, name = "Enraged Regeneration", tier = "major" },
        { ids = { 23920 }, name = "Spell Reflection", tier = "minor" },
        { ids = { 202168 }, name = "Impending Victory", tier = "minor" },
        { ids = { 1277297 }, name = "Ignore Pain", tier = "minor" },          -- Arms
        { ids = { 97462 }, name = "Rallying Cry", tier = "minor" },
    },
}

-- Cheat-death saves, recognised by the debuff (or buff) they leave on you,
-- by name. If a name doesn't match in game, that save just isn't reported.
D.CHEAT_DEATHS = {
    ROGUE = { { aura = "Cheated Death", name = "Cheat Death" } },
    MAGE = { { aura = "Cauterized", name = "Cauterize" } },
    EVOKER = { { aura = "Empty Hourglass", name = "Defy Fate" } },     -- Defy Fate's lockout debuff
    WARRIOR = { { aura = "Kill or Be Killed", name = "Kill or Be Killed" } },
}

-- Consumables, found in your bags by name (every quality counts).
D.HEALTH_POTIONS = ns.RaidCheck.HEALTH_POTIONS        -- one list, Raid Check's (update it each tier)
D.HEALTHSTONES = { "Healthstone", "Demonic Healthstone" }
