---@class PushMasterMainFrame
---Main UI frame for PushMaster addon
---Displays real-time Mythic+ tracking information in a one-line format
---Format: [⚡][🟢+15%] [🗑️][🟢+7%] [👹][🟡+1] [💀][🔴+2(+30s)]

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create MainFrame module
local MainFrame = {}
if not PushMaster.UI then
  PushMaster.UI = {}
end
PushMaster.UI.MainFrame = MainFrame

-- Local references
local frame = nil
local isInitialized = false
local timeDeltaFrame = nil
local elements = {
  keystoneHeader = nil,
  displayText = {},
  iconTextures = {},
  timeDelta = nil
}

-- PERFORMANCE OPTIMIZATION: Cache last display values to prevent redundant updates
local lastDisplayValues = {
  overall = nil,
  trash = nil,
  boss = nil,
  death = nil,
  keystoneHeader = nil,
  borderColor = nil,
  timeDelta = nil
}

-- STABILITY: Add smoothing for display values to prevent rapid fluctuations
local displaySmoothing = {
  timeDelta = {
    lastValue = nil,
    lastUpdateTime = 0,
    stabilityThreshold = 30, -- Only update if difference > 30 seconds
    timeThreshold = 2.0      -- Or if more than 2 seconds have passed
  }
}

-- PERFORMANCE OPTIMIZATION: Cache last comparison data to prevent redundant calculations
local lastComparisonCache = {
  data = nil,
  timestamp = 0,
  cacheValidityDuration = 1.5 -- Cache is valid for 1.5 seconds
}

-- Frame settings
local FRAME_WIDTH = 250        -- Reduced to better balance margins
local FRAME_HEIGHT = 50        -- Increased from 30 to accommodate header
local TIME_DELTA_HEIGHT = 30   -- Height for time delta frame
local HEADER_HEIGHT = 18       -- Height for the keystone header
local MAIN_CONTENT_HEIGHT = 30 -- Height for the main content area
local FRAME_PADDING = 8
local ICON_SIZE = 16
local ICON_SPACING = 8
local TEXT_SEGMENT_WIDTH = 42
local DEATH_SEGMENT_WIDTH = 35 -- Reduced from 60 to fit 2-digit deaths without time penalty

-- Color codes for WoW
local COLORS = {
  GREEN = "|cFF00FF00",  -- 🟢 Better performance
  RED = "|cFFFF0000",    -- 🔴 Worse performance
  YELLOW = "|cFFFFFF00", -- 🟡 Neutral/warning state
  GRAY = "|cFF808080",   -- No data
  WHITE = "|cFFFFFFFF",  -- Default text
  RESET = "|r"           -- Reset color
}

-- Border colors for frame backdrop
local BORDER_COLORS = {
  GREEN = { 0.2, 0.8, 0.2, 1 },  -- Green tint for on par or better
  RED = { 0.8, 0.2, 0.2, 1 },    -- Red tint for behind
  NEUTRAL = { 0.3, 0.3, 0.3, 1 } -- Default gray
}

-- Timer for regular UI updates
local updateTimer = nil
local UPDATE_INTERVAL = 2.0 -- PERFORMANCE FIX: Reduced from 1.0s to 2.0s to halve CPU load

-- Forward declare timer functions so they can be called from MainFrame methods
local startUpdateTimer, stopUpdateTimer

---Start the UI update timer
startUpdateTimer = function()
  if updateTimer then
    updateTimer:Cancel()
  end

  updateTimer = C_Timer.NewTicker(UPDATE_INTERVAL, function()
    -- Only update if we have an active Calculator and are tracking a run
    if PushMaster.Data and PushMaster.Data.Calculator and PushMaster.Data.Calculator:IsTrackingRun() then
      -- PERFORMANCE OPTIMIZATION: Check cache first
      local now = GetTime()
      local comparison = nil

      if lastComparisonCache.data and (now - lastComparisonCache.timestamp) < lastComparisonCache.cacheValidityDuration then
        -- Use cached data if still valid
        comparison = lastComparisonCache.data
      else
        -- Get fresh data and cache it
        comparison = PushMaster.Data.Calculator:GetCurrentComparison()
        if comparison then
          lastComparisonCache.data = comparison
          lastComparisonCache.timestamp = now
        end
      end

      if comparison and MainFrame:IsShown() then
        MainFrame:UpdateDisplay(comparison)
      end
    end
  end)
