---@class PushMasterSettingsFrame
---Settings GUI frame for PushMaster addon
---Styled to match DotMaster addon visual consistency
---Provides configuration options for the addon

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create SettingsFrame module
local SettingsFrame = {}
if not PushMaster.UI then
  PushMaster.UI = {}
end
PushMaster.UI.SettingsFrame = SettingsFrame

-- Local references
local frame = nil
local isInitialized = false

-- UI elements storage
local elements = {}

-- Addon font - use Expressway from media fonts
local ADDON_FONT = "Interface\\AddOns\\PushMaster\\Media\\Fonts\\Expressway.ttf"

-- Get player's class color for consistent theming
local function getClassColor()
  local playerClass = select(2, UnitClass("player"))
  return RAID_CLASS_COLORS[playerClass] or { r = 1, g = 0.82, b = 0 } -- Fallback to gold if class color not found
end

-- Default settings structure
local defaultSettings = {
  minimap = {
    hide = false,
    minimapPos = 220,
    lock = false
  },
  display = {
    showMainFrame = true,
    frameScale = 1.0,
    frameAlpha = 1.0,
    showBestTimes = true,
    showCurrentRun = true,
    showProgress = true
  },
  notifications = {
    chatAnnouncements = true,
    soundAlerts = false,
    screenFlash = false
  },
  data = {
    trackAllRuns = true,
    saveIncompleteRuns = false,
    autoReset = true,
    enableExtrapolation = false -- Default to disabled (advanced feature)
  }
}

---Create a standardized checkbox with label
---@param parent Frame The parent frame
---@param name string The checkbox name
---@param labelText string The label text
---@param tooltip string The tooltip text
---@return Frame checkbox The created checkbox
local function createCheckbox(parent, name, labelText, tooltip)
  local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  checkbox:SetSize(24, 24)

  -- Create custom label text (positioned to the right of checkbox)
  checkbox.labelText = checkbox:CreateFontString(nil, "OVERLAY")
  checkbox.labelText:SetFont(ADDON_FONT, 11)
  checkbox.labelText:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.labelText:SetText(labelText)
  checkbox.labelText:SetTextColor(0.9, 0.9, 0.9)

  -- Add tooltip
  if tooltip then
    checkbox:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
  end

  return checkbox
end

---Create a standardized slider with label
---@param parent Frame The parent frame
---@param name string The slider name
---@param labelText string The label text
---@param minVal number Minimum value
---@param maxVal number Maximum value
---@param step number Step size
---@return Frame slider The created slider
local function createSlider(parent, name, labelText, minVal, maxVal, step)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetSize(150, 20)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)

  -- Set slider texts
  _G[name .. "Low"]:SetText(tostring(minVal))
  _G[name .. "High"]:SetText(tostring(maxVal))
  _G[name .. "Text"]:SetText(labelText)

  -- Value text
  slider.valueText = slider:CreateFontString(nil, "OVERLAY")
  slider.valueText:SetFont(ADDON_FONT, 10)
  slider.valueText:SetPoint("TOP", slider, "BOTTOM", 0, -5)
  slider.valueText:SetTextColor(1, 1, 1)

  -- Update value text when slider changes
  slider:SetScript("OnValueChanged", function(self, value)
    self.valueText:SetText(string.format("%.1f", value))
  end)

  return slider
end

