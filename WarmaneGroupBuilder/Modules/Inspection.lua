-- Modules/Inspection.lua
-- Serial inspection queue. NotifyInspect has a server-side ~1.5s cooldown and
-- INSPECT_READY may not fire at all on a flaky connection — so we hard-cap with
-- a 5s timeout. Never run more than one inspection in flight.

local WGB = _G.WGB
local L = WGB.L

local Inspection = {
    queue           = {},     -- list of { name } -- unit token resolved at use time
    pending         = nil,    -- { name, startedAt }
    results         = {},     -- [playerName] = result
    timer           = nil,
}
WGB.Inspection = Inspection

-- Resolve a player's current unit token (raid1..25 / party1..4 / player) by name.
-- Unit tokens shift when the roster changes, so we never persist them.
local function resolveUnit(name)
    if not name then return nil end
    if name == UnitName("player") then return "player" end
    for unit, n in WGB.IterateGroup() do
        if n == name then return unit end
    end
    return nil
end

-- Slots that should have an enchant in 3.3.5a. Trinkets excluded.
local ENCHANTABLE_SLOTS = {
    [1]  = "Head",
    [3]  = "Shoulders",
    [5]  = "Chest",
    [9]  = "Wrists",
    [10] = "Hands",
    [7]  = "Legs",
    [8]  = "Feet",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [15] = "Cloak",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged",
}

local ALL_INSPECT_SLOTS = {
    1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
}

