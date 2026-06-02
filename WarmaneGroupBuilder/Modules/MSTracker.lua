-- Modules/MSTracker.lua
-- Roll-spec tracker. It is common on Warmane PUGs to join the raid as one spec
-- but roll for gear of a *different* spec, so the loot master needs a quick way
-- to see (and change) which spec each person is actually rolling for.
--
-- Each grouped player gets an auto-detected spec (pulled from the Inspection
-- results) which is auto-selected. The leader can override that spec per player
-- by picking any of that class's specs (e.g. a detected Balance druid who is
-- actually rolling for a Restoration off-set).
--
-- State is SESSION-ONLY on purpose: roll intent is transient per item and is
-- reset between items, so nothing is persisted to saved variables.

local WGB = _G.WGB

local MSTracker = {
    specOverride = {},   -- name -> spec string (manual override of detected spec)
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

-- Reset everyone back to their detected spec — the natural "new item / new
-- roll" action.
function MSTracker:ResetAll()
    for k in pairs(self.specOverride) do self.specOverride[k] = nil end
    fire()
end

-- Drop tracking for players who have left the group so stale names don't linger.
function MSTracker:Prune()
    local present = {}
    for _, name in WGB.IterateGroup() do present[name] = true end
    for name in pairs(self.specOverride) do
        if not present[name] then self.specOverride[name] = nil end
    end
end

-- A kicked/leaving player should not keep a tracked override.
WGB.Events:Register("PLAYER_KICKED", MSTracker, function(self, name)
    if name then self.specOverride[name] = nil end
end)
