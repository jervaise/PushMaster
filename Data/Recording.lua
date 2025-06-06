---@class PushMasterRecording
---Clean event recording module for PushMaster addon
---Listens to WoW events and sends data to API
---Uses Performance module for throttling and optimization

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Recording module
local Recording = {}
if not PushMaster.Data then
  PushMaster.Data = {}
end
PushMaster.Data.Recording = Recording

-- Local references for performance
local GetTime = GetTime
local C_Scenario = C_Scenario
local C_ChallengeMode = C_ChallengeMode
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers

-- Throttling state
local lastTrashUpdate = 0
local lastBossUpdate = 0

-- Event frame for listening to WoW events
local eventFrame = CreateFrame("Frame")

-- Death events lookup table for fast filtering
local DEATH_EVENTS = {
  ["UNIT_DIED"] = true,
  ["UNIT_DYING"] = true
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

---Get API module safely
---@return table|nil api The API module or nil if not available
local function getAPI()
  return PushMaster.Data.API
end

---Get Performance module safely
---@return table|nil performance The Performance module or nil if not available
local function getPerformance()
  return PushMaster.Core.Performance
end

---Get current trash progress from WoW API
---@return number|nil trashPercent Current trash percentage (0-100) or nil if not available
local function getCurrentTrashProgress()
  -- Try multiple methods to get scenario progress for better compatibility

  -- Method 1: Try C_Scenario.GetInfo() (newer API)
  if C_Scenario and C_Scenario.GetInfo then
    local _, _, _, _, _, _, _, _, _, scenarioProgress = C_Scenario.GetInfo()
    if scenarioProgress then
      -- Handle API compatibility: scenarioProgress might be a number instead of table
      if type(scenarioProgress) == "number" then
        -- Return the value as percentage (assuming it's already 0-100)
        -- PushMaster:DebugPrint("Scenario progress (number): " .. scenarioProgress)
        return math.min(math.max(scenarioProgress, 0), 100)
      elseif type(scenarioProgress) == "table" then
        for i = 1, #scenarioProgress do
          if scenarioProgress[i] and scenarioProgress[i].criteriaType == 2 then -- LE_CRITERIA_TYPE_ENEMY_FORCES
            local totalRequired = scenarioProgress[i].totalQuantity
            local currentProgress = scenarioProgress[i].quantity

            if not totalRequired or totalRequired == 0 then
              return 0
            end

            local percentage = (currentProgress / totalRequired) * 100

            -- Clamp to 100% to avoid API inconsistencies
            return math.min(percentage, 100)
          end
        end
      end
    end
  end

  -- Method 2: Try C_Scenario.GetCriteriaInfo() if available
  if C_Scenario and C_Scenario.GetCriteriaInfo then
    local criteriaInfo = C_Scenario.GetCriteriaInfo(1) -- Usually enemy forces is criteria 1
    if criteriaInfo and criteriaInfo.totalQuantity and criteriaInfo.totalQuantity > 0 then
      local percentage = (criteriaInfo.quantity / criteriaInfo.totalQuantity) * 100
      return math.min(percentage, 100)
    end
  end

  -- Method 3: Fallback - return nil if no method works
  return nil
end

---Get current instance data for M+ runs
---@return table|nil instanceData Current M+ instance data or nil if not in M+
local function getCurrentInstanceData()
  -- Check if we're in challenge mode
  if not C_ChallengeMode.IsChallengeModeActive() then
    -- Debug: Not in challenge mode
    return nil
  end

  local mapID = C_ChallengeMode.GetActiveChallengeMapID()
  if not mapID then
    -- Debug: No active challenge map ID
    return nil
  end

  -- Try multiple methods to get keystone info (API can be unreliable during transitions)
  local level, affixes, wasEnergized = C_ChallengeMode.GetActiveKeystoneInfo()
  local keyLevel = level

  -- Fallback if keyLevel is invalid
  if not keyLevel or type(keyLevel) ~= "number" or keyLevel <= 0 then
    -- Try alternative method if available
    local dungeonDisplay = C_ChallengeMode.GetActiveChallengeMapID()
    if dungeonDisplay then
      -- Use a reasonable default for testing
      keyLevel = 2
    else
      return nil
    end
  end

  local zoneName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)

  -- Ensure we have valid zone name
  if not zoneName or zoneName == "" then
    zoneName = "Unknown Dungeon"
  end

  -- Ensure we have valid time limit
  if not timeLimit or timeLimit <= 0 then
    timeLimit = 1800000 -- 30 minutes default
  end

  return {
    mapID = mapID,
    keyLevel = keyLevel,
    zoneName = zoneName,
    timeLimit = timeLimit,
    affixes = affixes or {}
  }
end

---Check if player is in our group (for death tracking)
---@param playerName string The player name to check
---@return boolean isInGroup True if player is in our group
local function isPlayerInGroup(playerName)
  if not playerName then
    return false
  end

  -- Check if it's us
  if UnitName("player") == playerName then
    return true
  end

  -- Check party/raid members
  local numGroupMembers = GetNumGroupMembers()
  for i = 1, numGroupMembers do
    local unitID = "party" .. i
    if UnitName(unitID) == playerName then
      return true
    end
  end

  return false
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

---Attempt to start run tracking
---@param instanceData table The instance data
local function attemptStartRun(instanceData)
  -- Track all keys +2 and above (users can configure this)
  if instanceData.keyLevel < 2 then
    print("PushMaster Recording: Key level " .. instanceData.keyLevel .. " below threshold, not tracking")
    return
  end

  local api = getAPI()
  if not api then
    print("PushMaster Recording: API not available")
    return
  end

  -- Start run in API
  local success = api:StartRun(
    instanceData.mapID,
    instanceData.keyLevel,
    instanceData.affixes,
    {
      zoneName = instanceData.zoneName,
      timeLimit = instanceData.timeLimit
    }
  )

  if success then
    print("PushMaster: Started tracking " .. instanceData.zoneName .. " +" .. instanceData.keyLevel)
  else
    print("PushMaster Recording: Failed to start run in API")
  end
end

---Handle Challenge Mode start
local function onChallengeModeStart()
  -- Add delay to allow game state to stabilize
  C_Timer.After(0.5, function()
    local instanceData = getCurrentInstanceData()
    if not instanceData then
      -- Try again with longer delay
      C_Timer.After(1.5, function()
        local retryData = getCurrentInstanceData()
        if not retryData then
          -- Silently fail - we're likely not in a valid M+ context
          return
        end
        attemptStartRun(retryData)
      end)
      return
    end

    attemptStartRun(instanceData)
  end)
end

---Handle Challenge Mode completion
local function onChallengeModeCompleted()
  local api = getAPI()
  if not api then
    return
  end

  -- Get completion info
  local mapID = C_ChallengeMode.GetActiveChallengeMapID()
  local completionTime = C_ChallengeMode.GetCompletionInfo()

  if mapID and completionTime then
    print("PushMaster: Run completed successfully - MapID: " .. mapID .. ", Time: " .. completionTime)
    api:CompleteRun(true, completionTime)
  else
    print("PushMaster: Run completed but no completion data found")
    api:CompleteRun(false)
  end
end

---Handle Challenge Mode reset
local function onChallengeModeReset()
  local api = getAPI()
  if api then
    api:ResetCurrentRun()
    print("PushMaster: Run reset")
  end
end

---Handle encounter start (boss fight start)
---@param encounterID number The encounter ID
---@param encounterName string The encounter name
local function onEncounterStart(encounterID, encounterName)
  local api = getAPI()
  if not api then
    return
  end

  local currentRun = api:GetCurrentRun()
  if not currentRun.isActive then
    return
  end

  api:StartBossFight(encounterName or ("Boss " .. (encounterID or "Unknown")))
end

---Handle encounter end (boss fight end)
---@param encounterID number The encounter ID
---@param encounterName string The encounter name
---@param difficultyID number The difficulty ID
---@param groupSize number The group size
---@param success boolean Whether the encounter was successful
local function onEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  local api = getAPI()
  if not api then
    return
  end

  local currentRun = api:GetCurrentRun()
  if not currentRun.isActive then
    return
  end

  if success then
    api:EndBossFight(encounterName or ("Boss " .. (encounterID or "Unknown")))
  end
end

---Handle scenario criteria update (trash progress)
local function onScenarioCriteriaUpdate()
  local api = getAPI()
  if not api then
    return
  end

  local currentRun = api:GetCurrentRun()
  if not currentRun.isActive then
    return
  end

  -- Check throttling
  local performance = getPerformance()
  if performance and not performance:CanUpdateTrash(lastTrashUpdate) then
    return
  end

  local trashPercent = getCurrentTrashProgress()
  if not trashPercent then
    return
  end

  -- Update API with new trash progress
  local success = api:RecordProgress(trashPercent)
  if success then
    lastTrashUpdate = GetTime()

    -- Update active boss fight if in progress
    if currentRun.activeBoss then
      if not performance or performance:CanUpdateBoss(lastBossUpdate) then
        api:UpdateBossFight()
        lastBossUpdate = GetTime()
      end
    end
  end
end

---Handle player entering world (for reconnections/reloads)
local function onPlayerEnteringWorld()
  -- Small delay to ensure game state is ready
  C_Timer.After(2.0, function()
    local instanceData = getCurrentInstanceData()
    if instanceData then
      -- We're in M+, restart tracking (with additional delay for stability)
      C_Timer.After(1.0, function()
        attemptStartRun(instanceData)
      end)
    else
      -- Not in M+, ensure clean state
      local api = getAPI()
      if api then
        api:ResetCurrentRun()
      end
    end
  end)
end

---Handle combat log events (for death tracking)
local function onCombatLogEventUnfiltered()
  local api = getAPI()
  if not api then
    return
  end

  local currentRun = api:GetCurrentRun()
  if not currentRun.isActive then
    return
  end

  local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
  destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

  -- Only process death events
  if not DEATH_EVENTS[subEvent] then
    return
  end

  -- Only process player deaths
  if destGUID and UnitIsPlayer(destName) and isPlayerInGroup(destName) then
    api:RecordDeath(destName)
  end
end

--------------------------------------------------------------------------------
-- Event Registration
--------------------------------------------------------------------------------

---Register an event with handler
---@param event string The event name
---@param handler function The event handler function
local function registerEvent(event, handler)
  eventFrame:RegisterEvent(event)

  -- Store handler for this event
  if not eventFrame.handlers then
    eventFrame.handlers = {}
  end
  eventFrame.handlers[event] = handler
end

---Event dispatcher
eventFrame:SetScript("OnEvent", function(self, event, ...)
  if self.handlers and self.handlers[event] then
    self.handlers[event](...)
  end
end)

--------------------------------------------------------------------------------
-- Public Methods
--------------------------------------------------------------------------------

---Initialize the Recording module
function Recording:Initialize()
  print("PushMaster Recording: Module initialized")

  -- Register all events
  registerEvent("CHALLENGE_MODE_START", onChallengeModeStart)
  registerEvent("CHALLENGE_MODE_COMPLETED", onChallengeModeCompleted)
  registerEvent("CHALLENGE_MODE_RESET", onChallengeModeReset)
  registerEvent("ENCOUNTER_START", onEncounterStart)
  registerEvent("ENCOUNTER_END", onEncounterEnd)
  registerEvent("SCENARIO_CRITERIA_UPDATE", onScenarioCriteriaUpdate)
  registerEvent("PLAYER_ENTERING_WORLD", onPlayerEnteringWorld)
  registerEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLogEventUnfiltered)
