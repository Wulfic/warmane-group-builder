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
