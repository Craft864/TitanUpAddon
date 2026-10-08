-- Titan Up - Report/Defensives.lua
-- The personal defensives the Pull Report checks, by class (reviewed list:
-- the guild's Class Info sheet cross-checked against Open Raid Library's
-- Midnight data and Wowhead). Each entry: spell IDs (alternatives - talent
-- replacements and spec versions - in one entry, counted once), a name for
-- the report, and a tier: "major" drives the green light, "minor" the
-- yellow. Spells a player doesn't know are simply skipped - no errors.
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
        { ids = { 198589 }, name = "Blur", tier = "major" },
        { ids = { 196555 }, name = "Netherwalk", tier = "major" },
    },
    DRUID = {
        { ids = { 22812 }, name = "Barkskin", tier = "major" },
        { ids = { 61336 }, name = "Survival Instincts", tier = "major" },
        { ids = { 108238 }, name = "Renewal", tier = "minor" },
        { ids = { 22842 }, name = "Frenzied Regeneration", tier = "minor" },
    },
    EVOKER = {
        { ids = { 363916 }, name = "Obsidian Scales", tier = "major" },
        { ids = { 374348 }, name = "Renewing Blaze", tier = "major" },
    },
    HUNTER = {
        { ids = { 186265 }, name = "Aspect of the Turtle", tier = "major" },
        { ids = { 264735 }, name = "Survival of the Fittest", tier = "major" },
        { ids = { 109304 }, name = "Exhilaration", tier = "major" },
    },
    MAGE = {
        { ids = { 45438, 414658 }, name = "Ice Block / Ice Cold", tier = "major" },   -- Ice Cold replaces Ice Block
        { ids = { 110959 }, name = "Greater Invisibility", tier = "major" },
        { ids = { 235450, 235313, 11426 }, name = "Barrier", tier = "minor" },        -- Prismatic / Blazing / Ice
        { ids = { 55342 }, name = "Mirror Image", tier = "minor" },
        { ids = { 235219 }, name = "Cold Snap", tier = "minor" },
        { ids = { 342245 }, name = "Alter Time", tier = "minor" },
    },
    MONK = {
        { ids = { 243435 }, name = "Fortifying Brew", tier = "major" },
        { ids = { 122470 }, name = "Touch of Karma", tier = "major" },
        { ids = { 122278 }, name = "Dampen Harm", tier = "major" },
        { ids = { 122783 }, name = "Diffuse Magic", tier = "major" },
    },
    PALADIN = {
        { ids = { 642 }, name = "Divine Shield", tier = "major" },
        { ids = { 498, 403876 }, name = "Divine Protection", tier = "major" },        -- Holy / Ret versions
        { ids = { 184662 }, name = "Shield of Vengeance", tier = "major" },
        { ids = { 205191 }, name = "Eye for an Eye", tier = "minor" },
    },
    PRIEST = {
        { ids = { 47585 }, name = "Dispersion", tier = "major" },
        { ids = { 19236 }, name = "Desperate Prayer", tier = "major" },
        { ids = { 586 }, name = "Fade", tier = "minor" },
    },
    ROGUE = {
        { ids = { 31224 }, name = "Cloak of Shadows", tier = "major" },
        { ids = { 5277, 199754 }, name = "Evasion / Riposte", tier = "major" },       -- Riposte is Outlaw's
        { ids = { 1966 }, name = "Feint", tier = "minor" },
        { ids = { 185311 }, name = "Crimson Vial", tier = "minor" },
    },
    SHAMAN = {
        { ids = { 108271 }, name = "Astral Shift", tier = "major" },
        { ids = { 108270 }, name = "Stone Bulwark Totem", tier = "major" },
        { ids = { 198103 }, name = "Earth Elemental", tier = "major" },          -- with its talent: +20% max health
    },
    WARLOCK = {
        { ids = { 104773 }, name = "Unending Resolve", tier = "major" },
        { ids = { 108416 }, name = "Dark Pact", tier = "major" },
        { ids = { 6789 }, name = "Mortal Coil", tier = "minor" },
    },
    WARRIOR = {
        { ids = { 118038 }, name = "Die by the Sword", tier = "major" },
        { ids = { 184364 }, name = "Enraged Regeneration", tier = "major" },
        { ids = { 383762 }, name = "Bitter Immunity", tier = "major" },
        { ids = { 23920 }, name = "Spell Reflection", tier = "minor" },
        { ids = { 202168 }, name = "Impending Victory", tier = "minor" },
    },
}

-- Cheat-death saves, recognised by the debuff (or buff) they leave on you,
-- by name. If a name doesn't match in game, that save just isn't reported.
D.CHEAT_DEATHS = {
    ROGUE = { { aura = "Cheated Death", name = "Cheat Death" } },
    MAGE = { { aura = "Cauterized", name = "Cauterize" } },
    EVOKER = { { aura = "Defy Fate", name = "Defy Fate" } },
    WARRIOR = { { aura = "Kill or Be Killed", name = "Kill or Be Killed" } },
}

-- Consumables, found in your bags by name (every quality counts).
D.HEALTH_POTIONS = ns.RaidCheck.HEALTH_POTIONS        -- one list, Raid Check's (update it each tier)
D.HEALTHSTONES = { "Healthstone", "Demonic Healthstone" }