end

---Stop event recording (alias for compatibility)
function Recording:StopRecording()
  if eventFrame then
    eventFrame:UnregisterAllEvents()
    eventFrame.handlers = {}
    print("PushMaster Recording: Stopped recording events")
  end
end

---Start event recording (alias for compatibility)
function Recording:StartRecording()
  self:Initialize()
  print("PushMaster Recording: Started recording events")
end

---Start tracking (alias for StopRecording)
function Recording:StartTracking()
  self:StartRecording()
end

---Stop tracking (alias for StopRecording)
function Recording:StopTracking()
  self:StopRecording()
end

---Check if currently in a Mythic+ dungeon
---@return boolean inMythicPlus True if in an active Mythic+ dungeon
function Recording:IsInMythicPlus()
  return getCurrentInstanceData() ~= nil
end

---Get current instance data (wrapper for compatibility)
---@return table|nil instanceData The current instance data or nil
function Recording:GetCurrentInstanceData()
  return getCurrentInstanceData()
end

---Check if currently in a high-level key (+12 or higher)
---@return boolean inHighKey True if in a +12 or higher Mythic+ dungeon
function Recording:IsInHighKey()
  local instanceData = getCurrentInstanceData()
  if not instanceData then
    return false
  end

  return instanceData.keyLevel and instanceData.keyLevel >= 12
end

---Get recording status
---@return boolean isRecording True if currently recording events
function Recording:IsRecording()
  return eventFrame and eventFrame:IsEventRegistered("CHALLENGE_MODE_START")
end

---Get current throttling status (for debugging)
---@return table throttleStatus Current throttling status
function Recording:GetThrottleStatus()
  local performance = getPerformance()
  local currentTime = GetTime()

  return {
    trashLastUpdate = lastTrashUpdate,
    bossLastUpdate = lastBossUpdate,
    trashCanUpdate = performance and performance:CanUpdateTrash(lastTrashUpdate) or true,
    bossCanUpdate = performance and performance:CanUpdateBoss(lastBossUpdate) or true,
    trashInterval = performance and performance:GetTrashUpdateInterval() or 0,
    bossInterval = performance and performance:GetBossUpdateInterval() or 0
  }
end

return Recording
