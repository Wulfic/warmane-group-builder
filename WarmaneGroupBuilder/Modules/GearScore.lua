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
    if not UnitExists(unit) then return nil end
    local total, count = 0, 0
    for _, slot in ipairs(INSPECT_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl and ilvl > 0 then
                total = total + ilvl
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    -- Approximate: avg iLvl scaled to GS-ish range.
    return math.floor((total / count) * 13)
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
        local score = b.fn(unit, name)
        if score and score > 0 then return score, false end -- not approximate
    end
    return fallbackScore(unit), true
end

WGB.Events:Register("WGB_PLAYER_LOGIN", GearScore, function(self) self:Init() end)
