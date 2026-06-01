-- Modules/Requirements.lua
-- Group requirement state machine. All mutation goes through setters; setters fire
-- REQUIREMENTS_CHANGED so UI / Advertisement / GroupManager rebuild themselves.

local WGB = _G.WGB

local Requirements = {
    activity              = nil,    -- activity id
    customName            = "",     -- used when activity == "custom"
    refillMode            = false,  -- group already running; advertise to refill
    currentBoss           = "",     -- boss the group is on (shown when refilling)
    roles                 = { tank = 0, heal = 0, rdps = 0, mdps = 0 },
    filled                = { tank = 0, heal = 0, rdps = 0, mdps = 0 },
    minGS                 = 0,
    requireFullGems       = false,
    requireFullEnchants   = false,
    noPvPGear             = false,
    flagOffSpecGear       = true,    -- warn when a player wears gear for another role
    requireAchievement    = false,   -- require the raid-completion achievement for the activity
    advancedComp          = false,   -- show the class/spec comp builder + advertise specs
    compThreshold         = 0.5,     -- start advertising specific specs once >= this fraction filled
    specRequirements      = {},     -- { {class="PALADIN", spec="Holy", count=1}, ... }
    specFilled            = {},     -- ["CLASS|Spec"] = count currently in the raid
}
WGB.Requirements = Requirements

local function fire()
    WGB.Events:Fire("REQUIREMENTS_CHANGED", Requirements)
end

function Requirements:ApplyActivityDefaults(activityId)
    local a = WGB.GetActivity(activityId)
    if not a then return end
    self.activity = activityId
    self.roles = {
        tank = a.defaultRoles.tank or 0,
        heal = a.defaultRoles.heal or 0,
        rdps = a.defaultRoles.rdps or 0,
        mdps = a.defaultRoles.mdps or 0,
    }
    self.minGS = a.defaultGS or 0
    self.currentBoss = ""
    self.specRequirements = {}
    self.specFilled = {}
    fire()
end

function Requirements:SetRole(role, count)
    if not self.roles[role] then return end
    count = tonumber(count) or 0
    if count < 0 then count = 0 end
    -- clamp to activity max
    local a = self.activity and WGB.GetActivity(self.activity) or nil
    if a and a.maxSize and count > a.maxSize then count = a.maxSize end
    self.roles[role] = count
    fire()
end