end

---Stop the UI update timer
stopUpdateTimer = function()
  if updateTimer then
    updateTimer:Cancel()
    updateTimer = nil
  end
end

-- Icon paths using custom TGA files from Media folder
local ICON_PATHS = {
  OVERALL = "Interface\\AddOns\\PushMaster\\Media\\flash", -- ⚡ Lightning/flash for overall speed
  TRASH = "Interface\\AddOns\\PushMaster\\Media\\bin",     -- 🗑️ Bin icon for trash
  BOSS = "Interface\\AddOns\\PushMaster\\Media\\dragon",   -- 👹 Dragon icon for bosses
  DEATH = "Interface\\AddOns\\PushMaster\\Media\\skull"    -- 💀 Skull icon for deaths
}

---Create icon texture
---@param parent Frame The parent frame
---@param iconPath string Path to the icon texture
---@param size number Size of the icon
---@return Texture iconTexture The created texture
local function createIconTexture(parent, iconPath, size)
  local texture = parent:CreateTexture(nil, "OVERLAY")
  texture:SetTexture(iconPath)
  texture:SetSize(size, size)
  return texture
end

---Create the time delta frame
local function createTimeDeltaFrame()
  -- Create time delta frame as child of main frame with border and BackdropTemplate
  timeDeltaFrame = CreateFrame("Frame", "PushMasterTimeDeltaFrame", frame, "BackdropTemplate")
  timeDeltaFrame:SetSize(FRAME_WIDTH, TIME_DELTA_HEIGHT)
  timeDeltaFrame:SetPoint("BOTTOM", frame, "TOP", 0, 5) -- Attach to top of main frame

  -- Set backdrop identical to main frame
  timeDeltaFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  timeDeltaFrame:SetBackdropColor(0, 0, 0, 0.8)
  timeDeltaFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) -- Default border color

  -- No drag functionality - frame moves with parent

  -- Create time delta text
  elements.timeDelta = timeDeltaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  elements.timeDelta:SetPoint("CENTER", timeDeltaFrame, "CENTER", 0, 0)
  elements.timeDelta:SetJustifyH("CENTER")
  elements.timeDelta:SetText("") -- Initially empty

  -- Initially hide the frame
  timeDeltaFrame:Hide()

  PushMaster:DebugPrint("Time delta frame created as child of main frame with matching border")
  return timeDeltaFrame
end

