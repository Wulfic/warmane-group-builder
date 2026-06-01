-- Modules/ActivityDB.lua
-- Static catalog of Wrath-era group/raid content. Keyed by activity ID.
-- Loot presets here are *defaults* applied when the activity is selected;
-- the leader can still toggle anything in the Loot Rules panel afterwards.

local WGB = _G.WGB

WGB.Activities = {
    -- ICC -------------------------------------------------------------
    ["icc25"] = {
        id = "icc25",
        name = "Icecrown Citadel 25",
        shortName = "ICC 25",
        maxSize = 25,
        defaultGS = 5800,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { primoSaronite = true, shadowfrostShard = false, boeRule = "raid" },
    },
    ["icc10"] = {
        id = "icc10",
        name = "Icecrown Citadel 10",
        shortName = "ICC 10",
        maxSize = 10,
        defaultGS = 5500,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { primoSaronite = true, shadowfrostShard = false, boeRule = "raid" },
    },

    -- ToC -------------------------------------------------------------
    ["toc25"] = {
        id = "toc25",
        name = "Trial of the Crusader 25",
        shortName = "ToC 25",
        maxSize = 25,
        defaultGS = 5200,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { crusaderOrb = true, boeRule = "raid" },
    },
    ["toc10"] = {
        id = "toc10",
        name = "Trial of the Crusader 10",
        shortName = "ToC 10",
        maxSize = 10,
        defaultGS = 5000,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { crusaderOrb = true, boeRule = "raid" },
    },

    -- Ulduar ----------------------------------------------------------
    ["ulduar25"] = {
        id = "ulduar25",
        name = "Ulduar 25",
        shortName = "Uld 25",
        maxSize = 25,
        defaultGS = 4800,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { runedOrb = true, yoggFragment = false, boeRule = "raid" },
    },
    ["ulduar10"] = {
        id = "ulduar10",
        name = "Ulduar 10",
        shortName = "Uld 10",
        maxSize = 10,
        defaultGS = 4600,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { runedOrb = true, boeRule = "raid" },
    },

    -- Ruby Sanctum ---------------------------------------------------
    ["rs25"] = {
        id = "rs25", name = "Ruby Sanctum 25", shortName = "RS 25",
        maxSize = 25, defaultGS = 5800,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { boeRule = "raid" },
    },
    ["rs10"] = {
        id = "rs10", name = "Ruby Sanctum 10", shortName = "RS 10",
        maxSize = 10, defaultGS = 5500,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { boeRule = "raid" },
    },

    -- VoA -------------------------------------------------------------
    ["voa25"] = {
        id = "voa25", name = "Vault of Archavon 25", shortName = "VoA 25",
        maxSize = 25, defaultGS = 4500,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { boeRule = "raid" },
    },
    ["voa10"] = {
        id = "voa10", name = "Vault of Archavon 10", shortName = "VoA 10",
        maxSize = 10, defaultGS = 4200,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { boeRule = "raid" },
    },

    -- Misc -----------------------------------------------------------
    ["onyxia25"] = {
        id = "onyxia25", name = "Onyxia 25", shortName = "Ony 25",
        maxSize = 25, defaultGS = 4500,
        defaultRoles = { tank = 2, heal = 5, rdps = 9, mdps = 9 },
        lootPresets = { boeRule = "raid" },
    },
    ["onyxia10"] = {
        id = "onyxia10", name = "Onyxia 10", shortName = "Ony 10",
        maxSize = 10, defaultGS = 4200,
        defaultRoles = { tank = 2, heal = 3, rdps = 3, mdps = 2 },
        lootPresets = { boeRule = "raid" },
    },

    ["custom"] = {
        id = "custom", name = "Custom", shortName = "Custom",
        maxSize = 25, defaultGS = 0,
        defaultRoles = { tank = 0, heal = 0, rdps = 0, mdps = 0 },
        lootPresets = { boeRule = "raid" },
    },
}

-- Order in which activities should appear in dropdowns.
WGB.ActivityOrder = {
    "icc25", "icc10",
    "toc25", "toc10",
    "ulduar25", "ulduar10",
    "rs25", "rs10",
    "voa25", "voa10",
    "onyxia25", "onyxia10",
    "custom",
}

