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
    -- Session-only safety gate. Auto-repeat (and the login re-arm of it) must
    -- NEVER send on its own: the first advert of a session has to be a
    -- deliberate manual Send (button or /wgb advert). Resets every /reload so
    -- a persisted "auto-repeat ON" can't silently start spamming on login.
    armed         = false,
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
    local labels = {
        tank = "Tanks",
        heal = "Heals",
        rdps = "RDPS",
        mdps = "MDPS",
    }
    local parts = {}
    for _, role in ipairs({ "tank", "heal", "rdps", "mdps" }) do
        local n = remaining[role]
        if n and n > 0 then
            table.insert(parts, ("%d %s"):format(n, labels[role]))
        end
    end
    return table.concat(parts, "/")
end

-- "5800" -> "5.8k", "5000" -> "5k", "5500" -> "5.5k".
local function formatGS(gs)
    local s = ("%.1f"):format(gs / 1000)
    s = s:gsub("%.0$", "")
    return s .. "k"
end

-- Compact, fill-aware spec fragment: the class/spec slots STILL needed, e.g.
-- "1 Holy Pal/2 Resto Sham". Mirrors the role fragment's "/" style so the
-- advert reads the same whether it's listing roles or specific specs.
local function specsFragment()
    local req = WGB.Requirements
    if not req then return "" end
    local remaining = req:GetRemainingSpecs()
    if #remaining == 0 then return "" end
    local parts = {}
    for _, s in ipairs(remaining) do
        local cls = WGB.ClassShort and WGB.ClassShort(s.class) or s.class
        table.insert(parts, ("%d %s %s"):format(s.count or 1, s.spec or "", cls or ""))
    end
    return table.concat(parts, "/")
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

    -- Format (plain, no color codes — public chat strips them anyway):
    --   LFM ICC 25 - 5.8k GS+ - 2 Tanks/5 Heals/8 RDPS/9 MDPS - <specs> - <loot> - <suffix>
    local segs = {}
    table.insert(segs, "LFM " .. actName)

    if req and req.minGS and req.minGS > 0 then
        table.insert(segs, formatGS(req.minGS) .. " GS+")
    end

    local roles = rolesFragment()

    -- While the raid is first forming we advertise broad roles (wide reach). Once
    -- it has filled past the comp threshold we switch to advertising the exact
    -- remaining class/spec slots instead — same compact "/"-joined style, so the
    -- message never balloons. Falls back to roles if no specific specs remain.
    local placed = false
    if req and req:ShouldAdvertiseComp() then
        local specs = specsFragment()
        if specs ~= "" then
            table.insert(segs, specs)
            placed = true
        end
    end
    if not placed and roles ~= "" then
        table.insert(segs, roles)
    end

    if WGB.LootRules then
        local loot = WGB.LootRules:GetMessageFragment()
        if loot and loot ~= "" then
            table.insert(segs, loot)
        end
    end

    local suffix = WGB_Settings and WGB_Settings.advertSuffix or ""
    if suffix and suffix ~= "" then table.insert(segs, suffix) end

    self.cachedMsg = table.concat(segs, " - ")
    self.dirty = false
    return self.cachedMsg
end

function Advert:GetMessage()
    if self.dirty or not self.cachedMsg then self:BuildMessage() end
    return self.cachedMsg
end

function Advert:Send(isAuto)
    -- Manual sends (button / slash) arm the session; auto-repeat refuses to
    -- fire until then, so the addon can't start broadcasting on its own.
    if isAuto then
        if not self.armed then
            WGB.Debug("Auto-repeat tick suppressed: not armed (click Send once first)")
            return false
        end
    else
        self.armed = true
    end

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
    -- CRITICAL: sanitize before sending. 3.3.5a rejects/mangles public-chat
    -- messages (SAY/YELL/CHANNEL) that contain escape sequences:
    --   * |c..|r color codes  -> stripped (preview keeps colors, wire is plain)
    --   * a lone | (our loot separator " | ") is the escape introducer and
    --     breaks the parser -> escape to || so it renders as a literal pipe.
    msg = WGB.StripColors(msg)
    msg = msg:gsub("|", "||")
    if not msg or msg:gsub("%s", "") == "" then
        WGB.Print("|cFFFF0000Advert message is empty.|r Set an activity in the Requirements tab.")
        return false
    end
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
    self.autoRepeat = WGB.NewTicker(intervalSec, function() Advert:Send(true) end)
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
