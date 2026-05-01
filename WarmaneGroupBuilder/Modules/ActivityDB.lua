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

function WGB.GetActivity(id)
    return WGB.Activities[id]
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