-- Boss progression per base zone (the 10 / 25 variants share a list). Used by
-- the refill flow to tag the advert with the boss the group is currently on.
WGB.ActivityBosses = {
    icc = {
        "Marrowgar", "Deathwhisper", "Gunship", "Saurfang",
        "Festergut", "Rotface", "Putricide",
        "Blood Princes", "Lana'thel", "Valithria", "Sindragosa", "Lich King",
    },
    toc = { "Beasts", "Jaraxxus", "Faction Champs", "Twin Val'kyr", "Anub'arak" },
    ulduar = {
        "Flame Leviathan", "Razorscale", "Ignis", "XT-002", "Assembly",
        "Kologarn", "Auriaya", "Hodir", "Thorim", "Freya", "Mimiron",
        "Vezax", "Yogg-Saron", "Algalon",
    },
    rs = { "Baltharus", "Saviana", "Zarithrian", "Halion" },
    voa = { "Archavon", "Emalon", "Koralon", "Toravon" },
    onyxia = { "Onyxia" },
}

-- ----------------------------------------------------------------------------
-- Class / spec catalog (Wrath 3.3.5a). Used by the advanced raid-comp builder
-- in the Requirements panel and by the advert's compact spec fragment.
-- ----------------------------------------------------------------------------
WGB.ClassSpecs = {
    WARRIOR     = { "Arms", "Fury", "Protection" },
    PALADIN     = { "Holy", "Protection", "Retribution" },
    HUNTER      = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE       = { "Assassination", "Combat", "Subtlety" },
    PRIEST      = { "Discipline", "Holy", "Shadow" },
    DEATHKNIGHT = { "Blood", "Frost", "Unholy" },
    SHAMAN      = { "Elemental", "Enhancement", "Restoration" },
    MAGE        = { "Arcane", "Fire", "Frost" },
    WARLOCK     = { "Affliction", "Demonology", "Destruction" },
    DRUID       = { "Balance", "Feral", "Restoration" },
}

-- Dropdown order for the comp builder.
WGB.ClassOrder = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

-- Compact class labels for the advert spec fragment ("1 Holy Pal/2 Resto Sham").
local CLASS_SHORT = {
    WARRIOR = "War", PALADIN = "Pal", HUNTER = "Hunt", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "DK", SHAMAN = "Sham", MAGE = "Mage",
    WARLOCK = "Lock", DRUID = "Druid",
}

-- Human-readable class label for dropdowns (Title Case from the token).
local CLASS_LABEL = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman",
    MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

function WGB.ClassShort(class)
    return CLASS_SHORT[class] or class or "?"
end

function WGB.ClassLabel(class)
    return CLASS_LABEL[class] or class or "?"
end

-- Deterministic role bucket (tank/heal/mdps/rdps) for an explicitly chosen
-- class+spec pair in the comp builder. Unlike GroupManager.inferRole (which
-- works off live inspect data and form heuristics), here the user has named the
-- spec, so we map it directly. Mirrors the same buckets the advert/roster use.
local COMP_SPEC_ROLE = {
    WARRIOR     = { Arms = "mdps", Fury = "mdps", Protection = "tank" },
    PALADIN     = { Holy = "heal", Protection = "tank", Retribution = "mdps" },
    HUNTER      = { ["Beast Mastery"] = "rdps", Marksmanship = "rdps", Survival = "rdps" },
    ROGUE       = { Assassination = "mdps", Combat = "mdps", Subtlety = "mdps" },
    PRIEST      = { Discipline = "heal", Holy = "heal", Shadow = "rdps" },
    DEATHKNIGHT = { Blood = "tank", Frost = "mdps", Unholy = "mdps" },
    SHAMAN      = { Elemental = "rdps", Enhancement = "mdps", Restoration = "heal" },
    MAGE        = { Arcane = "rdps", Fire = "rdps", Frost = "rdps" },
    WARLOCK     = { Affliction = "rdps", Demonology = "rdps", Destruction = "rdps" },
    DRUID       = { Balance = "rdps", Feral = "mdps", Restoration = "heal" },
}

function WGB.CompSpecRole(class, spec)
    local byClass = class and COMP_SPEC_ROLE[class] or nil
    return (byClass and byClass[spec]) or "mdps"
end

-- ----------------------------------------------------------------------------
-- Off-spec gear detection. Classifies an equipped item into a broad gear
-- "archetype" from its stats, and classifies a player's spec into a gear
-- "intent" (which archetypes they SHOULD be wearing). A mismatch means the
-- player is wearing gear meant for a different role — e.g. a tank in healer
-- gear, or a DPS in tank gear.
-- ----------------------------------------------------------------------------

