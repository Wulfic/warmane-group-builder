-- Modules/Inspection.lua
-- Serial inspection queue. NotifyInspect has a server-side ~1.5s cooldown and
-- INSPECT_READY may not fire at all (combat, out of range, another addon firing
-- NotifyInspect in the same frame). Rules:
--   * Hard timeout: 3s, with one automatic retry before giving up.
--   * Guard: skip while the player is in combat (server silently drops the request).
--   * GUID validation: ignore INSPECT_READY events not for our pending unit.
--   * ClearInspectPlayer after each result to keep the client cache clean.
--   * Re-kick the queue on PLAYER_REGEN_ENABLED (combat ends).

local WGB = _G.WGB
local L = WGB.L

local INSPECT_TIMEOUT   = 3.0   -- seconds before we consider an inspect stalled

local Inspection = {
    queue           = {},     -- list of { name } -- unit token resolved at use time
    pending         = nil,    -- { name, startedAt, retried, guid }
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
    -- Rings (11/12) intentionally excluded: ring enchants require the wearer to
    -- personally have the Enchanting profession, so an un-enchanted ring is NOT
    -- a gear-quality problem for most players and produced false warnings.
    [15] = "Cloak",
    [16] = "Main Hand",
    -- Off Hand (17) intentionally excluded: shields/off-hand frills/held items
    -- are usually NOT enchanted, so requiring it produced false "missing
    -- enchant" warnings on otherwise fully-enchanted players.
    [18] = "Ranged",
}

local ALL_INSPECT_SLOTS = {
    1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
}

-- Slots scanned for off-spec gear (shirt 4 and tabard 19 carry no stats). For
-- non-hunters slot 18 is a relic/thrown with no role-defining stats, so it is
-- skipped naturally by WGB.ItemArchetype returning nil.
local OFFSPEC_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18 }
local OFFSPEC_SLOT_NAMES = {
    [1]  = "Head",     [2]  = "Neck",      [3]  = "Shoulders", [5]  = "Chest",
    [6]  = "Waist",    [7]  = "Legs",      [8]  = "Feet",      [9]  = "Wrists",
    [10] = "Hands",    [11] = "Ring 1",    [12] = "Ring 2",    [13] = "Trinket 1",
    [14] = "Trinket 2",[15] = "Cloak",     [16] = "Main Hand", [17] = "Off Hand",
    [18] = "Ranged",
}

-- The 8 main armor slots scanned for wrong armor TYPE (proficiency). Cloak (15),
-- rings/neck/trinkets are Cloth/Misc for every class and must be excluded or a
-- plate wearer's cloth cloak would false-flag.
local ARMOR_SLOTS = { 1,3,5,6,7,8,9,10 }

-- Enchant detection from the item link, NOT a tooltip scan.
-- On 3.3.5a the tooltip enchant line is a plain green stat line with NO
-- "Enchanted:" prefix (that label is a retail-only feature), so scraping for
-- that string matched nothing and reported every slot as un-enchanted. The
-- reliable signal is the enchantId embedded in the item link:
--   |Hitem:itemId:enchantId:gem1:gem2:gem3:gem4:suffix:unique:...|h
-- A non-zero enchantId means the item is enchanted. This also works for
-- inspected units since GetInventoryItemLink returns the enchant data for them.
local function hasEnchant(itemLink)
    if not itemLink then return false end
    local enchantId = itemLink:match("|?H?item:%d+:(%d+):")
    return enchantId ~= nil and enchantId ~= "0" and enchantId ~= ""
end

