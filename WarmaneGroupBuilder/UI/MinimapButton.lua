-- UI/MinimapButton.lua
-- Hand-rolled minimap button (no LibDBIcon to keep deps minimal on 3.3.5a).

local WGB = _G.WGB
local L = WGB.L

local Btn = {}
WGB.MinimapButton = Btn

local button

local function updatePosition(self)
    local angle = WGB_Settings.minimapAngle or 215
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function build()
    if button then return end
    local b = CreateFrame("Button", "WGBMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)

    b:SetNormalTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    b:GetNormalTexture():SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetSize(54, 54)
    overlay:SetPoint("TOPLEFT")

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, click)
        if click == "LeftButton" then
            WGB.MainWindow:Toggle()
        else
            WGB.Advert:Send()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Warmane Group Builder")
        local r = WGB.Requirements
        if r then
            GameTooltip:AddLine(("Slots: %d / %d"):format(r:GetTotalFilled(), r:GetTotalSlots()), 1, 1, 1)
        end
        GameTooltip:AddLine("Left-click: open. Right-click: send advert.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag to reposition. OnUpdate only runs while actively dragging
    -- so the button doesn't burn frames sitting still on the minimap.
    local function dragOnUpdate(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        WGB_Settings.minimapAngle = angle
        updatePosition(self)
    end

    b:SetMovable(true); b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", dragOnUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    updatePosition(b)
    button = b
end

function Btn:SetShown(on)
    if not button then return end
    if on then button:Show() else button:Hide() end
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Btn, function()
    build()
    if WGB_Settings.showMinimap == false then button:Hide() end
end)
