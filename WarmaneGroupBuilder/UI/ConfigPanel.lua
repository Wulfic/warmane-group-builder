-- UI/ConfigPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.ConfigPanel = Panel
local frame
local w = {}

local multiEditCount = 0
local function multiEdit(parent, x, y, width, height, onCommit)
    multiEditCount = multiEditCount + 1
    local sf = CreateFrame("ScrollFrame", "WGBConfigScrollFrame" .. multiEditCount, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", x, y); sf:SetSize(width, height)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(GameFontHighlight)
    eb:SetWidth(width - 20); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText() or "") end)
    sf:SetScrollChild(eb)
    return eb
end

local function check(parent, label, x, y, onClick)
    local c = WGB.MakeCheckBox(parent, label, onClick)
    c:SetPoint("TOPLEFT", x, y)
    return c
end

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("TOPLEFT", 8, -8); lbl:SetText(L["WHISPER_RESPONSE"] .. " ({player} = invitee name):")
    -- Width leaves room on the right for the UIPanelScrollFrameTemplate scrollbar.
    w.whisper = multiEdit(frame, 8, -32, 480, 60,
        function(t) WGB_Settings.whisperResponse = t end)

    local kwLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kwLbl:SetPoint("TOPLEFT", 8, -110); kwLbl:SetText(L["AUTO_INVITE_KEYWORD"] .. " (blank = any whisper):")
    w.kw = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    w.kw:SetPoint("TOPLEFT", 8, -132); w.kw:SetSize(260, 22)
    w.kw:SetAutoFocus(false); w.kw:SetMaxLetters(40)
    w.kw:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.kw:SetScript("OnEditFocusLost", function(self) WGB_Settings.autoInviteKeyword = self:GetText() or "" end)

    w.minimap = check(frame, L["SHOW_MINIMAP"], 8, -170, function(v)
        WGB_Settings.showMinimap = v
        if WGB.MinimapButton then WGB.MinimapButton:SetShown(v) end
    end)

    w.reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.reset:SetPoint("BOTTOMLEFT", 8, 8); w.reset:SetSize(140, 24)
    w.reset:SetText(L["RESET_DEFAULTS"])
    w.reset:SetScript("OnClick", function() StaticPopup_Show("WGB_RESET_CONFIRM") end)
end

local function refresh()
    if not frame then return end
    w.whisper:SetText(WGB_Settings.whisperResponse or "")
    w.kw:SetText(WGB_Settings.autoInviteKeyword or "")
    w.minimap:SetChecked(WGB_Settings.showMinimap)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("config", L["CONFIG"], frame)
    refresh()
end)
