-- IDTooltipFrame.lua
-- Retail-only. Dragonflight Settings UI panel + movable ID frame.
-- Unlocked mode = persistent preview & ignores tooltips until locked.
-- Center-based, scale-safe save; absolute BOTTOMLEFT restore after UI scale settles.
-- No alpha hiding; shows a brief preview pulse after restore so you can always find it.

if WOW_PROJECT_ID and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
    return
end

local ADDON_NAME = "IDTooltipFrame"
local defaultX, defaultY = 0, 0

local frame
local settingsPanel
local hooksInstalled = false
local settleTicker

-- ## SavedVariables: IDTooltipFrameDB
-- Legacy keys: xPerc/yPerc (BL%). New keys: cxPerc/cyPerc (CENTER%).
IDTooltipFrameDB = IDTooltipFrameDB or {
    xPerc = nil, yPerc = nil,
    cxPerc = nil, cyPerc = nil,
    savedScale = nil,
    locked = false, width = 0,
    debug = false,
}

local DEBUG = IDTooltipFrameDB.debug or false
local function dprint(...) if DEBUG then print("|cff88ccff[IDTooltipFrame]|r", ...) end end

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------
local function ShowPreviewPulse(duration)
    if not frame then return end
    local dur = duration or 1.5
    -- If unlocked, EnterEditMode already shows a persistent preview, so skip pulse.
    if not frame.isLocked then return end
    local oldText = frame.text:GetText() or ""
    frame.text:SetText("|cffffaa00ID Tooltip|r — preview")
    frame:SetWidth(math.max(180, frame.text:GetStringWidth() + 20))
    frame:Show()
    C_Timer.After(dur, function()
        -- If still locked and not showing a real tooltip, hide again
        if frame and frame.isLocked and frame.text:GetText() == "|cffffaa00ID Tooltip|r — preview" then
            frame:Hide()
            frame.text:SetText(oldText)
        end
    end)
end

local function EnsureCenterInDB()
    local db = IDTooltipFrameDB
    if db.cxPerc and db.cyPerc then return end
    if db.xPerc and db.yPerc and frame then
        local fScale = frame:GetEffectiveScale()
        local pScale = UIParent:GetEffectiveScale()
        local uiW = UIParent:GetWidth() * pScale
        local uiH = UIParent:GetHeight() * pScale
        local w = frame:GetWidth()  or 0
        local h = frame:GetHeight() or 0

        local leftPx   = db.xPerc * uiW
        local bottomPx = db.yPerc * uiH
        local centerPxX = leftPx + (w * fScale) / 2
        local centerPxY = bottomPx + (h * fScale) / 2

        db.cxPerc = centerPxX / uiW
        db.cyPerc = centerPxY / uiH
        dprint(("Converted old BL%% -> CENTER%%: cxPerc=%.6f cyPerc=%.6f"):format(db.cxPerc, db.cyPerc))
    end
end

------------------------------------------------------------
-- UI (created on demand)
------------------------------------------------------------
local function CreateMovableFrame()
    if frame then return end

    frame = CreateFrame("Frame", ADDON_NAME, UIParent, "BackdropTemplate")
    frame:SetHeight(30)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetFrameStrata("TOOLTIP")

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")

    frame.handle = frame:CreateTexture(nil, "OVERLAY")
    frame.handle:SetSize(8, 8)
    frame.handle:SetPoint("TOPRIGHT", -6, -6)
    frame.handle:SetTexture("Interface\\CHATFRAME\\ChatFrameExpandArrow")

    frame:Hide()

    frame:SetScript("OnDragStart", function(self)
        if not self.isLocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local SavePosition = _G.IDT_SavePosition
        if SavePosition then SavePosition() end
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            if self.isLocked then
                _G.IDT_EnterEditMode()
            else
                _G.IDT_ExitEditMode()
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetText("Frame Locked", 1, 1, 1)
                GameTooltip:Show()
                C_Timer.After(1.0, function()
                    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                end)
            end
            if settingsPanel and settingsPanel:IsShown() and settingsPanel.lockCheck then
                settingsPanel.lockCheck:SetChecked(frame.isLocked)
            end
        end
    end)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown() then
            local w = math.max(80, self:GetWidth() + (delta * 10))
            frame:SetWidth(w)
            IDTooltipFrameDB.width = w
            if settingsPanel and settingsPanel:IsShown() and settingsPanel.widthSlider then
                settingsPanel.widthSlider:SetValue(w)
            end
        end
    end)
end

