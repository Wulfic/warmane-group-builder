-- Modules/GroupManager.lua
-- Tracks roster, drives Inspection enqueue on join, handles raid conversion when
-- party is about to exceed 5, queues kicks for after combat.

local WGB = _G.WGB
local L = WGB.L

local GroupManager = {
    knownMembers   = {},   -- [playerName] = unitToken
    approved       = {},   -- [playerName] = true
    pendingKicks   = {},   -- list of names
    convertPending = false,
}
WGB.GroupManager = GroupManager

local function snapshotRoster()
    local snap = {}
    for unit, name in WGB.IterateGroup() do
        if name then snap[name] = unit end
    end
    return snap
end

local SPEC_TO_ROLE = {
    -- Tank-ish
    ["Protection"] = "tank",
    -- Healers
    ["Holy"]       = "heal",
    ["Restoration"]= "heal",
    ["Discipline"] = "heal",
    -- "Blood" / "Feral" are class-dependent; resolved in inferRole.
    -- The rest map to dps; melee vs ranged decided by class
}
local CLASS_DPS_RANGE = {
    HUNTER = "rdps", MAGE = "rdps", WARLOCK = "rdps", PRIEST = "rdps",
    DRUID = "rdps", SHAMAN = "rdps",  -- elemental/balance — uncertain default
    DEATHKNIGHT = "mdps", ROGUE = "mdps", WARRIOR = "mdps", PALADIN = "mdps",
}

-- Resolve role from a player's class + inspection result. `result` may be nil
-- (not inspected yet) — in that case we fall back to class default.
local function inferRole(class, result)
    if not class then return "mdps" end
    local spec = result and result.spec or nil
    -- Only trust the named spec if the player actually has a dominant tree
    -- (>=51 points). A "Holy" Paladin with 30 points isn't a healer yet.
    if result and result.dominantSpec == false then
        spec = nil
    end

    -- Druid Feral: bear-form (or majority resilience-vs-armor talents) -> tank,
    -- cat-form -> mdps. If we observed an active form, trust it.
    if class == "DRUID" and spec == "Feral" then
        local form = result and result.druidForm
        if form == "bear" then return "tank" end
        if form == "cat"  then return "mdps" end
        -- No observed form: default Feral to mdps (more common in PUGs).
        return "mdps"
    end

    -- Druid Restoration shows in SPEC_TO_ROLE; Druid Balance falls through to
    -- ranged DPS via CLASS_DPS_RANGE.
    if class == "DRUID" and spec == "Balance" then return "rdps" end

    -- Death Knight: Blood/Frost/Unholy can all tank in 3.3.5a, but the
    -- distinguishing signal is the Frost Presence... not visible via inspect.
    -- Heuristic: a DK with ≥51 talent points in any tree AND ≥2 in tanking
    -- talents is a tank. Cheap proxy: if Blood is the primary tree, assume
    -- tank (most common Blood-tank build in 3.3.5a). Otherwise mdps.
    if class == "DEATHKNIGHT" then
        if spec == "Blood" then return "tank" end
        return "mdps"
    end

    -- Shaman Elemental -> rdps, Enhancement -> mdps, Restoration handled above
    if class == "SHAMAN" then
        if spec == "Enhancement" then return "mdps" end
        if spec == "Elemental"   then return "rdps" end
        -- Resto handled by SPEC_TO_ROLE
    end

    if spec and SPEC_TO_ROLE[spec] then return SPEC_TO_ROLE[spec] end
    return CLASS_DPS_RANGE[class] or "mdps"
end

function GroupManager:RecountFilled()
    local counts = { tank = 0, heal = 0, rdps = 0, mdps = 0 }
    local specCounts = {}   -- ["CLASS|Spec"] = n, for the advanced comp builder
    for unit, name in WGB.IterateGroup() do
        local result = WGB.Inspection and WGB.Inspection.results[name] or nil
        local _, class = UnitClass(unit)
        local role = inferRole(class, result)
        counts[role] = (counts[role] or 0) + 1
        -- Only tally a class/spec slot once we actually know the spec.
        local spec = result and result.spec or nil
        if class and spec then
            local key = class .. "|" .. spec
            specCounts[key] = (specCounts[key] or 0) + 1
        end
    end
    if WGB.Requirements then
        WGB.Requirements:SetSpecFilled(specCounts)
        for role, n in pairs(counts) do WGB.Requirements:SetFilled(role, n) end
    end
    if WGB.Requirements and WGB.Requirements:IsFull() then
        WGB.Events:Fire("GROUP_FULL")
    end
