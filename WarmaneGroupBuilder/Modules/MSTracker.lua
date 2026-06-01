-- Modules/MSTracker.lua
-- Main-spec / off-spec roll tracker. It is common on Warmane PUGs to join the
-- raid as one spec but roll for gear of a *different* spec, so the loot master
-- needs a quick way to see who is rolling MS vs OS and which spec each person is
-- actually rolling for.
--
-- Each grouped player gets an auto-detected spec (pulled from the Inspection
-- results) which is auto-selected. The leader can override that spec (e.g. a
-- detected Balance druid who is actually rolling for a Restoration off-set) and
-- flip each player between MS and OS to resolve rolls (MS > OS).
--
-- State is SESSION-ONLY on purpose: roll intent is transient per item and is
-- reset between items, so nothing is persisted to saved variables.

local WGB = _G.WGB

local MSTracker = {
    roll         = {},   -- name -> "MS" | "OS"   (default MS)
    specOverride = {},   -- name -> spec string   (manual override of detected spec)
}
WGB.MSTracker = MSTracker

local function fire()
    WGB.Events:Fire("MS_TRACKER_CHANGED")
end

-- The spec the player is actually playing, as read by the inspector. nil when
-- the player has not been inspected yet (or the talents could not be resolved).
function MSTracker:DetectedSpec(name)
    local res = WGB.Inspection and WGB.Inspection.results[name]
    return res and res.spec or nil
end

-- The spec currently tracked for this player: a manual override if set,
-- otherwise the auto-detected spec.
function MSTracker:GetSpec(name)
    return self.specOverride[name] or self:DetectedSpec(name)
end

-- True when the tracked spec was manually changed away from the detected one
-- (i.e. the player is rolling for a different spec than they joined as).
function MSTracker:IsOverridden(name)
    return self.specOverride[name] ~= nil
end

function MSTracker:SetSpec(name, spec)
    -- Setting it back to the detected spec clears the override so the row keeps
    -- auto-tracking future re-inspects.
    if spec and spec == self:DetectedSpec(name) then
        self.specOverride[name] = nil
    else
        self.specOverride[name] = spec
    end
    fire()
end

-- Advance the tracked spec to the next spec of the player's class. Used by the
-- one-click spec cell in the UI.
function MSTracker:CycleSpec(name, class)
    local specs = class and WGB.ClassSpecs[class]
    if not specs or #specs == 0 then return end
    local cur = self:GetSpec(name)
    local idx = 0
    for i, s in ipairs(specs) do
        if s == cur then idx = i break end
    end
    local nextSpec = specs[(idx % #specs) + 1]
    self:SetSpec(name, nextSpec)
end

function MSTracker:GetRoll(name)
    return self.roll[name] or "MS"
end

function MSTracker:SetRoll(name, mode)
    self.roll[name] = (mode == "OS") and "OS" or "MS"
    fire()
end

function MSTracker:ToggleRoll(name)
    self:SetRoll(name, self:GetRoll(name) == "MS" and "OS" or "MS")
end

-- Reset everyone back to MS and drop spec overrides — the natural "new item /
-- new roll" action.
function MSTracker:ResetAll()
    for k in pairs(self.roll)         do self.roll[k] = nil end
    for k in pairs(self.specOverride) do self.specOverride[k] = nil end
    fire()
end

-- Drop tracking for players who have left the group so stale names don't linger.
function MSTracker:Prune()
    local present = {}
    for _, name in WGB.IterateGroup() do present[name] = true end
    for name in pairs(self.roll) do
        if not present[name] then self.roll[name] = nil end
    end
    for name in pairs(self.specOverride) do
        if not present[name] then self.specOverride[name] = nil end
    end
end

-- A kicked/leaving player should not keep a tracked roll.
WGB.Events:Register("PLAYER_KICKED", MSTracker, function(self, name)
    if name then
        self.roll[name] = nil
        self.specOverride[name] = nil
    end
end)
