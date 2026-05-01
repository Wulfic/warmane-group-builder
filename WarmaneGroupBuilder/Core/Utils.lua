-- Core/Utils.lua
-- String/color helpers, throttle, range checks, OnUpdate ticker (no C_Timer in 3.3.5a),
-- protected-call wrappers. Keep this file pure-utility and stateless except for the
-- single ticker frame.

local WGB = _G.WGB
local L = WGB.L

WGB.COLOR = {
    ORANGE = "|cFFFF8000",
    YELLOW = "|cFFFFFF00",
    GREEN  = "|cFF00FF00",
    RED    = "|cFFFF0000",
    GREY   = "|cFF888888",
    WHITE  = "|cFFFFFFFF",
    RESET  = "|r",
}

function WGB.Color(colorCode, text)
    return (colorCode or "") .. tostring(text) .. "|r"
end

function WGB.ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "|cFFFFFFFF" end
    return ("|cFF%02X%02X%02X"):format(c.r * 255, c.g * 255, c.b * 255)
end

-- ----------------------------------------------------------------------------
-- Throttle: WGB.Throttle("key", 1.0, function() ... end)
-- Drops calls if the last call for `key` was within `interval` seconds.
-- ----------------------------------------------------------------------------
local lastCall = {}
function WGB.Throttle(key, interval, fn)
    local now = GetTime()
    local last = lastCall[key]
    if last and (now - last) < interval then return false end
    lastCall[key] = now
    if fn then fn() end
    return true
end

function WGB.ThrottleRemaining(key, interval)
    local last = lastCall[key]
    if not last then return 0 end
    local remaining = interval - (GetTime() - last)
    if remaining < 0 then return 0 end
    return remaining
end

-- ----------------------------------------------------------------------------
-- Inspect-range check. CheckInteractDistance index 1=inspect, 4=trade. We use 1.
-- (Some 3.3.5a docs say 3=duel/inspect; on Warmane 1 is the safe value.)
-- ----------------------------------------------------------------------------
function WGB.InInspectRange(unit)
    if not UnitExists(unit) or not UnitIsConnected(unit) then return false end
    if not CheckInteractDistance then return true end
    return CheckInteractDistance(unit, 1) == 1
end

-- ----------------------------------------------------------------------------
-- OnUpdate ticker (3.3.5a has no C_Timer.After).
-- WGB.After(seconds, fn)              -> one-shot
-- WGB.NewTicker(seconds, fn)          -> repeating, returns handle with :Cancel()
-- ----------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
local pending = {}    -- one-shots
local repeats = {}    -- repeating

ticker:SetScript("OnUpdate", function(_, elapsed)
    -- one-shots
    local now = GetTime()
    for i = #pending, 1, -1 do
        local item = pending[i]
        if now >= item.fireAt then
            local fn = item.fn
            table.remove(pending, i)
            local ok, err = pcall(fn)
            if not ok then WGB.Print("|cFFFF0000Timer error:|r " .. tostring(err)) end
        end
    end
    -- repeating
    for i = #repeats, 1, -1 do
        local r = repeats[i]
        if r.cancelled then
            table.remove(repeats, i)
        else
            r.acc = r.acc + elapsed
            if r.acc >= r.interval then
                r.acc = 0
                local ok, err = pcall(r.fn)
                if not ok then WGB.Print("|cFFFF0000Ticker error:|r " .. tostring(err)) end
            end
        end
    end
end)

function WGB.After(seconds, fn)
    table.insert(pending, { fireAt = GetTime() + (seconds or 0), fn = fn })
end

function WGB.NewTicker(interval, fn)
    local r = { interval = interval, fn = fn, acc = 0, cancelled = false }
    function r:Cancel() self.cancelled = true end
    table.insert(repeats, r)
    return r
end

-- ----------------------------------------------------------------------------
-- Safe protected-action guards.
-- ----------------------------------------------------------------------------
function WGB.SafeInvite(name)
    if not name or name == "" then return false, "no name" end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    InviteUnit(name)
    return true
end

function WGB.SafeKick(name)
    if not name or name == "" then return false, "no name" end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    UninviteUnit(name)
    return true
end

function WGB.SafeConvertToRaid()
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    if type(ConvertToRaid) ~= "function" then return false, "no api" end
    ConvertToRaid()
    return true
end

-- ----------------------------------------------------------------------------
-- Group helpers
-- ----------------------------------------------------------------------------
function WGB.IsInRaid()
    if IsInRaid then return IsInRaid() end
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

function WGB.GroupSize()
    if WGB.IsInRaid() then
        return (GetNumRaidMembers and GetNumRaidMembers()) or 0
    end
    return ((GetNumPartyMembers and GetNumPartyMembers()) or 0) + 1 -- include self
end

function WGB.IterateGroup()
    -- returns iterator producing (unitToken, name) pairs including the player
    local i = 0
    local inRaid = WGB.IsInRaid()
    local size = WGB.GroupSize()
    return function()
        i = i + 1
        if inRaid then
            if i > size then return nil end
            local unit = "raid" .. i
            return unit, UnitName(unit)
        else
            if i > size then return nil end
            if i == 1 then return "player", UnitName("player") end
            local unit = "party" .. (i - 1)
            return unit, UnitName(unit)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Send-chat queue. SendChatMessage is server-throttled; queue with min gap.
-- ----------------------------------------------------------------------------
local sendQueue = {}
local lastSend  = 0
local SEND_GAP  = 0.85

local function pumpSendQueue()
    if #sendQueue == 0 then return end
    local now = GetTime()
    if (now - lastSend) < SEND_GAP then return end
    local item = table.remove(sendQueue, 1)
    SendChatMessage(item.msg, item.kind, item.lang, item.target)
    lastSend = now
end

WGB.NewTicker(0.2, pumpSendQueue)

function WGB.QueueChat(msg, kind, target, lang)
    table.insert(sendQueue, { msg = msg, kind = kind, target = target, lang = lang })
end

-- ----------------------------------------------------------------------------
-- UI helper: a checkbox with a label that actually shows. The Blizzard
-- InterfaceOptionsCheckButtonTemplate in 3.3.5a uses _G[name.."Text"] which
-- requires a global name. We hand-roll instead to keep names anonymous.
-- ----------------------------------------------------------------------------
function WGB.MakeCheckBox(parent, label, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    -- UICheckButtonTemplate exists in 3.3.5a and provides the texture.
    c:SetSize(24, 24)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 4, 0)
    fs:SetText(label or "")
    c.label = fs
    c:SetScript("OnClick", function(self) if onClick then onClick(self:GetChecked() and true or false) end end)
    return c
end
