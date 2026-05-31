-- Modules/Requirements.lua
-- Group requirement state machine. All mutation goes through setters; setters fire
-- REQUIREMENTS_CHANGED so UI / Advertisement / GroupManager rebuild themselves.

local WGB = _G.WGB

local Requirements = {
    activity              = nil,    -- activity id
    roles                 = { tank = 0, heal = 0, rdps = 0, mdps = 0 },
    filled                = { tank = 0, heal = 0, rdps = 0, mdps = 0 },
    minGS                 = 0,
    requireFullGems       = false,
    requireFullEnchants   = false,
    noPvPGear             = false,
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
    if flag == "requireFullGems" or flag == "requireFullEnchants" or flag == "noPvPGear" then
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

-- True once the raid is filled enough that broad role advertising should give
-- way to advertising the exact remaining class/spec slots.
function Requirements:ShouldAdvertiseComp()
    if not self.advancedComp or #self.specRequirements == 0 then return false end
    local total = self:GetTotalSlots()
    if total <= 0 then return false end
    return (self:GetTotalFilled() / total) >= (self.compThreshold or 0.5)
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
