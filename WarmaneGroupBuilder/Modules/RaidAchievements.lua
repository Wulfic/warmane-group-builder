-- Modules/RaidAchievements.lua
-- Optional "has the applicant cleared this raid?" check.
--
-- When the leader enables the "Achievement Req" flag, this module verifies that
-- each inspected player owns the *raid-completion* achievement (the final-boss
-- kill) for the currently-selected activity. It uses the 3.3.5a achievement
-- comparison API, which works exactly like the right-click "Compare
-- Achievements" the client already supports:
--   SetAchievementComparisonUnit(unit)  -> fires INSPECT_ACHIEVEMENT_READY
--   GetComparisonAchievementInfo(achID) -> ..., completed (4th return)
--   ClearAchievementComparisonUnit()    -> tidy up
--
-- The check is strictly NON-BLOCKING: if we have no achievement ID mapped for
-- the activity, or the comparison data never arrives (out of range, private
-- core without comparison support, combat), HasCompletedCurrent() returns nil
-- and the player is NOT flagged. We only ever report "missing" when the server
-- positively tells us the achievement is not completed.

local WGB = _G.WGB
local L = WGB.L

local COMPARE_TIMEOUT = 3.0  -- seconds before a stalled comparison is abandoned

-- ---------------------------------------------------------------------------
-- Raid-completion achievement IDs (final-boss kill, NORMAL difficulty).
-- Keyed by the activity's base zone (the leading letters of the activity id,
-- e.g. "icc25" -> "icc"). Edit / extend this table to add more raids.
--
--   CONFIRMED ids:  icc, onyxia
--   UNVERIFIED:     toc, ulduar, rs, voa  -> left out on purpose. A wrong id
--                   would falsely reject EVERYONE, so an unmapped raid simply
--                   skips the check. Fill these in once the ids are confirmed.
-- ---------------------------------------------------------------------------
local RAID_ACHIEVEMENTS = {
    icc    = { [10] = 4530, [25] = 4597 },  -- The Fall of the Lich King
    onyxia = { [10] = 4396, [25] = 4397 },  -- Onyxia
    -- toc    = { [10] = nil, [25] = nil }, -- VERIFY: Anub'arak kill
    -- ulduar = { [10] = nil, [25] = nil }, -- VERIFY: Yogg-Saron kill
    -- rs     = { [10] = nil, [25] = nil }, -- VERIFY: Halion kill
    -- voa    = { [10] = nil, [25] = nil }, -- VERIFY: Archavon kill
}

-- Resolve the completion achievement id for an activity id ("icc25" etc.).
-- Returns the numeric achievement id, or nil when the raid/size is unmapped.
function WGB.GetRaidAchievement(activityId)
    if not activityId then return nil end
    local base = activityId:match("^%a+")
    local size = tonumber(activityId:match("(%d+)"))
    local entry = base and RAID_ACHIEVEMENTS[base] or nil
    if not entry or not size then return nil end
    return entry[size]
end

local RaidAchievements = {
    queue    = {},     -- list of { name }
    pending  = nil,    -- { name, achID, startedAt }
    results  = {},     -- [name] = { [achID] = bool }
    timer    = nil,
}
WGB.RaidAchievements = RaidAchievements

-- Resolve a player's current unit token by name (tokens shift with the roster).
local function resolveUnit(name)
    if not name then return nil end
    if name == UnitName("player") then return "player" end
    for unit, n in WGB.IterateGroup() do
        if n == name then return unit end
    end
    return nil
end

-- Read whether the active comparison unit has earned `achID`. Returns true,
-- false, or nil when the API isn't available on this client.
local function readComparison(achID)
    if type(GetComparisonAchievementInfo) == "function" then
        local _, _, _, completed = GetComparisonAchievementInfo(achID)
        return completed and true or false
    elseif type(GetAchievementComparisonInfo) == "function" then
        local completed = GetAchievementComparisonInfo(achID)
        return completed and true or false
    end
    return nil
end

-- Read OUR OWN completion of `achID` directly (no comparison inspect needed).
local function readSelf(achID)
    if type(GetAchievementInfo) ~= "function" then return nil end
    local _, _, _, completed = GetAchievementInfo(achID)
    return completed and true or false
end

local function clearComparison()
    if type(ClearAchievementComparisonUnit) == "function" then
        pcall(ClearAchievementComparisonUnit)
    end
end

local function store(name, achID, value)
    RaidAchievements.results[name] = RaidAchievements.results[name] or {}
    RaidAchievements.results[name][achID] = value
    WGB.Events:Fire("ACHIEVEMENT_CHECK_COMPLETE", name, achID, value)
end

-- Is the achievement check active for the current activity?
local function checkEnabled()
    local req = WGB.Requirements
    if not req or not req.requireAchievement then return false end
    return WGB.GetRaidAchievement(req.activity) ~= nil
end

-- Public: has `name` completed the current activity's raid achievement?
-- Returns true / false / nil (unknown). nil must be treated as "not yet known"
-- and never as a failure.
function RaidAchievements:HasCompletedCurrent(name)
    local req = WGB.Requirements
    local achID = req and WGB.GetRaidAchievement(req.activity) or nil
    if not achID then return nil end
    local r = self.results[name]
    if not r then return nil end
    local v = r[achID]
    if v == nil then return nil end
    return v
end

function RaidAchievements:Clear(name)
    self.results[name] = nil
    for i = #self.queue, 1, -1 do
        if self.queue[i].name == name then table.remove(self.queue, i) end
    end
    if self.pending and self.pending.name == name then
        clearComparison()
        self.pending = nil
    end
