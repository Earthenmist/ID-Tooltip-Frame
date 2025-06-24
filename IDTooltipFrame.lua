local defaultX, defaultY = 0, 0
local frame

local function CreateMovableFrame()
    frame = CreateFrame("Frame", "IDTooltipFrame", UIParent, "BackdropTemplate")
    frame:SetHeight(30)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame:Hide()

    frame:SetScript("OnDragStart", function(self)
        if not self.isLocked then self:StartMoving() end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left = self:GetLeft()
        local bottom = self:GetBottom()
        if left and bottom then
            IDTooltipFrameDB = { x = left, y = bottom }
            print("Saved position:", left, bottom)
        end
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self.isLocked = not self.isLocked
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(self.isLocked and "Frame Locked" or "Frame Unlocked", 1, 1, 1)
            GameTooltip:Show()
            C_Timer.After(1.5, function() GameTooltip:Hide() end)
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    CreateMovableFrame()

    frame:ClearAllPoints()
    local db = IDTooltipFrameDB
    if db and type(db.x) == "number" and type(db.y) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
        print("Restored position:", db.x, db.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
        print("Using default position.")
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(_, data)
        if data and data.id then
            local itemID = data.id
            local quality = select(3, GetItemInfo(itemID)) or 1
            local r, g, b = GetItemQualityColor(quality)
            local colorCode = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)

            frame.text:SetText(string.format("|cffffaa00Item ID:|r %s%d|r", colorCode, itemID))
            frame:SetWidth(frame.text:GetStringWidth() + 20)
            frame:Show()
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(_, data)
        if data and data.id then
            frame.text:SetText(string.format("|cffffaa00Spell ID:|r |cff00ff00%d|r", data.id))
            frame:SetWidth(frame.text:GetStringWidth() + 20)
            frame:Show()
        end
    end)

    GameTooltip:HookScript("OnHide", function()
        frame:Hide()
    end)

    SLASH_IDTOOLTIP1 = "/idtooltip"
    SlashCmdList["IDTOOLTIP"] = function(msg)
        msg = msg:lower()
        if msg == "show" then
            frame.text:SetText("|cffffaa00Item ID:|r |cff00ff000|r")
            frame:SetWidth(frame.text:GetStringWidth() + 20)
            frame:Show()
            print("IDTooltipFrame: Frame shown. Drag to reposition. Right-click to lock.")
        elseif msg == "hide" then
            frame:Hide()
            print("IDTooltipFrame: Frame hidden.")
        elseif msg == "reset" then
            IDTooltipFrameDB = nil
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
            print("IDTooltipFrame: Position reset.")
        else
            print("Usage: /idtooltip show | hide | reset")
        end
    end
end)