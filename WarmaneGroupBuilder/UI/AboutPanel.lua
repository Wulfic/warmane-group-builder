-- UI/AboutPanel.lua
-- Simple informational tab: project credit + copyable GitHub links. The 3.3.5a
-- client can't open a browser, so each link is shown in a read-only EditBox that
-- selects its whole contents on click — the user copies with Ctrl+C.

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.AboutPanel = Panel
local frame

-- A non-editable, selectable URL field. Clicking it highlights the whole URL so
-- the player can Ctrl+C. Any typing is reverted so the text stays the link.
local function makeLinkBox(parent, url, width)
    local eb = WGB.MakeInputBox(parent, width or 360, 22)
    eb:SetText(url)
    eb:SetCursorPosition(0)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); self:SetCursorPosition(0) end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= url then
            self:SetText(url)
            self:HighlightText()
        end
    end)
    eb:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    return eb
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "WGBAboutPanel", UIParent)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Warmane Group Builder")

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    version:SetText(WGB.Color(WGB.COLOR.GREY, ("v%s"):format(WGB.VERSION)))

    local by = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    by:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -4)
    by:SetText(L["ABOUT_BY"])

    -- GitHub project link
    local projLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    projLabel:SetPoint("TOPLEFT", by, "BOTTOMLEFT", 0, -24)
    projLabel:SetText(L["ABOUT_PROJECT"] .. ":")
    local projBox = makeLinkBox(frame, "https://github.com/Wulfic/warmane-group-builder", 360)
    projBox.border:SetPoint("TOPLEFT", projLabel, "BOTTOMLEFT", 0, -4)

    -- Found a bug? -> issues page
    local bugLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bugLabel:SetPoint("TOPLEFT", projBox.border, "BOTTOMLEFT", 0, -20)
    bugLabel:SetText(WGB.Color(WGB.COLOR.YELLOW, L["ABOUT_BUG"]) .. " " .. L["ABOUT_BUG_LABEL"])
    local bugBox = makeLinkBox(frame, "https://github.com/Wulfic/warmane-group-builder/issues", 360)
    bugBox.border:SetPoint("TOPLEFT", bugLabel, "BOTTOMLEFT", 0, -4)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", bugBox.border, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["ABOUT_COPY_HINT"])

    Panel.frame = frame
    return frame
end

function Panel:EnsureBuilt()
    build()
    return frame
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("about", L["ABOUT"], frame)
end)
