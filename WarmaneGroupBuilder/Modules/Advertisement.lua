-- Modules/Advertisement.lua
-- LFM message builder + sender + auto-repeat ticker.
-- Channel resolution is cached. SendChatMessage goes through WGB.QueueChat
-- which enforces the >0.85s gap.

local WGB = _G.WGB
local L = WGB.L

local MIN_SEND_GAP = 30  -- server etiquette: 30s minimum between channel sends

local Advert = {
    cachedMsg     = nil,
    dirty         = true,
    autoRepeat    = nil,    -- ticker handle
    channelNum    = nil,
    -- Sentinel: must be far enough in the past that the very first Send()
    -- after login isn't rejected. GetTime() at login is small but positive,
    -- so plain 0 falsely reads as "sent <30s ago".
    lastSendAt    = -MIN_SEND_GAP,
}
WGB.Advert = Advert

local function rolesFragment()
    local req = WGB.Requirements
    if not req then return "" end
    local remaining = req:GetRemainingRoles()
    local short = {
        tank = L["ROLE_TANK_SHORT"],
        heal = L["ROLE_HEAL_SHORT"],
        rdps = L["ROLE_RDPS_SHORT"],
        mdps = L["ROLE_MDPS_SHORT"],
    }
    local parts = {}
    for _, role in ipairs({ "tank", "heal", "rdps", "mdps" }) do
        local n = remaining[role]
        if n and n > 0 then
            table.insert(parts, ("%s%d%s%s"):format(WGB.COLOR.ORANGE, n, short[role], WGB.COLOR.RESET))
        end
    end
    return table.concat(parts, " ")
end

local function specsFragment()
    local req = WGB.Requirements
    if not req or #req.specRequirements == 0 then return "" end
    local parts = {}
    for _, s in ipairs(req.specRequirements) do
        table.insert(parts, ("%dx %s %s"):format(s.count or 1, s.spec or "", s.class or ""))
    end
    return table.concat(parts, ", ")
end

function Advert:_resolveChannel()
    -- cache the channel number for "global" (Warmane uses /global). Fall back to "World".
    local num = GetChannelName("global")
    if (not num) or num == 0 then num = GetChannelName("World") end
    if (not num) or num == 0 then num = GetChannelName("LookingForGroup") end
    self.channelNum = (num and num > 0) and num or nil
    return self.channelNum
end

function Advert:BuildMessage()
    local req = WGB.Requirements
    local activity = req and req.activity and WGB.GetActivity(req.activity) or nil
    local actName = activity and activity.shortName or "Custom"

    local segs = {}
    table.insert(segs, ("%s[WGB]%s LFM %s%s%s"):format(
        WGB.COLOR.ORANGE, WGB.COLOR.RESET,
        WGB.COLOR.ORANGE, actName, WGB.COLOR.RESET))

    local roles = rolesFragment()
    if roles ~= "" then table.insert(segs, "Need " .. roles) end

    if req and req.minGS and req.minGS > 0 then
        table.insert(segs, ("%s%dGS+%s"):format(WGB.COLOR.ORANGE, req.minGS, WGB.COLOR.RESET))
    end

    local specs = specsFragment()
    if specs ~= "" then table.insert(segs, specs) end

    if WGB.LootRules then
        local loot = WGB.LootRules:GetMessageFragment()
        if loot and loot ~= "" then
            table.insert(segs, WGB.COLOR.YELLOW .. loot .. WGB.COLOR.RESET)
        end
    end

    local suffix = WGB_Settings and WGB_Settings.advertSuffix or ""
    if suffix and suffix ~= "" then table.insert(segs, suffix) end

    self.cachedMsg = table.concat(segs, " — ")
    self.dirty = false
    return self.cachedMsg
end

function Advert:GetMessage()
    if self.dirty or not self.cachedMsg then self:BuildMessage() end
    return self.cachedMsg
end

function Advert:Send()
    local now = GetTime()
    if (now - self.lastSendAt) < MIN_SEND_GAP then
        local wait = MIN_SEND_GAP - (now - self.lastSendAt)
        WGB.Print(("Cooldown: %ds"):format(math.ceil(wait)))
        return false
    end
    -- Always re-resolve: the player may have joined /global after login.
    -- If we already had a number, verify it still maps to the same channel.
    self:_resolveChannel()
    if not self.channelNum then
        WGB.Print("|cFFFF0000No /global channel found.|r Type /join global first.")
        return false
    end
    local msg = self:GetMessage()
    -- SendChatMessage hard-caps at 255 chars
    if #msg > 255 then msg = msg:sub(1, 255) end
    WGB.QueueChat(msg, "CHANNEL", self.channelNum)
    self.lastSendAt = now
    return true
end

function Advert:StartAutoRepeat(intervalMin)
    self:StopAutoRepeat()
    intervalMin = intervalMin or (WGB_Settings and WGB_Settings.autoRepeatInterval) or 5
    if intervalMin < 1 then intervalMin = 1 end
    local intervalSec = intervalMin * 60
    self.autoRepeat = WGB.NewTicker(intervalSec, function() Advert:Send() end)
    if WGB_Settings then WGB_Settings.autoRepeatEnabled = true end
end

function Advert:StopAutoRepeat()
    if self.autoRepeat then self.autoRepeat:Cancel() end
    self.autoRepeat = nil
    if WGB_Settings then WGB_Settings.autoRepeatEnabled = false end
end

function Advert:CooldownRemaining()
    local r = MIN_SEND_GAP - (GetTime() - self.lastSendAt)
    if r < 0 then r = 0 end
    return r
end

-- React to changes
WGB.Events:Register("REQUIREMENTS_CHANGED", Advert, function(self) self.dirty = true end)
WGB.Events:Register("LOOT_RULES_CHANGED",   Advert, function(self) self.dirty = true end)
WGB.Events:Register("ROLE_FILLED",          Advert, function(self) self.dirty = true end)

-- Re-arm auto-repeat across /reload. The setting persists in saved vars but
-- the ticker is Lua-state only, so without this it silently stays off.
WGB.Events:Register("WGB_PLAYER_LOGIN", Advert, function(self)
    if WGB_Settings and WGB_Settings.autoRepeatEnabled then
        self:StartAutoRepeat(WGB_Settings.autoRepeatInterval)
    end
end)