---Create the main frame
local function createMainFrame()
  -- Get the player's class color
  local playerClass = select(2, UnitClass("player"))
  local classColor = RAID_CLASS_COLORS[playerClass] or
      { r = 1, g = 0.82, b = 0 } -- Fallback to gold if class color not found

  -- Create main frame
  frame = CreateFrame("Frame", "PushMasterMainFrame", UIParent, "BackdropTemplate")
  frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

  -- Set backdrop for sleek design
  frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

  -- Create keystone header
  elements.keystoneHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  elements.keystoneHeader:SetPoint("TOP", frame, "TOP", 0, -8)
  elements.keystoneHeader:SetJustifyH("CENTER")
  elements.keystoneHeader:SetTextColor(classColor.r, classColor.g, classColor.b, 1) -- Use class color
  elements.keystoneHeader:SetText("Keystone Info")

  -- Create time delta frame separately
  createTimeDeltaFrame()

  -- Make frame movable
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position
    local point, _, relativePoint, x, y = self:GetPoint()
    if PushMasterDB and PushMasterDB.settings then
      PushMasterDB.settings.framePosition = { point = point, relativePoint = relativePoint, x = x, y = y }
    end
  end)

  -- Create icon textures
  elements.iconTextures.overall = createIconTexture(frame, ICON_PATHS.OVERALL, ICON_SIZE)
  elements.iconTextures.trash = createIconTexture(frame, ICON_PATHS.TRASH, ICON_SIZE)
  elements.iconTextures.boss = createIconTexture(frame, ICON_PATHS.BOSS, ICON_SIZE)
  elements.iconTextures.death = createIconTexture(frame, ICON_PATHS.DEATH, ICON_SIZE)

  -- Create individual text segments with fixed positioning
  elements.displayText = {}
  elements.displayText.overall = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  elements.displayText.trash = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  elements.displayText.boss = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  elements.displayText.death = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  -- Set text properties
  for _, textElement in pairs(elements.displayText) do
    textElement:SetJustifyH("LEFT")
    textElement:SetTextColor(1, 1, 1, 1)
  end

  -- Position elements with fixed spacing - center aligned horizontally
  -- Calculate total content width: 4 icons + 4 text segments + spacing between them
  local totalContentWidth = (ICON_SIZE * 4) + (2 * 4) + (TEXT_SEGMENT_WIDTH * 3) + DEATH_SEGMENT_WIDTH
  -- Account for frame backdrop insets and add 10px left margin
  local availableWidth = FRAME_WIDTH - 8
  local startX = (availableWidth - totalContentWidth) / 2 + 8 + 10 -- +10 for additional left margin
  local yOffset = -8                                               -- Moved back down 2px for better spacing

  local xOffset = startX

  -- Overall speed: Icon + Text
  elements.iconTextures.overall:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + ICON_SIZE + 2
  elements.displayText.overall:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + TEXT_SEGMENT_WIDTH

  -- Trash progress: Icon + Text
  elements.iconTextures.trash:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + ICON_SIZE + 2
  elements.displayText.trash:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + TEXT_SEGMENT_WIDTH

  -- Boss progress: Icon + Text
  elements.iconTextures.boss:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + ICON_SIZE + 2
  elements.displayText.boss:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + TEXT_SEGMENT_WIDTH

  -- Death count: Icon + Text (with extra width for time penalty)
  elements.iconTextures.death:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)
  xOffset = xOffset + ICON_SIZE + 2
  elements.displayText.death:SetPoint("LEFT", frame, "LEFT", xOffset, yOffset)

  -- Set initial text
  elements.displayText.overall:SetText("?%")
  elements.displayText.trash:SetText("?%")
  elements.displayText.boss:SetText("?")
  elements.displayText.death:SetText("0")

  -- Initially hide the frame
  frame:Hide()

  PushMaster:DebugPrint("Fixed-layout main frame with icons created")
  return frame
end

---Format percentage difference with appropriate color and better context
---@param value number The percentage difference
---@param isEfficiency boolean Whether this is progress efficiency (vs simple percentage)
---@return string formattedText Colored and formatted percentage
local function formatPercentage(value, isEfficiency)
  if value == nil then                          -- Explicitly check for nil, as 0 is a valid value
    return COLORS.GRAY .. "N/A" .. COLORS.RESET -- Changed from ? to N/A for clarity
  end

  local color
  local sign = ""

  if value > 0 then
    color = COLORS.GREEN
    sign = "+"
  elseif value < 0 then
    color = COLORS.RED
    sign = "" -- Negative sign is already included in the number
  else
    -- Neutral value (exactly 0) - being on par with best run is good, so use green
    color = COLORS.GREEN
    sign = ""
  end

  -- For efficiency, add context to make it clearer
  local suffix = isEfficiency and "%" or "%"

  -- Don't use math.abs - show the actual value with proper sign
  return color .. sign .. string.format("%.0f", value) .. suffix .. COLORS.RESET
end

---Format boss count difference with appropriate color
---@param value number The boss count difference
---@return string formattedText Colored and formatted boss count
local function formatBossCount(value)
  if value == nil then                          -- Explicitly check for nil
    return COLORS.GRAY .. "N/A" .. COLORS.RESET -- Changed from ? to N/A for clarity
  end

  local color
  local sign = ""

  if value > 0 then
    color = COLORS.GREEN
    sign = "+"
  elseif value < 0 then
    color = COLORS.RED
    sign = "" -- Negative sign is already included in the number
  else
    -- Neutral value (exactly 0) - being on par with best run is good, so use green
    color = COLORS.GREEN
    sign = ""
  end

  -- Don't use math.abs - show the actual value with proper sign
  return color .. sign .. tostring(value) .. COLORS.RESET
