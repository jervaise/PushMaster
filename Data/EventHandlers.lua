---@class PushMasterEventHandlers
---Event handling module for PushMaster addon
---Manages WoW events related to Mythic+ dungeons
---Adapted from MythicPlusTimer event system with performance optimizations

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create EventHandlers module
local EventHandlers = {}
if not PushMaster.Data then
  PushMaster.Data = {}
end
PushMaster.Data.EventHandlers = EventHandlers

-- Local references for performance
local C_ChallengeMode = C_ChallengeMode
local C_Scenario = C_Scenario
local C_ScenarioInfo = C_ScenarioInfo
local GetTime = GetTime
local GetInstanceInfo = GetInstanceInfo

-- PERFORMANCE OPTIMIZATION: Cache frequently accessed data
local lastTrashPercent = 0
local lastUpdateTime = 0
local TRASH_UPDATE_THROTTLE = 1.0 -- PERFORMANCE FIX: Increased to 1s to reduce CPU load

-- CRITICAL FIX: Cache combat log function to prevent repeated calls
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

-- Event listeners storage
local eventListeners = {}

-- Create event frame
local eventFrame = CreateFrame("Frame", addonName .. "EventFrame")

-- CRITICAL FIX: Pre-filter combat log events to reduce processing overhead
local DEATH_EVENTS = {
  ["UNIT_DIED"] = true,
  ["PARTY_KILL"] = true,
  ["SPELL_INSTAKILL"] = true
}

-- Timer for continuous progress checking (backup for when events stop firing)
local progressCheckTimer = nil
local PROGRESS_CHECK_INTERVAL = 2.0 -- PERFORMANCE FIX: Increased to 2s to reduce CPU load

-- Timer update throttling
local lastTimerUpdate = 0
local TIMER_UPDATE_THROTTLE = 2.0 -- PERFORMANCE FIX: Increased to 2s to reduce CPU load

-- PERFORMANCE FIX: Cache scenario API calls to reduce overhead
local scenarioCache = {
  lastUpdate = 0,
  cacheDuration = 0.5, -- Cache for 0.5 seconds
  steps = nil,
  criteriaInfo = nil
}

---Get cached scenario data to reduce API calls
---@return number|nil steps, table|nil criteriaInfo
local function getCachedScenarioData()
  local now = GetTime()
  if now - scenarioCache.lastUpdate < scenarioCache.cacheDuration then
    return scenarioCache.steps, scenarioCache.criteriaInfo
  end

  -- Update cache
  local _, _, steps = C_Scenario.GetStepInfo()
  local criteriaInfo = nil

  if steps and steps > 0 then
    criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(steps)
  end

  scenarioCache.steps = steps
  scenarioCache.criteriaInfo = criteriaInfo
  scenarioCache.lastUpdate = now

  return steps, criteriaInfo
end

---Get current trash progress from scenario API
---@return number|nil trashPercent Current trash percentage or nil if not available
local function getCurrentTrashProgress()
  local steps, criteriaInfo = getCachedScenarioData()

  if not steps or steps <= 0 then
    return nil
  end

  if not criteriaInfo or not criteriaInfo.quantity or not criteriaInfo.totalQuantity then
    return nil
  end

  -- Handle weighted progress like MythicPlusTimer does
  local percentage
  if criteriaInfo.isWeightedProgress and criteriaInfo.quantityString then
    -- For weighted progress, extract the numeric value from quantityString
    -- but then calculate percentage as: (extracted_value / totalQuantity) * 100
    local numericValue = tonumber(string.sub(criteriaInfo.quantityString, 1, string.len(criteriaInfo.quantityString) - 1))
    if numericValue and criteriaInfo.totalQuantity > 0 then
      percentage = (numericValue / criteriaInfo.totalQuantity) * 100
    else
      return nil
    end
  else
    -- For non-weighted progress, calculate percentage from quantity/totalQuantity
    -- SAFETY: Prevent division by zero
    if criteriaInfo.totalQuantity == 0 then
      return nil
    end
    percentage = (criteriaInfo.quantity / criteriaInfo.totalQuantity) * 100
  end

  -- FIX: Clamp percentage to prevent going above 100% due to API inconsistencies
  local originalPercentage = percentage
  percentage = math.max(0, math.min(100, percentage))

  -- DEBUG: Log when we have to clamp values
  if originalPercentage > 100 then
    PushMaster:DebugPrint(string.format(
      "WARNING: Trash percentage exceeded 100%% - API returned %.2f%%, clamped to %.2f%%", originalPercentage, percentage))
    PushMaster:DebugPrint(string.format(
      "Raw API data - quantity: %s, totalQuantity: %s, isWeighted: %s, quantityString: %s",
      tostring(criteriaInfo.quantity),
      tostring(criteriaInfo.totalQuantity),
      tostring(criteriaInfo.isWeightedProgress),
      tostring(criteriaInfo.quantityString)))
  end

  return percentage
