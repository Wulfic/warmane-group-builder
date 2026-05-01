-- Modules/LootRules.lua
-- Loot rule state + message-fragment builder. The message fragment is what gets
-- appended to the LFM advert ("Primos Res | BoEs to Raid | MS>OS").
--
-- Every mutation fires LOOT_RULES_CHANGED so the advert rebuilds.

local WGB = _G.WGB
local L = WGB.L

local LootRules = {
    masterLoot       = false,
    lootSystem       = "MSOS",        -- "MSOS" | "SK" | "Random" | "Custom"
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

    -- commodity reservations
    if self.primoSaronite    then table.insert(parts, "Primos Res") end
    if self.shadowfrostShard then table.insert(parts, "Shadowfrost Res") end
    if self.crusaderOrb      then table.insert(parts, "Crusader Orbs Res") end
    if self.runedOrb         then table.insert(parts, "Runed Orbs Res") end
    if self.yoggFragment     then table.insert(parts, "Val'anyr Frags Res") end

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

    -- BoE rule
    if self.boeRule == "raid"    then table.insert(parts, "BoEs to Raid")
    elseif self.boeRule == "reserve" then table.insert(parts, "BoEs Res")
    elseif self.boeRule == "open"    then table.insert(parts, "Open Roll BoEs") end

    -- loot system
    if     self.lootSystem == "MSOS"   then table.insert(parts, "MS>OS")
    elseif self.lootSystem == "SK"     then table.insert(parts, "Suicide Kings")
    elseif self.lootSystem == "Random" then table.insert(parts, "Random")
    elseif self.lootSystem == "Custom" then table.insert(parts, "Custom Loot") end

    return table.concat(parts, " | ")
end
