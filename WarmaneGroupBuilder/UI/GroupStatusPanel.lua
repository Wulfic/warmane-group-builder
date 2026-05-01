-- UI/GroupStatusPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.GroupStatusPanel = Panel
local frame
local rows = {}
local header

local MAX_ROWS = 25

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 8, -8)

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(460, 18)
        row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * 18)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 0, 0); row.name:SetWidth(160); row.name:SetJustifyH("LEFT")

        row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.role:SetPoint("LEFT", 165, 0); row.role:SetWidth(60)

        row.gs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.gs:SetPoint("LEFT", 230, 0); row.gs:SetWidth(80)

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.status:SetPoint("LEFT", 315, 0); row.status:SetWidth(140)

        row:SetScript("OnClick", function(self)
            local name = self.playerName
            if not name then return end
            local res = WGB.Inspection and WGB.Inspection.results[name] or nil
            if res then WGB.InspectionPopup:Show(name, res) end
        end)
        row:Hide()
        rows[i] = row
    end
end

local function refresh()
    if not frame then return end
    local r = WGB.Requirements
    header:SetText(("%s%s Tanks %d/%d  Heals %d/%d  RDPS %d/%d  MDPS %d/%d"):format(
        WGB.COLOR.ORANGE, "Roster:" .. WGB.COLOR.RESET,
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
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("group", L["GROUP_STATUS"], frame)
    refresh()
end)
WGB.Events:Register("INSPECTION_COMPLETE", Panel, refresh)
WGB.Events:Register("INSPECTION_TIMEOUT",  Panel, refresh)
WGB.Events:Register("ROLE_FILLED",          Panel, refresh)
WGB.Events:Register("PLAYER_APPROVED",      Panel, refresh)
WGB.Events:Register("PLAYER_KICKED",        Panel, refresh)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