---Create the main settings frame
local function createSettingsFrame()
  -- Get the player's class color
  local classColor = getClassColor()

  -- Create main frame (wider for two-column layout)
  frame = CreateFrame("Frame", "PushMasterSettingsFrame", UIParent, "BackdropTemplate")
  frame:SetSize(600, 520) -- Increased height for more slider space
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  -- Register with UI special frames to enable Escape key closing
  tinsert(UISpecialFrames, "PushMasterSettingsFrame")

  -- Ensure ESC and other hides trigger our custom hide logic
  frame:HookScript("OnHide", function(self)
    SettingsFrame:Hide()
  end)

  -- Add backdrop (matching DotMaster style)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, frame)
  titleBar:SetSize(frame:GetWidth() - 8, 40)
  titleBar:SetPoint("TOP", frame, "TOP", 0, -4)

  -- Title text
  local title = titleBar:CreateFontString(nil, "OVERLAY")
  title:SetFont(ADDON_FONT, 16, "OUTLINE")
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText("PushMaster")
  title:SetTextColor(classColor.r, classColor.g, classColor.b)

  -- Close button
  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
  closeButton:SetSize(26, 26)
  closeButton:SetScript("OnClick", function()
    SettingsFrame:Hide()
  end)

  -- Create info area (similar to DotMaster)
  local infoArea = CreateFrame("Frame", nil, frame)
  infoArea:SetSize(530, 70)
  infoArea:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)

  -- Info title
  local infoTitle = infoArea:CreateFontString(nil, "OVERLAY")
  infoTitle:SetFont(ADDON_FONT, 14, "OUTLINE")
  infoTitle:SetPoint("TOP", infoArea, "TOP", 0, 0)
  infoTitle:SetText("Real-time M+ Delta Analyzer")
  infoTitle:SetTextColor(1, 0.82, 0) -- Gold color

  -- Info description
  local infoDesc = infoArea:CreateFontString(nil, "OVERLAY")
  infoDesc:SetFont(ADDON_FONT, 11)
  infoDesc:SetPoint("TOP", infoTitle, "BOTTOM", 0, -10)
  infoDesc:SetWidth(500)
  infoDesc:SetJustifyH("CENTER")
  infoDesc:SetText("Shows real-time pace analysis: are you ahead or behind your best time for successful key pushing?")
  infoDesc:SetTextColor(0.8, 0.8, 0.8)

  -- Main content area (container for two boxes)
  local contentArea = CreateFrame("Frame", nil, frame)
  contentArea:SetSize(550, 340)
  contentArea:SetPoint("TOP", infoArea, "BOTTOM", 0, -5)

  -- === LEFT BOX - CONFIGURATION ===
  local leftBox = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
  leftBox:SetSize(265, 340)
  leftBox:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)

  -- Left box backdrop
  leftBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  leftBox:SetBackdropColor(0, 0, 0, 0.7)
  leftBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

  -- Configuration section title
  local configTitle = leftBox:CreateFontString(nil, "OVERLAY")
  configTitle:SetFont(ADDON_FONT, 14, "OUTLINE")
  configTitle:SetPoint("TOP", leftBox, "TOP", 0, -20)
  configTitle:SetText("Configuration")
  configTitle:SetTextColor(classColor.r, classColor.g, classColor.b)

  -- Enable/Disable checkbox
  elements.enableCheckbox = createCheckbox(
    leftBox,
    "PushMasterEnableCheckbox",
    "Enable PushMaster",
    "Enable or disable the PushMaster addon"
  )
  elements.enableCheckbox:SetPoint("TOPLEFT", leftBox, "TOPLEFT", 20, -50)

  -- Show minimap icon checkbox
  elements.minimapCheckbox = createCheckbox(
    leftBox,
    "PushMasterMinimapCheckbox",
    "Show Minimap Icon",
    "Show or hide the minimap button"
  )
  elements.minimapCheckbox:SetPoint("TOPLEFT", elements.enableCheckbox, "BOTTOMLEFT", 0, -10)

  -- Key Level Extrapolation checkbox
  elements.extrapolationCheckbox = createCheckbox(
    leftBox,
    "PushMasterExtrapolationCheckbox",
    "Key Level Extrapolation",
    "Compare against lower key levels when no data exists for current level.\nUses mythic+ scaling to estimate performance at higher keys."
  )
  elements.extrapolationCheckbox:SetPoint("TOPLEFT", elements.minimapCheckbox, "BOTTOMLEFT", 0, -10)

  -- Frame Scale section
  local scaleLabel = leftBox:CreateFontString(nil, "OVERLAY")
  scaleLabel:SetFont(ADDON_FONT, 10)
  scaleLabel:SetPoint("TOP", configTitle, "BOTTOM", 0, -140)
  scaleLabel:SetText("Frame Scale:")
  scaleLabel:SetTextColor(1, 1, 1)

  elements.scaleSlider = CreateFrame("Slider", "PushMasterScaleSlider", leftBox, "OptionsSliderTemplate")
  elements.scaleSlider:SetSize(180, 20)
  elements.scaleSlider:SetPoint("TOP", scaleLabel, "BOTTOM", 0, -10)
  elements.scaleSlider:SetMinMaxValues(0.5, 1.5)
  elements.scaleSlider:SetValue(1.0)
  elements.scaleSlider:SetValueStep(0.1)
  elements.scaleSlider:SetObeyStepOnDrag(true)

  -- Scale slider value text
  local scaleText = elements.scaleSlider:CreateFontString(nil, "OVERLAY")
  scaleText:SetFont(ADDON_FONT, 10)
  scaleText:SetPoint("TOP", elements.scaleSlider, "BOTTOM", 0, -5)
  scaleText:SetText("100%")
  scaleText:SetTextColor(1, 1, 1)
  elements.scaleSlider.text = scaleText

  -- Scale slider labels
  elements.scaleSlider.Low:SetText("50%")
  elements.scaleSlider.High:SetText("150%")
  elements.scaleSlider.Text:SetText("")

  -- Performance/Accuracy slider
  local accuracyLabel = leftBox:CreateFontString(nil, "OVERLAY")
  accuracyLabel:SetFont(ADDON_FONT, 10)
  accuracyLabel:SetPoint("TOP", elements.scaleSlider, "BOTTOM", 0, -35)
  accuracyLabel:SetText("Accuracy:")
  accuracyLabel:SetTextColor(1, 1, 1)

  elements.accuracySlider = CreateFrame("Slider", "PushMasterAccuracySlider", leftBox, "OptionsSliderTemplate")
  elements.accuracySlider:SetSize(180, 20)
  elements.accuracySlider:SetPoint("TOP", accuracyLabel, "BOTTOM", 0, -10)
  elements.accuracySlider:SetMinMaxValues(1, 3)
  elements.accuracySlider:SetValue(2)
  elements.accuracySlider:SetValueStep(1)
  elements.accuracySlider:SetObeyStepOnDrag(true)

  -- Accuracy slider value text
  local accuracyText = elements.accuracySlider:CreateFontString(nil, "OVERLAY")
  accuracyText:SetFont(ADDON_FONT, 10)
  accuracyText:SetPoint("TOP", elements.accuracySlider, "BOTTOM", 0, -5)
  accuracyText:SetText("Balanced")
  accuracyText:SetTextColor(1, 1, 1)
  elements.accuracySlider.text = accuracyText

  -- Accuracy slider labels
  elements.accuracySlider.Low:SetText("Light")
  elements.accuracySlider.High:SetText("Aggressive")
  elements.accuracySlider.Text:SetText("")

  -- Add tooltip for accuracy slider
  elements.accuracySlider:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Performance vs Accuracy", 1, 1, 1)
    GameTooltip:AddLine("Light: Lower CPU usage, less frequent updates", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Balanced: Moderate CPU usage, standard updates", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Aggressive: Higher CPU usage, more frequent updates", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  elements.accuracySlider:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- === RIGHT BOX - TEST MODE ===
  local rightBox = CreateFrame("Frame", nil, contentArea, "BackdropTemplate")
  rightBox:SetSize(265, 340)
  rightBox:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)

  -- Right box backdrop
  rightBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  rightBox:SetBackdropColor(0, 0, 0, 0.7)
  rightBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

  -- Test mode section title
  local testTitle = rightBox:CreateFontString(nil, "OVERLAY")
  testTitle:SetFont(ADDON_FONT, 14, "OUTLINE")
  testTitle:SetPoint("TOP", rightBox, "TOP", 0, -20)
  testTitle:SetText("Test Mode")
  testTitle:SetTextColor(classColor.r, classColor.g, classColor.b)

  -- Test mode description
  local testDesc = rightBox:CreateFontString(nil, "OVERLAY")
  testDesc:SetFont(ADDON_FONT, 10)
  testDesc:SetPoint("TOP", testTitle, "BOTTOM", 0, -10)
  testDesc:SetWidth(220)
  testDesc:SetJustifyH("CENTER")
  testDesc:SetText("Simulate a Mythic+ run to test the addon interface")
  testDesc:SetTextColor(0.8, 0.8, 0.8)

  -- Start/Stop test mode button
  elements.testButton = CreateFrame("Button", "PushMasterTestButton", rightBox, "UIPanelButtonTemplate")
  elements.testButton:SetSize(140, 30)
  elements.testButton:SetPoint("TOP", testDesc, "BOTTOM", 0, -25)
  elements.testButton:SetText("Start Test Mode")

  -- Add class color to the button
  if classColor then
    local normalTexture = elements.testButton:GetNormalTexture()
    if normalTexture then
      normalTexture:SetVertexColor(
        classColor.r * 0.7 + 0.3,
        classColor.g * 0.7 + 0.3,
        classColor.b * 0.7 + 0.3
      )
    end
  end

  -- Create divider line
  local divider = rightBox:CreateTexture(nil, "ARTWORK")
  divider:SetSize(200, 1)
  divider:SetPoint("TOP", elements.testButton, "BOTTOM", 0, -20)
  divider:SetColorTexture(0.4, 0.4, 0.4, 0.8)

  -- Reset position button
  elements.resetPosButton = CreateFrame("Button", "PushMasterResetPosButton", rightBox, "UIPanelButtonTemplate")
  elements.resetPosButton:SetSize(140, 30)
  elements.resetPosButton:SetPoint("TOP", divider, "BOTTOM", 0, -20)
  elements.resetPosButton:SetText("Reset Position")

  -- Clear data button
  elements.clearDataButton = CreateFrame("Button", "PushMasterClearDataButton", rightBox, "UIPanelButtonTemplate")
  elements.clearDataButton:SetSize(140, 30)
  elements.clearDataButton:SetPoint("TOP", elements.resetPosButton, "BOTTOM", 0, -10)
  elements.clearDataButton:SetText("Clear Best Times")

  -- === FOOTER WITH VERSION INFO ===

  -- Create footer frame
  local footerFrame = CreateFrame("Frame", nil, frame)
  footerFrame:SetSize(frame:GetWidth(), 65)
  footerFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

  -- Version and author info centered with gold color
  local versionText = footerFrame:CreateFontString(nil, "OVERLAY")
  versionText:SetFont(ADDON_FONT, 11)
  versionText:SetPoint("CENTER", footerFrame, "CENTER", 0, 0)
  versionText:SetTextColor(1, 0.82, 0) -- Gold color

  -- Store reference for dynamic updates
  elements.versionText = versionText

  PushMaster:DebugPrint("Settings frame created")
