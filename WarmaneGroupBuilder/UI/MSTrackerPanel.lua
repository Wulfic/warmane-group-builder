-- UI/MSTrackerPanel.lua
-- Roll-management tab. Lists every grouped player with their auto-detected spec
-- (auto-selected) and a dropdown holding that class's specs. When a player is
-- rolling for a different spec than they joined as, pick the rolled spec from
-- the dropdown; the row label turns yellow to flag the override.

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.MSTrackerPanel = Panel
local frame
local rows = {}
local header
local scrollChild
local refresh   -- forward declaration: build()'s Reset button captures this

local MAX_ROWS   = 40
local ROW_HEIGHT = 26
local ROW_WIDTH  = 470

-- Resolve a player's class token, preferring inspect data but falling back to
-- the live unit so uninspected players still get a class color + spec list.
local function classOf(name, unit)
    local res = WGB.Inspection and WGB.Inspection.results[name]
    if res and res.class then return res.class end
    if unit then local _, c = UnitClass(unit); return c end
    return nil
end

local function buildRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(140); row.name:SetJustifyH("LEFT")

    -- Per-player spec dropdown: lists that class's specs, auto-selected to the
    -- detected spec, changeable to whatever spec they are rolling for.
    row.specDD = CreateFrame("Frame", "WGBMSSpecDD" .. i, row, "UIDropDownMenuTemplate")
    row.specDD:SetPoint("LEFT", 132, 0)
    UIDropDownMenu_SetWidth(row.specDD, 130)
    UIDropDownMenu_Initialize(row.specDD, function()
        local name  = row.playerName
        local class = row.class
        local specs = class and WGB.ClassSpecs[class]
        if not name or not specs then return end
        for _, spec in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = spec
            info.value = spec
            info.func  = function()
                WGB.MSTracker:SetSpec(name, spec)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    row:Hide()
    return row
end

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 8, -8)

    -- Reset everyone to MS and clear spec overrides — the "new item" button.
    local reset = CreateFrame("Button", "WGBMSResetButton", frame, "UIPanelButtonTemplate")
    reset:SetSize(90, 22)
    reset:SetPoint("TOPRIGHT", -26, -6)
    reset:SetText(L["MS_RESET"])
    reset:SetScript("OnClick", function()
        WGB.MSTracker:ResetAll()
        refresh()
    end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["MS_RESET_TOOLTIP"])
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local scroll = CreateFrame("ScrollFrame", "WGBMSScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -34)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)

    scrollChild = CreateFrame("Frame", "WGBMSScrollChild", scroll)
    scrollChild:SetSize(ROW_WIDTH, ROW_HEIGHT)
    scroll:SetScrollChild(scrollChild)

    for i = 1, MAX_ROWS do
        rows[i] = buildRow(scrollChild, i)
    end
end

refresh = function()
    if not frame then return end
    local mst = WGB.MSTracker
    mst:Prune()

    local i, overridden = 0, 0
    for unit, name in WGB.IterateGroup() do
        i = i + 1
        local row = rows[i]; if not row then break end
        local class = classOf(name, unit)
        row:Show()
        row.playerName = name
        row.class = class

        row.name:SetText((class and WGB.ClassColor(class) or WGB.COLOR.WHITE) .. (name or "?") .. "|r")

        local spec = mst:GetSpec(name)
        if class and WGB.ClassSpecs[class] then
            UIDropDownMenu_EnableDropDown(row.specDD)
            UIDropDownMenu_SetSelectedValue(row.specDD, spec)
            if spec then
                -- A manual off-spec override is highlighted yellow so the loot
                -- master can see who is rolling for a spec other than the one
                -- they joined as.
                local color = mst:IsOverridden(name) and WGB.COLOR.YELLOW or WGB.COLOR.WHITE
                UIDropDownMenu_SetText(row.specDD, color .. spec .. "|r")
            else
                UIDropDownMenu_SetText(row.specDD, WGB.COLOR.GREY .. L["MS_NO_SPEC"] .. "|r")
            end
        else
            UIDropDownMenu_SetText(row.specDD, WGB.COLOR.GREY .. L["MS_NO_SPEC"] .. "|r")
            UIDropDownMenu_DisableDropDown(row.specDD)
        end
        if mst:IsOverridden(name) then overridden = overridden + 1 end
    end
    for j = i + 1, MAX_ROWS do rows[j]:Hide() end

    header:SetText(("%sMS Tracker:%s  %s  %s"):format(
        WGB.COLOR.ORANGE, WGB.COLOR.RESET,
        ("Players %d"):format(i),
        WGB.Color(WGB.COLOR.YELLOW, ("Off-spec rolls %d"):format(overridden))))

    scrollChild:SetHeight(math.max(1, i) * ROW_HEIGHT)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("mstracker", L["MS_TRACKER"], frame)
    refresh()
end)
WGB.Events:Register("MS_TRACKER_CHANGED",   Panel, refresh)
WGB.Events:Register("INSPECTION_COMPLETE",  Panel, refresh)
WGB.Events:Register("INSPECTION_TIMEOUT",   Panel, refresh)
WGB.Events:Register("PLAYER_APPROVED",      Panel, refresh)
WGB.Events:Register("PLAYER_KICKED",        Panel, refresh)