-- GetItemStats keys grouped by the archetype they signal. Neutral stats shared
-- by everyone (stamina, hit, crit, haste, resilience, armor) are intentionally
-- omitted: they never indicate a role on their own.
local ARCHETYPE_STATS = {
    -- Caster / healer: spell power, spirit, mana regen. Intellect is omitted on
    -- purpose — hunters stack intellect for mana, so it is not a clean caster
    -- signal; spell power / spirit / mp5 are.
    spell = {
        "ITEM_MOD_SPELL_POWER",
        "ITEM_MOD_SPELL_DAMAGE_DONE",
        "ITEM_MOD_SPELL_HEALING_DONE",
        "ITEM_MOD_SPIRIT_SHORT",
        "ITEM_MOD_MANA_REGENERATION",
    },
    -- Tank: avoidance / mitigation that only a tank itemizes for.
    tank = {
        "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
        "ITEM_MOD_DODGE_RATING_SHORT",
        "ITEM_MOD_PARRY_RATING_SHORT",
        "ITEM_MOD_BLOCK_RATING_SHORT",
        "ITEM_MOD_BLOCK_VALUE",
    },
    -- Physical DPS (melee or ranged): str/agi/AP plus melee-only ratings.
    physical = {
        "ITEM_MOD_STRENGTH_SHORT",
        "ITEM_MOD_AGILITY_SHORT",
        "ITEM_MOD_ATTACK_POWER",
        "ITEM_MOD_RANGED_ATTACK_POWER",
        "ITEM_MOD_EXPERTISE_RATING_SHORT",
        "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    },
}

-- Priority is spell > tank > physical: a spell-power piece never carries
-- str/agi, and a threat-plate tank piece often has BOTH strength and defense —
-- its defining stat is the tank avoidance, so tank must win over physical.
local ARCHETYPE_ORDER = { "spell", "tank", "physical" }

local ARCHETYPE_LABEL = {
    spell    = "caster/healer gear",
    tank     = "tank gear",
    physical = "melee/physical gear",
}

function WGB.ArchetypeLabel(a)
    return ARCHETYPE_LABEL[a] or a or "?"
end

-- Returns "spell" | "tank" | "physical" | nil for an item link. nil means the
-- item carries no role-defining stat (pure stamina, resist, proc-only, a relic,
-- etc.) and is never flagged as off-spec.
function WGB.ItemArchetype(itemLink)
    if not itemLink then return nil end
    local stats = GetItemStats and GetItemStats(itemLink) or nil
    if not stats then return nil end
    for _, arche in ipairs(ARCHETYPE_ORDER) do
        for _, key in ipairs(ARCHETYPE_STATS[arche]) do
            local v = stats[key]
            if v and v ~= 0 then return arche end
        end
    end
    return nil
end

-- The set of gear archetypes each "intent" SHOULD be wearing. Anything NOT in
-- the accept set is flagged off-spec. Dual-role intents (Feral, any DK) accept
-- BOTH physical and tank so we don't false-flag a bear tank's threat gear or a
-- DK who tanks. Pure roles are stricter.
local INTENT_ACCEPT = {
    spellUser    = { spell = true },                  -- healers + caster dps
    physicalPure = { physical = true },               -- rogue, arms/fury, ret, enh, hunter
    tankPure     = { tank = true, physical = true },  -- prot warrior / prot paladin
    hybridMelee  = { physical = true, tank = true },  -- feral, DK, unknown plate/melee
}

-- spec tab name -> intent, by class. A spec missing here => unknown intent.
local SPEC_INTENT = {
    WARRIOR     = { Arms = "physicalPure", Fury = "physicalPure", Protection = "tankPure" },
    PALADIN     = { Holy = "spellUser", Protection = "tankPure", Retribution = "physicalPure" },
    HUNTER      = { ["Beast Mastery"] = "physicalPure", Marksmanship = "physicalPure", Survival = "physicalPure" },
    ROGUE       = { Assassination = "physicalPure", Combat = "physicalPure", Subtlety = "physicalPure" },
    PRIEST      = { Discipline = "spellUser", Holy = "spellUser", Shadow = "spellUser" },
    DEATHKNIGHT = { Blood = "hybridMelee", Frost = "hybridMelee", Unholy = "hybridMelee" },
    SHAMAN      = { Elemental = "spellUser", Enhancement = "physicalPure", Restoration = "spellUser" },
    MAGE        = { Arcane = "spellUser", Fire = "spellUser", Frost = "spellUser" },
    WARLOCK     = { Affliction = "spellUser", Demonology = "spellUser", Destruction = "spellUser" },
    -- The Feral tab reads "Feral Combat" on some cores, "Feral" on others.
    DRUID       = { Balance = "spellUser", Feral = "hybridMelee",
                    ["Feral Combat"] = "hybridMelee", Restoration = "spellUser" },
}

-- Class fallback when the spec is unknown / not yet dominant. Only set where we
-- can be confident regardless of tree; ambiguous classes (paladin, shaman,
-- druid) are left nil so we never guess and false-flag.
local CLASS_INTENT_FALLBACK = {
    MAGE = "spellUser", WARLOCK = "spellUser", PRIEST = "spellUser",
    HUNTER = "physicalPure", ROGUE = "physicalPure",
    DEATHKNIGHT = "hybridMelee", WARRIOR = "hybridMelee",
}

-- Returns acceptSet, intentName for a player's class + inspection result.
-- acceptSet is nil when intent is unknown (caller should flag nothing).
function WGB.GearIntent(class, result)
    if not class then return nil, nil end
    local spec = result and result.spec or nil
    -- Only trust the named spec if there is a dominant (>=51 pt) tree; mirrors
    -- GroupManager's role inference so a half-specced char isn't misjudged.
    if result and result.dominantSpec == false then spec = nil end
    local intent
    if spec and SPEC_INTENT[class] then
        intent = SPEC_INTENT[class][spec]
    end
    if not intent then intent = CLASS_INTENT_FALLBACK[class] end
    if not intent then return nil, nil end
    return INTENT_ACCEPT[intent], intent
end

-- ----------------------------------------------------------------------------
-- Armor-type proficiency check. Distinct from the stat-archetype check above:
-- this catches a class wearing a LOWER armor class than it should (a paladin in
-- cloth/leather, a hunter in leather, etc.) regardless of the stats on it.
-- ----------------------------------------------------------------------------
local ARMOR_TIER  = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }

