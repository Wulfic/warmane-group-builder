-- UI/MSTrackerPanel.lua
-- Roll-management tab. Lists every grouped player with their auto-detected spec
-- (auto-selected) and an MS/OS toggle. Click the spec cell to cycle to a
-- different spec when the player is rolling for an off-set; the cell turns
-- yellow to flag that the tracked spec differs from what they joined as. Click
-- the MS/OS cell to flip their roll category.

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
local ROW_HEIGHT = 20
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

    -- Spec cell: clicking cycles through the class's specs (auto-detected by
    -- default, yellow when manually pointed at a different roll spec).
    row.spec = CreateFrame("Button", nil, row)
    row.spec:SetSize(150, ROW_HEIGHT)
    row.spec:SetPoint("LEFT", 144, 0)
    row.spec.text = row.spec:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.spec.text:SetAllPoints()
    row.spec.text:SetJustifyH("LEFT")
    row.spec:SetScript("OnClick", function(self)
        local name = row.playerName
        if name then WGB.MSTracker:CycleSpec(name, row.class) end
    end)
    row.spec:SetScript("OnEnter", function(self)
        if not row.playerName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["MS_SPEC_TOOLTIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.spec:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- MS/OS toggle.
    row.roll = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.roll:SetSize(50, ROW_HEIGHT - 2)
    row.roll:SetPoint("LEFT", 300, 0)
    row.roll:SetScript("OnClick", function(self)
        local name = row.playerName
        if name then WGB.MSTracker:ToggleRoll(name) end
    end)
    row.roll:SetScript("OnEnter", function(self)
        if not row.playerName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["MS_ROLL_TOOLTIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    row.roll:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

    local i, msCount, osCount = 0, 0, 0
    for unit, name in WGB.IterateGroup() do
        i = i + 1
        local row = rows[i]; if not row then break end
        local class = classOf(name, unit)
        row:Show()
        row.playerName = name
        row.class = class

        row.name:SetText((class and WGB.ClassColor(class) or WGB.COLOR.WHITE) .. (name or "?") .. "|r")

        local spec = mst:GetSpec(name)
        if spec then
            -- Detected spec shows in class color; a manual off-spec override is
            -- highlighted yellow so the loot master can see who is rolling for a
            -- spec other than the one they joined as.
            local color = mst:IsOverridden(name) and WGB.COLOR.YELLOW
                or (class and WGB.ClassColor(class) or WGB.COLOR.WHITE)
            row.spec.text:SetText(color .. spec .. "|r")
        else
            row.spec.text:SetText(WGB.COLOR.GREY .. (L["MS_NO_SPEC"]) .. "|r")
        end

        local roll = mst:GetRoll(name)
        if roll == "OS" then
            row.roll:SetText(WGB.Color(WGB.COLOR.ORANGE, L["MS_OS"]))
            osCount = osCount + 1
        else
            row.roll:SetText(WGB.Color(WGB.COLOR.GREEN, L["MS_MS"]))
            msCount = msCount + 1
        end
    end
    for j = i + 1, MAX_ROWS do rows[j]:Hide() end

    header:SetText(("%sMS Tracker:%s  %s %d  %s %d"):format(
        WGB.COLOR.ORANGE, WGB.COLOR.RESET,
        WGB.Color(WGB.COLOR.GREEN, L["MS_MS"]), msCount,
        WGB.Color(WGB.COLOR.ORANGE, L["MS_OS"]), osCount))

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
