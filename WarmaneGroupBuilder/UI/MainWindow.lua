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
    f:SetSize(math.max(WGB_Settings.mainWindow.width or 760, 760),
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

    -- Master enable switch (top-left corner). Unchecking suspends all
    -- automation (auto-invite whispers + auto-repeat advertising).
    local enableCheck = WGB.MakeCheckBox(f, L["MASTER_ENABLED"], function(on)
        WGB.SetEnabled(on)
    end)
    enableCheck:SetPoint("TOPLEFT", 14, -12)
    enableCheck:SetChecked(WGB.IsEnabled())
    enableCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["MASTER_ENABLED_TOOLTIP"], nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    enableCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.enableCheck = enableCheck

    -- Keep the checkbox in sync if the master switch is toggled elsewhere
    -- (e.g. /wgb start|stop or another code path).
    WGB.Events:Register("WGB_ENABLED_CHANGED", enableCheck, function(self, on)
        self:SetChecked(on)
    end)

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
-- draw up to ~684px wide, so 690 keeps everything inside the child (which is
-- 700 wide and fits the scroll viewport without a horizontal scrollbar).
local SECTION_WIDTH = 690

-- Width of each half-panel when two sections share a row.  Each half is 338 px
-- wide with a 10 px gap, totalling 338+10+338 = 686 inside the 700-wide child.
local HALF_W   = 338
local RIGHT_X  = 4 + HALF_W + 10   -- = 352
local HDR_GAP  = 28   -- header label + divider band above each section body
local ROW_GAP  = 14   -- trailing gap below a section row before the next

-- Re-flow all registered rows top-to-bottom.  Called on every (un)registration
-- and whenever a section's height changes (e.g. Requirements Advanced toggle),
-- so collapsing a section reclaims its vertical space instead of leaving a gap.
local function layoutCombined(c)
    local child = c.child
    local y = -4
    for _, row in ipairs(c.rows) do
        local h = row.height
        if row.kind == "pair" then
            h = math.max(row.heightA or 0, row.heightB or 0)

            row.hdrA:ClearAllPoints()
            row.hdrA:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - 4)
            row.lineA:ClearAllPoints()
            row.lineA:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - 26)
            row.frameA:ClearAllPoints()
            row.frameA:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - HDR_GAP)
            row.frameA:SetHeight(h)

            row.hdrB:ClearAllPoints()
            row.hdrB:SetPoint("TOPLEFT", child, "TOPLEFT", RIGHT_X, y - 4)
            row.lineB:ClearAllPoints()
            row.lineB:SetPoint("TOPLEFT", child, "TOPLEFT", RIGHT_X, y - 26)
            row.frameB:ClearAllPoints()
            row.frameB:SetPoint("TOPLEFT", child, "TOPLEFT", RIGHT_X, y - HDR_GAP)
            row.frameB:SetHeight(h)
        else
            row.hdr:ClearAllPoints()
            row.hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - 4)
            row.line:ClearAllPoints()
            row.line:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - 26)
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y - HDR_GAP)
            row.frame:SetHeight(h)
        end
        y = y - HDR_GAP - h - ROW_GAP
    end
    child:SetHeight(-y + 10)
end

-- Lazily build the single scrollable tab that hosts the config/advert/loot/
-- requirements "sections". Registers itself as a normal tab once.
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

    self.combined = { outer = outer, scroll = scroll, child = child, rows = {}, byId = {} }
    self:RegisterTab("setup", L["SETUP"], outer)
    return self.combined
end

local function makeHeader(child, label)
    local hdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetText(label)
    local line = child:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0.5, 0.5, 0.5, 0.8)
    line:SetSize(HALF_W, 1)
    return hdr, line
end

-- Add a single full-width panel frame as a stacked section.
function MainWindow:RegisterSection(id, label, frame, height)
    local c = self:EnsureCombinedTab()
    local hdr, line = makeHeader(c.child, label)
    line:SetSize(SECTION_WIDTH, 1)
    frame:SetParent(c.child)
    frame:SetWidth(SECTION_WIDTH)
    frame:Show()
    local row = { kind = "single", id = id, hdr = hdr, line = line, frame = frame, height = height }
    table.insert(c.rows, row)
    c.byId[id] = row
    layoutCombined(c)
end

-- Place two panel frames side-by-side on the same scroll row.  Each section
-- gets its own header label and 1px divider; the row height is the taller of
-- the two supplied heights and re-flows when either changes.
function MainWindow:RegisterSectionPair(idA, labelA, frameA, heightA, idB, labelB, frameB, heightB)
    local c = self:EnsureCombinedTab()
    local hdrA, lineA = makeHeader(c.child, labelA)
    local hdrB, lineB = makeHeader(c.child, labelB)
    frameA:SetParent(c.child); frameA:SetWidth(HALF_W); frameA:Show()
    frameB:SetParent(c.child); frameB:SetWidth(HALF_W); frameB:Show()
    local row = {
        kind = "pair",
        idA = idA, hdrA = hdrA, lineA = lineA, frameA = frameA, heightA = heightA,
        idB = idB, hdrB = hdrB, lineB = lineB, frameB = frameB, heightB = heightB,
    }
    table.insert(c.rows, row)
    c.byId[idA] = row
    c.byId[idB] = row
    layoutCombined(c)
end

-- Change a registered section's body height and re-flow the whole tab so the
-- space below it grows/shrinks to match (used for the Requirements Advanced
-- expand/collapse).
function MainWindow:SetSectionHeight(id, height)
    local c = self.combined
    if not c then return end
    local row = c.byId[id]
    if not row then return end
    if row.kind == "pair" then
        if row.idA == id then row.heightA = height else row.heightB = height end
    else
        row.height = height
    end
    layoutCombined(c)
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
        -- Re-open through OpenTab so the current tab's EditBoxes (hidden by the
        -- frame's OnHide handler) get shown again. A plain frame:Show() would
        -- leave every input box invisible until the user clicked another tab.
        if self.current and self.tabById[self.current] then
            self:OpenTab(self.current)
        elseif self.tabs[1] then
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
