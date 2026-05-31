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

-- =====================================================================
-- Native GearScore (canonical GearScoreLite formula, WotLK / 3.3.5a).
-- Ported from the public GearScoreLite algorithm (also used by TacoTip).
-- This is synchronous and reliable; we use it as the PRIMARY source and
-- only fall back to an external GS addon if native can't resolve.
-- =====================================================================
local GS_SCALE = 1.8618

-- Per-slot weighting keyed by INVTYPE (9th return of GetItemInfo).
local GS_SLOTMOD = {
    INVTYPE_RELIC          = 0.3164,
    INVTYPE_TRINKET        = 0.5625,
    INVTYPE_2HWEAPON       = 2.000,
    INVTYPE_WEAPONMAINHAND = 1.000,
    INVTYPE_WEAPONOFFHAND  = 1.000,
    INVTYPE_RANGED         = 0.3164,
    INVTYPE_THROWN         = 0.3164,
    INVTYPE_RANGEDRIGHT    = 0.3164,
    INVTYPE_SHIELD         = 1.000,
    INVTYPE_WEAPON         = 1.000,
    INVTYPE_HOLDABLE       = 1.000,
    INVTYPE_HEAD           = 1.000,
    INVTYPE_NECK           = 0.5625,
    INVTYPE_SHOULDER       = 0.750,
    INVTYPE_CHEST          = 1.000,
    INVTYPE_ROBE           = 1.000,
    INVTYPE_WAIST          = 0.750,
    INVTYPE_LEGS           = 1.000,
    INVTYPE_FEET           = 0.750,
    INVTYPE_WRIST          = 0.5625,
    INVTYPE_HAND           = 0.750,
    INVTYPE_FINGER         = 0.5625,
    INVTYPE_CLOAK          = 0.5625,
    INVTYPE_BODY           = 0,
    INVTYPE_TABARD         = 0,
}

-- Quality/iLvl coefficient tables keyed by rarity (2=green,3=blue,4=epic).
local GS_TABLE_A = { [4] = { A = 91.45, B = 0.65   }, [3] = { A = 81.375, B = 0.8125 }, [2] = { A = 73.0, B = 1.0  } }
local GS_TABLE_B = { [4] = { A = 26.0,  B = 1.2    }, [3] = { A = 0.75,   B = 1.8    }, [2] = { A = 8.0,  B = 2.0  }, [1] = { A = 0.0, B = 2.25 } }
local GS_TABLE_C = { [4] = { A = 0.25,  B = 1.6275 } }

-- All equippable inventory slots (skip 4 = shirt, 19 = tabard).
local GS_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18 }

local floor = math.floor

-- Returns scaled GS for one item link, plus its INVTYPE. nil if iteminfo
-- hasn't cached yet (caller should retry).
local function itemScore(link)
    if not link then return 0, nil end
    local _, _, rarity, ilvl, _, _, _, _, equipLoc = GetItemInfo(link)
    if not (rarity and ilvl and equipLoc) then return nil, nil end
    local slotmod = GS_SLOTMOD[equipLoc]
    if not slotmod then return 0, equipLoc end

    local qualityScale = 1
    if rarity == 5 then            -- legendary
        qualityScale = 1.3; rarity = 4
    elseif rarity == 1 or rarity == 0 then  -- common / poor
        qualityScale = 0.005; rarity = 2
    elseif rarity == 7 then        -- heirloom
        rarity = 3; ilvl = 187.05
    end

    local tbl
    if ilvl < 100 and rarity == 4 then
        tbl = GS_TABLE_C
    elseif (ilvl < 168 and rarity == 4)
        or (ilvl < 148 and rarity == 3)
        or (ilvl < 138 and rarity == 2)
        or (ilvl <= 120) then
        tbl = GS_TABLE_B
    else
        tbl = GS_TABLE_A
    end

    if rarity < 2 or rarity > 4 then return 0, equipLoc end
    local coeff = tbl[rarity]
    if not coeff then return 0, equipLoc end

    local score = floor(((ilvl - coeff.A) / coeff.B) * slotmod * GS_SCALE * qualityScale)
    if score < 0 then score = 0 end
    return score, equipLoc
end

-- Computes total native GS for a unit. Returns total, missingCount.
-- missingCount > 0 means some slots' item info hadn't cached yet.
local function nativeScore(unit)
    if not UnitExists(unit) then return nil, 0 end
    local total, count, missing = 0, 0, 0
    local mainHandLoc, offHandLoc
    local mainHandScore, offHandScore = 0, 0
    local rangedScore = 0

    for _, slot in ipairs(GS_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local s, loc = itemScore(link)
            if s == nil then
                missing = missing + 1
            else
                count = count + 1
                if slot == 16 then
                    mainHandScore = s; mainHandLoc = loc
                elseif slot == 17 then
                    offHandScore = s; offHandLoc = loc
                elseif slot == 18 then
                    rangedScore = s
                else
                    total = total + s
                end
            end
        end
    end

    -- Class-specific weapon weighting.
    local _, class = UnitClass(unit)
    if class == "HUNTER" then
        -- For hunters the ranged weapon carries the weight, melee is minimized.
        mainHandScore = floor(mainHandScore * 0.3164)
        offHandScore  = floor(offHandScore * 0.3164)
        rangedScore   = floor(rangedScore * 5.3224)
    elseif offHandLoc == "INVTYPE_2HWEAPON" then
        -- Titan's Grip: dual-wielding 2H, halve both weapon contributions.
        mainHandScore = floor(mainHandScore * 0.5)
        offHandScore  = floor(offHandScore * 0.5)
    end

    total = total + mainHandScore + offHandScore + rangedScore
    if count == 0 then return nil, missing end
    return total, missing
end

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

    -- PRIMARY: native GearScoreLite computation (synchronous, reliable).
    local native, missing = nativeScore(unit)
    if native and native > 0 and (missing or 0) == 0 then
        return native, false, 0
    end

    -- SECONDARY: a real GS addon, if one is installed and has data.
    for _, b in ipairs(self._backends) do
        local ok, score = pcall(b.fn, unit, name)
        if ok and score and score > 0 then
            return score, false, 0
        end
    end

    -- Native with some slots still uncached: return what we have and flag a
    -- retry (approx=true) so the deferred recompute fills in the rest.
    if native and native > 0 then
        return native, true, missing or 0
    end
    return native, true, missing or 0
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