end

---Load current settings into the UI
local function loadSettings()
  if not frame or not PushMasterDB then
    return
  end

  -- Set initial values from saved variables with error handling
  if PushMasterDB and PushMasterDB.settings then
    elements.enableCheckbox:SetChecked(PushMasterDB.settings.enabled ~= false) -- Default to true
  else
    elements.enableCheckbox:SetChecked(true)                                   -- Default fallback
  end

  if PushMasterDB and PushMasterDB.minimap then
    elements.minimapCheckbox:SetChecked(not PushMasterDB.minimap.hide)
  else
    elements.minimapCheckbox:SetChecked(true) -- Default fallback
  end

  -- Load extrapolation setting (default to false for this advanced feature)
  if PushMasterDB and PushMasterDB.settings then
    elements.extrapolationCheckbox:SetChecked(PushMasterDB.settings.enableExtrapolation == true)
  else
    elements.extrapolationCheckbox:SetChecked(false) -- Default to disabled
  end

  -- Load scale setting
  local scale = 1.0
  if PushMasterDB and PushMasterDB.settings and PushMasterDB.settings.frameScale then
    scale = PushMasterDB.settings.frameScale
    -- Clamp scale to new valid range (0.5-1.5)
    scale = math.max(0.5, math.min(1.5, scale))
  end
  elements.scaleSlider:SetValue(scale)
  elements.scaleSlider.text:SetText(string.format("%.0f%%", scale * 100))

  -- Load accuracy setting
  local accuracy = 2 -- Default to Balanced
  if PushMasterDB and PushMasterDB.settings and PushMasterDB.settings.accuracy then
    accuracy = PushMasterDB.settings.accuracy
    accuracy = math.max(1, math.min(3, accuracy))
  end
  elements.accuracySlider:SetValue(accuracy)
  local accuracyTexts = { [1] = "Light", [2] = "Balanced", [3] = "Aggressive" }
  elements.accuracySlider.text:SetText(accuracyTexts[accuracy])

  -- Apply performance profile on load
  if PushMaster.Core and PushMaster.Core.Performance then
    local profiles = { [1] = "LOW", [2] = "BALANCED", [3] = "HIGH" }
    PushMaster.Core.Performance:SetProfile(profiles[accuracy])
  end

  -- Update version and author text from TOC metadata
  if elements.versionText then
    local version = "1.2.1"   -- Fallback version
    local author = "Jervaise" -- Fallback author

    -- Always try to get the latest version from TOC metadata first
    if GetAddOnMetadata then
      local tocVersion = GetAddOnMetadata(addonName, "Version")
      local tocAuthor = GetAddOnMetadata(addonName, "Author")

      if tocVersion then
        version = tocVersion
        -- Update the centralized PushMaster version to keep it in sync
        PushMaster.version = version
      end

      if tocAuthor then
        author = tocAuthor
        -- Update the centralized PushMaster author to keep it in sync
        PushMaster.author = author
      end
    else
      -- If GetAddOnMetadata is not available, use the stored PushMaster values
      if PushMaster.version and PushMaster.version ~= "Loading..." then
        version = PushMaster.version
      end

      if PushMaster.author and PushMaster.author ~= "Loading..." then
        author = PushMaster.author
      end
    end

    elements.versionText:SetText("by " .. author .. " - v" .. version)
    PushMaster:DebugPrint("Footer refreshed: v" .. version .. " by " .. author)
  end

  PushMaster:DebugPrint("Settings loaded into UI")