------------------------------------------------------------
-- Save (center) / Restore (absolute BL)
------------------------------------------------------------
local function SavePosition()
    if not frame then return end
    local fScale = frame:GetEffectiveScale()
    local pScale = UIParent:GetEffectiveScale()
    local cX, cY = frame:GetCenter()
    if not (cX and cY and fScale and pScale) then return end

    local centerPxX = cX * fScale
    local centerPxY = cY * fScale

    local uiW = UIParent:GetWidth() * pScale
    local uiH = UIParent:GetHeight() * pScale
    if not (uiW > 0 and uiH > 0) then return end

    IDTooltipFrameDB.cxPerc = centerPxX / uiW
    IDTooltipFrameDB.cyPerc = centerPxY / uiH
    IDTooltipFrameDB.savedScale = UIParent:GetEffectiveScale() -- record target scale

    dprint(("Saved CENTER: fScale=%.3f pScale=%.3f centerPx=(%.1f, %.1f) -> cxPerc=%.6f cyPerc=%.6f")
        :format(fScale, pScale, centerPxX, centerPxY, IDTooltipFrameDB.cxPerc, IDTooltipFrameDB.cyPerc))
end
_G.IDT_SavePosition = SavePosition

local function RestorePosition()
    CreateMovableFrame()
    if not frame then return end

    frame:ClearAllPoints()

    local db = IDTooltipFrameDB
    local fScale = frame:GetEffectiveScale()
    local pScale = UIParent:GetEffectiveScale()
    local uiW = UIParent:GetWidth() * pScale
    local uiH = UIParent:GetHeight() * pScale

    if not (uiW and uiH and uiW > 0 and uiH > 0) then
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
        dprint("Restore: UIParent size not ready; using default CENTER")
        return
    end

    EnsureCenterInDB()

    if db and db.cxPerc and db.cyPerc then
        local centerPxX = db.cxPerc * uiW
        local centerPxY = db.cyPerc * uiH

        local w = (db.width and db.width > 0) and db.width or frame:GetWidth()
        local h = frame:GetHeight()

        local leftPx   = centerPxX - (w * fScale) / 2
        local bottomPx = centerPxY - (h * fScale) / 2

        leftPx   = math.floor(leftPx + 0.5)
        bottomPx = math.floor(bottomPx + 0.5)

        local leftUI   = leftPx   / fScale
        local bottomUI = bottomPx / fScale

        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", leftUI, bottomUI)
        if db.width and db.width > 0 then
            frame:SetWidth(db.width)
        end

        dprint(("Restore BL: fScale=%.3f pScale=%.3f centerPx=(%.1f, %.1f) -> leftUI=%.1f bottomUI=%.1f")
            :format(fScale, pScale, centerPxX, centerPxY, leftUI, bottomUI))
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
        dprint("Restore: using default CENTER (no saved center)")
    end

    frame.isLocked = db and db.locked or false
end

------------------------------------------------------------
-- Modes
------------------------------------------------------------
local function EnterEditMode()
    CreateMovableFrame()
    if not frame then return end
    frame.isLocked = false
    IDTooltipFrameDB.locked = false
    frame.text:SetText("|cffffaa00ID Tooltip|r — drag me; right-click to lock")
    frame:SetWidth(math.max(180, frame.text:GetStringWidth() + 20))
    frame:Show()
end
_G.IDT_EnterEditMode = EnterEditMode

local function ExitEditMode()
    CreateMovableFrame()
    if not frame then return end
    frame.isLocked = true
    IDTooltipFrameDB.locked = true
    -- Stay hidden until a tooltip appears (or pulse shows it briefly).
end
_G.IDT_ExitEditMode = ExitEditMode

------------------------------------------------------------
-- Tooltip hooks
------------------------------------------------------------
local function HookTooltipHide(tooltip)
    if tooltip and tooltip.HookedForIDTooltip ~= true then
        tooltip:HookScript("OnHide", function()
            if frame and frame.isLocked then
                frame:Hide()
            end
        end)
        tooltip.HookedForIDTooltip = true
    end
end