end

local function alreadyQueued(name)
    for _, item in ipairs(RaidAchievements.queue) do
        if item.name == name then return true end
    end
    return RaidAchievements.pending and RaidAchievements.pending.name == name
end

function RaidAchievements:Enqueue(name)
    if not name then return end
    local achID = WGB.GetRaidAchievement(WGB.Requirements and WGB.Requirements.activity)
    if not achID then return end
    -- Already have an answer for this player + achievement: don't re-check.
    if self.results[name] and self.results[name][achID] ~= nil then return end

    -- Our own toon is read directly — you can't comparison-inspect yourself.
    if name == UnitName("player") then
        local v = readSelf(achID)
        if v ~= nil then store(name, achID, v) end
        return
    end

    if alreadyQueued(name) then return end
    table.insert(self.queue, { name = name })
    self:_kick()
end

local function stopTimerIfIdle()
    if RaidAchievements.pending then return end
    if #RaidAchievements.queue > 0 then return end
    if RaidAchievements.timer then
        RaidAchievements.timer:Cancel()
        RaidAchievements.timer = nil
    end
end

function RaidAchievements:_kick()
    if self.pending then return end
    if not self.timer then
        self.timer = WGB.NewTicker(0.5, function() RaidAchievements:_pump() end)
    end
    self:_pump()
end

function RaidAchievements:_pump()
    -- The comparison request travels on the same inspect channel as the gear
    -- scan, so never fire one while a gear inspect is mid-flight or in combat.
    if UnitAffectingCombat("player") then return end

    if self.pending then
        if (GetTime() - self.pending.startedAt) <= COMPARE_TIMEOUT then return end
        -- Stalled: give up on this one (leaves the result unknown -> non-blocking).
        WGB.Debug(("Achievement compare timed out for %s"):format(self.pending.name))
        clearComparison()
        self.pending = nil
    end

    if #self.queue == 0 then
        stopTimerIfIdle()
        return
    end

    -- Don't compete with an in-flight gear inspect.
    if WGB.Inspection and WGB.Inspection.pending then return end

    if type(SetAchievementComparisonUnit) ~= "function" then
        -- Client/core has no comparison API; drain the queue silently.
        self.queue = {}
        stopTimerIfIdle()
        return
    end

    local achID = WGB.GetRaidAchievement(WGB.Requirements and WGB.Requirements.activity)
    if not achID then
        self.queue = {}
        stopTimerIfIdle()
        return
    end

    -- Pick the first queued player who is currently in inspect range.
    local picked, pickedIndex, pickedUnit
    for i, item in ipairs(self.queue) do
        local unit = resolveUnit(item.name)
        if unit and UnitExists(unit) and WGB.InInspectRange(unit) then
            picked, pickedIndex, pickedUnit = item, i, unit
            break
        elseif not unit then
            table.remove(self.queue, i)
            return self:_pump()
        end
    end
    if not picked then return end

    if not WGB.Throttle("achievcompare", 1.6) then return end

    table.remove(self.queue, pickedIndex)
    clearComparison()
    local ok, success = pcall(SetAchievementComparisonUnit, pickedUnit)
    if not ok or success == false then
        -- Request refused (out of range / not inspectable). Leave it unknown.
        clearComparison()
        return self:_pump()
    end
    self.pending = { name = picked.name, achID = achID, startedAt = GetTime() }
end

-- INSPECT_ACHIEVEMENT_READY: comparison data has arrived.
local listener = CreateFrame("Frame")
-- CRITICAL: on 3.3.5a RegisterEvent throws for an unknown event name and aborts
-- this whole chunk, which would leave the OnEvent handler unset. Guard it.
local function safeRegister(frame, event)
    local okreg = pcall(frame.RegisterEvent, frame, event)
    if not okreg then WGB.Debug("RaidAchievements: event unsupported: " .. event) end
    return okreg
end
safeRegister(listener, "INSPECT_ACHIEVEMENT_READY")
safeRegister(listener, "PLAYER_REGEN_ENABLED")
listener:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if #RaidAchievements.queue > 0 or RaidAchievements.pending then
            RaidAchievements:_kick()
        end
        return
    end

    -- INSPECT_ACHIEVEMENT_READY
    local p = RaidAchievements.pending
    if not p then return end
    local value = readComparison(p.achID)
    clearComparison()
    RaidAchievements.pending = nil
    if value ~= nil then
        store(p.name, p.achID, value)
    end
    RaidAchievements:_pump()
end)

-- A gear inspect just finished for this player; if the achievement gate is on
-- and we still don't know their status, queue a comparison.
WGB.Events:Register("INSPECTION_COMPLETE", RaidAchievements, function(_, name)
    if not checkEnabled() then return end
    RaidAchievements:Enqueue(name)
end)

-- Switching activities changes which achievement matters. Re-check anyone we
-- haven't answered for under the new activity on the next inspect cycle; we keep
-- old per-achievement answers (they remain valid if the activity is switched back).
WGB.Events:Register("REQUIREMENTS_CHANGED", RaidAchievements, function()
    if not checkEnabled() then
        -- Gate turned off: stop any in-flight work.
        RaidAchievements.queue = {}
        if RaidAchievements.pending then
            clearComparison()
            RaidAchievements.pending = nil
        end
        return
    end
    -- Gate on: re-queue everyone we already inspected but haven't answered for.
    if WGB.Inspection and WGB.Inspection.results then
        for name in pairs(WGB.Inspection.results) do
            RaidAchievements:Enqueue(name)
        end
    end
end)
