-- Modules/GearScore.lua
-- Optional dependency wrapper. Tries known 3.3.5a GearScore-style addons via
-- their public globals; otherwise falls back to a coarse iLvl average.
--
-- Adding a custom backend (e.g. a private fork) from another addon:
--     WGB.GearScore:RegisterBackend("MyAddon", function(unit, name)
--         return MyAddon.GetScore(name) -- return number, or nil to skip
--     end)
--
-- Note: BonusScanner is *not* a GS provider — it sums stats (EP, hit cap, etc.)
-- and does not expose a GearScore number. We don't probe it.

local WGB = _G.WGB

local GearScore = {
    _backends = {},   -- ordered list of { name = "...", fn = function(unit, name) -> number? }
    _initialized = false,
}
WGB.GearScore = GearScore

local INSPECT_SLOTS = {
    1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18
}

-- Built-in probes for known addons. Each returns a getter function or nil.
local BUILTIN_PROBES = {
    -- Egingell's GearScore + GearScore2 + most forks expose this global.
    {
        name = "GearScore_GetScore",
        probe = function()
            if type(_G.GearScore_GetScore) == "function" then
                return function(unit, name)
                    local ok, score = pcall(_G.GearScore_GetScore, name, unit)
                    if ok and tonumber(score) then return tonumber(score) end
                end
            end
        end,
    },
    -- TalentedGS / RecountGearScore variants
    {
        name = "RecountGearScore",
        probe = function()
            if type(_G.RecountGearScore) == "function" then
                return function(unit, name)
                    local ok, score = pcall(_G.RecountGearScore, name, unit)
                    if ok and tonumber(score) then return tonumber(score) end
                end
            end
        end,
    },
    -- PallyPower-style table on _G.GearScore (rare but seen)
    {
        name = "GearScore.Score",
        probe = function()
            if type(_G.GearScore) == "table" and type(_G.GearScore.GetScore) == "function" then
                return function(unit, name)
                    local ok, score = pcall(_G.GearScore.GetScore, _G.GearScore, name, unit)
                    if ok and tonumber(score) then return tonumber(score) end
                end
            end
        end,
    },
}

local function fallbackScore(unit)
    if not UnitExists(unit) then return nil, 0 end
    local total, count, missing = 0, 0, 0
    for _, slot in ipairs(INSPECT_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl and ilvl > 0 then
                total = total + ilvl
                count = count + 1
            else
                -- Item link present but iLvl unresolved: this slot's iteminfo
                -- will arrive asynchronously. Track so the caller can retry.
                missing = missing + 1
            end
        end
    end
    if count == 0 then return nil, missing end
    -- Approximate: avg iLvl scaled to GS-ish range.
    return math.floor((total / count) * 13), missing
end

function GearScore:RegisterBackend(name, fn)
    if type(fn) ~= "function" then return end
    table.insert(self._backends, { name = name or "anonymous", fn = fn })
    WGB.Debug("GearScore: registered backend " .. (name or "anonymous"))
end

function GearScore:Init()
    self._initialized = true
    -- Run built-in probes once at login.
    for _, p in ipairs(BUILTIN_PROBES) do
        local getter = p.probe()
        if getter then
            self:RegisterBackend(p.name, getter)
        end
    end
    if #self._backends == 0 then
        WGB.Debug("GearScore: no backend addon detected, using fallback iLvl avg.")
    else
        local names = {}
        for _, b in ipairs(self._backends) do table.insert(names, b.name) end
        WGB.Debug("GearScore: backends = " .. table.concat(names, ", "))
    end
end

function GearScore:GetScore(unit)
    if not self._initialized then self:Init() end
    local name = UnitName(unit)
    -- Try registered backends in order; first usable score wins. A backend
    -- that returns 0 (or negative) is treated as "no data" so we fall
    -- through to the next backend / fallback instead of reporting 0 GS.
    for _, b in ipairs(self._backends) do
        local ok, score = pcall(b.fn, unit, name)
        if ok and score and score > 0 then
            -- approximate=false, missing=0 (third return for callers that
            -- want to know if a retry might help; backends are authoritative)
            return score, false, 0
        end
    end
    local fb, missing = fallbackScore(unit)
    return fb, true, missing or 0
end

-- Helper: schedule a deferred recompute. Calls `cb(score, approx)` once a
-- non-nil score is produced, or after `maxAttempts` retries (whichever first).
-- Used by Inspection to fill in scores when items haven't cached yet.
function GearScore:GetScoreDeferred(unit, name, cb, maxAttempts)
    maxAttempts = maxAttempts or 4
    local attempt = 0
    local function tryOnce()
        attempt = attempt + 1
        -- Re-resolve the unit token by name each attempt (raid roster shifts).
        local u = unit
        if name then
            if name == UnitName("player") then
                u = "player"
            else
                for unitTok, n in WGB.IterateGroup() do
                    if n == name then u = unitTok; break end
                end
            end
        end
        if not u or not UnitExists(u) then cb(nil, true); return end
        local score, approx, missing = self:GetScore(u)
        if score and score > 0 and (not approx or missing == 0) then
            cb(score, approx); return
        end
        if attempt >= maxAttempts then
            cb(score, approx); return
        end
        WGB.After(0.6, tryOnce)
    end
    tryOnce()
end

WGB.Events:Register("WGB_PLAYER_LOGIN", GearScore, function(self) self:Init() end)