-- Hidden tooltip used to scrape enchant text.
local scanTip = CreateFrame("GameTooltip", "WGBScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function scanEnchant(unit, slot)
    scanTip:ClearLines()
    if not scanTip.SetInventoryItem then return false end
    local hasItem = scanTip:SetInventoryItem(unit, slot)
    if not hasItem then return false end
    -- Tooltip line 2..n; "Enchanted: ..." indicates an enchant.
    for i = 2, scanTip:NumLines() do
        local line = _G["WGBScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText() or ""
            if text:find("Enchanted:", 1, true) then return true end
        end
    end
    return false
end

local function countSocketsAndGems(itemLink)
    if not itemLink then return 0, 0 end
    local sockets, gems = 0, 0
    -- Sockets: parse via tooltip stat scan would be heavy; cheap heuristic via
    -- GetItemStats which returns EMPTY_SOCKET_* counts.
    local stats = GetItemStats and GetItemStats(itemLink) or nil
    if stats then
        for k, v in pairs(stats) do
            if k:find("EMPTY_SOCKET", 1, true) then sockets = sockets + (v or 0) end
        end
    end
    -- Gems present: check the 3 gem indices.
    for i = 1, 3 do
        local _, gemLink = GetItemGem(itemLink, i)
        if gemLink then gems = gems + 1 end
    end
    return sockets, gems
end

local function detectPvP(itemLink)
    if not itemLink then return false end
    local _, _, _, _, _, itype, isubtype = GetItemInfo(itemLink)
    if not itype then return false end
    -- Resilience-bearing items in 3.3.5a sit in armor/weapon types but the
    -- cleanest signal is item set / "Gladiator" / "Wrathful" name match.
    local name = itemLink:match("%[(.-)%]") or ""
    if name:find("Gladiator") or name:find("Wrathful") or name:find("Furious")
        or name:find("Relentless") or name:find("Hateful") or name:find("Deadly") then
        return true
    end
    return false
end

local function gatherResult(unit)
    local name = UnitName(unit) or "?"
    local _, class = UnitClass(unit)
    local result = {
        name             = name,
        class            = class,
        gearScore        = nil,
        approximateGS    = false,
        missingGems      = 0,
        missingEnchants  = {},
        pvpItemCount     = 0,
        spec             = nil,
        specIcon         = nil,
        talentPoints     = { 0, 0, 0 }, -- per-tree point totals
        dominantSpec     = false,       -- true when primary tree has >= 51 points
        specConfidence   = "unknown",   -- "high" | "low" | "unknown"
        druidForm        = nil,         -- "bear" | "cat" | "tree" | "moonkin" | nil
        slots            = {},
    }

    -- Gear walk
    for _, slot in ipairs(ALL_INSPECT_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            result.slots[slot] = link
            local sockets, gems = countSocketsAndGems(link)
            if sockets > gems then
                result.missingGems = result.missingGems + (sockets - gems)
            end
            if detectPvP(link) then result.pvpItemCount = result.pvpItemCount + 1 end
            if ENCHANTABLE_SLOTS[slot] then
                if not scanEnchant(unit, slot) then
                    table.insert(result.missingEnchants, ENCHANTABLE_SLOTS[slot])
                end
            end
        end
    end

    -- Spec via talent tabs (inspect-mode signature; 2nd arg true)
    local maxPoints, primaryIdx = -1, 1
    for i = 1, 3 do
        local tabName, icon, points = GetTalentTabInfo(i, true)
        result.talentPoints[i] = points or 0
        if points and points > maxPoints then
            maxPoints = points
            primaryIdx = i
            result.spec = tabName
            result.specIcon = icon
        end
    end
    -- A "real" 3.3.5a spec needs >=51 points to reach the capstone of one tree;
    -- below that the player is hybrid/leveling/respeccing and the spec name we
    -- report is just "the tree they happened to put the most points in".
    if maxPoints >= 51 then
        result.dominantSpec = true
        result.specConfidence = "high"
    elseif maxPoints > 0 then
        result.dominantSpec = false
        result.specConfidence = "low"
    else
        result.specConfidence = "unknown"
    end

    -- Druid form (only useful for class == "DRUID"). Form auras are visible
    -- to anyone in inspect range, so we don't need extra API permissions.
    if class == "DRUID" then
        for i = 1, 40 do
            local auraName = UnitBuff(unit, i)
            if not auraName then break end
            if auraName == "Dire Bear Form" or auraName == "Bear Form" then
                result.druidForm = "bear"; break
            elseif auraName == "Cat Form" then
                result.druidForm = "cat"; break
            elseif auraName == "Tree of Life" then
                result.druidForm = "tree"; break
            elseif auraName == "Moonkin Form" then
                result.druidForm = "moonkin"; break
            end
        end
    end

    -- GearScore
    if WGB.GearScore then
        local gs, approx = WGB.GearScore:GetScore(unit)
        result.gearScore = gs
        result.approximateGS = approx and true or false
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Queue management
-- ---------------------------------------------------------------------------
local function alreadyQueued(name)
    for _, item in ipairs(Inspection.queue) do
        if item.name == name then return true end
    end
    if Inspection.pending and Inspection.pending.name == name then
        return true
    end
    return false
end

function Inspection:Enqueue(unit)
    if not unit or not UnitExists(unit) then return end
    local name = UnitName(unit)
    if not name then return end
    if name == UnitName("player") then return end -- no self-inspect
    if alreadyQueued(name) then return end
    table.insert(self.queue, { name = name })
    self:_kick()
end

function Inspection:Clear(playerName)
    self.results[playerName] = nil
    for i = #self.queue, 1, -1 do
        if self.queue[i].name == playerName then table.remove(self.queue, i) end
    end
    if self.pending and self.pending.name == playerName then
        self.pending = nil
    end
end

local function stopTimerIfIdle()
    if Inspection.pending then return end
    if #Inspection.queue > 0 then return end
    if Inspection.timer then
        Inspection.timer:Cancel()
        Inspection.timer = nil
    end
end

function Inspection:_kick()
    if self.pending then return end
    if not self.timer then
        self.timer = WGB.NewTicker(0.5, function() Inspection:_pump() end)
    end
    self:_pump()
end

function Inspection:_pump()
    if self.pending then
        -- timeout check
        if (GetTime() - self.pending.startedAt) > 5.0 then
            local timedOutName = self.pending.name
            WGB.Debug(L["INSPECT_TIMEOUT"]:format(timedOutName))
            self.pending = nil
            WGB.Events:Fire("INSPECTION_TIMEOUT", timedOutName)
        else
            return
        end
    end
    if #self.queue == 0 then
        stopTimerIfIdle()
        return
    end

    -- Find the first queued name whose unit is currently in range.
    local picked, pickedIndex, pickedUnit
    for i, item in ipairs(self.queue) do
        local unit = resolveUnit(item.name)
        if unit and UnitExists(unit) and WGB.InInspectRange(unit) then
            picked, pickedIndex, pickedUnit = item, i, unit
            break
        elseif not unit then
            -- player has left the group; drop the entry
            table.remove(self.queue, i)
            -- index shift: restart loop
            return self:_pump()
        end
    end
    if not picked then return end -- everyone out of range; try later

    table.remove(self.queue, pickedIndex)

    if not WGB.Throttle("notifyinspect", 1.6) then
        -- shouldn't happen because pump runs at 0.5s but be safe
        table.insert(self.queue, 1, picked)
        return
    end

    self.pending = { name = picked.name, startedAt = GetTime() }
    NotifyInspect(pickedUnit)
    WGB.Debug(L["INSPECTING"]:format(picked.name))
end

-- INSPECT_READY: gather and continue
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")           -- modern name (may not exist 3.3.5a)
listener:RegisterEvent("INSPECT_TALENT_READY")    -- 3.3.5a name
listener:SetScript("OnEvent", function(_, event, guid)
    local p = Inspection.pending
    if not p then return end
    local unit = resolveUnit(p.name)
    if not unit or not UnitExists(unit) then
        Inspection.pending = nil
        stopTimerIfIdle()
        return
    end
    local result = gatherResult(unit)
    Inspection.results[p.name] = result
    Inspection.pending = nil
    WGB.Events:Fire("INSPECTION_COMPLETE", p.name, result)
    if #Inspection.queue > 0 then
        Inspection:_pump()
    else
        stopTimerIfIdle()
    end
end)