-- Count UNFILLED sockets on an item WITHOUT depending on the client item cache.
--
-- Two earlier approaches both broke on inspected players because they needed the
-- player's *gem* items to be cached locally:
--   1. GetItemStats total minus GetItemGem count: GetItemGem returns nil for an
--      inspected unit's gems when the gem item isn't cached, so every socket
--      looked empty -> a fully-gemmed paladin reported ~17 "missing gems".
--   2. A scanning tooltip via SetHyperlink: this was claimed to be cache-
--      independent but is NOT. When the inspected player's gem items aren't in
--      your local cache the tooltip renders their FILLED sockets as
--      EMPTY_SOCKET_* lines (over-count), and when the item's BASE info isn't
--      cached it renders nothing (0 -> a false "pass"). That cache roulette is
--      why some players still mis-read while others slipped through clean.
--
-- The item link itself encodes the socketed gem item IDs for both the local
-- player AND inspected units, and reading a string never touches the cache:
--   |Hitem:itemId:enchantId:gem1:gem2:gem3:gem4:suffix:unique:level:...|h
-- gem1..gem4 are the gem item IDs in each socket (gem4 is the extra slot from a
-- belt buckle / Blacksmithing socket); 0 means empty. We compare the number of
-- filled gem IDs against the item's total socket count.
local function countMissingGems(itemLink)
    if not itemLink then return 0 end
    -- Total sockets on the base item. GetItemStats only needs the item's BASE
    -- info, which is present whenever the slot link itself resolved; if it isn't
    -- cached yet we report 0 rather than risk a false "missing gem" flag.
    local stats = GetItemStats(itemLink)
    if not stats then return 0 end
    local total = (stats.EMPTY_SOCKET_RED or 0)
        + (stats.EMPTY_SOCKET_YELLOW or 0)
        + (stats.EMPTY_SOCKET_BLUE or 0)
        + (stats.EMPTY_SOCKET_META or 0)
        + (stats.EMPTY_SOCKET_PRISMATIC or 0)
    if total == 0 then return 0 end
    -- Gems actually socketed, read straight from the link (cache-independent).
    local g1, g2, g3, g4 = itemLink:match("|?H?item:%-?%d+:%-?%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):")
    local filled = 0
    for _, g in ipairs({ g1, g2, g3, g4 }) do
        if g and g ~= "0" and g ~= "" then filled = filled + 1 end
    end
    local missing = total - filled
    if missing < 0 then missing = 0 end -- buckle/BS extra socket can exceed base count
    return missing
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

