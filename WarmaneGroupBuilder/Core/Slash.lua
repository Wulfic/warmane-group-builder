-- Core/Slash.lua
-- Loaded last so every module's public API exists before commands dispatch to them.

local WGB = _G.WGB
local L = WGB.L

local function help()
    WGB.Print(L["SLASH_HELP_HEADER"])
    WGB.Print("  " .. L["SLASH_HELP_TOGGLE"])
    WGB.Print("  " .. L["SLASH_HELP_HELP"])
    WGB.Print("  " .. L["SLASH_HELP_ADVERT"])
    WGB.Print("  " .. L["SLASH_HELP_START"])
    WGB.Print("  " .. L["SLASH_HELP_STOP"])
    WGB.Print("  " .. L["SLASH_HELP_LOCK"])
    WGB.Print("  " .. L["SLASH_HELP_KICK"])
    WGB.Print("  " .. L["SLASH_HELP_APPROVE"])
    WGB.Print("  " .. L["SLASH_HELP_CONFIG"])
    WGB.Print("  " .. L["SLASH_HELP_RESET"])
    WGB.Print("  " .. L["SLASH_HELP_DEBUG"])
end

local dispatch = {
    [""] = function()
        if WGB.MainWindow and WGB.MainWindow.Toggle then WGB.MainWindow:Toggle() end
    end,
    help = help,

    advert = function()
        if WGB.Advert and WGB.Advert.Send then WGB.Advert:Send() end
    end,

    start = function()
        if WGB.AutoInvite then WGB.AutoInvite:SetEnabled(true) end
        if WGB.Advert then WGB.Advert:StartAutoRepeat() end
        WGB.Print("Recruiting started.")
    end,

    stop = function()
        if WGB.AutoInvite then WGB.AutoInvite:SetEnabled(false) end
        if WGB.Advert then WGB.Advert:StopAutoRepeat() end
        WGB.Print("Recruiting stopped.")
    end,

    lock = function()
        if WGB.AutoInvite then WGB.AutoInvite:SetEnabled(false) end
        WGB.Print("Auto-invite locked. Existing group preserved.")
    end,

    kick = function(arg)
        local name = arg and arg:match("^%s*(%S+)") or nil
        if not name or name == "" then WGB.Print("Usage: /wgb kick <name>"); return end
        if WGB.GroupManager and WGB.GroupManager.RejectPlayer then
            WGB.GroupManager:RejectPlayer(name, "manual kick")
        else
            local ok, why = WGB.SafeKick(name)
            if not ok and why == "combat" then
                WGB.Print(L["WILL_KICK_AFTER_COMBAT"]:format(name))
            end
        end
    end,

    approve = function(arg)
        local name = arg and arg:match("^%s*(%S+)") or nil
        if not name or name == "" then WGB.Print("Usage: /wgb approve <name>"); return end
        if WGB.GroupManager then WGB.GroupManager:ApprovePlayer(name) end
    end,

    config = function()
        if WGB.MainWindow and WGB.MainWindow.OpenTab then WGB.MainWindow:OpenTab("config") end
    end,

    reset = function()
        StaticPopup_Show("WGB_RESET_CONFIRM")
    end,

    debug = function(arg)
        local sub = arg and arg:match("^%s*(%S+)") or ""
        if sub == "dump" then
            WGB.Print("=== WGB Debug Dump ===")
            WGB.Print("Version: " .. WGB.VERSION)
            WGB.Print("debug: "              .. tostring(WGB_Settings.debug))
            WGB.Print("autoInviteEnabled: "  .. tostring(WGB_Settings.autoInviteEnabled))
            WGB.Print("autoInviteKeyword: '" .. tostring(WGB_Settings.autoInviteKeyword) .. "'")
            WGB.Print("autoRepeatEnabled: "  .. tostring(WGB_Settings.autoRepeatEnabled))
            WGB.Print("autoRepeatInterval: " .. tostring(WGB_Settings.autoRepeatInterval) .. " min")
            WGB.Print("defaultActivity: "    .. tostring(WGB_Settings.defaultActivity))
            WGB.Print("showMinimap: "        .. tostring(WGB_Settings.showMinimap))
            WGB.Print("whisperResponse: '"   .. tostring(WGB_Settings.whisperResponse) .. "'")
            if WGB.Events and WGB.Events.ListEvents then
                WGB.Events:ListEvents()
            end
        else
            WGB_Settings.debug = not WGB_Settings.debug
            WGB.Print("Debug: " .. (WGB_Settings.debug and "ON" or "OFF"))
        end
    end,
}

StaticPopupDialogs["WGB_RESET_CONFIRM"] = {
    text = L["RESET_CONFIRM"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        wipe(WGB_Settings)
        if WGB_CharSettings then wipe(WGB_CharSettings) end
        ReloadUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

SLASH_WGB1 = "/wgb"
SlashCmdList["WGB"] = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local fn = dispatch[cmd]
    if fn then fn(rest) else help() end
end
