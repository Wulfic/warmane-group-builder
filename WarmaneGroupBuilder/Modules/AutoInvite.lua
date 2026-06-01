-- Modules/AutoInvite.lua
-- Listens for whispers; queues invites (1 per ~1.5s); sends configurable response.
-- Skips: full group, already in group, blacklisted, recent duplicate whisper.

local WGB = _G.WGB
local L = WGB.L

local AutoInvite = {
    enabled       = false,
    inviteQueue   = {},       -- list of player names pending invite
    inviteCooldown= {},       -- [name] = GetTime when last invited
    listenerFrame = nil,
    pumpTicker    = nil,
}
WGB.AutoInvite = AutoInvite

local PER_PLAYER_COOLDOWN = 30
local INVITE_GAP          = 1.6

local function isInGroup(name)
    if name == UnitName("player") then return true end
    for unit, n in WGB.IterateGroup() do
        if n == name then return true end
    end
    return false
end

local function isBlacklisted(name)
    return WGB_CharSettings and WGB_CharSettings.blacklist and WGB_CharSettings.blacklist[name]
end

function AutoInvite:SetEnabled(on)
    self.enabled = on and true or false
    if WGB_Settings then WGB_Settings.autoInviteEnabled = self.enabled end
    if self.enabled then self:_start() else self:_stop() end
end

function AutoInvite:_start()
    if not self.listenerFrame then
        self.listenerFrame = CreateFrame("Frame")
        self.listenerFrame:SetScript("OnEvent", function(_, _, text, sender)
            AutoInvite:_onWhisper(text, sender)
        end)
    end
    -- Always (re-)register: _stop calls UnregisterAllEvents on the same
    -- frame, so a stop->start cycle would otherwise leave us deaf.
    self.listenerFrame:RegisterEvent("CHAT_MSG_WHISPER")
    if not self.pumpTicker then
        self.pumpTicker = WGB.NewTicker(0.4, function() AutoInvite:_pump() end)
    end
end

function AutoInvite:_stop()
    if self.listenerFrame then self.listenerFrame:UnregisterAllEvents() end
    if self.pumpTicker then self.pumpTicker:Cancel(); self.pumpTicker = nil end
    -- Drop any names the user already whispered; otherwise re-enabling later
    -- would invite stale whisperers.
    wipe(self.inviteQueue)
end

function AutoInvite:_onWhisper(text, sender)
    if not self.enabled then return end
    if not WGB.IsEnabled() then return end
    if not sender or sender == "" then return end
    text = text or ""
    -- Strip realm suffix if present
    sender = sender:match("^([^%-]+)") or sender

    local keyword = WGB_Settings and WGB_Settings.autoInviteKeyword or ""
    if keyword ~= "" then
        if not text:lower():find(keyword:lower(), 1, true) then return end
    end

    self:TryInvite(sender)
end

function AutoInvite:TryInvite(name)
    if not self.enabled then return false, "disabled" end
    if not WGB.IsEnabled() then return false, "disabled" end
    if WGB.Requirements and WGB.Requirements:IsFull() then
        WGB.Events:Fire("GROUP_FULL")
        return false, "full"
    end
    if isInGroup(name) then return false, "in group" end
    if isBlacklisted(name) then return false, "blacklisted" end
    local cd = self.inviteCooldown[name]
    if cd and (GetTime() - cd) < PER_PLAYER_COOLDOWN then return false, "cooldown" end

    -- Queue it
    table.insert(self.inviteQueue, name)
    return true
end

function AutoInvite:_pump()
    if #self.inviteQueue == 0 then return end
    -- Drop any leading names that are already in the group WITHOUT spending the
    -- invite throttle on them — otherwise a stale whisperer who already joined
    -- would consume the 1.6s slot and delay the next real invite.
    while #self.inviteQueue > 0 and isInGroup(self.inviteQueue[1]) do
        table.remove(self.inviteQueue, 1)
    end
    if #self.inviteQueue == 0 then return end
    -- Group filled up while names were queued: stop inviting.
    if WGB.Requirements and WGB.Requirements:IsFull() then return end
    -- Only now spend the throttle, since we have a genuinely invitable name.
    if not WGB.Throttle("autoinvite", INVITE_GAP) then return end
    local name = table.remove(self.inviteQueue, 1)

    local ok, why = WGB.SafeInvite(name)
    if not ok then
        WGB.Debug("Invite blocked (" .. tostring(why) .. ") for " .. name)
        return
    end
    self.inviteCooldown[name] = GetTime()
    WGB.Events:Fire("PLAYER_INVITED", name)
    self:SendResponse(name)
end

function AutoInvite:SendResponse(name)
    local msg = WGB_Settings and WGB_Settings.whisperResponse or ""
    if not msg or msg == "" then return end
    msg = msg:gsub("{player}", name)
    WGB.QueueChat(msg, "WHISPER", name)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", AutoInvite, function(self)
    if not WGB.IsEnabled() then return end
    if WGB_Settings and WGB_Settings.autoInviteEnabled then
        self:SetEnabled(true)
    end
end)

-- Master enable switch: suspend the whisper listener when the addon is
-- disabled, and restore it (if the user had auto-invite on) when re-enabled.
-- Does not touch the autoInviteEnabled pref so the user's choice is preserved.
WGB.Events:Register("WGB_ENABLED_CHANGED", AutoInvite, function(self, on)
    if on then
        if WGB_Settings and WGB_Settings.autoInviteEnabled then self:_start() end
    else
        self:_stop()
    end
end)
