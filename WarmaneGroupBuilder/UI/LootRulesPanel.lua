-- UI/LootRulesPanel.lua

local WGB = _G.WGB
local L = WGB.L

local Panel = {}
WGB.LootRulesPanel = Panel
local frame
local w = {}

local function check(parent, label, x, y, onClick)
    local c = WGB.MakeCheckBox(parent, label, onClick)
    c:SetPoint("TOPLEFT", x, y)
    return c
end

local dropdownCount = 0
local function dropdown(parent, x, y, width, options, onPick)
    dropdownCount = dropdownCount + 1
    local dd = CreateFrame("Frame", "WGBLootDropdown" .. dropdownCount, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y + 4)
    UIDropDownMenu_SetWidth(dd, width or 140)
    UIDropDownMenu_Initialize(dd, function()
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label; info.value = opt.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dd, opt.value)
                UIDropDownMenu_SetText(dd, opt.label)
                onPick(opt.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dd
end

local function build()
    if frame then return end
    frame = CreateFrame("Frame")

    -- Loot system + master loot
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8); title:SetText(L["LOOT_SYSTEM"] .. ":")
    w.lootSystem = dropdown(frame, 100, -4, 140, {
        { label = L["LOOT_MSOS"],   value = "MSOS"   },
        { label = L["LOOT_SK"],     value = "SK"     },
        { label = L["LOOT_RANDOM"], value = "Random" },
        { label = L["LOOT_GROUP"],  value = "Group"  },
        { label = L["LOOT_CUSTOM"], value = "Custom" },
    }, function(v) WGB.LootRules:Set("lootSystem", v) end)

    w.masterLoot = check(frame, L["LOOT_MASTER"], 260, -8,
        function(v) WGB.LootRules:Set("masterLoot", v) end)

    w.advertiseSystem = check(frame, L["LOOT_ADVERTISE_SYSTEM"], 100, -28,
        function(v) WGB.LootRules:Set("advertiseLootSystem", v) end)

    -- Commodities
    local y = -50
    w.primo  = check(frame, L["LOOT_PRIMOS_RES"]      .. " (ICC)",      8, y,
        function(v) WGB.LootRules:Set("primoSaronite", v) end); y = y - 22
    w.shadow = check(frame, L["LOOT_SHADOWFROST_RES"] .. " (ICC SM)",  8, y,
        function(v) WGB.LootRules:Set("shadowfrostShard", v) end); y = y - 22
    w.crus   = check(frame, L["LOOT_CRUSADER_RES"]    .. " (ToC)",      8, y,
        function(v) WGB.LootRules:Set("crusaderOrb", v) end); y = y - 22
    w.runed  = check(frame, L["LOOT_RUNED_RES"]       .. " (Ulduar)",   8, y,
        function(v) WGB.LootRules:Set("runedOrb", v) end); y = y - 22
    w.valan  = check(frame, L["LOOT_VALANYR_RES"]     .. " (Ulduar)",   8, y,
        function(v) WGB.LootRules:Set("yoggFragment", v) end); y = y - 30

    -- BoE rule
    local boeLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    boeLbl:SetPoint("TOPLEFT", 8, y); boeLbl:SetText(L["LOOT_BOE_RULE"] .. ":")
    w.boeRule = dropdown(frame, 100, y + 4, 140, {
        { label = L["LOOT_BOE_RAID"], value = "raid" },
        { label = L["LOOT_BOE_RES"],  value = "reserve" },
        { label = L["LOOT_BOE_OPEN"], value = "open" },
    }, function(v) WGB.LootRules:Set("boeRule", v) end)
    y = y - 36

    -- Custom reserves
    local crLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    crLbl:SetPoint("TOPLEFT", 8, y); crLbl:SetText(L["LOOT_CUSTOM_RESERVES"]); y = y - 22

    w.crEdit = WGB.MakeInputBox(frame, 280, 24)
    w.crEdit.border:SetPoint("TOPLEFT", 16, y)
    w.crEdit:SetScript("OnReceiveDrag", function(self)
        local cursorType, _, link = GetCursorInfo()
        if cursorType == "item" and link then
            self:SetText(link)
            ClearCursor()
        end
    end)
    w.crEdit:SetScript("OnMouseUp", function(self)
        local cursorType, _, link = GetCursorInfo()
        if cursorType == "item" and link then
            self:SetText(link); ClearCursor()
        end
    end)

    w.crAdd = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.crAdd:SetPoint("TOPLEFT", w.crEdit.border, "TOPRIGHT", 6, 0)
    w.crAdd:SetSize(60, 22); w.crAdd:SetText("Add")
    w.crAdd:SetScript("OnClick", function()
        local text = w.crEdit:GetText()
        if text and text ~= "" then
            WGB.LootRules:AddReservedItem(text)
            w.crEdit:SetText("")
        end
    end)
    y = y - 28

    -- Reserve list (clickable rows; right-click a row to remove it).
    local MAX_RESERVE_ROWS = 6
    w.reserveRows = {}
    for i = 1, MAX_RESERVE_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(440, 16)
        row:SetPoint("TOPLEFT", 16, y - (i - 1) * 16)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetWidth(420); row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self, button)
            if not self.reserveIndex then return end
            if button == "RightButton" then
                WGB.LootRules:RemoveReservedItem(self.reserveIndex)
            elseif button == "LeftButton" then
                -- Show item tooltip on left-click for sanity-checking the link.
                if self.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        w.reserveRows[i] = row
    end
    w.reserveOverflow = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.reserveOverflow:SetPoint("TOPLEFT", 16, y - MAX_RESERVE_ROWS * 16)
    w.reserveOverflow:SetWidth(440); w.reserveOverflow:SetJustifyH("LEFT")
    y = y - (MAX_RESERVE_ROWS + 1) * 16

    w.clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    w.clearBtn:SetPoint("TOPLEFT", 16, y); w.clearBtn:SetSize(120, 22)
    w.clearBtn:SetText("Clear Reserves")
    w.clearBtn:SetScript("OnClick", function() WGB.LootRules:ClearReservedItems() end)
    y = y - 32

    -- Preview (flows below the Clear Reserves button so the two never overlap)
    local prev = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    prev:SetPoint("TOPLEFT", 8, y); prev:SetText(L["LOOT_PREVIEW"] .. ":")
    y = y - 22

    w.preview = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.preview:SetPoint("TOPLEFT", 8, y)
    w.preview:SetWidth(500); w.preview:SetJustifyH("LEFT")
    w.preview:SetNonSpaceWrap(true)