end

---Format death count delta with appropriate color
---@param deathDelta number The death count difference vs best run
---@param timePenalty number Time penalty in seconds (unused now)
---@return string formattedText Colored and formatted death delta
local function formatDeaths(deathDelta, timePenalty)
  if deathDelta == nil then                     -- Explicitly check for nil
    return COLORS.GRAY .. "N/A" .. COLORS.RESET -- No comparison data available
  end

  local color
  local sign = ""

  if deathDelta > 0 then
    color = COLORS.RED
    sign = "+"
  elseif deathDelta < 0 then
    color = COLORS.GREEN
    sign = "" -- Negative sign is already included in the number
  else
    -- Neutral value (exactly 0) - same deaths as best run
    color = COLORS.GREEN
    sign = ""
  end

  -- Show the actual delta value with proper sign
  return color .. sign .. tostring(deathDelta) .. COLORS.RESET
end

---Format time delta with confidence interval and smoothing
---@param timeDelta number Time difference in seconds (positive = behind, negative = ahead)
---@param confidence number Confidence percentage (0-100)
---@return string formattedText Colored and formatted time delta
local function formatTimeDelta(timeDelta, confidence)
  if timeDelta == nil or confidence == nil then
    return "" -- Don't show if no data
  end

  if confidence < 30 then
    return "" -- Don't show if low confidence
  end

  -- STABILITY: Apply smoothing to prevent rapid fluctuations
  local currentTime = GetTime()
  local smoothing = displaySmoothing.timeDelta

  local shouldUpdate = false
  if smoothing.lastValue == nil then
    -- First time, always update
    shouldUpdate = true
  elseif math.abs(timeDelta - smoothing.lastValue) > smoothing.stabilityThreshold then
    -- Significant change, update immediately
    shouldUpdate = true
  elseif (currentTime - smoothing.lastUpdateTime) > smoothing.timeThreshold then
    -- Enough time has passed, update even with small changes
    shouldUpdate = true
  end

  if not shouldUpdate then
    -- Use the last displayed value to prevent flickering
    timeDelta = smoothing.lastValue
  else
    -- Update the smoothing values
    smoothing.lastValue = timeDelta
    smoothing.lastUpdateTime = currentTime
  end

  local color
  local sign = ""
  local absTime = math.abs(timeDelta)

  if timeDelta > 0 then
    -- Behind (positive delta)
    color = COLORS.RED
    sign = "+"
  else
    -- Ahead (negative delta)
    color = COLORS.GREEN
    sign = "-"
  end

  -- Format time as minutes:seconds or just seconds
  local timeText
  if absTime >= 60 then
    local minutes = math.floor(absTime / 60)
    local seconds = math.floor(absTime % 60)
    timeText = string.format("%dm%02ds", minutes, seconds)
  else
    timeText = string.format("%ds", math.floor(absTime))
  end

  -- No confidence indicator shown
  return color .. sign .. timeText .. COLORS.RESET
end

