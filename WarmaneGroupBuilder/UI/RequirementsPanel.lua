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
local COMP_ROW_HEIGHT    = 16
local VISIBLE_COMP_ROWS  = 5     -- rows visible before the list scrolls
local COMP_LIST_WIDTH    = 450

-- Lazily create (and cache) a clickable row inside the scroll child.
local function acquireCompRow(adv, i)
    local row = adv.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, adv.scrollChild)
    row:SetSize(COMP_LIST_WIDTH, COMP_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * COMP_ROW_HEIGHT)
    row:RegisterForClicks("RightButtonUp")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetWidth(COMP_LIST_WIDTH - 10); row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
        if self.specIndex then WGB.Requirements:RemoveSpecRequirement(self.specIndex) end
    end)
    adv.rows[i] = row
    return row
end


local function build()
    if frame then return frame end
    frame = CreateFrame("Frame")

    makeLabel(frame, L["ACTIVITY"] .. ":", 8, -8)
    widgets.activity = makeActivityDropdown(frame, 90, -4)

    -- Custom activity name input (visible only when "Custom" is selected).
    widgets.customName = WGB.MakeInputBox(frame, 280, 22)
    widgets.customName.border:SetPoint("TOPLEFT", 8, -38)
    widgets.customName:SetMaxLetters(60)
    widgets.customName:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    widgets.customName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    widgets.customName:SetScript("OnEditFocusLost", function(self)
        WGB.Requirements:SetCustomName(self:GetText())
    end)
    widgets.customName.border:Hide()

    local rolesY = -80
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

    makeLabel(frame, L["MIN_GS"] .. ":", 8, -150, 110)
    widgets.gs = makeEditNumber(frame, 124, -146, 70,
        function(v) WGB.Requirements:SetMinGS(v) end)
    widgets.gsDisable = makeCheck(frame, L["GS_DISABLE"], 204, -150,
        function(v)
            if v then
                WGB.Requirements:SetMinGS(0)
                widgets.gs:SetText("0")
            end
        end)

    widgets.fullGems = makeCheck(frame, L["FULL_GEMS"], 8, -180,
        function(v) WGB.Requirements:SetFlag("requireFullGems", v) end)
    widgets.fullEnch = makeCheck(frame, L["FULL_ENCHANTS"], 8, -210,
        function(v) WGB.Requirements:SetFlag("requireFullEnchants", v) end)
    widgets.noPvP    = makeCheck(frame, L["NO_PVP_GEAR"], 8, -240,
        function(v) WGB.Requirements:SetFlag("noPvPGear", v) end)
    widgets.offSpec  = makeCheck(frame, L["FLAG_OFFSPEC_GEAR"], 300, -240,
        function(v) WGB.Requirements:SetFlag("flagOffSpecGear", v) end)

    -- Refill flow (right column): advertise to backfill an in-progress group and
    -- tag the boss it's currently on. Boss dropdown reads the live activity list.
    widgets.refill = makeCheck(frame, L["REFILL_MODE"], 300, -150,
        function(v) WGB.Requirements:SetRefillMode(v) end)

    widgets.bossLabel = makeLabel(frame, L["BOSS"] .. ":", 300, -184)
    widgets.bossDD = CreateFrame("Frame", "WGBBossDropdown", frame, "UIDropDownMenuTemplate")
    widgets.bossDD:SetPoint("TOPLEFT", 300 - 16, -204 + 4)
    UIDropDownMenu_SetWidth(widgets.bossDD, 150)
    UIDropDownMenu_Initialize(widgets.bossDD, function()
        for _, boss in ipairs(WGB.GetBosses(WGB.Requirements.activity)) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = boss
            info.value = boss
            info.func  = function()
                WGB.Requirements:SetCurrentBoss(boss)
                UIDropDownMenu_SetSelectedValue(widgets.bossDD, boss)
                UIDropDownMenu_SetText(widgets.bossDD, boss)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Advanced raid-comp toggle + builder ------------------------------------
    widgets.advanced = makeCheck(frame, L["ADVANCED_COMP"], 8, -274,
        function(v) WGB.Requirements:SetAdvancedComp(v) end)

    -- Everything below is only shown while Advanced is enabled.
    local adv = {}
    widgets.adv = adv

    local compY = -306
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

    -- Requirement list (right-click a row to remove it). The list lives inside a
    -- scroll frame so a full 25-man comp (10+ distinct spec rows) stays reachable
    -- instead of being capped at the handful of rows that fit the panel.
    local countY = rowY - 28
    adv.countSummary = makeLabel(frame, "", 16, countY, 460)

    local listY = countY - 20
    adv.scroll = CreateFrame("ScrollFrame", "WGBCompListScroll", frame, "UIPanelScrollFrameTemplate")
    adv.scroll:SetPoint("TOPLEFT", 16, listY)
    adv.scroll:SetSize(COMP_LIST_WIDTH, VISIBLE_COMP_ROWS * COMP_ROW_HEIGHT)

    adv.scrollChild = CreateFrame("Frame", nil, adv.scroll)
    adv.scrollChild:SetSize(COMP_LIST_WIDTH, VISIBLE_COMP_ROWS * COMP_ROW_HEIGHT)
    adv.scroll:SetScrollChild(adv.scrollChild)

    -- Rows are pooled lazily into the scroll child as the comp grows.
    adv.rows = {}

    adv.empty = adv.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    adv.empty:SetPoint("TOPLEFT", 0, 0)
    adv.empty:SetText(L["COMP_LIST_EMPTY"])

    -- Saved comp presets (always visible — loading one can also flip Advanced on).
    local pre = {}
    widgets.presets = pre
    local presY = listY - VISIBLE_COMP_ROWS * COMP_ROW_HEIGHT - 14

    pre.title = makeLabel(frame, L["COMP_PRESETS"] .. ":", 8, presY)

    pre.name = WGB.MakeInputBox(frame, 220, 24)
    pre.name.border:SetPoint("TOPLEFT", 8, presY - 24)
    pre.name:SetMaxLetters(40)
    pre.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    pre.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    pre.saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pre.saveBtn:SetPoint("TOPLEFT", pre.name.border, "TOPRIGHT", 8, 0)
    pre.saveBtn:SetSize(80, 24)
    pre.saveBtn:SetText(L["SAVE"])
    pre.saveBtn:SetScript("OnClick", function()
        local nm = pre.name:GetText()
        if nm and nm:match("%S") then
            if WGB.Requirements:SavePreset(nm) then
                WGB.Print(L["COMP_SAVED"]:format(nm:match("^%s*(.-)%s*$")))
                pre.name:SetText("")
                pre.selected = nm:match("^%s*(.-)%s*$")
                refresh()
            end
        end
    end)

    -- Row 2: dropdown (interior width 190) + Load + Delete.
    -- UIDropDownMenuTemplate adds ~28px for the arrow; we position the frame
    -- at x-16 (standard offset) so the visible text area starts at x=8.
    -- Visual right edge of the text area ≈ 8+190 = 198; buttons start at 206.
    pre.dd = CreateFrame("Frame", "WGBCompPresetDropdown", frame, "UIDropDownMenuTemplate")
    pre.dd:SetPoint("TOPLEFT", 8 - 16, presY - 52)
    UIDropDownMenu_SetWidth(pre.dd, 190)
    UIDropDownMenu_Initialize(pre.dd, function()
        for _, nm in ipairs(WGB.Requirements:ListPresets()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = nm
            info.value = nm
            info.func  = function()
                pre.selected = nm
                UIDropDownMenu_SetSelectedValue(pre.dd, nm)
                UIDropDownMenu_SetText(pre.dd, nm)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    pre.loadBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pre.loadBtn:SetPoint("TOPLEFT", 206, presY - 48)
    pre.loadBtn:SetSize(80, 24)
    pre.loadBtn:SetText(L["LOAD"])
    pre.loadBtn:SetScript("OnClick", function()
        if pre.selected and WGB.Requirements:LoadPreset(pre.selected) then
            WGB.Print(L["COMP_LOADED"]:format(pre.selected))
        end
    end)

    pre.delBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pre.delBtn:SetPoint("TOPLEFT", pre.loadBtn, "TOPRIGHT", 6, 0)
    pre.delBtn:SetSize(80, 24)
    pre.delBtn:SetText(L["DELETE"])
    pre.delBtn:SetScript("OnClick", function()
        if pre.selected and WGB.Requirements:DeletePreset(pre.selected) then
            WGB.Print(L["COMP_DELETED"]:format(pre.selected))
            pre.selected = nil
            refresh()
        end
    end)

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
    adv.countSummary[fn](adv.countSummary)
    adv.scroll[fn](adv.scroll)
    adv.empty[fn](adv.empty)
    for _, row in ipairs(adv.rows) do
        if shown and row.specIndex then row:Show() else row:Hide() end
    end
end

local function setRefillShown(shown)
    local fn = shown and "Show" or "Hide"
    if widgets.bossLabel then widgets.bossLabel[fn](widgets.bossLabel) end
    if widgets.bossDD then widgets.bossDD[fn](widgets.bossDD) end
end

local function refreshComp()
    local adv = widgets.adv
    if not adv then return end
    local r = WGB.Requirements
    local list = r.specRequirements

    -- Tally the chosen comp into role buckets for the summary header.
    local sum = { tank = 0, heal = 0, mdps = 0, rdps = 0 }
    for _, sr in ipairs(list) do
        local role = WGB.CompSpecRole(sr.class, sr.spec)
        sum[role] = (sum[role] or 0) + (sr.count or 1)
    end
    local total = sum.tank + sum.heal + sum.mdps + sum.rdps
    adv.countSummary:SetText(
        L["COMP_COUNT_SUMMARY"]:format(sum.tank, sum.heal, sum.mdps, sum.rdps, total))

    for i = 1, #list do
        local sr  = list[i]
        local row = acquireCompRow(adv, i)
        row.specIndex = i
        row.text:SetText(("%d. %dx %s %s   |cFF888888(right-click to remove)|r"):format(
            i, sr.count or 1, sr.spec or "?", WGB.ClassLabel(sr.class)))
        row:Show()
    end
    for i = #list + 1, #adv.rows do
        adv.rows[i].specIndex = nil
        adv.rows[i]:Hide()
    end

    -- Grow the scroll child so the scrollbar engages once the list overflows.
    local rows = math.max(#list, VISIBLE_COMP_ROWS)
    adv.scrollChild:SetHeight(rows * COMP_ROW_HEIGHT)

    if #list == 0 then
        adv.empty:SetText(L["COMP_LIST_EMPTY"])
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
    widgets.gsDisable:SetChecked(r.minGS == 0)
    local isCustom = (r.activity == "custom")
    if isCustom then
        widgets.customName.border:Show()
        widgets.customName:SetText(r.customName or "")
    else
        widgets.customName.border:Hide()
    end
    widgets.fullGems:SetChecked(r.requireFullGems)
    widgets.fullEnch:SetChecked(r.requireFullEnchants)
    widgets.noPvP:SetChecked(r.noPvPGear)
    widgets.offSpec:SetChecked(r.flagOffSpecGear)
    widgets.refill:SetChecked(r.refillMode)
    setRefillShown(r.refillMode)
    if r.currentBoss and r.currentBoss ~= "" then
        UIDropDownMenu_SetText(widgets.bossDD, r.currentBoss)
    else
        UIDropDownMenu_SetText(widgets.bossDD, L["BOSS_PICK"])
    end
    widgets.advanced:SetChecked(r.advancedComp)
    refreshComp()
    setAdvShown(r.advancedComp)

    local pre = widgets.presets
    if pre then
        -- Drop a stale selection if the preset was deleted elsewhere.
        if pre.selected then
            local exists = false
            for _, nm in ipairs(WGB.Requirements:ListPresets()) do
                if nm == pre.selected then exists = true; break end
            end
            if not exists then pre.selected = nil end
        end
        UIDropDownMenu_SetText(pre.dd, pre.selected or L["COMP_PICK_PROMPT"])
    end
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterSection("requirements", L["REQUIREMENTS"], frame, 570)
    refresh()
end)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