end

function GroupManager:OnRosterChange()
    local snap = snapshotRoster()

    -- Detect new joins
    for name, unit in pairs(snap) do
        if not self.knownMembers[name] then
            if WGB.Inspection and name ~= UnitName("player") then
                WGB.Inspection:Enqueue(unit)
            end
        end
    end
    -- Detect leaves
    for name, _ in pairs(self.knownMembers) do
        if not snap[name] then
            if WGB.Inspection then WGB.Inspection:Clear(name) end
            self.approved[name] = nil
        end
    end
    self.knownMembers = snap

    -- Refresh our own gear/talents each roster change (we can't NotifyInspect
    -- ourselves, so this is the only way our row gets real data).
    if WGB.Inspection and WGB.Inspection.InspectSelf then
        WGB.Inspection:InspectSelf()
    end

    self:RecountFilled()

    -- Auto-convert when party hits 5: ConvertToRaid is the only way to grow.
    if not WGB.IsInRaid() and GetNumPartyMembers and GetNumPartyMembers() >= 4 then
        if not self.convertPending then
            self.convertPending = true
            WGB.SafeConvertToRaid()
            -- Reset flag after a short delay; ConvertToRaid is silent on failure
            WGB.After(2.0, function() GroupManager.convertPending = false end)
        end
    end
end

function GroupManager:ApprovePlayer(name)
    self.approved[name] = true
    WGB.Events:Fire("PLAYER_APPROVED", name)
end

function GroupManager:RejectPlayer(name, reason)
    local ok, why = WGB.SafeKick(name)
    if not ok and why == "combat" then
        self:QueueKickAfterCombat(name)
        WGB.Print(L["WILL_KICK_AFTER_COMBAT"]:format(name))
        return
    end
    if not ok then
        -- SafeKick refused for some other reason (no name, no API).
        -- Don't whisper the player or fire PLAYER_KICKED — they're still
        -- in the group, and lying to the rest of the addon causes UI to
        -- mark them as gone while they're still happily here.
        WGB.Debug(("RejectPlayer: SafeKick rejected (%s) for %s"):format(tostring(why), tostring(name)))
        return
    end
    if WGB_Settings and reason and reason ~= "" then
        WGB.QueueChat(("Removed: %s"):format(reason), "WHISPER", name)
    end
    WGB.Events:Fire("PLAYER_KICKED", name, reason)
end

function GroupManager:QueueKickAfterCombat(name)
    table.insert(self.pendingKicks, name)
end

function GroupManager:_drainKicksAfterCombat()
    if InCombatLockdown and InCombatLockdown() then return end
    while #self.pendingKicks > 0 do
        local name = table.remove(self.pendingKicks, 1)
        UninviteUnit(name)
        WGB.Events:Fire("PLAYER_KICKED", name, "deferred")
    end
end

local watcher = CreateFrame("Frame")
-- 3.3.5a raises a Lua error when registering an unknown event. GROUP_ROSTER_UPDATE
-- only exists on later clients / some cores; registering it directly would abort
-- this chunk and the SetScript below would never run, so roster changes (and
-- therefore inspection enqueue) would silently never fire. Guard each one.
local function safeRegister(event)
    local ok = pcall(watcher.RegisterEvent, watcher, event)
    if not ok then WGB.Debug("GroupManager: event unsupported on this client: " .. event) end
end
safeRegister("PARTY_MEMBERS_CHANGED")
safeRegister("RAID_ROSTER_UPDATE")
safeRegister("GROUP_ROSTER_UPDATE")     -- modern alias; harmless if unsupported
safeRegister("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        GroupManager:_drainKicksAfterCombat()
    else
        GroupManager:OnRosterChange()
    end
end)

WGB.Events:Register("INSPECTION_COMPLETE", GroupManager, function(self)
    -- Re-classify after we learn specs
    self:RecountFilled()
end)
