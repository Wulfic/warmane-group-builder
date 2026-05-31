-- UI/InspectionPopup.lua
-- Reusable popup. Receives INSPECTION_COMPLETE; queues if currently shown.

local WGB = _G.WGB
local L = WGB.L

local Popup = {
    queue = {},
    current = nil,
    frame = nil,
}
WGB.InspectionPopup = Popup

local function build()
    if Popup.frame then return Popup.frame end
    local f = CreateFrame("Frame", "WGBInspectionPopup", UIParent)
    f:SetSize(360, 240)
    f:SetPoint("CENTER", 0, 100)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:EnableMouse(true)
    f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)

    f.spec = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.spec:SetPoint("TOPLEFT", 16, -40)

    f.gs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gs:SetPoint("TOPLEFT", 16, -60)

    f.gems = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.gems:SetPoint("TOPLEFT", 16, -80)

    f.enchants = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.enchants:SetPoint("TOPLEFT", 16, -100)
    f.enchants:SetWidth(330); f.enchants:SetJustifyH("LEFT")
    f.enchants:SetNonSpaceWrap(true)

    f.pvp = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.pvp:SetPoint("TOPLEFT", 16, -154)

    -- Buttons
    local approve = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    approve:SetPoint("BOTTOMLEFT", 16, 16); approve:SetSize(90, 24); approve:SetText(L["APPROVE"])
    approve:SetScript("OnClick", function()
        if Popup.current then WGB.GroupManager:ApprovePlayer(Popup.current.name) end
        Popup:_advance()
    end)

    local kick = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    kick:SetPoint("BOTTOMLEFT", 112, 16); kick:SetSize(90, 24); kick:SetText(L["KICK"])
    kick:SetScript("OnClick", function()
        if Popup.current then WGB.GroupManager:RejectPlayer(Popup.current.name, "Did not meet requirements") end
        Popup:_advance()
    end)

    local skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skip:SetPoint("BOTTOMLEFT", 208, 16); skip:SetSize(60, 24); skip:SetText(L["SKIP"])
    skip:SetScript("OnClick", function() Popup:_advance() end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    Popup.frame = f
    return f
end

local function colorForGS(gs, minGS)
    if not gs then return WGB.COLOR.GREY end
    if gs >= minGS then return WGB.COLOR.GREEN end
    if gs >= (minGS - 200) then return WGB.COLOR.YELLOW end
    return WGB.COLOR.RED
end

function Popup:Show(name, result)
    build()
    self.current = { name = name, result = result }
    local f = self.frame

    f.title:SetText(WGB.ClassColor(result.class) .. name .. "|r")

    local pts = result.talentPoints or { 0, 0, 0 }
    local specText = result.spec or "?"
    if result.dominantSpec then
        specText = ("%s  |cFF888888(%d/%d/%d)|r"):format(specText, pts[1] or 0, pts[2] or 0, pts[3] or 0)
    else
        -- Hybrid / leveling / mid-respec — flag it loudly so the leader notices.
        specText = WGB.Color(WGB.COLOR.YELLOW,
            ("%s  (hybrid %d/%d/%d — no 51-pt tree)"):format(specText, pts[1] or 0, pts[2] or 0, pts[3] or 0))
    end
    f.spec:SetText("Spec: " .. specText)

    local minGS = WGB.Requirements.minGS or 0
    f.gs:SetText("GS: " .. WGB.Color(colorForGS(result.gearScore, minGS),
        tostring(result.gearScore or "?") .. (result.approximateGS and " (approx)" or "")))

    if result.missingGems and result.missingGems > 0 then
        f.gems:SetText(WGB.Color(WGB.COLOR.RED, L["MISSING_GEMS"]:format(result.missingGems)))
    else
        f.gems:SetText(WGB.Color(WGB.COLOR.GREEN, "All sockets gemmed"))
    end

    if result.missingEnchants and #result.missingEnchants > 0 then
        f.enchants:SetText(WGB.Color(WGB.COLOR.RED,
            L["MISSING_ENCHANTS"]:format(table.concat(result.missingEnchants, ", "))))
    else
        f.enchants:SetText(WGB.Color(WGB.COLOR.GREEN, "Fully enchanted"))
    end

    if result.pvpItemCount and result.pvpItemCount > 0 then
        f.pvp:SetText(WGB.Color(WGB.COLOR.RED, ("PvP gear: %d pieces"):format(result.pvpItemCount)))
    else
        f.pvp:SetText("")
    end

    f:Show()
end

function Popup:_advance()
    if self.frame then self.frame:Hide() end
    self.current = nil
    if #self.queue > 0 then
        local next_ = table.remove(self.queue, 1)
        self:Show(next_.name, next_.result)
    end
end

WGB.Events:Register("INSPECTION_COMPLETE", Popup, function(_, name, result)
    -- Do NOT auto-open on every inspect. During a 25-man fill that would throw a
    -- popup over the main window for every single player. The leader opens the
    -- popup on demand by clicking a row in the Group Status tab. We only refresh
    -- in place when the player whose popup is already open gets updated data
    -- (e.g. a deferred GearScore arriving after the popup was opened).
    if Popup.frame and Popup.frame:IsShown() and Popup.current and Popup.current.name == name then
        Popup:Show(name, result)
    end
end)