end

---Timer-based progress checker (backup for when events stop firing)
local function checkProgressTimer()
  -- Only run if we're tracking a run
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  local currentTrash = getCurrentTrashProgress()
  if not currentTrash then
    return
  end

  -- Use same epsilon comparison as the event handler
  local epsilon = 0.01
  if math.abs(currentTrash - (lastTrashPercent or 0)) > epsilon then
    lastTrashPercent = currentTrash

    -- Update progress through API
    API:UpdateProgress(currentTrash, nil, nil)
  end
end

---Start the progress check timer
local function startProgressTimer()
  if progressCheckTimer then
    progressCheckTimer:Cancel()
  end

  progressCheckTimer = C_Timer.NewTicker(PROGRESS_CHECK_INTERVAL, checkProgressTimer)
  PushMaster:DebugPrint("Started progress check timer (backup system)")
end

---Stop the progress check timer
local function stopProgressTimer()
  if progressCheckTimer then
    progressCheckTimer:Cancel()
    progressCheckTimer = nil
    PushMaster:DebugPrint("Stopped progress check timer")
  end
end

---Event handler function
---@param self Frame
---@param event string
---@param ... any
local function onEvent(self, event, ...)
  if not eventListeners[event] then
    return
  end

  for callback, _ in pairs(eventListeners[event]) do
    local success, error = pcall(callback, ...)
    if not success then
      PushMaster:Print("Error in event handler for " .. event .. ": " .. tostring(error))
    end
  end
end

eventFrame:SetScript("OnEvent", onEvent)

---Register an event with a callback function
---@param event string The event name
---@param callback function The callback function
function EventHandlers:RegisterEvent(event, callback)
  if not eventListeners[event] then
    eventFrame:RegisterEvent(event)
    eventListeners[event] = {}
  end

  eventListeners[event][callback] = true
  PushMaster:DebugPrint("Registered event: " .. event)
end

---Unregister an event callback
---@param event string The event name
---@param callback function The callback function
function EventHandlers:UnregisterEvent(event, callback)
  if not eventListeners[event] then
    return
  end

  eventListeners[event][callback] = nil

  -- Check if any callbacks remain
  local hasCallbacks = false
  for _ in pairs(eventListeners[event]) do
    hasCallbacks = true
    break
  end

  -- Unregister the event if no callbacks remain
  if not hasCallbacks then
    eventListeners[event] = nil
    eventFrame:UnregisterEvent(event)
    PushMaster:DebugPrint("Unregistered event: " .. event)
  end
end

---Get current instance data for Mythic+ tracking
---Adapted from MythicPlusTimer's resolve_current_instance_data()
---@return table|nil instanceData The current instance data or nil if not in M+
local function getCurrentInstanceData()
  local _, _, _, _, _, _, _, currentZoneID = GetInstanceInfo()
  local currentMapID = C_ChallengeMode.GetActiveChallengeMapID()
  local keystoneLevel, keystoneAffixes = C_ChallengeMode.GetActiveKeystoneInfo()

  -- Debug console messages to help diagnose detection issues
  -- print("PushMaster Debug: Zone ID = " .. tostring(currentZoneID))
  -- print("PushMaster Debug: Map ID = " .. tostring(currentMapID))
  -- print("PushMaster Debug: CM Level = " .. tostring(keystoneLevel))

  if not currentMapID or not keystoneLevel or keystoneLevel == 0 then
    --  print("PushMaster Debug: No active challenge mode detected")
    return nil
  end

  local _, _, steps = C_Scenario.GetStepInfo()
  local zoneName, _, maxTime = C_ChallengeMode.GetMapUIInfo(currentMapID)

  -- More debug info
  -- print("PushMaster Debug: Zone Name = " .. tostring(zoneName))
  -- print("PushMaster Debug: Max Time = " .. tostring(maxTime))
  -- print("PushMaster Debug: Steps = " .. tostring(steps))

  local affixIDs = {}
  local isTeeming = false

  if keystoneAffixes then
    for _, affixID in pairs(keystoneAffixes) do
      table.insert(affixIDs, affixID)
      if affixID == 5 then -- Teeming affix
        isTeeming = true
      end
    end
  end

  local affixKey = "affixes"
  for _, id in ipairs(affixIDs) do
    affixKey = affixKey .. "-" .. id
  end

  -- print("PushMaster Debug: Successfully detected " .. tostring(zoneName) .. " +" .. tostring(cmLevel))

  return {
    cmLevel = keystoneLevel,
    levelKey = "l" .. keystoneLevel,
    affixes = affixIDs,
    affixKey = affixKey,
    zoneName = zoneName,
    currentZoneID = currentZoneID,
    currentMapID = currentMapID,
    maxTime = maxTime,
    steps = steps,
    isTeeming = isTeeming,
  }