-- Highest armor type each class wears at max level.
local CLASS_ARMOR = {
    WARRIOR = "Plate", PALADIN = "Plate", DEATHKNIGHT = "Plate",
    HUNTER  = "Mail",  SHAMAN  = "Mail",
    ROGUE   = "Leather", DRUID = "Leather",
    MAGE    = "Cloth", PRIEST = "Cloth", WARLOCK = "Cloth",
}

-- Classes that routinely itemize with a lower armor type and should NOT be
-- flagged for it (warriors commonly wear leather/mail pieces with the right
-- stats). They are STILL flagged for cloth, which is never correct.
local ARMOR_LENIENT = { WARRIOR = true }

-- Returns "Cloth"|"Leather"|"Mail"|"Plate" for a body-armor item, else nil.
-- NOTE: cloaks report subtype "Cloth" and rings/necks/trinkets report
-- "Miscellaneous"; callers must only pass the 8 main armor slots so those never
-- reach here and false-flag every plate wearer's cloth cloak.
function WGB.ItemArmorType(itemLink)
    if not itemLink then return nil end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if itemType ~= "Armor" then return nil end
    if ARMOR_TIER[itemSubType] then return itemSubType end
    return nil
end

-- True when `armorType` is below what `class` should wear. Also returns the
-- class's expected (max) armor type for messaging. Honors ARMOR_LENIENT.
function WGB.WrongArmorType(class, armorType)
    if not class or not armorType then return false, nil end
    local expected = CLASS_ARMOR[class]
    if not expected then return false, nil end
    local want, have = ARMOR_TIER[expected], ARMOR_TIER[armorType]
    if not (want and have) then return false, expected end
    if have >= want then return false, expected end           -- correct type
    if ARMOR_LENIENT[class] and armorType ~= "Cloth" then
        return false, expected                                 -- lenient downgrade
    end
    return true, expected
end

function WGB.GetActivity(id)
    return WGB.Activities[id]
end

-- Bosses for an activity id (10/25 variants resolve to the same base list).
function WGB.GetBosses(id)
    local base = id and id:gsub("%d+$", "") or ""
    return WGB.ActivityBosses[base] or {}
end

function WGB.ListActivities()
    local out = {}
    for _, id in ipairs(WGB.ActivityOrder) do
        local a = WGB.Activities[id]
        if a then
            table.insert(out, { id = id, name = a.name, shortName = a.shortName })
        end
    end
    return out
end
