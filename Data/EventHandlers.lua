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
local TRASH_UPDATE_THROTTLE = 0.1 -- Only process trash updates every 100ms (was 500ms)

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

  -- Only track keys +12 and above
  if instanceData.cmLevel < 12 then
    PushMaster:DebugPrint("Key level " .. instanceData.cmLevel .. " below threshold, not tracking")
    return
  end

  PushMaster:Print("Starting tracking for " .. instanceData.zoneName .. " +" .. instanceData.cmLevel)

  -- Start tracking in Calculator
  if PushMaster.Data.Calculator then
    PushMaster.Data.Calculator:StartNewRun(instanceData)
  end

  -- Show UI
  if PushMaster.UI and PushMaster.UI.MainFrame then
    PushMaster.UI.MainFrame:Show()
  end
end

---Handle Challenge Mode completion event
---@param ... any Event arguments
local function onChallengeModeCompleted(...)
  PushMaster:DebugPrint("Challenge Mode completed")

  -- Complete the run in Calculator
  if PushMaster.Data.Calculator then
    PushMaster.Data.Calculator:CompleteCurrentRun()
  end

  -- Keep UI visible for a moment to show final results
  -- It will auto-hide when leaving the dungeon
end

---Handle Challenge Mode reset event
---@param ... any Event arguments
local function onChallengeModeReset(...)
  PushMaster:DebugPrint("Challenge Mode reset")

  -- Reset tracking in Calculator
  if PushMaster.Data.Calculator then
    PushMaster.Data.Calculator:ResetCurrentRun()
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
  if not PushMaster.Data.Calculator or not PushMaster.Data.Calculator:IsTrackingRun() then
    return
  end

  PushMaster:DebugPrint("Boss encounter started: " ..
    (encounterName or "Unknown") .. " (ID: " .. (encounterID or "Unknown") .. ")")

  -- Store encounter start time for potential use
  local startTime = GetTime()
  if not PushMaster.Data.Calculator.currentEncounter then
    PushMaster.Data.Calculator.currentEncounter = {}
  end

  PushMaster.Data.Calculator.currentEncounter = {
    id = encounterID,
    name = encounterName,
    startTime = startTime
  }
end

---Handle encounter end event (boss kills)
---@param encounterID number The encounter ID
---@param encounterName string The encounter name
---@param difficultyID number The difficulty ID
---@param groupSize number The group size
---@param success boolean Whether the encounter was successful
local function onEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  -- Only process if we're tracking a run
  if not PushMaster.Data.Calculator or not PushMaster.Data.Calculator:IsTrackingRun() then
    return
  end

  if success then
    PushMaster:DebugPrint("Boss encounter completed successfully: " .. (encounterName or "Unknown"))

    -- Record the boss kill
    if PushMaster.Data.Calculator then
      PushMaster.Data.Calculator:RecordBossKill(encounterName or ("Boss " .. (encounterID or "Unknown")))
    end
  else
    PushMaster:DebugPrint("Boss encounter failed: " .. (encounterName or "Unknown"))
  end

  -- Clear current encounter data
  if PushMaster.Data.Calculator.currentEncounter then
    PushMaster.Data.Calculator.currentEncounter = nil
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
  if not PushMaster.Data.Calculator or not PushMaster.Data.Calculator:IsTrackingRun() then
    return
  end

  local _, _, steps = C_Scenario.GetStepInfo()
  if not steps or steps <= 0 then
    return
  end

  local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(steps)
  if not criteriaInfo or not criteriaInfo.quantity or not criteriaInfo.totalQuantity then
    return
  end

  local currentTrash = (criteriaInfo.quantity / criteriaInfo.totalQuantity) * 100

  -- Check if we've crossed a milestone boundary (every 5% for more granular tracking)
  local oldMilestone = math.floor(lastTrashPercent / 5) * 5
  local newMilestone = math.floor(currentTrash / 5) * 5

  -- Always update if we've crossed a milestone boundary, or if it's been a significant change
  local shouldUpdate = (newMilestone > oldMilestone) or (math.abs(currentTrash - lastTrashPercent) >= 1.0)

  if not shouldUpdate then
    return
  end

  lastTrashPercent = currentTrash
  lastUpdateTime = now

  -- Update progress in Calculator (Calculator will handle milestone recording)
  PushMaster.Data.Calculator:UpdateProgress({
    trash = currentTrash
  })

  PushMaster:DebugPrint(string.format("Trash progress updated: %.1f%%", currentTrash))
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
    if PushMaster.Data.Calculator then
      PushMaster.Data.Calculator:ResetCurrentRun()
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
  if not PushMaster.Data.Calculator or not PushMaster.Data.Calculator:IsTrackingRun() then
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
      if PushMaster.Data.Calculator then
        PushMaster.Data.Calculator:RecordDeath(timestamp, destGUID)
      end
    end
  end
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