end

---Handle Challenge Mode start event
---@param ... any Event arguments
local function onChallengeModeStart(...)
  PushMaster:DebugPrint("Challenge Mode started")

  local instanceData = getCurrentInstanceData()
  if not instanceData then
    PushMaster:DebugPrint("No instance data available")
    return
  end

  -- Only track keys +2 and above (users can configure this in settings)
  if instanceData.cmLevel < 2 then
    PushMaster:DebugPrint("Key level " .. instanceData.cmLevel .. " below threshold, not tracking")
    return
  end

  PushMaster:Print("Starting tracking for " .. instanceData.zoneName .. " +" .. instanceData.cmLevel)

  -- Start tracking through API
  local API = PushMaster.Core and PushMaster.Core.API
  if API then
    API:StartNewRun(instanceData.currentMapID, instanceData.cmLevel, instanceData.affixes)
  end

  -- Start the progress check timer (backup system)
  startProgressTimer()

  -- Show UI
  if PushMaster.UI and PushMaster.UI.MainFrame then
    PushMaster.UI.MainFrame:Show()
  end
end

---Handle Challenge Mode completion event
---@param ... any Event arguments
local function onChallengeModeCompleted(...)
  PushMaster:DebugPrint("Challenge Mode completed")

  -- Stop the progress check timer
  stopProgressTimer()

  -- Complete the run through API
  local API = PushMaster.Core and PushMaster.Core.API
  if API then
    -- Get completion info from WoW API
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    local level, time, onTime = C_ChallengeMode.GetCompletionInfo()

    if time then
      API:StopRun(true, onTime)
    else
      API:StopRun(false, false)
    end
  end

  -- Keep UI visible for a moment to show final results
  -- It will auto-hide when leaving the dungeon
end

---Handle Challenge Mode reset event
---@param ... any Event arguments
local function onChallengeModeReset(...)
  PushMaster:DebugPrint("Challenge Mode reset")

  -- Stop the progress check timer
  stopProgressTimer()

  -- Reset tracking through API
  local API = PushMaster.Core and PushMaster.Core.API
  if API then
    API:ResetCurrentRun()
  end

  -- Hide UI
  if PushMaster.UI and PushMaster.UI.MainFrame then
    PushMaster.UI.MainFrame:Hide()
  end
end

---Handle encounter start event (boss fights)
---@param encounterID number The encounter ID
---@param encounterName string The encounter name
---@param difficultyID number The difficulty ID
---@param groupSize number The group size
local function onEncounterStart(encounterID, encounterName, difficultyID, groupSize)
  -- Only process if we're tracking a run
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  PushMaster:DebugPrint("Boss encounter started: " ..
    (encounterName or "Unknown") .. " (ID: " .. (encounterID or "Unknown") .. ")")

  -- Let Calculator handle boss tracking through API
  local Calculator = PushMaster.Data and PushMaster.Data.Calculator
  if Calculator then
    Calculator:StartBossFight(encounterName or ("Boss " .. (encounterID or "Unknown")))
  end
end