end

local function refresh()
    if not frame then return end
    local lr = WGB.LootRules
    UIDropDownMenu_SetSelectedValue(w.lootSystem, lr.lootSystem)
    UIDropDownMenu_SetText(w.lootSystem, ({
        MSOS   = L["LOOT_MSOS"],
        SK     = L["LOOT_SK"],
        Random = L["LOOT_RANDOM"],
        Group  = L["LOOT_GROUP"],
        Custom = L["LOOT_CUSTOM"],
    })[lr.lootSystem] or lr.lootSystem)
    UIDropDownMenu_SetSelectedValue(w.boeRule, lr.boeRule)
    UIDropDownMenu_SetText(w.boeRule, ({ raid = L["LOOT_BOE_RAID"], reserve = L["LOOT_BOE_RES"], open = L["LOOT_BOE_OPEN"] })[lr.boeRule])

    w.masterLoot:SetChecked(lr.masterLoot)
    w.advertiseSystem:SetChecked(lr.advertiseLootSystem)
    w.primo:SetChecked(lr.primoSaronite)
    w.shadow:SetChecked(lr.shadowfrostShard)
    w.crus:SetChecked(lr.crusaderOrb)
    w.runed:SetChecked(lr.runedOrb)
    w.valan:SetChecked(lr.yoggFragment)

    -- Only show commodity reserves relevant to the selected instance, and
    -- stack the visible ones from the top so there are no blank rows. This
    -- prevents advertising e.g. Crusader Orbs for an ICC raid.
    local rel = lr:RelevantCommodities()
    local commodities = {
        { box = w.primo,  key = "primoSaronite"    },
        { box = w.shadow, key = "shadowfrostShard" },
        { box = w.crus,   key = "crusaderOrb"      },
        { box = w.runed,  key = "runedOrb"         },
        { box = w.valan,  key = "yoggFragment"     },
    }
    local cy = -50
    for _, c in ipairs(commodities) do
        if rel[c.key] then
            c.box:ClearAllPoints()
            c.box:SetPoint("TOPLEFT", 8, cy)
            c.box:Show()
            cy = cy - 22
        else
            c.box:Hide()
        end
    end

    -- Reserve list
    local total = #lr.reservedItems
    local rows = w.reserveRows
    local shown = math.min(#rows, total)
    for i = 1, shown do
        local r = lr.reservedItems[i]
        local row = rows[i]
        row.reserveIndex = i
        row.itemLink = r.itemLink
        row.text:SetText(("%d. %s   |cFF888888(right-click to remove)|r"):format(i, r.itemLink or r.itemName or "?"))
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i].reserveIndex = nil
        rows[i].itemLink = nil
        rows[i]:Hide()
    end
    if total == 0 then
        w.reserveOverflow:SetText("|cFF888888(none)|r")
    elseif total > #rows then
        w.reserveOverflow:SetText(("|cFF888888+%d more (use Clear Reserves to start over)|r"):format(total - #rows))
    else
        w.reserveOverflow:SetText("")
    end

    w.preview:SetText(lr:GetMessageFragment())
end

WGB.Events:Register("WGB_PLAYER_LOGIN", Panel, function()
    build()
    WGB.MainWindow:RegisterTab("lootrules", L["LOOT_RULES"], frame)
    refresh()
end)
WGB.Events:Register("LOOT_RULES_CHANGED", Panel, refresh)
-- Activity changes don't fire LOOT_RULES_CHANGED on their own; re-run refresh so
-- the relevant commodity checkboxes update when the selected instance changes.
WGB.Events:Register("REQUIREMENTS_CHANGED", Panel, refresh)
