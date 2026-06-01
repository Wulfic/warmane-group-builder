-- Core/Core.lua
-- Addon bootstrap, SavedVariables defaults, debug print.

local ADDON, ns = ...
_G.WGB = _G.WGB or {}
local WGB = _G.WGB

WGB.ADDON_NAME   = ADDON
-- Derive the version straight from the .toc metadata so the two can never
-- drift (a stale literal here used to print a "version mismatch" warning on
-- every login). Falls back to a literal only if the API is unavailable.
WGB.VERSION      = (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "1.0.0"
WGB.L            = ns.L  -- locale table set up in Locale-enUS.lua
WGB._ns          = ns

-- ----------------------------------------------------------------------------
-- Default SavedVariables
-- ----------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    version              = 1,
    debug                = false,
    enabled              = true,   -- master switch; when false all auto features are suspended
    mainWindow           = { x = 0, y = 0, point = "CENTER", width = 580, height = 620, shown = false },
    minimapAngle         = 215,
    showMinimap          = true,
    autoInviteEnabled    = false,
    autoInviteKeyword    = "",     -- "" = any whisper triggers invite
    autoRepeatEnabled    = false,
    autoRepeatInterval   = 5,      -- minutes
    advertChannels       = { global = true, trade = false, lfg = false, yell = false, say = false, guild = false },
    whisperResponse      = "Invite incoming. Please come to Dalaran for inspection. (auto-msg)",
    advertSuffix         = "PST for inv",
    defaultActivity      = "icc25",
    lootRulesDefaults    = {
        lootSystem = "MSOS",
        boeRule    = "raid",
    },
    compPresets          = {},     -- [presetName] = saved raid-comp config snapshot
}

local DEFAULT_CHAR = {
    blacklist = {},  -- [playerName] = reason
}

local function deepCopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = deepCopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- ----------------------------------------------------------------------------
-- Print / debug
-- ----------------------------------------------------------------------------
function WGB.Print(msg)
    if not msg then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8000[WGB]|r " .. tostring(msg))
end

function WGB.Debug(msg)
    if not (WGB_Settings and WGB_Settings.debug) then return end
    local ts = date("%H:%M:%S")
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[WGB-DBG " .. ts .. "]|r " .. tostring(msg))
end

-- Convenience wrapper: WGB.DebugF("Player %s has GS %d", name, gs)
function WGB.DebugF(fmt, ...)
    if not (WGB_Settings and WGB_Settings.debug) then return end
    WGB.Debug(fmt:format(...))
end

-- WGB.Warn: always printed (not gated by debug flag), for non-fatal issues.
function WGB.Warn(msg)
    local ts = date("%H:%M:%S")
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8000[WGB-WARN " .. ts .. "]|r " .. tostring(msg))
end

-- ----------------------------------------------------------------------------
-- Master enable switch
-- When disabled the addon stops all background automation (auto-invite
-- whisper listener, auto-repeat advertising). The per-feature prefs
-- (autoInviteEnabled / autoRepeatEnabled) are preserved so toggling the
-- master switch back on restores whatever the user had configured.
-- ----------------------------------------------------------------------------
function WGB.IsEnabled()
    -- Default to enabled if settings haven't loaded yet.
    return not WGB_Settings or WGB_Settings.enabled ~= false
end

function WGB.SetEnabled(on)
    on = on and true or false
    if WGB_Settings then WGB_Settings.enabled = on end
    WGB.Print(on and "|cFF00FF00Enabled.|r" or "|cFFFF8000Disabled.|r Auto features suspended.")
    if WGB.Events and WGB.Events.Fire then
        WGB.Events:Fire("WGB_ENABLED_CHANGED", on)
    end
end

-- ----------------------------------------------------------------------------
-- Bootstrap
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        WGB_Settings     = deepCopyDefaults(WGB_Settings,     DEFAULT_SETTINGS)
        WGB_CharSettings = deepCopyDefaults(WGB_CharSettings, DEFAULT_CHAR)
        WGB.Settings = WGB_Settings
        WGB.CharSettings = WGB_CharSettings
        if WGB.Events and WGB.Events.Fire then
            WGB.Events:Fire("WGB_INITIALIZED")
        end
    elseif event == "PLAYER_LOGIN" then
        WGB.Print(("v%s %s. /wgb for help."):format(WGB.VERSION, WGB.L["Loaded"]))
        -- Verify the .toc Version field matches WGB.VERSION. If they drift
        -- a hot-fix can ship without one of them being bumped, which has
        -- bitten us before.
        local tocVersion = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or nil
        if tocVersion and tocVersion ~= WGB.VERSION then
            WGB.Print(("|cFFFF8000Version mismatch:|r .toc=%s vs Core=%s"):format(
                tostring(tocVersion), tostring(WGB.VERSION)))
        end
        if WGB.Events and WGB.Events.Fire then
            WGB.Events:Fire("WGB_PLAYER_LOGIN")
        end
    end
end)