local function gatherResult(unit, inspectFlag)
    -- inspectFlag distinguishes "inspecting someone else" (true) from reading
    -- our OWN character (false). Talent APIs need the right flag or they return
    -- the wrong player's data / nothing.
    if inspectFlag == nil then inspectFlag = true end
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
        offSpecItems     = {},          -- list of { slot, slotName, name, archetype }
        offSpecCount     = 0,
        gearIntent       = nil,         -- "spellUser" | "physicalPure" | "tankPure" | "hybridMelee"
        wrongArmorItems  = {},          -- list of { slot, slotName, name, armorType }
        wrongArmorCount  = 0,
        expectedArmor    = nil,         -- "Cloth"|"Leather"|"Mail"|"Plate" this class should wear
        slots            = {},
    }

    -- Gear walk
    for _, slot in ipairs(ALL_INSPECT_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            result.slots[slot] = link
            result.missingGems = result.missingGems + countMissingGems(link)
            if detectPvP(link) then result.pvpItemCount = result.pvpItemCount + 1 end
            if ENCHANTABLE_SLOTS[slot] then
                -- The Ranged slot (18) only holds an enchantable weapon for
                -- hunters (bow/gun/crossbow). For everyone else it's a relic
                -- (idol/libram/totem/sigil) or thrown/wand that can't take an
                -- enchant, so don't flag it as "missing".
                if slot ~= 18 or class == "HUNTER" then
                    if not hasEnchant(link) then
                        table.insert(result.missingEnchants, ENCHANTABLE_SLOTS[slot])
                    end
                end
            end
        end
    end

    -- Spec via talent tabs (inspect-mode signature; 2nd arg true)
    local maxPoints, primaryIdx, primaryTab, primaryIcon = -1, 1, nil, nil
    for i = 1, 3 do
        local tabName, icon, points = GetTalentTabInfo(i, inspectFlag)
        result.talentPoints[i] = points or 0
        if points and points > maxPoints then
            maxPoints = points
            primaryIdx = i
            primaryTab = tabName
            primaryIcon = icon
        end
    end
    -- Normalize the raw talent-tab name to a canonical spec and confirm it
    -- belongs to THIS unit's class. If it doesn't (e.g. a Shaman reading a Death
    -- Knight's "Blood" tree), the inspect talent cache is stale — see
    -- WGB.NormalizeSpec — so flag it and DON'T store the wrong spec. The listener
    -- retries the inspect for stale results.
    local canonical = WGB.NormalizeSpec and WGB.NormalizeSpec(class, primaryTab) or primaryTab
    if primaryTab and maxPoints > 0 and not canonical then
        result.talentStale = true
        result.spec = nil
        result.specIcon = nil
    else
        result.spec = canonical
        result.specIcon = primaryIcon
    end
    -- A "real" 3.3.5a spec needs >=51 points to reach the capstone of one tree;
    -- below that the player is hybrid/leveling/respeccing and the spec name we
    -- report is just "the tree they happened to put the most points in".
    if result.talentStale then
        result.dominantSpec = false
        result.specConfidence = "unknown"
    elseif maxPoints >= 51 then
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

    -- Off-spec gear: compare each equipped item's archetype against the gear
    -- archetypes this spec should wear. Flags e.g. a tank in healer gear or a
    -- DPS in tank gear. Spec/form are resolved above, so the intent is known.
    if WGB.GearIntent then
        local accept, intentName = WGB.GearIntent(class, result)
        result.gearIntent = intentName
        if accept then
            for _, slot in ipairs(OFFSPEC_SLOTS) do
                local link = result.slots[slot]
                if link then
                    local arche = WGB.ItemArchetype(link)
                    if arche and not accept[arche] then
                        table.insert(result.offSpecItems, {
                            slot      = slot,
                            slotName  = OFFSPEC_SLOT_NAMES[slot] or ("Slot " .. slot),
                            name      = link:match("%[(.-)%]") or "?",
                            archetype = arche,
                        })
                    end
                end
            end
            result.offSpecCount = #result.offSpecItems
        end
    end

    -- Wrong armor type: a class wearing armor below its proficiency (a paladin
    -- in cloth/leather, a hunter in leather). Only the 8 main armor slots are
    -- checked; cloak/rings/neck/trinkets are Cloth/Misc for everyone and would
    -- false-flag. Warriors are lenient (leather/mail allowed, cloth still flagged).
    if WGB.WrongArmorType then
        for _, slot in ipairs(ARMOR_SLOTS) do
            local link = result.slots[slot]
            if link then
                local atype = WGB.ItemArmorType(link)
                if atype then
                    local wrong, expected = WGB.WrongArmorType(class, atype)
                    result.expectedArmor = expected
                    if wrong then
                        table.insert(result.wrongArmorItems, {
                            slot      = slot,
                            slotName  = OFFSPEC_SLOT_NAMES[slot] or ("Slot " .. slot),
                            name      = link:match("%[(.-)%]") or "?",
                            armorType = atype,
                        })
                    end
                end
            end
        end
        result.wrongArmorCount = #result.wrongArmorItems
    end

    -- GearScore: synchronous attempt now, then a deferred retry to fill in
    -- the result if items hadn't cached client-side yet (or the external GS
    -- backend wasn't ready). We re-fire INSPECTION_COMPLETE on update so
    -- panels showing "..." can refresh.
    if WGB.GearScore then
        local gs, approx, missing = WGB.GearScore:GetScore(unit)
        result.gearScore = gs
        result.approximateGS = approx and true or false
        if (not gs) or (approx and (missing or 0) > 0) then
            local pname = result.name
            WGB.GearScore:GetScoreDeferred(unit, pname, function(score, isApprox)
                local stored = Inspection.results[pname]
                if not stored then return end
                if score and score > 0 then
                    stored.gearScore = score
                    stored.approximateGS = isApprox and true or false
                    WGB.Events:Fire("INSPECTION_COMPLETE", pname, stored)
                end
            end, 4)
        end
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

function Inspection:Enqueue(unit, force)
    if not unit or not UnitExists(unit) then return end
    local name = UnitName(unit)
    if not name then return end
    if name == UnitName("player") then return end -- no self-inspect
    -- Inspect each player ONCE. If we already have a result for them this
    -- session, don't fire another NotifyInspect — re-inspecting the whole raid
    -- on every roster tick spams the server and causes the network lag the
    -- leader sees during checks. Their result is cleared when they leave
    -- (Inspection:Clear), so a rejoin is correctly re-inspected. Pass force=true
    -- to deliberately re-check someone (e.g. a manual "re-inspect" action).
    if not force and self.results[name] then return end
    if alreadyQueued(name) then return end
    table.insert(self.queue, { name = name })
    self:_kick()
end

-- You cannot NotifyInspect yourself, so the player's own row would otherwise
-- show "Inspecting..." forever. Read our own gear/talents locally instead.
-- Cheap and synchronous; safe to call on login and on every roster change.
function Inspection:InspectSelf()
    local name = UnitName("player")
    if not name then return end
    local ok, result = pcall(gatherResult, "player", false)
    if not ok then
        WGB.Debug("InspectSelf failed: " .. tostring(result))
        return
    end
    self.results[name] = result
    WGB.Events:Fire("INSPECTION_COMPLETE", name, result)

    -- GetTalentTabInfo can read back 0/0/0 for the player right after login,
    -- before the client has cached our own talents. When solo there's no roster
    -- change to trigger a re-read, so our row would show "hybrid 0/0/0 — no
    -- 51-pt tree" forever. Retry a few times until talents populate.
    local pts = result.talentPoints or { 0, 0, 0 }
    local sum = (pts[1] or 0) + (pts[2] or 0) + (pts[3] or 0)
    if sum > 0 then
        self._selfRetries = 0
    elseif (self._selfRetries or 0) < 5 then
        self._selfRetries = (self._selfRetries or 0) + 1
        WGB.After(2.0, function() Inspection:InspectSelf() end)
    end
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

-- Re-inspect everyone in the group who has NOT been approved yet. Used by the
-- Group Status "Rescan" button: a misread GearScore or a player who just swapped
-- gear sets can throw off the first scan, so this drops their cached result and
-- force-queues a fresh inspect. Approved players are left untouched. Our own row
-- is refreshed locally via InspectSelf (can't NotifyInspect yourself).
function Inspection:RescanUnapproved()
    local approved = (WGB.GroupManager and WGB.GroupManager.approved) or {}
    local me = UnitName("player")
    for unit, name in WGB.IterateGroup() do
        if name == me then
            self:InspectSelf()
        elseif not approved[name] then
            self._staleRetries = self._staleRetries or {}
            self._staleRetries[name] = nil
            self.results[name] = nil
            self:Enqueue(unit, true)
        end
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
    -- Don't attempt any inspect while in combat — server silently drops the request.
    if UnitAffectingCombat("player") then return end

    if self.pending then
        local elapsed = GetTime() - self.pending.startedAt
        if elapsed <= INSPECT_TIMEOUT then return end

        -- Timed out. Try one automatic retry if the unit is still in range.
        local timedOutName = self.pending.name
        local unit = resolveUnit(timedOutName)
        if not self.pending.retried and unit and UnitExists(unit) and WGB.InInspectRange(unit) then
            WGB.Debug(("Inspect retry: %s"):format(timedOutName))
            self.pending = { name = timedOutName, startedAt = GetTime(), retried = true }
            NotifyInspect(unit)
            return
        end

        WGB.Debug(L["INSPECT_TIMEOUT"]:format(timedOutName))
        ClearInspectPlayer()
        self.pending = nil
        WGB.Events:Fire("INSPECTION_TIMEOUT", timedOutName)
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
            -- Player left the group; drop silently.
            table.remove(self.queue, i)
            return self:_pump()
        end
    end
    if not picked then return end -- everyone out of range; try later

    table.remove(self.queue, pickedIndex)

    if not WGB.Throttle("notifyinspect", 1.6) then
        table.insert(self.queue, 1, picked)
        return
    end

    local pendingGuid = UnitGUID(pickedUnit)
    self.pending = { name = picked.name, startedAt = GetTime(), retried = false, guid = pendingGuid }
    NotifyInspect(pickedUnit)
    WGB.Debug(L["INSPECTING"]:format(picked.name))
end

-- INSPECT_READY: gather and continue
local listener = CreateFrame("Frame")
-- CRITICAL: on 3.3.5a `RegisterEvent` raises a Lua error for unknown event
-- names (e.g. INSPECT_READY only exists on later clients). That error aborts
-- the rest of THIS chunk — including the SetScript below — leaving the listener
-- with no handler, so INSPECTION_COMPLETE never fires and every inspect appears
-- to "hang forever". Guard each registration so an unsupported name on one
-- client can't break the others.
local function safeRegister(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then WGB.Debug("Inspection: event unsupported on this client: " .. event) end
    return ok
end
safeRegister(listener, "INSPECT_READY")           -- retail / some cores
safeRegister(listener, "INSPECT_TALENT_READY")    -- 3.3.5a name
safeRegister(listener, "PLAYER_REGEN_ENABLED")    -- combat ended
listener:SetScript("OnEvent", function(_, event, guid)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Resume any stalled queue once combat drops.
        if #Inspection.queue > 0 or Inspection.pending then
            Inspection:_kick()
        end
        return
    end

    -- INSPECT_READY / INSPECT_TALENT_READY
    local p = Inspection.pending
    if not p then return end

    -- Validate GUID: ignore results fired for a unit we didn't request.
    -- guid may be nil on servers that don't pass it; fall back to trusting order.
    if guid and p.guid and guid ~= p.guid then
        WGB.Debug(("Ignoring INSPECT_READY for foreign GUID (wanted %s, got %s)"):format(
            tostring(p.guid), tostring(guid)))
        return
    end

    local unit = resolveUnit(p.name)
    if not unit or not UnitExists(unit) then
        ClearInspectPlayer()
        Inspection.pending = nil
        stopTimerIfIdle()
        return
    end
    -- Guard the gather: a single malformed item or missing API on a private
    -- core must not throw and leave `pending` set (which would jam the whole
    -- queue and make every following player inspect forever).
    local ok, result = pcall(gatherResult, unit)
    ClearInspectPlayer()
    Inspection.pending = nil
    if ok then
        -- Stale talent cache (Shaman read as a DK's Blood spec, etc.): the
        -- talents belonged to a previously-inspected unit. Retry a couple of
        -- times after a short settle delay so the client can load THIS unit's
        -- talents, rather than storing a bogus spec.
        Inspection._staleRetries = Inspection._staleRetries or {}
        if result.talentStale and (Inspection._staleRetries[p.name] or 0) < 3 then
            Inspection._staleRetries[p.name] = (Inspection._staleRetries[p.name] or 0) + 1
            WGB.Debug(("Stale inspect talents for %s; retry %d"):format(
                p.name, Inspection._staleRetries[p.name]))
            local n = p.name
            WGB.After(0.6, function()
                local u = resolveUnit(n)
                if u and UnitExists(u) then
                    Inspection.results[n] = nil
                    Inspection:Enqueue(u, true)
                end
            end)
        else
            Inspection._staleRetries[p.name] = nil
            Inspection.results[p.name] = result
            WGB.Events:Fire("INSPECTION_COMPLETE", p.name, result)
        end
    else
        WGB.Warn(("Inspect gather failed for %s: %s"):format(tostring(p.name), tostring(result)))
        WGB.Events:Fire("INSPECTION_TIMEOUT", p.name)
    end
    if #Inspection.queue > 0 then
        Inspection:_pump()
    else
        stopTimerIfIdle()
    end
end)

-- Populate our own row as soon as we log in (and again whenever gear changes
-- via roster updates, handled in GroupManager).
WGB.Events:Register("WGB_PLAYER_LOGIN", Inspection, function()
    Inspection:InspectSelf()
end)