end

---Save current UI settings
local function saveSettings()
  if not frame or not PushMasterDB then
    return
  end

  -- Save settings with error handling
  if PushMasterDB and PushMasterDB.settings then
    PushMasterDB.settings.enabled = elements.enableCheckbox:GetChecked()
    PushMasterDB.settings.frameScale = elements.scaleSlider:GetValue()
    PushMasterDB.settings.enableExtrapolation = elements.extrapolationCheckbox:GetChecked()
    PushMasterDB.settings.accuracy = elements.accuracySlider:GetValue()
  end

  local showMinimap = elements.minimapCheckbox:GetChecked()
  if PushMasterDB and PushMasterDB.minimap then
    PushMasterDB.minimap.hide = not showMinimap
  end

  -- Update minimap button visibility
  if PushMaster.UI.MinimapButton then
    if showMinimap then
      PushMaster.UI.MinimapButton:Show()
    else
      PushMaster.UI.MinimapButton:Hide()
    end
  end

  -- Apply scale to main frame
  local scale = elements.scaleSlider:GetValue()
  if PushMaster.UI.MainFrame and PushMaster.UI.MainFrame.GetFrame then
    local mainFrame = PushMaster.UI.MainFrame:GetFrame()
    if mainFrame then
      mainFrame:SetScale(scale)
    end
  end

  PushMaster:DebugPrint("Settings saved")