function Requirements:SetMinGS(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 6500 then value = 6500 end
    self.minGS = value
    fire()
end

function Requirements:SetFlag(flag, value)
    if flag == "requireFullGems" or flag == "requireFullEnchants"
        or flag == "noPvPGear" or flag == "flagOffSpecGear"
        or flag == "requireAchievement" then
        self[flag] = value and true or false
        fire()
    end
end

function Requirements:AddSpecRequirement(class, spec, count)
    table.insert(self.specRequirements, { class = class, spec = spec, count = tonumber(count) or 1 })
    fire()
end

function Requirements:RemoveSpecRequirement(index)
    table.remove(self.specRequirements, index)
    fire()
end

function Requirements:SetAdvancedComp(value)
    self.advancedComp = value and true or false
    fire()
end

function Requirements:SetCustomName(name)
    self.customName = name or ""
    fire()
end

function Requirements:SetRefillMode(value)
    self.refillMode = value and true or false
    fire()
end

function Requirements:SetCurrentBoss(name)
    self.currentBoss = name or ""
    fire()
end

-- ----------------------------------------------------------------------------
-- Named raid-comp presets (saved across sessions in WGB_Settings.compPresets).
-- A preset is a full snapshot of the requirement state so loading it recreates
-- the activity, role counts, GS floor, gear flags and the advanced class/spec
-- list exactly. `filled`/`specFilled` are live roster data and are NOT saved.
-- ----------------------------------------------------------------------------
local function presetStore()
    if not WGB_Settings then return nil end
    WGB_Settings.compPresets = WGB_Settings.compPresets or {}
    return WGB_Settings.compPresets
end

function Requirements:SavePreset(name)
    name = name and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false end
    local store = presetStore()
    if not store then return false end
    local specs = {}
    for _, sr in ipairs(self.specRequirements) do
        table.insert(specs, { class = sr.class, spec = sr.spec, count = sr.count or 1 })
    end
    store[name] = {
        activity            = self.activity,
        customName          = self.customName or "",
        roles               = { tank = self.roles.tank or 0, heal = self.roles.heal or 0,
                                 rdps = self.roles.rdps or 0, mdps = self.roles.mdps or 0 },
        minGS               = self.minGS or 0,
        requireFullGems     = self.requireFullGems and true or false,
        requireFullEnchants = self.requireFullEnchants and true or false,
        noPvPGear           = self.noPvPGear and true or false,
        flagOffSpecGear     = self.flagOffSpecGear and true or false,
        requireAchievement  = self.requireAchievement and true or false,
        advancedComp        = self.advancedComp and true or false,
        specRequirements    = specs,
    }
    return true
end

function Requirements:LoadPreset(name)
    local store = presetStore()
    local p = store and store[name] or nil
    if not p then return false end
    self.activity            = p.activity
    self.customName          = p.customName or ""
    self.roles               = { tank = (p.roles and p.roles.tank) or 0,
                                 heal = (p.roles and p.roles.heal) or 0,
                                 rdps = (p.roles and p.roles.rdps) or 0,
                                 mdps = (p.roles and p.roles.mdps) or 0 }
    self.minGS               = p.minGS or 0
    self.requireFullGems     = p.requireFullGems and true or false
    self.requireFullEnchants = p.requireFullEnchants and true or false
    self.noPvPGear           = p.noPvPGear and true or false
    -- Older presets predate this flag; default it ON when absent.
    if p.flagOffSpecGear == nil then
        self.flagOffSpecGear = true
    else
        self.flagOffSpecGear = p.flagOffSpecGear and true or false
    end
    -- Older presets predate this flag; default it OFF when absent.
    self.requireAchievement  = p.requireAchievement and true or false
    self.advancedComp        = p.advancedComp and true or false
    self.specRequirements    = {}
    for _, sr in ipairs(p.specRequirements or {}) do
        table.insert(self.specRequirements, { class = sr.class, spec = sr.spec, count = sr.count or 1 })
    end
    self.specFilled = {}
    -- Loading a comp also realigns the loot preset to the new activity.
    if self.activity and WGB.LootRules and WGB.LootRules.ApplyActivityPreset then
        WGB.LootRules:ApplyActivityPreset(self.activity)
    end
    fire()
    return true
end

function Requirements:DeletePreset(name)
    local store = presetStore()
    if store and store[name] then
        store[name] = nil
        return true
    end
    return false
end

function Requirements:ListPresets()
    local store = presetStore()
    local out = {}
    if store then
        for name in pairs(store) do table.insert(out, name) end
        table.sort(out)
    end
    return out
end

-- GroupManager calls this each recount with a { ["CLASS|Spec"] = count } map.
-- Stored silently: the ROLE_FILLED fire from the same recount already dirties
-- the advert, which then reads this fresh map when it rebuilds.
function Requirements:SetSpecFilled(map)
    self.specFilled = map or {}
end

-- Remaining specific class/spec needs, e.g. { {class="PALADIN", spec="Holy", count=1} }.
function Requirements:GetRemainingSpecs()
    local out = {}
    for _, sr in ipairs(self.specRequirements) do
        local key  = (sr.class or "") .. "|" .. (sr.spec or "")
        local have = self.specFilled[key] or 0
        local want = sr.count or 1
        if want > have then
            table.insert(out, { class = sr.class, spec = sr.spec, count = want - have })
        end
    end
    return out
end

-- True when the advert should list the exact remaining class/spec slots instead
-- of broad roles. Two stage advert: while the group is still forming we want the
-- widest reach, so we broadcast generic role counts ("2 Tanks/2 Heals/3 RDPS/3
-- MDPS"). Once the raid has filled past compThreshold we switch to the exact
-- remaining specs ("1 Resto Sham/1 Demo Lock") so the closing slots get the
-- precise classes the comp wants — and the message stays short because only a
-- few specs are ever left by then. The fill fraction is derived from the comp
-- itself (sum of spec counts), NOT the separate generic role counts, so a comp
-- built without role numbers still gates correctly.
function Requirements:ShouldAdvertiseComp()
    if not (self.advancedComp and #self.specRequirements > 0) then return false end
    local total, have = 0, 0
    for _, sr in ipairs(self.specRequirements) do
        local key  = (sr.class or "") .. "|" .. (sr.spec or "")
        local want = sr.count or 1
        local got  = self.specFilled[key] or 0
        if got > want then got = want end
        total = total + want
        have  = have + got
    end
    if total <= 0 then return true end
    return (have / total) >= (self.compThreshold or 0.5)
end

function Requirements:SetFilled(role, count)
    if not self.filled[role] then return end
    self.filled[role] = tonumber(count) or 0
    WGB.Events:Fire("ROLE_FILLED", role, self.filled[role])
end

function Requirements:GetRemainingRoles()
    local out = {}
    for role, want in pairs(self.roles) do
        local have = self.filled[role] or 0
        if want > have then out[role] = want - have end
    end
    return out
end

function Requirements:GetTotalSlots()
    return (self.roles.tank or 0) + (self.roles.heal or 0)
         + (self.roles.rdps or 0) + (self.roles.mdps or 0)
end

function Requirements:GetTotalFilled()
    return (self.filled.tank or 0) + (self.filled.heal or 0)
         + (self.filled.rdps or 0) + (self.filled.mdps or 0)
end

function Requirements:IsFull()
    local total = self:GetTotalSlots()
    if total <= 0 then return false end
    return self:GetTotalFilled() >= total
end

-- ValidatePlayer: takes inspection result table, returns ok(bool), warnings(table)
function Requirements:ValidatePlayer(result)
    local warnings = {}
    if not result then return false, { "no inspection data" } end

    if self.minGS > 0 and (result.gearScore or 0) < self.minGS then
        table.insert(warnings, ("GS %d below required %d"):format(result.gearScore or 0, self.minGS))
    end
    if self.requireFullGems and result.missingGems and result.missingGems > 0 then
        table.insert(warnings, ("Missing %d gems"):format(result.missingGems))
    end
    if self.requireFullEnchants and result.missingEnchants and #result.missingEnchants > 0 then
        table.insert(warnings, "Missing enchants: " .. table.concat(result.missingEnchants, ", "))
    end
    if self.noPvPGear and result.pvpItemCount and result.pvpItemCount > 0 then
        table.insert(warnings, ("PvP gear: %d pieces"):format(result.pvpItemCount))
    end
    if self.flagOffSpecGear and result.offSpecCount and result.offSpecCount > 0 then
        local names = {}
        for _, it in ipairs(result.offSpecItems) do
            table.insert(names, it.slotName)
        end
        table.insert(warnings, "Off-spec gear: " .. table.concat(names, ", "))
    end
    if self.flagOffSpecGear and result.wrongArmorCount and result.wrongArmorCount > 0 then
        local parts = {}
        for _, it in ipairs(result.wrongArmorItems) do
            table.insert(parts, ("%s (%s)"):format(it.slotName, it.armorType))
        end
        table.insert(warnings, "Wrong armor type: " .. table.concat(parts, ", "))
    end
    -- Raid-completion achievement: only a CONFIRMED "not completed" is a warning.
    -- An unknown result (no data yet / unmapped raid) must never reject a player.
    if self.requireAchievement and WGB.RaidAchievements then
        if WGB.RaidAchievements:HasCompletedCurrent(result.name) == false then
            table.insert(warnings, L["NO_RAID_ACHIEVEMENT"])
        end
    end

    return (#warnings == 0), warnings
end

-- Apply the saved default activity at login so a fresh user does not open
-- the addon to a 0/0/0/0 raid.
WGB.Events:Register("WGB_PLAYER_LOGIN", Requirements, function(self)
    if self.activity then return end -- already initialized this session
    local id = (WGB_Settings and WGB_Settings.defaultActivity) or "icc25"
    if WGB.GetActivity(id) then
        self:ApplyActivityDefaults(id)
        if WGB.LootRules and WGB.LootRules.ApplyActivityPreset then
            WGB.LootRules:ApplyActivityPreset(id)
        end
    end
end)