------------------------------------------------------------
-- Dragonflight Settings (canvas)
------------------------------------------------------------
local function BuildSettingsPanel()
    if settingsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = ADDON_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("IDTooltipFrame")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Retail only. Shows Item/Spell IDs.\nUnlocked mode stays visible and ignores tooltips until locked.")

    local lockCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -18)
    lockCheck:SetChecked(IDTooltipFrameDB.locked)
    local lockLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lockLabel:SetPoint("LEFT", lockCheck, "RIGHT", 6, 0)
    lockLabel:SetText("Locked (follow tooltips)")
    lockCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then ExitEditMode() else EnterEditMode() end
        self:SetChecked(frame and frame.isLocked)
    end)

    local showBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    showBtn:SetSize(96, 22)
    showBtn:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -12)
    showBtn:SetText("Show")
    showBtn:SetScript("OnClick", function()
        CreateMovableFrame()
        if not frame then return end
        if frame.isLocked then
            frame.text:SetText("|cffffaa00Item ID:|r |cff00ff000|r")
        else
            frame.text:SetText("|cffffaa00ID Tooltip|r — drag me; right-click to lock")
        end
        frame:SetWidth(math.max(180, frame.text:GetStringWidth() + 20))
        frame:Show()
    end)

    local hideBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    hideBtn:SetSize(96, 22)
    hideBtn:SetPoint("LEFT", showBtn, "RIGHT", 8, 0)
    hideBtn:SetText("Hide")
    hideBtn:SetScript("OnClick", function() if frame then frame:Hide() end end)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 22)
    resetBtn:SetPoint("LEFT", hideBtn, "RIGHT", 8, 0)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        IDTooltipFrameDB.cxPerc, IDTooltipFrameDB.cyPerc = nil, nil
        CreateMovableFrame()
        if not frame then return end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
        SavePosition()
        ShowPreviewPulse(1.2)
    end)

    local sliderName = ADDON_NAME .. "_WidthSlider"
    local widthSlider = CreateFrame("Slider", sliderName, panel, "OptionsSliderTemplate")
    widthSlider:SetPoint("TOPLEFT", showBtn, "BOTTOMLEFT", 0, -28)
    widthSlider:SetMinMaxValues(80, 500)
    widthSlider:SetValueStep(1)
    widthSlider:SetObeyStepOnDrag(true)
    widthSlider:SetWidth(340)
    _G[sliderName .. "Low"]:SetText("80")
    _G[sliderName .. "High"]:SetText("500")
    _G[sliderName .. "Text"]:SetText("Frame Width")
    widthSlider:SetScript("OnValueChanged", function(self, value)
        CreateMovableFrame()
        if frame then
            frame:SetWidth(value)
            IDTooltipFrameDB.width = value
        end
    end)

    local tip = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tip:SetPoint("TOPLEFT", widthSlider, "BOTTOMLEFT", 0, -10)
    tip:SetText("Tip: Hold Ctrl + Mouse Wheel over the frame to adjust width quickly.")

    panel:SetScript("OnShow", function()
        CreateMovableFrame()
        if frame then
            lockCheck:SetChecked(frame.isLocked)
            widthSlider:SetValue(frame:GetWidth())
        end
    end)

    panel.lockCheck = lockCheck
    panel.widthSlider = widthSlider

    local category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_NAME)
    category.ID = ADDON_NAME
    Settings.RegisterAddOnCategory(category)

    settingsPanel = panel
end

------------------------------------------------------------
-- Scale settle: wait until UI scale stops changing, then restore once
------------------------------------------------------------
local function StopSettleTicker()
    if settleTicker then
        settleTicker:Cancel()
        settleTicker = nil
    end
end

-- Wait until scale hasn't changed for `stableFor` seconds (or matches savedScale), up to maxWait
local function RestoreWhenScaleStable(opts)
    opts = opts or {}
    local maxWait   = opts.maxWait   or 12.0
    local stableFor = opts.stableFor or 0.5
    local target    = IDTooltipFrameDB.savedScale -- may be nil

    CreateMovableFrame()
    if not frame then return end

    local lastScale = UIParent:GetEffectiveScale()
    local lastChangeTime = GetTime()
    local startTime = lastChangeTime

    dprint(("Settle: start (scale=%.3f) target=%s maxWait=%.1fs stableFor=%.1fs")
        :format(lastScale, target and string.format("%.3f", target) or "nil", maxWait, stableFor))

    StopSettleTicker()
    settleTicker = C_Timer.NewTicker(0.05, function()
        local now = GetTime()
        local s = UIParent:GetEffectiveScale()

        if math.abs(s - lastScale) > 1e-6 then
            lastScale = s
            lastChangeTime = now
            dprint(("Settle: scale changed -> %.3f"):format(s))
        end

        local stableEnough = (now - lastChangeTime) >= stableFor
        local matchesTarget = (target and math.abs(s - target) < 1e-4) or (target == nil)

        if (now - startTime) >= maxWait or (stableEnough and matchesTarget) then
            StopSettleTicker()
            dprint(("Settle: restoring at scale=%.3f (stable %.2fs, waited %.2fs)")
                :format(s, now - lastChangeTime, now - startTime))

            RestorePosition()

            -- enter desired mode & give a tiny preview pulse so it's discoverable
            if IDTooltipFrameDB.locked then
                ExitEditMode()
                ShowPreviewPulse(1.2)
            else
                EnterEditMode()
            end
        end
    end)
end