end

---Setup event handlers for UI elements
local function setupEventHandlers()
  -- Checkbox change handlers
  elements.enableCheckbox:SetScript("OnClick", saveSettings)
  elements.minimapCheckbox:SetScript("OnClick", saveSettings)
  elements.extrapolationCheckbox:SetScript("OnClick", saveSettings)

  -- Scale slider handler
  elements.scaleSlider:SetScript("OnValueChanged", function(self, value)
    local percentage = string.format("%.0f%%", value * 100)
    self.text:SetText(percentage)
    saveSettings()
  end)

  -- Accuracy slider handler
  elements.accuracySlider:SetScript("OnValueChanged", function(self, value)
    local accuracyTexts = { [1] = "Light", [2] = "Balanced", [3] = "Aggressive" }
    self.text:SetText(accuracyTexts[value])
    saveSettings()

    -- Update Performance module settings
    if PushMaster.Core and PushMaster.Core.Performance then
      local profiles = { [1] = "LOW", [2] = "BALANCED", [3] = "HIGH" }
      PushMaster.Core.Performance:SetProfile(profiles[value])
    end
  end)

  -- Test mode button (toggle functionality)
  elements.testButton:SetScript("OnClick", function()
    if PushMaster.UI.TestMode then
      if PushMaster.UI.TestMode:IsActive() then
        -- Stop test mode and reset to default state
        PushMaster.UI.TestMode:StopTest()
        elements.testButton:SetText("Start Test Mode")

        -- Don't update MainFrame here - let TestMode:StopTest() handle it properly
      else
        -- Start test mode
        PushMaster.UI.TestMode:StartTest()
        elements.testButton:SetText("Stop Test Mode")
      end
    end
  end)

  -- Reset position button
  elements.resetPosButton:SetScript("OnClick", function()
    if PushMaster.UI.MainFrame then
      PushMaster.UI.MainFrame:ResetPosition()
      PushMaster:Print("Main frame position reset")
    end
  end)

  -- Clear data button
  elements.clearDataButton:SetScript("OnClick", function()
    StaticPopup_Show("PUSHMASTER_RESET_CONFIRM")
  end)

  PushMaster:DebugPrint("Event handlers setup")
