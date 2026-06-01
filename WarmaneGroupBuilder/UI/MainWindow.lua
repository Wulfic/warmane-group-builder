-- UI/MainWindow.lua
-- Top-level frame + tab controller. Each panel registers itself via
-- WGB.MainWindow:RegisterTab(id, label, frameRef).

local WGB = _G.WGB
local L = WGB.L

local MainWindow = {
    frame    = nil,
    tabs     = {},          -- list { id, label, frame, button }
    tabById  = {},
    current  = nil,
}
WGB.MainWindow = MainWindow

-- Forward declaration so buildFrame's OnHide closure can capture the real
-- local (it's defined further down). Without this, the reference would bind to
-- a nil global instead of the local function.
local clearEditFocus

local function buildFrame()
    local f = CreateFrame("Frame", "WGBMainFrame", UIParent)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetSize(math.max(WGB_Settings.mainWindow.width or 580, 580),
              math.max(WGB_Settings.mainWindow.height or 620, 620))
    f:SetPoint(WGB_Settings.mainWindow.point or "CENTER",
               WGB_Settings.mainWindow.x or 0, WGB_Settings.mainWindow.y or 0)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        WGB_Settings.mainWindow.point = point
        WGB_Settings.mainWindow.x = x
        WGB_Settings.mainWindow.y = y
    end)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:Hide()

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Warmane Group Builder v" .. WGB.VERSION)

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Content area – explicit level keeps panel children above the backdrop.
    local content = CreateFrame("Frame", "WGBMainContent", f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -56)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    content:SetFrameLevel(f:GetFrameLevel() + 2)
    f.content = content

    tinsert(UISpecialFrames, "WGBMainFrame")

    -- Closing the window (X button, Escape via UISpecialFrames, or Toggle) does
    -- NOT route through OpenTab, so a still-focused EditBox would keep drawing
    -- its caret over the world. Drop focus on every tab when the frame hides.
    f:SetScript("OnHide", function()
        for _, t in ipairs(MainWindow.tabs) do
            pcall(clearEditFocus, t.frame)
        end
    end)

    return f
end

local function relayoutTabs()
    local prev
    for i, tab in ipairs(MainWindow.tabs) do
        local b = tab.button
        b:ClearAllPoints()
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            b:SetPoint("BOTTOMLEFT", MainWindow.frame, "TOPLEFT", 12, 2)
        end
        prev = b
    end
end

-- A focused EditBox keeps rendering its cursor/text even after its parent is
-- hidden, so it "bleeds through" onto the next tab. On this 3.3.5a core even an
-- UNfocused InputBoxTemplate box can keep drawing its border under a hidden
-- ancestor (this is what made the loot "custom reserves" box show on every tab).
-- Walk a panel's descendants and both drop focus AND explicitly hide every
-- EditBox when the tab hides; re-show them when the tab opens. Every EditBox in
-- our panels is always-visible on its own tab, so blanket show/hide is safe.
local function setEditBoxesShown(frame, shown)
    if not frame or not frame.GetChildren then return end
    local kids = { frame:GetChildren() }
    for _, child in ipairs(kids) do
        if child.GetObjectType and child:GetObjectType() == "EditBox" then
            if shown then
                if child.Show then child:Show() end
            else
                if child.ClearFocus then child:ClearFocus() end
                if child.Hide then child:Hide() end
            end
        end
        setEditBoxesShown(child, shown)
    end
end
clearEditFocus = function(frame)
    setEditBoxesShown(frame, false)
end

function MainWindow:RegisterTab(id, label, frame)
    if not self.frame then self.frame = buildFrame() end
    frame:SetParent(self.frame.content)
    frame:ClearAllPoints()
    frame:SetAllPoints(self.frame.content)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(self.frame.content:GetFrameLevel() + 1)
    frame:Hide()

    local b = CreateFrame("Button", "WGBTab_" .. id, self.frame, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetText(label)
    b:SetScript("OnClick", function() MainWindow:OpenTab(id) end)

    local tab = { id = id, label = label, frame = frame, button = b }
    table.insert(self.tabs, tab)
    self.tabById[id] = tab
    relayoutTabs()
end

-- Width of a stacked section's body inside the combined scroll child. Panels
-- draw up to ~508px wide, so 510 keeps everything inside the child (which is
-- 520 wide and fits the scroll viewport without a horizontal scrollbar).
local SECTION_WIDTH = 510

-- Lazily build the single scrollable tab that hosts the stacked config/advert/
-- loot/requirements "sections". Registers itself as a normal tab once.
function MainWindow:EnsureCombinedTab()
    if self.combined then return self.combined end
    if not self.frame then self.frame = buildFrame() end

    local outer = CreateFrame("Frame")

    local scroll = CreateFrame("ScrollFrame", "WGBCombinedScroll", outer, "UIPanelScrollFrameTemplate")
    -- Leave room on the right so the template scrollbar stays inside the panel.
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)

    local child = CreateFrame("Frame", "WGBCombinedScrollChild", scroll)
    child:SetSize(SECTION_WIDTH + 10, 10)
    scroll:SetScrollChild(child)

    self.combined = { outer = outer, scroll = scroll, child = child, y = -4, sections = {} }
    self:RegisterTab("setup", L["SETUP"], outer)
    return self.combined
end

-- Add a panel frame as a stacked section in the combined scroll tab. Each
-- section gets a header label and a divider, and is given a fixed height so the
-- following section flows beneath it.
function MainWindow:RegisterSection(id, label, frame, height)
    local c = self:EnsureCombinedTab()
    local child = c.child

    local hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 4, c.y - 4)
    hdr:SetText(label)

    local line = child:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0.5, 0.5, 0.5, 0.8)
    line:SetSize(SECTION_WIDTH, 1)
    line:SetPoint("TOPLEFT", child, "TOPLEFT", 4, c.y - 26)

    frame:SetParent(child)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", child, "TOPLEFT", 4, c.y - 32)
    frame:SetWidth(SECTION_WIDTH)
    frame:SetHeight(height)
    frame:Show()

    -- header (32) + body + trailing gap (24)
    c.y = c.y - 32 - height - 24
    child:SetHeight(-c.y + 10)

    table.insert(c.sections, { id = id, label = label, frame = frame })
end

function MainWindow:OpenTab(id)
    if not self.frame then return end
    local tab = self.tabById[id]
    if not tab then return end
    for _, t in ipairs(self.tabs) do
        pcall(clearEditFocus, t.frame)
        t.frame:Hide()
        t.button:UnlockHighlight()
        t.button:SetNormalFontObject(GameFontNormal)
    end
    tab.frame:Show()
    setEditBoxesShown(tab.frame, true)
    tab.button:LockHighlight()
    tab.button:SetNormalFontObject(GameFontHighlight)
    self.current = id
    self.frame:Show()
end

function MainWindow:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        if not self.current and self.tabs[1] then
            self:OpenTab(self.tabs[1].id)
        else
            self.frame:Show()
        end
    end
end

function MainWindow:Show() if self.frame then self.frame:Show() end end
function MainWindow:Hide() if self.frame then self.frame:Hide() end end

WGB.Events:Register("WGB_PLAYER_LOGIN", MainWindow, function(self)
    if not self.frame then self.frame = buildFrame() end
end)