---Handle encounter end event (boss kills)
---@param encounterID number The encounter ID
---@param encounterName string The encounter name
---@param difficultyID number The difficulty ID
---@param groupSize number The group size
---@param success boolean Whether the encounter was successful
local function onEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  -- Only process if we're tracking a run
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  if success then
    PushMaster:DebugPrint("Boss encounter completed successfully: " .. (encounterName or "Unknown"))

    -- Record the boss kill through Calculator
    local Calculator = PushMaster.Data and PushMaster.Data.Calculator
    if Calculator then
      Calculator:EndBossFight(encounterName or ("Boss " .. (encounterID or "Unknown")))

      -- Update boss count through API
      local currentState = Calculator:GetCurrentState()
      if currentState then
        API:UpdateProgress(nil, currentState.bosses, nil)
      end
    end
  else
    PushMaster:DebugPrint("Boss encounter failed: " .. (encounterName or "Unknown"))
  end
end

---Handle scenario criteria update (trash percentage changes)
---@param ... any Event arguments
local function onScenarioCriteriaUpdate(...)
  -- PERFORMANCE OPTIMIZATION: Throttle trash updates to prevent spam
  local now = GetTime()
  if now - lastUpdateTime < TRASH_UPDATE_THROTTLE then
    return
  end

  -- Only process if we're tracking a run
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  -- Use the cached helper function to get current progress (reduces API calls)
  local currentTrash = getCurrentTrashProgress()
  if not currentTrash then
    return
  end

  -- FIX: Use a small epsilon for floating-point comparison instead of exact equality
  local epsilon = 0.01 -- 0.01% threshold
  local shouldUpdate = math.abs(currentTrash - (lastTrashPercent or 0)) > epsilon

  if not shouldUpdate then
    return
  end

  lastTrashPercent = currentTrash
  lastUpdateTime = now

  -- Update progress through API
  API:UpdateProgress(currentTrash, nil, nil)
end

---Handle player entering world (for reconnections, reloads)
---@param ... any Event arguments
local function onPlayerEnteringWorld(...)
  PushMaster:DebugPrint("Player entering world")

  -- Check if we're in a Mythic+ dungeon
  local instanceData = getCurrentInstanceData()
  if instanceData then
    -- We're in M+, restart tracking
    PushMaster:DebugPrint("Resuming M+ tracking after world enter")
    onChallengeModeStart()
  else
    -- Not in M+, ensure UI is hidden and tracking is stopped
    local API = PushMaster.Core and PushMaster.Core.API
    if API then
      API:ResetCurrentRun()
    end
    if PushMaster.UI and PushMaster.UI.MainFrame then
      PushMaster.UI.MainFrame:Hide()
    end
  end
end

---Handle combat log events for death tracking
---CRITICAL PERFORMANCE FIX: Optimized to minimize CombatLogGetCurrentEventInfo calls
---@param ... any Combat log event arguments
local function onCombatLogEventUnfiltered(...)
  -- Early exit if not tracking
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  -- PERFORMANCE FIX: Get event info only once and cache it
  local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
  destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

  -- PERFORMANCE FIX: Early exit for non-death events using lookup table
  if not DEATH_EVENTS[subEvent] then
    return
  end

  -- Only process if it's a player death
  if destGUID and UnitIsPlayer(destName) then
    -- Check if it's a party/raid member
    local isPartyMember = false

    -- Check if it's the player
    if UnitGUID("player") == destGUID then
      isPartyMember = true
    else
      -- Check party members
      for i = 1, 4 do
        if UnitExists("party" .. i) and UnitGUID("party" .. i) == destGUID then
          isPartyMember = true
          break
        end
      end

      -- Check raid members if in raid
      if not isPartyMember and IsInRaid() then
        for i = 1, 40 do
          if UnitExists("raid" .. i) and UnitGUID("raid" .. i) == destGUID then
            isPartyMember = true
            break
          end
        end
      end
    end

    if isPartyMember then
      PushMaster:DebugPrint("Player death detected: " .. (destName or "Unknown"))
      local Calculator = PushMaster.Data and PushMaster.Data.Calculator
      if Calculator then
        Calculator:RecordDeath(destName)

        -- Update death count through API
        local currentState = Calculator:GetCurrentState()
        if currentState then
          API:UpdateProgress(nil, nil, currentState.deaths)
        end
      end
    end
  end
end