end

---Initialize the SettingsFrame module
function SettingsFrame:Initialize()
  if isInitialized then
    return
  end

  PushMaster:DebugPrint("SettingsFrame module initialized")

  -- Create the frame
  createSettingsFrame()

  -- Setup event handlers
  setupEventHandlers()

  -- Register for metadata updates (when PLAYER_LOGIN loads the real version/author)
  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("PLAYER_LOGIN")
  eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
      -- Update footer with newly loaded metadata
      C_Timer.After(0.1, function() -- Small delay to ensure metadata is loaded
        if frame and frame:IsShown() then
          SettingsFrame:RefreshFooter()
        end
      end)
    end
  end)

  isInitialized = true
end

---Show the settings frame
function SettingsFrame:Show()
  if frame then
    loadSettings()

    -- Update test button text based on current state
    if elements.testButton and PushMaster.UI.TestMode then
      if PushMaster.UI.TestMode:IsActive() then
        elements.testButton:SetText("Stop Test Mode")
      else
        elements.testButton:SetText("Start Test Mode")
      end
    end

    -- Refresh footer to ensure version/author are current
    self:RefreshFooter()

    frame:Show()

    -- Show main frame when settings panel is open so people can drag it
    if PushMaster.UI and PushMaster.UI.MainFrame then
      PushMaster.UI.MainFrame:Show()
    end

    PushMaster:DebugPrint("Settings frame shown")
  end
end

---Hide the settings frame
function SettingsFrame:Hide()
  if frame then
    frame:Hide()

    -- Stop test mode if running
    if PushMaster.UI and PushMaster.UI.TestMode and PushMaster.UI.TestMode:IsActive() then
      PushMaster.UI.TestMode:StopTest()
      if elements.testButton then
        elements.testButton:SetText("Start Test Mode")
      end

      -- Don't hide MainFrame immediately - let test mode reset it first
      return
    end

    -- Hide main frame when settings panel closes (unless in a mythic+ dungeon)
    if PushMaster.UI and PushMaster.UI.MainFrame then
      if PushMaster.Data and PushMaster.Data.EventHandlers and not PushMaster.Data.EventHandlers:IsInMythicPlus() then
        PushMaster.UI.MainFrame:Hide()
      end
    end
  end
end

---Toggle the settings frame visibility
function SettingsFrame:Toggle()
  if frame then
    if frame:IsShown() then
      self:Hide()
    else
      self:Show()
    end
  end
