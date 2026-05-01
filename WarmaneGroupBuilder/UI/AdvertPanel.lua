-- UI/AdvertPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.AdvertPanel = Panel
local frame
local w = {}

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("TOPLEFT", 8, -8); lbl:SetText("Preview:")

    -- Scroll-edit for preview
    local sf = CreateFrame("ScrollFrame", "WGBAdvertScroll", frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -32); sf:SetSize(460, 80)

    w.preview = CreateFrame("EditBox", nil, sf)
    w.preview:SetMultiLine(true)
    w.preview:SetFontObject(GameFontHighlight)
    w.preview:SetWidth(440); w.preview:SetAutoFocus(false)
    w.preview:EnableMouse(true)
    w.preview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(w.preview)

    -- Suffix
    local sfxLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sfxLbl:SetPoint("TOPLEFT", 8, -130); sfxLbl:SetText(L["ADVERT_SUFFIX"] .. ":")
    w.suffix = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    w.suffix:SetPoint("TOPLEFT", 100, -126); w.suffix:SetSize(360, 22)
    w.suffix:SetAutoFocus(false); w.suffix:SetMaxLetters(120)
    w.suffix:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.suffix:SetScript("OnEditFocusLost", function(self)
        WGB_Settings.advertSuffix = self:GetText() or ""
        WGB.Advert.dirty = true
        Panel:Refresh()
    end)

    -- Send Now
    w.send = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.send:SetPoint("TOPLEFT", 8, -160); w.send:SetSize(110, 24)
    w.send:SetText(L["SEND_NOW"])
    w.send:SetScript("OnClick", function() WGB.Advert:Send() end)

    -- Auto-Repeat toggle
    w.repeatBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.repeatBtn:SetPoint("TOPLEFT", 130, -160); w.repeatBtn:SetSize(170, 24)
    w.repeatBtn:SetScript("OnClick", function()
        if WGB_Settings.autoRepeatEnabled then
            WGB.Advert:StopAutoRepeat()
        else
            WGB.Advert:StartAutoRepeat(WGB_Settings.autoRepeatInterval)
        end
        Panel:Refresh()
    end)

    -- Interval edit
    local ivLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ivLbl:SetPoint("TOPLEFT", 312, -156); ivLbl:SetText(L["INTERVAL_MIN"] .. ":")
    w.interval = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    w.interval:SetPoint("TOPLEFT", 410, -160); w.interval:SetSize(40, 22)
    w.interval:SetAutoFocus(false); w.interval:SetNumeric(true); w.interval:SetMaxLetters(3)
    w.interval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.interval:SetScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText()) or 5
        if v < 1 then v = 1 end
        WGB_Settings.autoRepeatInterval = v
        if WGB_Settings.autoRepeatEnabled then WGB.Advert:StartAutoRepeat(v) end
    end)

    -- Cooldown text
    w.cd = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.cd:SetPoint("TOPLEFT", 8, -200)

    -- Live cooldown ticker
    WGB.NewTicker(0.5, function() Panel:RefreshCooldown() end)
end

function Panel:Refresh()
    if not frame then return end
    w.preview:SetText(WGB.Advert:GetMessage() or "")
    w.suffix:SetText(WGB_Settings.advertSuffix or "")
    w.interval:SetText(tostring(WGB_Settings.autoRepeatInterval or 5))
    w.repeatBtn:SetText(WGB_Settings.autoRepeatEnabled and (L["AUTO_REPEAT"] .. ": ON") or (L["AUTO_REPEAT"] .. ": OFF"))
end

function Panel:RefreshCooldown()
    if not frame or not frame:IsVisible() then return end
    local r = WGB.Advert:CooldownRemaining()
    if r > 0 then
        w.cd:SetText(L["NEXT_SEND"]:format(math.ceil(r)))
    else
        w.cd:SetText("Ready.")
    end
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("advert", L["ADVERTISEMENT"], frame)
    Panel:Refresh()
end)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, function() Panel:Refresh() end)
WGB.Events:Register("LOOT_RULES_CHANGED",   Panel, function() Panel:Refresh() end)
WGB.Events:Register("ROLE_FILLED",          Panel, function() Panel:Refresh() end)
