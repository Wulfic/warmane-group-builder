-- UI/AdvertPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.AdvertPanel = Panel
local frame
local w = {}

local function check(parent, label, x, y, onClick)
    local c = WGB.MakeCheckBox(parent, label, onClick)
    c:SetPoint("TOPLEFT", x, y)
    return c
end

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lbl:SetPoint("TOPLEFT", 8, -8); lbl:SetText("Preview:")

    -- Bordered scroll-edit for preview — narrowed for ~338 px half-panel.
    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", 8, -26); box:SetSize(300, 60)
    box:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.55)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local sf = CreateFrame("ScrollFrame", "WGBAdvertScroll", box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)

    w.preview = CreateFrame("EditBox", nil, sf)
    w.preview:SetMultiLine(true)
    w.preview:SetFontObject(GameFontHighlight)
    w.preview:SetWidth(264); w.preview:SetHeight(200)
    w.preview:SetAutoFocus(false)
    w.preview:EnableMouse(true)
    w.preview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    w.preview:SetScript("OnTextChanged", function(self)
        self:GetParent():UpdateScrollChildRect()
    end)
    sf:SetScrollChild(w.preview)

    -- Suffix
    local sfxLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sfxLbl:SetPoint("TOPLEFT", 8, -92); sfxLbl:SetText(L["ADVERT_SUFFIX"] .. ":")
    w.suffix = WGB.MakeInputBox(frame, 290, 22)
    w.suffix.border:SetPoint("TOPLEFT", 8, -108)
    w.suffix:SetMaxLetters(120)
    w.suffix:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.suffix:SetScript("OnEditFocusLost", function(self)
        WGB_Settings.advertSuffix = self:GetText() or ""
        WGB.Advert.dirty = true
        Panel:Refresh()
    end)

    -- Send Now + Auto-Repeat on the same row
    w.send = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.send:SetPoint("TOPLEFT", 8, -134); w.send:SetSize(110, 24)
    w.send:SetText(L["SEND_NOW"])
    w.send:SetScript("OnClick", function() WGB.Advert:Send() end)

    w.repeatBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.repeatBtn:SetPoint("TOPLEFT", 126, -134); w.repeatBtn:SetSize(170, 24)
    w.repeatBtn:SetScript("OnClick", function()
        if WGB_Settings.autoRepeatEnabled then
            WGB.Advert:StopAutoRepeat()
        else
            WGB.Advert:StartAutoRepeat(WGB_Settings.autoRepeatInterval)
        end
        Panel:Refresh()
    end)

    -- Interval (below send/repeat row)
    local ivLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ivLbl:SetPoint("TOPLEFT", 8, -168); ivLbl:SetText(L["INTERVAL_MIN"] .. ":")
    w.interval = WGB.MakeInputBox(frame, 44, 22, true)
    w.interval.border:SetPoint("TOPLEFT", 130, -164)
    w.interval:SetMaxLetters(3)
    w.interval:SetJustifyH("CENTER")
    w.interval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.interval:SetScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText()) or 5
        if v < 1 then v = 1 end
        WGB_Settings.autoRepeatInterval = v
        if WGB_Settings.autoRepeatEnabled then WGB.Advert:StartAutoRepeat(v) end
    end)

    -- Cooldown text
    w.cd = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.cd:SetPoint("TOPLEFT", 8, -196)

    -- Live cooldown ticker
    WGB.NewTicker(0.5, function() Panel:RefreshCooldown() end)

    -- Channel selection: 3 per row to fit the narrow column.
    local chanLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chanLbl:SetPoint("TOPLEFT", 8, -216); chanLbl:SetText(L["ADVERTISE_IN"])

    w.chanGlobal = check(frame, L["CHAN_GLOBAL"], 8,   -236, function(v) WGB_Settings.advertChannels.global = v end)
    w.chanTrade  = check(frame, L["CHAN_TRADE"],  120, -236, function(v) WGB_Settings.advertChannels.trade  = v end)
    w.chanLFG    = check(frame, L["CHAN_LFG"],    232, -236, function(v) WGB_Settings.advertChannels.lfg    = v end)
    w.chanYell   = check(frame, L["CHAN_YELL"],   8,   -260, function(v) WGB_Settings.advertChannels.yell   = v end)
    w.chanSay    = check(frame, L["CHAN_SAY"],    120, -260, function(v) WGB_Settings.advertChannels.say    = v end)
    w.chanGuild  = check(frame, L["CHAN_GUILD"],  232, -260, function(v) WGB_Settings.advertChannels.guild  = v end)

    local chanHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    chanHint:SetPoint("TOPLEFT", 8, -282)
    chanHint:SetWidth(290); chanHint:SetJustifyH("LEFT")
    chanHint:SetText(L["CHAN_ROTATE_HINT"])
end

function Panel:Refresh()
    if not frame then return end
    w.preview:SetText(WGB.Advert:GetMessage() or "")
    w.preview:GetParent():SetVerticalScroll(0)
    w.suffix:SetText(WGB_Settings.advertSuffix or "")
    w.interval:SetText(tostring(WGB_Settings.autoRepeatInterval or 5))
    w.repeatBtn:SetText(WGB_Settings.autoRepeatEnabled and (L["AUTO_REPEAT"] .. ": ON") or (L["AUTO_REPEAT"] .. ": OFF"))
    local ch = WGB_Settings.advertChannels or {}
    w.chanGlobal:SetChecked(ch.global ~= false)
    w.chanTrade:SetChecked(ch.trade == true)
    w.chanLFG:SetChecked(ch.lfg == true)
    w.chanYell:SetChecked(ch.yell == true)
    w.chanSay:SetChecked(ch.say == true)
    w.chanGuild:SetChecked(ch.guild == true)
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

-- Idempotent build so the combined Setup tab can construct this panel regardless
-- of WGB_PLAYER_LOGIN handler firing order (the event bus uses pairs(), which is
-- unordered).
function Panel:EnsureBuilt()
    build()
    self.frame = frame
    return frame
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    Panel:EnsureBuilt()
    Panel:Refresh()
end)
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, function() Panel:Refresh() end)
WGB.Events:Register("LOOT_RULES_CHANGED",   Panel, function() Panel:Refresh() end)
WGB.Events:Register("ROLE_FILLED",          Panel, function() Panel:Refresh() end)