end

---Check if the settings frame is shown
---@return boolean isShown True if the frame is shown
function SettingsFrame:IsShown()
  return frame and frame:IsShown() or false
end

---Get the settings frame object
---@return Frame|nil frame The settings frame or nil if not created
function SettingsFrame:GetFrame()
  return frame
end

---Show export dialog for data export
function SettingsFrame:ShowExportDialog()
  -- Get the player's class color
  local classColor = getClassColor()

  -- Create a simple export dialog
  local exportFrame = CreateFrame("Frame", "PushMasterExportFrame", UIParent, "BackdropTemplate")
  exportFrame:SetSize(400, 300)
  exportFrame:SetPoint("CENTER")
  exportFrame:SetFrameStrata("DIALOG")
  exportFrame:SetMovable(true)
  exportFrame:EnableMouse(true)
  exportFrame:RegisterForDrag("LeftButton")
  exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
  exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)

  -- Add backdrop
  exportFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  exportFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  exportFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

  -- Title
  local title = exportFrame:CreateFontString(nil, "OVERLAY")
  title:SetFont(ADDON_FONT, 14, "OUTLINE")
  title:SetPoint("TOP", exportFrame, "TOP", 0, -15)
  title:SetText("Export PushMaster Data")
  title:SetTextColor(classColor.r, classColor.g, classColor.b)

  -- Export text area
  local scrollFrame = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 15, -45)
  scrollFrame:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -35, 45)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetWidth(scrollFrame:GetWidth())
  editBox:SetAutoFocus(false)
  scrollFrame:SetScrollChild(editBox)

  -- Generate export data
  local exportData = "PushMaster Export Data\n"
  exportData = exportData .. "Version: " .. (PushMaster.version or "Unknown") .. "\n"
  exportData = exportData .. "Export Date: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n"

  if PushMasterDB and PushMasterDB.bestTimes then
    exportData = exportData .. "Best Times:\n"
    for dungeonKey, data in pairs(PushMasterDB.bestTimes) do
      exportData = exportData .. dungeonKey .. ": " .. tostring(data) .. "\n"
    end
  else
    exportData = exportData .. "No best times data available.\n"
  end

  editBox:SetText(exportData)
  editBox:HighlightText()

  -- Close button
  local closeButton = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -3, -3)
  closeButton:SetScript("OnClick", function()
    exportFrame:Hide()
  end)

  -- Copy button
  local copyButton = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
  copyButton:SetSize(80, 25)
  copyButton:SetPoint("BOTTOM", exportFrame, "BOTTOM", 0, 15)
  copyButton:SetText("Select All")
  copyButton:SetScript("OnClick", function()
    editBox:HighlightText()
    editBox:SetFocus()
  end)

  exportFrame:Show()
  PushMaster:DebugPrint("Export dialog shown")
end

---Refresh the footer version and author text
function SettingsFrame:RefreshFooter()
  if elements.versionText then
    local version = "1.2.1"   -- Fallback version
    local author = "Jervaise" -- Fallback author

    -- Always try to get the latest version from TOC metadata first
    if GetAddOnMetadata then
      local tocVersion = GetAddOnMetadata(addonName, "Version")
      local tocAuthor = GetAddOnMetadata(addonName, "Author")

      if tocVersion then
        version = tocVersion
        -- Update the centralized PushMaster version to keep it in sync
        PushMaster.version = version
      end

      if tocAuthor then
        author = tocAuthor
        -- Update the centralized PushMaster author to keep it in sync
        PushMaster.author = author
      end
    else
      -- If GetAddOnMetadata is not available, use the stored PushMaster values
      if PushMaster.version and PushMaster.version ~= "Loading..." then
        version = PushMaster.version
      end

      if PushMaster.author and PushMaster.author ~= "Loading..." then
        author = PushMaster.author
      end
    end

    elements.versionText:SetText("by " .. author .. " - v" .. version)
    PushMaster:DebugPrint("Footer refreshed: v" .. version .. " by " .. author)
  end
end
