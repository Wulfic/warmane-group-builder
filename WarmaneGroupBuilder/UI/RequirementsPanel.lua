-- UI/RequirementsPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.RequirementsPanel = Panel

local frame
local widgets = {}

local function makeLabel(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    if width then fs:SetWidth(width); fs:SetJustifyH("LEFT") end
    fs:SetText(text)
    return fs
end

local function makeEditNumber(parent, x, y, w, onChange)
    local eb = WGB.MakeInputBox(parent, w or 50, 24, true)
    eb.border:SetPoint("TOPLEFT", x, y)
    eb:SetMaxLetters(5)
    eb:SetJustifyH("CENTER")
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

-- Comp builder selection state (session-only; the committed requirements live
-- in WGB.Requirements.specRequirements).
local selClass, selSpec
local MAX_COMP_ROWS = 6

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

    makeLabel(frame, L["MIN_GS"] .. ":", 8, -120, 110)
    widgets.gs = makeEditNumber(frame, 124, -116, 70,
        function(v) WGB.Requirements:SetMinGS(v) end)

    widgets.fullGems = makeCheck(frame, L["FULL_GEMS"], 8, -150,
        function(v) WGB.Requirements:SetFlag("requireFullGems", v) end)
    widgets.fullEnch = makeCheck(frame, L["FULL_ENCHANTS"], 8, -180,
        function(v) WGB.Requirements:SetFlag("requireFullEnchants", v) end)
    widgets.noPvP    = makeCheck(frame, L["NO_PVP_GEAR"], 8, -210,
        function(v) WGB.Requirements:SetFlag("noPvPGear", v) end)

    -- Advanced raid-comp toggle + builder ------------------------------------
    widgets.advanced = makeCheck(frame, L["ADVANCED_COMP"], 8, -244,
        function(v) WGB.Requirements:SetAdvancedComp(v) end)

    -- Everything below is only shown while Advanced is enabled.
    local adv = {}
    widgets.adv = adv

    local compY = -276
    adv.title = makeLabel(frame, L["SPEC_REQUIREMENTS"] .. ":", 8, compY)

    local rowY = compY - 26

    adv.classDD = CreateFrame("Frame", "WGBCompClassDropdown", frame, "UIDropDownMenuTemplate")
    adv.classDD:SetPoint("TOPLEFT", 8 - 16, rowY + 4)
    UIDropDownMenu_SetWidth(adv.classDD, 110)
    UIDropDownMenu_Initialize(adv.classDD, function()
        for _, class in ipairs(WGB.ClassOrder) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = WGB.ClassLabel(class)
            info.value = class
            info.func  = function()
                selClass = class
                selSpec  = nil
                UIDropDownMenu_SetSelectedValue(adv.classDD, class)
                UIDropDownMenu_SetText(adv.classDD, WGB.ClassLabel(class))
                UIDropDownMenu_SetText(adv.specDD, L["SPEC"])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    adv.specDD = CreateFrame("Frame", "WGBCompSpecDropdown", frame, "UIDropDownMenuTemplate")
    adv.specDD:SetPoint("TOPLEFT", 130 - 16, rowY + 4)
    UIDropDownMenu_SetWidth(adv.specDD, 110)
    UIDropDownMenu_Initialize(adv.specDD, function()
        local specs = (selClass and WGB.ClassSpecs[selClass]) or {}
        for _, spec in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = spec
            info.value = spec
            info.func  = function()
                selSpec = spec
                UIDropDownMenu_SetSelectedValue(adv.specDD, spec)
                UIDropDownMenu_SetText(adv.specDD, spec)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    adv.count = WGB.MakeInputBox(frame, 40, 24, true)
    adv.count.border:SetPoint("TOPLEFT", 256, rowY + 4)
    adv.count:SetMaxLetters(2)
    adv.count:SetJustifyH("CENTER")
    adv.count:SetText("1")
    adv.count:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    adv.count:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    adv.addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    adv.addBtn:SetPoint("TOPLEFT", adv.count.border, "TOPRIGHT", 6, 0)
    adv.addBtn:SetSize(50, 24)
    adv.addBtn:SetText(L["ADD"])
    adv.addBtn:SetScript("OnClick", function()
        if not selClass or not selSpec then return end
        local n = tonumber(adv.count:GetText()) or 1
        if n < 1 then n = 1 end
        WGB.Requirements:AddSpecRequirement(selClass, selSpec, n)
    end)

    -- Requirement list (right-click a row to remove it).
    local listY = rowY - 30
    adv.rows = {}
    for i = 1, MAX_COMP_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(440, 16)
        row:SetPoint("TOPLEFT", 16, listY - (i - 1) * 16)
        row:RegisterForClicks("RightButtonUp")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetWidth(420); row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            if self.specIndex then WGB.Requirements:RemoveSpecRequirement(self.specIndex) end
        end)
        row:Hide()
        adv.rows[i] = row
    end
    adv.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    adv.empty:SetPoint("TOPLEFT", 16, listY)
    adv.empty:SetText(L["COMP_LIST_EMPTY"])

    return frame
end

local function setAdvShown(shown)
    local adv = widgets.adv
    if not adv then return end
    local fn = shown and "Show" or "Hide"
    adv.title[fn](adv.title)
    adv.classDD[fn](adv.classDD)
    adv.specDD[fn](adv.specDD)
    adv.count.border[fn](adv.count.border)
    adv.addBtn[fn](adv.addBtn)
    adv.empty[fn](adv.empty)
    for _, row in ipairs(adv.rows) do
        if shown and row.specIndex then row:Show() else row:Hide() end
    end
end

local function refreshComp()
    local adv = widgets.adv
    if not adv then return end
    local r = WGB.Requirements
    local list = r.specRequirements
    local shown = math.min(#adv.rows, #list)
    for i = 1, shown do
        local sr  = list[i]
        local row = adv.rows[i]
        row.specIndex = i
        row.text:SetText(("%d. %dx %s %s   |cFF888888(right-click to remove)|r"):format(
            i, sr.count or 1, sr.spec or "?", WGB.ClassLabel(sr.class)))
    end
    for i = shown + 1, #adv.rows do
        adv.rows[i].specIndex = nil
        adv.rows[i]:Hide()
    end
    if #list == 0 then
        adv.empty:SetText(L["COMP_LIST_EMPTY"])
    elseif #list > #adv.rows then
        adv.empty:SetText(("|cFF888888+%d more|r"):format(#list - #adv.rows))
    else
        adv.empty:SetText("")
    end
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
    widgets.advanced:SetChecked(r.advancedComp)
    refreshComp()
    setAdvShown(r.advancedComp)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("requirements", L["REQUIREMENTS"], frame)
    refresh()
end)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
