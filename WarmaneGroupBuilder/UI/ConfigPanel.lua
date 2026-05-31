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
    -- Bordered container so the edit area + scrollbar read as one widget instead
    -- of leaving the scroll arrows floating in empty space.
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(width, height)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.55)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local sf = CreateFrame("ScrollFrame", "WGBConfigScrollFrame" .. multiEditCount, box, "UIPanelScrollFrameTemplate")
    -- Leave room on the right for the template's scrollbar so it stays inside
    -- the border rather than spilling past the edge of the box.
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(GameFontHighlight)
    eb:SetWidth(width - 36); eb:SetHeight(height * 4)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText() or "") end)
    eb:SetScript("OnTextChanged", function(self)
        self:GetParent():UpdateScrollChildRect()
    end)
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
    w.kw = WGB.MakeInputBox(frame, 260, 22)
    w.kw.border:SetPoint("TOPLEFT", 8, -132)
    w.kw:SetMaxLetters(40)
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
    w.whisper:GetParent():SetVerticalScroll(0)
    w.kw:SetText(WGB_Settings.autoInviteKeyword or "")
    w.minimap:SetChecked(WGB_Settings.showMinimap)
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("config", L["CONFIG"], frame)
    refresh()
end)