---Update the display with current comparison data
---@param comparisonData table The comparison data from Calculator
function MainFrame:UpdateDisplay(comparisonData)
  if not frame or not elements.displayText then
    return
  end

  -- DEBUG: Log suspicious values that might indicate calculation issues
  if comparisonData.trashProgress and math.abs(comparisonData.trashProgress) > 200 then
    PushMaster:DebugPrint(string.format("SUSPICIOUS: Trash progress value %.1f%% seems too extreme",
      comparisonData.trashProgress))
  end

  if comparisonData.timeDelta and math.abs(comparisonData.timeDelta) > 1800 then -- More than 30 minutes
    PushMaster:DebugPrint(string.format("SUSPICIOUS: Time delta %.0fs (%.1fm) seems too extreme",
      comparisonData.timeDelta, comparisonData.timeDelta / 60))
  end

  if comparisonData.progress and comparisonData.progress.trash and comparisonData.progress.trash > 100 then
    PushMaster:DebugPrint(string.format("ISSUE: Current trash progress %.1f%% exceeds 100%%",
      comparisonData.progress.trash))
  end

  -- Format display values
  local overallText = formatPercentage(comparisonData.progressEfficiency, true)
  local trashText = formatPercentage(comparisonData.trashProgress, true)
  local bossText = formatBossCount(comparisonData.bossProgress)
  local deathText = formatDeaths(comparisonData.deathProgress, comparisonData.deathTimePenalty)
  local keystoneText = string.format("%s +%d", comparisonData.dungeon or "Unknown", comparisonData.level or 0)

  -- Update border color based on overall performance
  local borderColor = BORDER_COLORS.NEUTRAL
  local performanceStatus = "neutral"

  if comparisonData.progressEfficiency ~= nil then
    if comparisonData.progressEfficiency > 0 then
      borderColor = BORDER_COLORS.GREEN
      performanceStatus = "ahead"
    elseif comparisonData.progressEfficiency < 0 then
      borderColor = BORDER_COLORS.RED
      performanceStatus = "behind"
    else
      -- Exactly 0 - on par with best run, which is good
      borderColor = BORDER_COLORS.GREEN
      performanceStatus = "onpar"
    end
  end

  -- Only update border color if it changed
  if performanceStatus ~= lastDisplayValues.borderColor then
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    -- Apply same border color to time delta frame if it exists
    if timeDeltaFrame then
      timeDeltaFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end

    lastDisplayValues.borderColor = performanceStatus
  end

  -- PERFORMANCE OPTIMIZATION: Only update text when it actually changes
  if overallText ~= lastDisplayValues.overall then
    elements.displayText.overall:SetText(overallText)
    lastDisplayValues.overall = overallText
  end

  if trashText ~= lastDisplayValues.trash then
    elements.displayText.trash:SetText(trashText)
    lastDisplayValues.trash = trashText
  end

  if bossText ~= lastDisplayValues.boss then
    elements.displayText.boss:SetText(bossText)
    lastDisplayValues.boss = bossText
  end

  if deathText ~= lastDisplayValues.death then
    elements.displayText.death:SetText(deathText)
    lastDisplayValues.death = deathText
  end

  -- Update keystone header only if changed
  if keystoneText ~= lastDisplayValues.keystoneHeader then
    elements.keystoneHeader:SetText(keystoneText)
    lastDisplayValues.keystoneHeader = keystoneText
  end

  -- Update time delta display and frame visibility
  local timeDeltaText = formatTimeDelta(comparisonData.timeDelta, comparisonData.timeConfidence)
  if timeDeltaText ~= lastDisplayValues.timeDelta then
    elements.timeDelta:SetText(timeDeltaText)
    lastDisplayValues.timeDelta = timeDeltaText

    -- Show/hide time delta frame based on whether we have data to display
    if timeDeltaFrame then
      if timeDeltaText ~= "" then
        timeDeltaFrame:Show()
      else
        timeDeltaFrame:Hide()
      end
    end
  end
end

---Reset cached display values (call when frame is hidden/reset)
function MainFrame:ResetDisplayCache()
  lastDisplayValues = {
    overall = nil,
    trash = nil,
    boss = nil,
    death = nil,
    keystoneHeader = nil,
    borderColor = nil,
    timeDelta = nil
  }

  -- STABILITY: Reset display smoothing values
  displaySmoothing.timeDelta.lastValue = nil
  displaySmoothing.timeDelta.lastUpdateTime = 0

  PushMaster:DebugPrint("Display cache reset")
end

---Clear the comparison cache (called when run state changes)
function MainFrame:ClearCache()
  lastComparisonCache.data = nil
  lastComparisonCache.timestamp = 0
end

---Show the main frame
function MainFrame:Show()
  if not isInitialized then
    self:Initialize()
  end

  -- Clear cache when showing to ensure fresh data
  self:ClearCache()
  self:ResetDisplayCache() -- STABILITY: Reset display smoothing when showing

  if frame then
    frame:Show()
    -- Time delta frame will automatically show/hide with parent frame based on data availability
    startUpdateTimer()
  end