------------------------------------------------------------
-- Events (robust restore + scale/size watchers)
------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            IDTooltipFrameDB = IDTooltipFrameDB or {
                xPerc=nil, yPerc=nil, cxPerc=nil, cyPerc=nil,
                savedScale=nil, locked=false, width=0, debug=false,
            }
            DEBUG = not not IDTooltipFrameDB.debug
            dprint("ADDON_LOADED: debug =", DEBUG and "true" or "false")
            BuildSettingsPanel()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        CreateMovableFrame()

        -- Wait for UI scale to settle, then restore once (no visible jump)
        RestoreWhenScaleStable({ maxWait = 12.0, stableFor = 0.5 })

        if not hooksInstalled then
            HookTooltipHide(GameTooltip)
            HookTooltipHide(ItemRefTooltip)
            if ShoppingTooltip1 then HookTooltipHide(ShoppingTooltip1) end
            if ShoppingTooltip2 then HookTooltipHide(ShoppingTooltip2) end

            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(_, data)
                if frame and frame.isLocked and data and data.id then
                    local itemID = data.id
                    local quality = select(3, GetItemInfo(itemID)) or 1
                    local r, g, b = GetItemQualityColor(quality)
                    local colorCode = string.format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
                    frame.text:SetText(string.format("|cffffaa00Item ID:|r %s%d|r", colorCode, itemID))
                    frame:SetWidth(frame.text:GetStringWidth() + 20)
                    frame:Show()
                end
            end)

            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(_, data)
                if frame and frame.isLocked and data and data.id then
                    frame.text:SetText(string.format("|cffffaa00Spell ID:|r |cff00ff00%d|r", data.id))
                    frame:SetWidth(frame.text:GetStringWidth() + 20)
                    frame:Show()
                end
            end)

            GameTooltip:HookScript("OnTooltipCleared", function()
                if frame and frame.isLocked then
                    frame.text:SetText("")
                    frame:Hide()
                end
            end)

            -- Slash commands
            SLASH_IDTOOLTIP1 = "/idtooltip"
            SlashCmdList["IDTOOLTIP"] = function(msg)
                msg = (msg or ""):lower()
                if msg == "show" then
                    CreateMovableFrame()
                    if frame.isLocked then
                        frame.text:SetText("|cffffaa00Item ID:|r |cff00ff000|r")
                    else
                        frame.text:SetText("|cffffaa00ID Tooltip|r — drag me; right-click to lock")
                    end
                    frame:SetWidth(math.max(180, frame.text:GetStringWidth() + 20))
                    frame:Show()
                    print("IDTooltipFrame: Frame shown. Drag to reposition (unlocked). Right-click to toggle lock.")
                elseif msg == "hide" then
                    if frame then frame:Hide() end
                    print("IDTooltipFrame: Frame hidden.")
                elseif msg == "reset" then
                    IDTooltipFrameDB.cxPerc, IDTooltipFrameDB.cyPerc = nil, nil
                    CreateMovableFrame()
                    if frame then
                        frame:ClearAllPoints()
                        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
                        SavePosition()
                        ShowPreviewPulse(1.2)
                    end
                    print("IDTooltipFrame: Position reset.")
                elseif msg == "lock" then
                    ExitEditMode()
                    print("IDTooltipFrame: Locked. Will follow tooltips.")
                elseif msg == "unlock" then
                    EnterEditMode()
                    print("IDTooltipFrame: Unlocked. Ignores tooltips until locked.")
                elseif msg == "restore" then
                    dprint("Slash: manual restore (immediate)")
                    RestorePosition()
                    ShowPreviewPulse(1.2)
                elseif msg:match("^debug") then
                    local arg = msg:match("^debug%s+(%S+)$")
                    if arg == "on" then
                        DEBUG = true
                        IDTooltipFrameDB.debug = true
                        print("IDTooltipFrame: Debug ON")
                    elseif arg == "off" then
                        DEBUG = false
                        IDTooltipFrameDB.debug = false
                        print("IDTooltipFrame: Debug OFF")
                    else
                        print("Usage: /idtooltip debug on|off")
                    end
                else
                    print("Usage: /idtooltip show | hide | reset | lock | unlock | restore | debug on|off")
                end

                if settingsPanel and settingsPanel:IsShown() then
                    if settingsPanel.lockCheck then settingsPanel.lockCheck:SetChecked(frame and frame.isLocked) end
                    if settingsPanel.widthSlider and frame then settingsPanel.widthSlider:SetValue(frame:GetWidth()) end
                end
            end

            hooksInstalled = true
        end
        return
    end

    -- If UI scale or resolution changes (e.g., your scaling addon), re-place after a short stability period
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        dprint(event .. ": settle & restore")
        RestoreWhenScaleStable({ maxWait = 6.0, stableFor = 0.3 })
        return
    end
end)
