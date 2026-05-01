-- UI/RequirementsPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.RequirementsPanel = Panel

local frame
local widgets = {}

local function makeLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function makeEditNumber(parent, x, y, w, onChange)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetSize(w or 50, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(5)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self)
        if onChange then onChange(tonumber(self:GetText()) or 0) end
    end)
    return eb
end

local function makeCheck(parent, label, x, y, onChange)
    local c = WGB.MakeCheckBox(parent, label, onChange)
    c:SetPoint("TOPLEFT", x, y)
    return c
end

-- Activity dropdown
local function makeActivityDropdown(parent, x, y)
    local dd = CreateFrame("Frame", "WGBActivityDropdown", parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y + 4)
    UIDropDownMenu_SetWidth(dd, 180)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, a in ipairs(WGB.ListActivities()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = a.name
            info.value = a.id
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dd, a.id)
                UIDropDownMenu_SetText(dd, a.name)
                WGB.Requirements:ApplyActivityDefaults(a.id)
                WGB.LootRules:ApplyActivityPreset(a.id)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    return dd
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame")

    makeLabel(frame, L["ACTIVITY"] .. ":", 8, -8)
    widgets.activity = makeActivityDropdown(frame, 90, -4)

    local rolesY = -50
    makeLabel(frame, L["ROLE_TANK"], 8, rolesY)
    widgets.tank = makeEditNumber(frame, 90, rolesY + 4, 50,
        function(v) WGB.Requirements:SetRole("tank", v) end)

    makeLabel(frame, L["ROLE_HEAL"], 160, rolesY)
    widgets.heal = makeEditNumber(frame, 240, rolesY + 4, 50,
        function(v) WGB.Requirements:SetRole("heal", v) end)

    makeLabel(frame, L["ROLE_RDPS"], 8, rolesY - 28)
    widgets.rdps = makeEditNumber(frame, 90, rolesY - 24, 50,
        function(v) WGB.Requirements:SetRole("rdps", v) end)

    makeLabel(frame, L["ROLE_MDPS"], 160, rolesY - 28)
    widgets.mdps = makeEditNumber(frame, 240, rolesY - 24, 50,
        function(v) WGB.Requirements:SetRole("mdps", v) end)

    makeLabel(frame, L["MIN_GS"], 8, -120)
    widgets.gs = makeEditNumber(frame, 90, -116, 60,
        function(v) WGB.Requirements:SetMinGS(v) end)

    widgets.fullGems = makeCheck(frame, L["FULL_GEMS"], 8, -150,
        function(v) WGB.Requirements:SetFlag("requireFullGems", v) end)
    widgets.fullEnch = makeCheck(frame, L["FULL_ENCHANTS"], 8, -180,
        function(v) WGB.Requirements:SetFlag("requireFullEnchants", v) end)
    widgets.noPvP    = makeCheck(frame, L["NO_PVP_GEAR"], 8, -210,
        function(v) WGB.Requirements:SetFlag("noPvPGear", v) end)

    return frame
end

local function refresh()
    if not frame then return end
    local r = WGB.Requirements
    if r.activity and widgets.activity then
        local a = WGB.GetActivity(r.activity)
        if a then
            UIDropDownMenu_SetSelectedValue(widgets.activity, r.activity)
            UIDropDownMenu_SetText(widgets.activity, a.name)
        end
    end
    widgets.tank:SetText(tostring(r.roles.tank or 0))
    widgets.heal:SetText(tostring(r.roles.heal or 0))
    widgets.rdps:SetText(tostring(r.roles.rdps or 0))
    widgets.mdps:SetText(tostring(r.roles.mdps or 0))
    widgets.gs:SetText(tostring(r.minGS or 0))
    widgets.fullGems:SetChecked(r.requireFullGems)
    widgets.fullEnch:SetChecked(r.requireFullEnchants)
    widgets.noPvP:SetChecked(r.noPvPGear)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("requirements", L["REQUIREMENTS"], frame)
    refresh()
end)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
