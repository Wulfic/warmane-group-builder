-- Modules/Advertisement.lua
-- LFM message builder + sender + auto-repeat ticker.
-- Channel resolution is cached. SendChatMessage goes through WGB.QueueChat
-- which enforces the >0.85s gap.

local WGB = _G.WGB
local L = WGB.L

local MIN_SEND_GAP = 30  -- server etiquette: 30s minimum between channel sends

-- Order matters: this is the rotation order. Each entry resolves to a chat
-- target at send-time. "channel" entries are numbered channels you must have
-- joined; "type" entries are direct chat types (YELL, SAY, GUILD).
local ADVERT_TARGETS = {
    { key = "global", kind = "channel", names = { "global", "World" } },
    { key = "trade",  kind = "channel", names = { "Trade - City", "Trade" } },
    { key = "lfg",    kind = "channel", names = { "LookingForGroup" } },
    { key = "yell",   kind = "type",    chatType = "YELL"  },
    { key = "say",    kind = "type",    chatType = "SAY"   },
    { key = "guild",  kind = "type",    chatType = "GUILD", requires = function() return IsInGuild and IsInGuild() end },
}

-- Rotation index is session-only (resets on reload).
local channelRotationIdx = 1

local Advert = {
    cachedMsg     = nil,
    dirty         = true,
    autoRepeat    = nil,    -- ticker handle
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

function Advert:_resolveActiveTargets()
    local settings = WGB_Settings and WGB_Settings.advertChannels or { global = true }
    local result = {}
    for _, entry in ipairs(ADVERT_TARGETS) do
        if settings[entry.key] then
            if entry.kind == "channel" then
                for _, name in ipairs(entry.names) do
                    local num = GetChannelName(name)
                    if num and num > 0 then
                        table.insert(result, { kind = "CHANNEL", target = num, label = entry.key })
                        break
                    end
                end
            elseif entry.kind == "type" then
                if (not entry.requires) or entry.requires() then
                    table.insert(result, { kind = entry.chatType, target = nil, label = entry.key })
                end
            end
        end
    end
    return result
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
    local targets = self:_resolveActiveTargets()
    if #targets == 0 then
        WGB.Print("|cFFFF0000No advert targets active.|r Enable one in the Advertisement tab.")
        return false
    end
    -- Rotate through the active targets so each send goes to the next one.
    if channelRotationIdx > #targets then channelRotationIdx = 1 end
    local t = targets[channelRotationIdx]
    channelRotationIdx = channelRotationIdx % #targets + 1

    local msg = self:GetMessage()
    -- SendChatMessage hard-caps at 255 chars
    if #msg > 255 then msg = msg:sub(1, 255) end
    WGB.QueueChat(msg, t.kind, t.target)
    WGB.Debug(("Advert sent via %s"):format(t.label))
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