end

---Hide the main frame
function MainFrame:Hide()
  if frame then
    frame:Hide()
    stopUpdateTimer()
    -- Clear cache when hiding to free memory
    self:ClearCache()
    self:ResetDisplayCache() -- STABILITY: Reset display smoothing when hiding
  end

  -- Time delta frame automatically hides with parent frame
end

---Check if the main frame is shown
---@return boolean isShown True if the frame is shown
function MainFrame:IsShown()
  return frame and frame:IsShown() or false
end

---Get the actual frame object
---@return Frame|nil frame The main frame object or nil if not initialized
function MainFrame:GetFrame()
  return frame
end

---Get the time delta frame object
---@return Frame|nil timeDeltaFrame The time delta frame object or nil if not initialized
function MainFrame:GetTimeDeltaFrame()
  return timeDeltaFrame
end

---Toggle the main frame visibility
function MainFrame:Toggle()
  if self:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

---Reset the main frame position to default
function MainFrame:ResetPosition()
  if not frame then
    PushMaster:DebugPrint("MainFrame not initialized, cannot reset position")
    return false
  end

  -- Reset to default position (center-top of screen)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

  -- Clear saved position
  if PushMasterDB and PushMasterDB.settings then
    PushMasterDB.settings.framePosition = nil
  end

  PushMaster:DebugPrint("MainFrame position reset to default")
  return true
end

---Load saved frame position
local function loadFramePosition()
  if not frame or not PushMasterDB or not PushMasterDB.settings then
    return
  end

  -- Load main frame position
  if PushMasterDB.settings.framePosition then
    local pos = PushMasterDB.settings.framePosition
    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 200)
    PushMaster:DebugPrint("MainFrame position loaded from saved settings")
  end
end

---Setup event handlers for the frame
local function setupEventHandlers()
  if not frame then
    return
  end

  -- Frame is already set up with drag handlers in createMainFrame
  -- This function is here for future event handler additions
  PushMaster:DebugPrint("MainFrame event handlers setup")
end

---Initialize the main frame
function MainFrame:Initialize()
  if frame then
    return
  end

  frame = createMainFrame()

  -- Apply saved scale setting
  if PushMasterDB and PushMasterDB.settings and PushMasterDB.settings.frameScale then
    frame:SetScale(PushMasterDB.settings.frameScale)
  end

  setupEventHandlers()
  loadFramePosition()

  -- Register for dungeon events to auto-show/hide
  frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  frame:RegisterEvent("CHALLENGE_MODE_START")
  frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
  frame:RegisterEvent("CHALLENGE_MODE_RESET")

  frame:SetScript("OnEvent", function(self, event, ...)
    MainFrame:OnEvent(event, ...)
  end)

  PushMaster:DebugPrint("MainFrame initialized with fixed-layout design and continuous updates")
end

---Handle events for auto-show/hide functionality
function MainFrame:OnEvent(event, ...)
  if event == "ZONE_CHANGED_NEW_AREA" or
      event == "CHALLENGE_MODE_START" or
      event == "CHALLENGE_MODE_COMPLETED" or
      event == "CHALLENGE_MODE_RESET" then
    -- Check if we're in a Mythic+ dungeon
    if PushMaster.Data and PushMaster.Data.EventHandlers then
      local inMythicPlus = PushMaster.Data.EventHandlers:IsInMythicPlus()

      if inMythicPlus then
        -- Auto-show in Mythic+ dungeons
        self:Show()
        PushMaster:DebugPrint("Auto-showing MainFrame in Mythic+ dungeon")
      else
        -- Auto-hide when leaving dungeon (unless settings panel is open)
        local settingsOpen = PushMaster.UI and PushMaster.UI.SettingsFrame and PushMaster.UI.SettingsFrame:IsShown()
        if not settingsOpen then
          self:Hide()
          PushMaster:DebugPrint("Auto-hiding MainFrame outside Mythic+ dungeon")
        end
      end
    end
  end
end
