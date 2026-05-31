-- Modules/LootRules.lua
-- Loot rule state + message-fragment builder. The message fragment is what gets
-- appended to the LFM advert ("Primos Res | BoEs to Raid | MS>OS").
--
-- Every mutation fires LOOT_RULES_CHANGED so the advert rebuilds.

local WGB = _G.WGB
local L = WGB.L

local LootRules = {
    masterLoot       = false,
    lootSystem       = "MSOS",        -- "MSOS" | "SK" | "Random" | "Group" | "Custom"
    advertiseLootSystem = true,       -- include the loot system (MS>OS etc.) in the advert
    boeRule          = "raid",        -- "raid" | "reserve" | "open"
    primoSaronite    = false,
    shadowfrostShard = false,
    crusaderOrb      = false,
    runedOrb         = false,
    yoggFragment     = false,
    emblems          = "personal",
    reservedItems    = {},            -- list of { itemLink, itemName, reservedBy }
}
WGB.LootRules = LootRules

local function fire()
    WGB.Events:Fire("LOOT_RULES_CHANGED", LootRules)
end

-- Keys callers are allowed to mutate via :Set. Anything else is rejected
-- so a typo'd key can't silently create a junk field on the table.
local SETTABLE_KEYS = {
    masterLoot       = true,
    lootSystem       = true,
    advertiseLootSystem = true,
    boeRule          = true,
    primoSaronite    = true,
    shadowfrostShard = true,
    crusaderOrb      = true,
    runedOrb         = true,
    yoggFragment     = true,
    emblems          = true,
}

function LootRules:Set(key, value)
    if not SETTABLE_KEYS[key] then return end
    self[key] = value
    fire()
end

function LootRules:ApplyActivityPreset(activityId)
    local a = WGB.GetActivity(activityId)
    if not a or not a.lootPresets then return end
    -- reset commodities, then apply preset
    self.primoSaronite    = a.lootPresets.primoSaronite    and true or false
    self.shadowfrostShard = a.lootPresets.shadowfrostShard and true or false
    self.crusaderOrb      = a.lootPresets.crusaderOrb      and true or false
    self.runedOrb         = a.lootPresets.runedOrb         and true or false
    self.yoggFragment     = a.lootPresets.yoggFragment     and true or false
    self.boeRule          = a.lootPresets.boeRule or self.boeRule
    fire()
end

-- Which commodity reserves make sense for which instance. Keyed by the
-- alphabetic prefix of the activity id (icc25 -> "icc", ulduar10 -> "ulduar").
-- Anything not listed (rs, voa, onyxia, custom) has no commodity reserves.
local COMMODITY_BY_INSTANCE = {
    icc    = { primoSaronite = true, shadowfrostShard = true },
    toc    = { crusaderOrb = true },
    ulduar = { runedOrb = true, yoggFragment = true },
}

-- Returns a set { [commodityKey] = true } of the commodities relevant to the
-- currently selected activity. Used to gate both the advert fragment and which
-- checkboxes the loot panel shows, so you can't accidentally advertise Crusader
-- Orbs for an ICC raid.
function LootRules:RelevantCommodities()
    local activityId = WGB.Requirements and WGB.Requirements.activity
    local key = activityId and activityId:match("^%a+") or nil
    return (key and COMMODITY_BY_INSTANCE[key]) or {}
end

function LootRules:AddReservedItem(itemLink, reservedBy)
    if not itemLink or itemLink == "" then return false end
    local name = itemLink:match("%[(.-)%]") or itemLink
    table.insert(self.reservedItems, {
        itemLink = itemLink, itemName = name, reservedBy = reservedBy or "",
    })
    fire()
    return true
end

function LootRules:RemoveReservedItem(index)
    if self.reservedItems[index] then
        table.remove(self.reservedItems, index)
        fire()
    end
end

function LootRules:ClearReservedItems()
    wipe(self.reservedItems)
    fire()
end

-- ----------------------------------------------------------------------------
-- Message fragment.
-- Returns plain text (no color codes) so callers can colorize as they wish.
-- ----------------------------------------------------------------------------
function LootRules:GetMessageFragment()
    local parts = {}

    -- Reservation set: commodities relevant to the instance, plus BoE when its
    -- rule is "reserve". When exactly one thing is reserved we spell it out
    -- ("Primos Res"); with two or more we condense to abbreviations joined with
    -- "+" and a single trailing "Res" ("P+B+SFS Res") to keep the advert short.
    local rel = self:RelevantCommodities()
    local reserves = {}
    if self.primoSaronite    and rel.primoSaronite    then table.insert(reserves, { full = "Primos Res",         abbr = "P"     }) end
    if self.boeRule == "reserve"                      then table.insert(reserves, { full = "BoEs Res",           abbr = "B"     }) end
    if self.shadowfrostShard and rel.shadowfrostShard then table.insert(reserves, { full = "Shadowfrost Res",    abbr = "SFS"   }) end
    if self.crusaderOrb      and rel.crusaderOrb      then table.insert(reserves, { full = "Crusader Orbs Res",  abbr = "Orb"   }) end
    if self.runedOrb         and rel.runedOrb         then table.insert(reserves, { full = "Runed Orbs Res",     abbr = "RO"    }) end
    if self.yoggFragment     and rel.yoggFragment     then table.insert(reserves, { full = "Val'anyr Frags Res", abbr = "Frags" }) end

    if #reserves == 1 then
        table.insert(parts, reserves[1].full)
    elseif #reserves >= 2 then
        local abbrs = {}
        for _, r in ipairs(reserves) do table.insert(abbrs, r.abbr) end
        table.insert(parts, table.concat(abbrs, "+") .. " Res")
    end

    -- custom reserves
    if #self.reservedItems > 0 then
        local SHOW = 4
        local total = #self.reservedItems
        local shown = math.min(SHOW, total)
        local names = {}
        for i = 1, shown do
            table.insert(names, self.reservedItems[i].itemName)
        end
        if total > shown then
            table.insert(names, ("+%d more"):format(total - shown))
        end
        table.insert(parts, "SR: " .. table.concat(names, ", "))
    end

    -- BoE rule (the "reserve" case is folded into the reservation set above)
    if self.boeRule == "raid"    then table.insert(parts, "BoEs to Raid")
    elseif self.boeRule == "open"    then table.insert(parts, "Open Roll BoEs") end

    -- loot system (optional — leaders can hide it via the panel checkbox)
    if self.advertiseLootSystem then
        if     self.lootSystem == "MSOS"   then table.insert(parts, "MS>OS")
        elseif self.lootSystem == "SK"     then table.insert(parts, "Suicide Kings")
        elseif self.lootSystem == "Random" then table.insert(parts, "Random")
        elseif self.lootSystem == "Group"  then table.insert(parts, "Group Loot")
        elseif self.lootSystem == "Custom" then table.insert(parts, "Custom Loot") end
    end

    return table.concat(parts, " | ")
end