---Handle Blizzard's ScenarioObjectiveTracker UpdateTime
---@param self table The ScenarioObjectiveTracker.ChallengeModeBlock itself
---@param elapsedTime number The elapsed time from Blizzard's timer
local function onBlizzardTimerUpdate(self, elapsedTime)
  -- Check if PushMaster and its modules are loaded and active
  local API = PushMaster.Core and PushMaster.Core.API
  if not API or not API:IsTrackingRun() then
    return
  end

  -- Throttle timer updates to prevent spam
  local now = GetTime()
  if now - lastTimerUpdate < TIMER_UPDATE_THROTTLE then
    return
  end
  lastTimerUpdate = now

  -- Timer updates are handled internally by Calculator through elapsed time
  -- We don't need to explicitly update through API for timer ticks
end

---Handle zone change event
---@param ... any Event arguments
local function onZoneChanged(...)
  PushMaster:DebugPrint("Zone changed")

  -- Don't interfere with zone changes during active challenge modes
  -- The challenge mode events will handle starting/stopping tracking appropriately
  local isInChallengeMode = C_ChallengeMode.GetActiveChallengeMapID() ~= nil
  if isInChallengeMode then
    PushMaster:DebugPrint("Zone changed during active challenge mode - ignoring to avoid interference")
    return
  end

  local instanceData = getCurrentInstanceData()
  if not instanceData then
    PushMaster:DebugPrint("Not in an instance, hiding UI")

    -- Stop the progress check timer when leaving instance
    stopProgressTimer()

    -- Hide UI when not in an instance
    if PushMaster.UI and PushMaster.UI.MainFrame then
      PushMaster.UI.MainFrame:Hide()
    end
    return
  end

  PushMaster:DebugPrint("In instance: " .. instanceData.zoneName)

  -- Note: We don't need to update Calculator with zone info during active runs
  -- The challenge mode events handle that appropriately
end

---Initialize the event handling system
function EventHandlers:Initialize()
  PushMaster:DebugPrint("EventHandlers module initialized")

  -- Register core Mythic+ events
  self:RegisterEvent("CHALLENGE_MODE_START", onChallengeModeStart)
  self:RegisterEvent("CHALLENGE_MODE_COMPLETED", onChallengeModeCompleted)
  self:RegisterEvent("CHALLENGE_MODE_RESET", onChallengeModeReset)
  self:RegisterEvent("SCENARIO_CRITERIA_UPDATE", onScenarioCriteriaUpdate)
  self:RegisterEvent("PLAYER_ENTERING_WORLD", onPlayerEnteringWorld)
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLogEventUnfiltered)

  -- Register boss encounter events
  self:RegisterEvent("ENCOUNTER_START", onEncounterStart)
  self:RegisterEvent("ENCOUNTER_END", onEncounterEnd)

  -- Hook Blizzard's M+ timer update
  if ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock and ScenarioObjectiveTracker.ChallengeModeBlock.UpdateTime then
    hooksecurefunc(ScenarioObjectiveTracker.ChallengeModeBlock, "UpdateTime", onBlizzardTimerUpdate)
    PushMaster:DebugPrint("Hooked ScenarioObjectiveTracker.ChallengeModeBlock.UpdateTime")
  else
    PushMaster:Print("Error: Could not hook Blizzard M+ Timer. Timer accuracy may be affected.")
  end

  -- Register zone change event
  self:RegisterEvent("ZONE_CHANGED", onZoneChanged)
end

---Start tracking events
function EventHandlers:StartTracking()
  PushMaster:DebugPrint("Started event tracking")
  -- Events are automatically tracked once registered
  -- This function exists for compatibility with the main addon structure
end

---Stop tracking events
function EventHandlers:StopTracking()
  PushMaster:DebugPrint("Stopped event tracking")

  -- Unregister all events
  for event, callbacks in pairs(eventListeners) do
    eventFrame:UnregisterEvent(event)
  end

  eventListeners = {}
end

---Check if currently in a Mythic+ dungeon
---@return boolean inMythicPlus True if in an active Mythic+ dungeon
function EventHandlers:IsInMythicPlus()
  local instanceData = getCurrentInstanceData()
  return instanceData ~= nil
end

---Check if currently in a +12 or higher Mythic+ dungeon (PushMaster activation threshold)
---@return boolean inHighKey True if in a +12 or higher Mythic+ dungeon
function EventHandlers:IsInHighKey()
  local instanceData = getCurrentInstanceData()
  return instanceData ~= nil and instanceData.cmLevel >= 12
end

---Get current instance data
---@return table|nil instanceData Current instance data or nil
function EventHandlers:GetCurrentInstanceData()
  return getCurrentInstanceData()
end
