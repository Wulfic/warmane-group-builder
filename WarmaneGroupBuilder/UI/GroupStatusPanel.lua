-- UI/GroupStatusPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.GroupStatusPanel = Panel
local frame
local rows = {}
local header
local scrollChild
local refresh   -- forward declaration: build()'s Rescan button captures this

-- Up to a full 40-man raid. Two columns of clickable rows live inside a scroll
-- frame so the whole roster stays reachable.
local MAX_ROWS    = 40
local COLS        = 2
local ROW_HEIGHT  = 18
local COL_WIDTH   = 340   -- horizontal stride between the two columns
local ROW_WIDTH   = 330   -- width of a single row's clickable/content area

local function buildRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    local col  = (i - 1) % COLS
    local line = math.floor((i - 1) / COLS)
    row:SetPoint("TOPLEFT", col * COL_WIDTH, -line * ROW_HEIGHT)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 0, 0); row.name:SetWidth(120); row.name:SetJustifyH("LEFT")

    row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.role:SetPoint("LEFT", 124, 0); row.role:SetWidth(50); row.role:SetJustifyH("LEFT")

    row.gs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.gs:SetPoint("LEFT", 178, 0); row.gs:SetWidth(50); row.gs:SetJustifyH("LEFT")

    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", 232, 0); row.status:SetWidth(95); row.status:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        local name = self.playerName
        if not name then return end
        local res = WGB.Inspection and WGB.Inspection.results[name] or nil
        if res then WGB.InspectionPopup:Show(name, res) end
    end)
    row:Hide()
    return row
end

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 8, -8)

    -- Rescan button: re-inspect everyone not yet approved (handles misread
    -- GearScore or a player who swapped gear sets after the first scan).
    local rescan = CreateFrame("Button", "WGBGroupRescanButton", frame, "UIPanelButtonTemplate")
    rescan:SetSize(80, 22)
    rescan:SetPoint("TOPRIGHT", -26, -6)
    rescan:SetText(L["RESCAN"])
    rescan:SetScript("OnClick", function()
        if WGB.Inspection and WGB.Inspection.RescanUnapproved then
            WGB.Inspection:RescanUnapproved()
            refresh()
        end
    end)
    rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["RESCAN_TOOLTIP"])
        GameTooltip:Show()
    end)
    rescan:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Scroll frame holds all rows; -26 on the right keeps the template scrollbar
    -- inside the panel rather than spilling past the edge.
    local scroll = CreateFrame("ScrollFrame", "WGBGroupScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -34)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)

    scrollChild = CreateFrame("Frame", "WGBGroupScrollChild", scroll)
    scrollChild:SetSize(COLS * COL_WIDTH, ROW_HEIGHT)
    scroll:SetScrollChild(scrollChild)

    for i = 1, MAX_ROWS do
        rows[i] = buildRow(scrollChild, i)
    end
end

refresh = function()
    if not frame then return end
    local r = WGB.Requirements

    local total = 0
    for _ in WGB.IterateGroup() do total = total + 1 end

    header:SetText(("%s%s Players %d  Tanks %d/%d  Heals %d/%d  RDPS %d/%d  MDPS %d/%d"):format(
        WGB.COLOR.ORANGE, "Roster:" .. WGB.COLOR.RESET,
        total,
        r.filled.tank or 0, r.roles.tank or 0,
        r.filled.heal or 0, r.roles.heal or 0,
        r.filled.rdps or 0, r.roles.rdps or 0,
        r.filled.mdps or 0, r.roles.mdps or 0))

    local i = 0
    for unit, name in WGB.IterateGroup() do
        i = i + 1
        local row = rows[i]; if not row then break end
        row:Show()
        row.playerName = name
        local _, class = UnitClass(unit)
        row.name:SetText((class and WGB.ClassColor(class) or "|cFFFFFFFF") .. (name or "?") .. "|r")
        local result = WGB.Inspection and WGB.Inspection.results[name] or nil
        row.role:SetText(result and result.spec or "")
        row.gs:SetText(result and tostring(result.gearScore or "?") or "...")
        if WGB.GroupManager.approved[name] then
            row.status:SetText(WGB.Color(WGB.COLOR.GREEN, "Approved"))
        elseif result then
            local ok, warns = WGB.Requirements:ValidatePlayer(result)
            row.status:SetText(ok and WGB.Color(WGB.COLOR.GREEN, "Pass")
                                  or WGB.Color(WGB.COLOR.RED, "Issues: " .. #warns))
        else
            row.status:SetText(WGB.Color(WGB.COLOR.YELLOW, "Inspecting..."))
        end
    end
    for j = i + 1, MAX_ROWS do rows[j]:Hide() end

    -- Grow the scroll child to the number of visible rows so the scrollbar
    -- engages once the roster overflows the viewport.
    local lines = math.max(1, math.ceil(i / COLS))
    scrollChild:SetHeight(lines * ROW_HEIGHT)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("group", L["GROUP_STATUS"], frame)
    refresh()
end)
WGB.Events:Register("INSPECTION_COMPLETE", Panel, refresh)
WGB.Events:Register("INSPECTION_TIMEOUT",  Panel, refresh)
WGB.Events:Register("ACHIEVEMENT_CHECK_COMPLETE", Panel, refresh)
WGB.Events:Register("ROLE_FILLED",          Panel, refresh)
WGB.Events:Register("PLAYER_APPROVED",      Panel, refresh)
WGB.Events:Register("PLAYER_KICKED",        Panel, refresh)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
