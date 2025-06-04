---@class PushMasterCalculator
---Core calculation module for PushMaster addon
---Handles run tracking, progress calculation, and comparison logic
---Adapted from MythicPlusTimer addon tracking system

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Calculator module
local Calculator = {}
if not PushMaster.Data then
  PushMaster.Data = {}
end
PushMaster.Data.Calculator = Calculator

-- Local references for performance
local GetTime = GetTime
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- Current run state
local currentRun = {
  isActive = false,
  instanceData = nil,
  startTime = nil,
  completionTime = nil,
  progress = {
    trash = 0,
    bosses = 0,
    deaths = 0,
    elapsedTime = 0,
    timeLostToDeaths = 0
  },
  deathTimes = {},
  playerLastDeathTimestamp = {}, -- NEW: Track last death timestamp per player GUID
  bossKillTimes = {},            -- NEW: Record exact boss kill times
  trashSamples = {},             -- NEW: Record trash progression samples
  progressHistory = {},
  loggedDeaths = {},
  loggedDeathsByGUID = {}
}

-- PERFORMANCE OPTIMIZATION: Cache calculation results to avoid repeated expensive operations
local calculationCache = {
  dungeonWeights = { data = nil, bestTimeHash = nil },
  trashDelta = { data = nil, lastTrash = nil, lastTime = nil },
  bossDelta = { data = nil, lastBossCount = nil, lastTime = nil },
  deathDelta = { data = nil, lastDeathCount = nil, lastTime = nil },
  lastDebugTime = 0,
  debugThrottle = 5.0 -- PERFORMANCE FIX: Increased to 5 seconds to reduce spam
}

-- SAVED VARIABLES OPTIMIZATION: Limits to prevent bloating
local SAVED_VARS_LIMITS = {
  maxBestTimesPerDungeon = 3, -- Only keep best 3 times per dungeon/level
  maxTrashSamples = 20,       -- Compress to 20 key samples instead of hundreds
  maxBossKillTimes = 10,      -- Limit boss data
  maxOldDataDays = 90,        -- Remove data older than 90 days
  compressionEnabled = true,  -- Enable data compression
  cleanupOnStartup = true     -- Clean up on addon load
}

-- Best times storage (will be loaded from saved variables)
local bestTimes = {}

-- Add throttling variables at the top of the file
local lastProgressDebugTime = 0
local PROGRESS_DEBUG_THROTTLE = 5.0 -- PERFORMANCE FIX: Increased to 5 seconds to reduce spam

---Compress trash samples to reduce saved variable size
---@param trashSamples table Full trash samples array
---@return table compressedSamples Compressed samples (key milestones only)
local function compressTrashSamples(trashSamples)
  if not trashSamples or #trashSamples == 0 then
    return {}
  end

  local compressed = {}
  local targetSamples = SAVED_VARS_LIMITS.maxTrashSamples
  local totalSamples = #trashSamples

  if totalSamples <= targetSamples then
    return trashSamples -- No compression needed
  end

  -- Always include first and last samples
  table.insert(compressed, trashSamples[1])

  -- Calculate step size for even distribution
  local step = math.max(1, math.floor(totalSamples / (targetSamples - 2)))

  -- Add evenly distributed samples
  for i = step, totalSamples - step, step do
    if #compressed < targetSamples - 1 then
      table.insert(compressed, trashSamples[i])
    end
  end

  -- Always include final sample
  if #compressed < targetSamples then
    table.insert(compressed, trashSamples[totalSamples])
  end

  PushMaster:DebugPrint(string.format("Compressed trash samples: %d -> %d (%.1f%% reduction)",
    totalSamples, #compressed, (1 - #compressed / totalSamples) * 100))

  return compressed
end

---Compress boss kill times to essential data only
---@param bossKillTimes table Full boss kill times array
---@return table compressedBoss Compressed boss data
local function compressBossKillTimes(bossKillTimes)
  if not bossKillTimes or #bossKillTimes == 0 then
    return {}
  end

  local compressed = {}
  local maxBosses = math.min(#bossKillTimes, SAVED_VARS_LIMITS.maxBossKillTimes)

  for i = 1, maxBosses do
    local boss = bossKillTimes[i]
    if boss then
      -- Store only essential data
      table.insert(compressed, {
        name = boss.name or ("Boss " .. i),
        killTime = boss.killTime,
        bossNumber = i
      })
    end
  end

  return compressed
end

---Clean up old best times data to prevent indefinite growth
---@param bestTimesData table The best times data to clean
---@return table cleanedData Cleaned best times data
local function cleanupOldBestTimes(bestTimesData)
  if not bestTimesData or not SAVED_VARS_LIMITS.cleanupOnStartup then
    return bestTimesData
  end

  local cleaned = {}
  local currentTime = time()
  local maxAge = SAVED_VARS_LIMITS.maxOldDataDays * 24 * 60 * 60 -- Convert days to seconds
  local removedCount = 0
  local totalCount = 0

  for mapID, levels in pairs(bestTimesData) do
    for level, data in pairs(levels) do
      totalCount = totalCount + 1

      -- Parse date string to timestamp for age comparison
      local dataTime = 0
      if data.date then
        local year, month, day, hour, min, sec = data.date:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if year then
          dataTime = time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
          })
        end
      end

      -- Keep data if it's recent enough or if we can't parse the date
      local age = currentTime - dataTime
      if dataTime == 0 or age <= maxAge then
        if not cleaned[mapID] then
          cleaned[mapID] = {}
        end
        cleaned[mapID][level] = data
      else
        removedCount = removedCount + 1
      end
    end
  end

  if removedCount > 0 then
    PushMaster:Print(string.format("Cleaned up %d old best times (older than %d days)",
      removedCount, SAVED_VARS_LIMITS.maxOldDataDays))
  end

  PushMaster:DebugPrint(string.format("Best times cleanup: %d/%d entries kept",
    totalCount - removedCount, totalCount))

  return cleaned
end

---Limit the number of best times per dungeon/level to prevent bloating
---@param bestTimesData table The best times data
---@return table limitedData Limited best times data
local function limitBestTimesPerDungeon(bestTimesData)
  if not bestTimesData then
    return {}
  end

  local limited = {}
  local removedCount = 0
  local totalCount = 0

  for mapID, levels in pairs(bestTimesData) do
    limited[mapID] = {}

    for level, data in pairs(levels) do
      totalCount = totalCount + 1

      -- For now, keep only the single best time per level
      -- Future enhancement: Could keep top N times
      limited[mapID][level] = data
    end
  end

  PushMaster:DebugPrint(string.format("Best times limiting: %d entries processed", totalCount))
  return limited
end

---Optimize saved variables data before saving
---@param runData table The run data to optimize
---@return table optimizedData Optimized run data for saving
local function optimizeRunDataForSaving(runData)
  if not runData then
    return nil
  end

  local optimized = {
    time = runData.progress.elapsedTime,
    date = date("%Y-%m-%d %H:%M:%S"),
    deaths = runData.progress.deaths,
    affixes = runData.instanceData.affixes,
    deathTimes = runData.deathTimes or {} -- Include death times for delta comparison
  }

  -- Compress heavy data arrays
  if SAVED_VARS_LIMITS.compressionEnabled then
    optimized.bossKillTimes = compressBossKillTimes(runData.bossKillTimes or {})
    optimized.trashSamples = compressTrashSamples(runData.trashSamples or {})
  else
    optimized.bossKillTimes = runData.bossKillTimes or {}
    optimized.trashSamples = runData.trashSamples or {}
  end

  return optimized
end

---Initialize the Calculator module
function Calculator:Initialize()
  PushMaster:DebugPrint("Calculator module initialized")

  -- Load best times from saved variables
  if PushMasterDB and PushMasterDB.bestTimes then
    -- SAVED VARIABLES OPTIMIZATION: Clean up data on startup
    local originalSize = self:_calculateDataSize(PushMasterDB.bestTimes)

    -- Apply cleanup and optimization
    local cleanedData = cleanupOldBestTimes(PushMasterDB.bestTimes)
    cleanedData = limitBestTimesPerDungeon(cleanedData)

    bestTimes = cleanedData
    PushMasterDB.bestTimes = cleanedData

    local newSize = self:_calculateDataSize(cleanedData)
    local reduction = originalSize > 0 and ((originalSize - newSize) / originalSize * 100) or 0

    if reduction > 5 then -- Only report significant reductions
      PushMaster:Print(string.format("Optimized saved variables: %.1f%% size reduction", reduction))
    end

    PushMaster:DebugPrint(string.format("Best times loaded and optimized: %d bytes -> %d bytes (%.1f%% reduction)",
      originalSize, newSize, reduction))
  else
    bestTimes = {}
  end
end

---Start tracking a new Mythic+ run
---@param instanceData table The instance data from EventHandlers
function Calculator:StartNewRun(instanceData)
  if not instanceData then
    PushMaster:DebugPrint("Cannot start run: no instance data")
    return
  end

  -- PERFORMANCE OPTIMIZATION: Clear calculation caches when starting new run
  calculationCache.dungeonWeights = { data = nil, bestTimeHash = nil }
  calculationCache.trashDelta = { data = nil, lastTrash = nil, lastTime = nil }
  calculationCache.bossDelta = { data = nil, lastBossCount = nil, lastTime = nil }
  calculationCache.deathDelta = { data = nil, lastDeathCount = nil, lastTime = nil }
  calculationCache.lastDebugTime = 0

  -- Reset current run state
  currentRun = {
    isActive = true,
    instanceData = instanceData,
    startTime = GetTime(), -- Retain for historical/reference if needed, but not for primary elapsedTime calc
    completionTime = nil,
    progress = {
      trash = 0,
      bosses = 0,
      deaths = 0,
      elapsedTime = 0,
      timeLostToDeaths = 0
    },
    deathTimes = {},
    playerLastDeathTimestamp = {}, -- Reset this too
    bossKillTimes = {},            -- NEW: Record exact boss kill times
    trashSamples = {},             -- NEW: Record trash progression samples
    progressHistory = {},
    loggedDeaths = {},
    loggedDeathsByGUID = {}
  }

  PushMaster:DebugPrint("Started new run: " .. instanceData.zoneName .. " +" .. instanceData.cmLevel)
end

---Check if currently tracking a run
---@return boolean isTracking True if actively tracking a run
function Calculator:IsTrackingRun()
  return currentRun.isActive
end

---Update progress for the current run
---@param progressData table Progress data containing trash, elapsedTime, etc.
function Calculator:UpdateProgress(progressData)
  if not currentRun.isActive then
    return
  end

  -- SAFETY: Validate progressData parameter
  if not progressData or type(progressData) ~= "table" then
    PushMaster:DebugPrint("Warning: Invalid progressData passed to UpdateProgress")
    return
  end

  local authoritativeElapsedTime
  if progressData.elapsedTime ~= nil then -- Check for nil explicitly
    -- SAFETY: Validate elapsedTime is a positive number
    if type(progressData.elapsedTime) == "number" and progressData.elapsedTime >= 0 then
      authoritativeElapsedTime = progressData.elapsedTime
    else
      PushMaster:DebugPrint("Warning: Invalid elapsedTime value in progressData")
      return
    end
  elseif currentRun.startTime then -- Fallback ONLY if hook somehow fails AND startTime exists
    authoritativeElapsedTime = GetTime() - currentRun.startTime
    PushMaster:DebugPrint("Warning: Using GetTime() fallback for elapsedTime in Calculator:UpdateProgress.")
  else
    PushMaster:Print("Error: elapsedTime not available in Calculator:UpdateProgress.")
    return -- Cannot proceed without a valid time
  end

  -- Update current progress with safety checks
  if progressData.trash and type(progressData.trash) == "number" then
    -- SAFETY: Clamp trash percentage to valid range
    currentRun.progress.trash = math.max(0, math.min(100, progressData.trash))

    -- Sample trash progress for ghost-car interpolation only when trash data is provided
    currentRun.trashSamples = currentRun.trashSamples or {}
    table.insert(currentRun.trashSamples, { time = authoritativeElapsedTime, trash = currentRun.progress.trash })
  end

  currentRun.progress.elapsedTime = authoritativeElapsedTime -- Store the authoritative time

  -- NEW: Update death count from API
  if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
    local apiDeathCount, apiTimeLost = C_ChallengeMode.GetDeathCount()
    if apiDeathCount and apiDeathCount ~= currentRun.progress.deaths then
      -- Death count increased - record the death time for best run comparison
      if apiDeathCount > currentRun.progress.deaths then
        -- Calculate how many new deaths occurred
        local newDeaths = apiDeathCount - currentRun.progress.deaths
        -- Record the current elapsed time for each new death
        for i = 1, newDeaths do
          table.insert(currentRun.deathTimes, authoritativeElapsedTime)
        end
        PushMaster:DebugPrint(string.format("API Death Count Updated: %d (was %d). Added %d death time(s) at %.1fs",
          apiDeathCount, currentRun.progress.deaths, newDeaths, authoritativeElapsedTime))
      end

      currentRun.progress.deaths = apiDeathCount
    end

    -- Store the actual time penalty from API
    if apiTimeLost then
      currentRun.progress.timeLostToDeaths = apiTimeLost
    end
  end

  -- Store progress history for analysis
  table.insert(currentRun.progressHistory, {
    time = authoritativeElapsedTime, -- Use authoritativeElapsedTime
    trash = currentRun.progress.trash,
    bosses = currentRun.progress.bosses,
    deaths = currentRun.progress.deaths
  })

  -- Throttle debug messages to reduce spam
  local now = GetTime()
  if now - lastProgressDebugTime >= PROGRESS_DEBUG_THROTTLE then
    PushMaster:DebugPrint(string.format("Progress updated: %.1f%% trash, %.1fs elapsed",
      currentRun.progress.trash, authoritativeElapsedTime))
    lastProgressDebugTime = now
  end
end

---Record a death during the current run
---@param deathTime number The time when the death occurred (this should be a raw timestamp from combat log)
---@param playerGUID string The GUID of the player who died
function Calculator:RecordDeath(deathTime, playerGUID)
  if not currentRun.isActive then
    return
  end

  -- Debounce for logging purposes, to prevent spamming the deathTimes list for the same event if it fires multiple times rapidly.
  if playerGUID and currentRun.playerLastDeathTimestamp[playerGUID] and (deathTime - currentRun.playerLastDeathTimestamp[playerGUID] < 0.5) then -- Reduced debounce to 0.5s for logging
    PushMaster:DebugPrint("Debounced duplicate death event for logging for " .. playerGUID)
    return
  end

  if not currentRun.startTime then
    PushMaster:Print("Error: currentRun.startTime not set, cannot accurately record death time for log.")
    return
  end
  local elapsedTimeAtDeath = deathTime - currentRun.startTime

  -- Log the death event for detailed summary/tooltip (similar to MPT)
  if not currentRun.loggedDeaths then currentRun.loggedDeaths = {} end
  if not currentRun.loggedDeathsByGUID then currentRun.loggedDeathsByGUID = {} end

  table.insert(currentRun.loggedDeaths, { guid = playerGUID, time = elapsedTimeAtDeath, timestamp = deathTime })
  if playerGUID then
    currentRun.loggedDeathsByGUID[playerGUID] = (currentRun.loggedDeathsByGUID[playerGUID] or 0) + 1
    currentRun.playerLastDeathTimestamp[playerGUID] =
        deathTime -- Update last death timestamp for this player for logging debounce
  end

  -- The primary currentRun.progress.deaths is now updated from C_ChallengeMode.GetDeathCount() in UpdateProgress.
  -- Death times for best run comparison are also recorded there when API death count increases.
  -- This function is now primarily for detailed logging of individual death events.

  PushMaster:DebugPrint("Logged death for " ..
    (playerGUID or "Unknown") ..
    " at run time " .. string.format("%.1f", elapsedTimeAtDeath) .. "s. API deaths: " .. currentRun.progress.deaths)
end

---Record a boss kill during the current run
---@param bossName string The name of the boss killed
---@param killTime number The time when the boss was killed (optional, combat log timestamp)
function Calculator:RecordBossKill(bossName, killTime)
  if not currentRun.isActive then
    return
  end

  -- SAFETY: Validate bossName parameter
  if not bossName or type(bossName) ~= "string" or bossName == "" then
    PushMaster:DebugPrint("Warning: Invalid bossName passed to RecordBossKill")
    return
  end

  local actualKillTime = killTime or GetTime() -- killTime is a timestamp from combat log or GetTime() if not provided

  -- SAFETY: Validate killTime is a valid number
  if type(actualKillTime) ~= "number" or actualKillTime < 0 then
    PushMaster:DebugPrint("Warning: Invalid killTime passed to RecordBossKill")
    return
  end

  if not currentRun.startTime then
    PushMaster:Print("Error: currentRun.startTime not set, cannot accurately record boss kill time.")
    return
  end
  local elapsedTimeAtKill = actualKillTime - currentRun.startTime

  -- SAFETY: Ensure elapsed time is reasonable (not negative, not excessively large)
  if elapsedTimeAtKill < 0 then
    PushMaster:DebugPrint("Warning: Negative elapsed time for boss kill, adjusting to 0")
    elapsedTimeAtKill = 0
  elseif elapsedTimeAtKill > 7200 then -- 2 hours seems like a reasonable maximum
    PushMaster:DebugPrint("Warning: Excessively large elapsed time for boss kill")
  end

  table.insert(currentRun.bossKillTimes, {
    name = bossName,
    killTime = elapsedTimeAtKill, -- Store elapsed time relative to run start
    bossNumber = #currentRun.bossKillTimes + 1
  })

  currentRun.progress.bosses = #currentRun.bossKillTimes

  PushMaster:Print("Boss kill recorded: " .. bossName .. " at " .. string.format("%.1f", elapsedTimeAtKill) .. "s")
end

---Complete the current run
function Calculator:CompleteCurrentRun()
  if not currentRun.isActive then
    return
  end

  -- currentRun.completionTime = GetTime() -- This was original
  -- The run is completed, the final elapsed time is already in currentRun.progress.elapsedTime from the hook
  -- If we need an absolute timestamp for completion, GetTime() is fine here.
  currentRun.completionTimeAbsolute = GetTime()     -- Store absolute completion for reference

  local totalTime = currentRun.progress.elapsedTime -- This is the most accurate total time

  -- Ensure final trash percentage is 100% at completion
  currentRun.progress.trash = 100

  -- Add final trash sample at 100% completion
  currentRun.trashSamples = currentRun.trashSamples or {}
  table.insert(currentRun.trashSamples, { time = totalTime, trash = 100 })

  currentRun.isActive = false

  PushMaster:DebugPrint("Run completed in " .. string.format("%.1f", totalTime) .. "s with final trash at 100%")

  -- Store as best time if applicable
  self:UpdateBestTime(currentRun, totalTime) -- Pass totalTime explicitly
end

---Reset the current run
function Calculator:ResetCurrentRun()
  -- PERFORMANCE OPTIMIZATION: Clear calculation caches when resetting run
  calculationCache.dungeonWeights = { data = nil, bestTimeHash = nil }
  calculationCache.trashDelta = { data = nil, lastTrash = nil, lastTime = nil }
  calculationCache.bossDelta = { data = nil, lastBossCount = nil, lastTime = nil }
  calculationCache.deathDelta = { data = nil, lastDeathCount = nil, lastTime = nil }
  calculationCache.lastDebugTime = 0

  currentRun = {
    isActive = false,
    instanceData = nil,
    startTime = nil,
    completionTime = nil,
    progress = {
      trash = 0,
      bosses = 0,
      deaths = 0,
      elapsedTime = 0,
      timeLostToDeaths = 0
    },
    deathTimes = {},
    playerLastDeathTimestamp = {}, -- Reset this too
    bossKillTimes = {},            -- NEW: Record exact boss kill times
    trashSamples = {},             -- NEW: Record trash progression samples
    progressHistory = {},
    loggedDeaths = {},
    loggedDeathsByGUID = {}
  }

  PushMaster:DebugPrint("Current run reset")
end

---Get the current run data
---@return table currentRunData The current run data
function Calculator:GetCurrentRun()
  return currentRun
end

---Update best time for a dungeon/key level combination
---@param runData table The completed run data
function Calculator:UpdateBestTime(runData, totalTime)                 -- Added totalTime parameter
  if not runData.instanceData or not runData.progress.elapsedTime then -- Check progress.elapsedTime
    return
  end

  local instanceData = runData.instanceData
  -- local totalTime = runData.completionTime - runData.startTime -- Original logic
  -- totalTime is now passed as a parameter, which is runData.progress.elapsedTime

  -- Create key for this dungeon/level combination
  local dungeonKey = instanceData.currentMapID .. "_" .. instanceData.cmLevel

  -- Initialize best times for this dungeon if needed
  if not bestTimes[instanceData.currentMapID] then
    bestTimes[instanceData.currentMapID] = {}
  end

  -- SAVED VARIABLES OPTIMIZATION: Use optimized data structure
  local optimizedRunData = optimizeRunDataForSaving(runData)
  optimizedRunData.time = totalTime -- Ensure we use the passed totalTime

  if not bestTimes[instanceData.currentMapID][instanceData.cmLevel] then
    bestTimes[instanceData.currentMapID][instanceData.cmLevel] = optimizedRunData
    PushMaster:DebugPrint("New best time recorded: " .. string.format("%.1f", totalTime) .. "s")
  elseif totalTime < bestTimes[instanceData.currentMapID][instanceData.cmLevel].time then
    bestTimes[instanceData.currentMapID][instanceData.cmLevel] = optimizedRunData
    PushMaster:DebugPrint("Best time improved: " .. string.format("%.1f", totalTime) .. "s")
  end

  -- Save to persistent storage with optimization
  if not PushMasterDB then
    PushMasterDB = {}
  end
  PushMasterDB.bestTimes = bestTimes

  -- SAVED VARIABLES OPTIMIZATION: Report compression stats
  local originalSamples = #(runData.trashSamples or {})
  local compressedSamples = #(optimizedRunData.trashSamples or {})
  if originalSamples > compressedSamples then
    PushMaster:DebugPrint(string.format("Saved variables optimized: %d trash samples -> %d (%.1f%% reduction)",
      originalSamples, compressedSamples, (1 - compressedSamples / originalSamples) * 100))
  end
end

---Get best time for current dungeon/level
---@return table|nil bestTime The best time data or nil if none exists
function Calculator:GetBestTime()
  if not currentRun.instanceData then
    return nil
  end

  local instanceData = currentRun.instanceData

  if bestTimes[instanceData.currentMapID] and
      bestTimes[instanceData.currentMapID][instanceData.cmLevel] then
    return bestTimes[instanceData.currentMapID][instanceData.cmLevel]
  end

  return nil
end

---Calculate chest timers based on dungeon max time
---Adapted from MythicPlusTimer's chest calculation logic
---@param maxTime number Maximum time for the dungeon in seconds
---@return table chestTimers Table with +2 and +3 chest times
local function calculateChestTimers(maxTime)
  return {
    plus2 = maxTime * 0.8, -- 80% for +2
    plus3 = maxTime * 0.6  -- 60% for +3
  }
end

---Get current comparison data for UI display
---@return table|nil comparison Comparison data or nil if not tracking
function Calculator:GetCurrentComparison()
  if not currentRun.isActive or not currentRun.instanceData then
    return nil
  end

  local instanceData = currentRun.instanceData

  -- Use stored elapsed time if available (for test mode), otherwise calculate from real time
  local elapsedTime
  if currentRun.progress.elapsedTime then
    elapsedTime = currentRun.progress.elapsedTime  -- Use simulated time from test mode
  else
    elapsedTime = GetTime() - currentRun.startTime -- Use real time for actual runs
  end

  local bestTime = self:GetBestTime()

  -- Only show intelligent analysis for keys +12 and above
  if instanceData.cmLevel < 12 then
    return nil
  end

  -- Calculate chest timers (updated for TWW Season 2)
  local chestTimers = calculateChestTimers(instanceData.maxTime)

  -- Determine current pace
  local currentPace = "unknown"
  local timeRemaining = instanceData.maxTime - elapsedTime

  if elapsedTime <= chestTimers.plus3 then
    currentPace = "+3"
  elseif elapsedTime <= chestTimers.plus2 then
    currentPace = "+2"
  elseif elapsedTime <= instanceData.maxTime then
    currentPace = "+1"
  else
    currentPace = "overtime"
  end

  -- Initialize comparison metrics
  local progressEfficiency = 0
  local trashProgress = 0
  local bossProgress = 0
  local deathProgress = 0
  local deathTimePenalty = currentRun.progress.timeLostToDeaths or 0

  if bestTime then
    -- INTELLIGENT PACE CALCULATION - Learn from actual run patterns
    local paceData = self:CalculateIntelligentPace(currentRun, bestTime, elapsedTime)

    progressEfficiency = paceData.efficiency
    trashProgress = paceData.trashDelta
    bossProgress = paceData.bossDelta
    deathProgress = paceData.deathDelta

    PushMaster:DebugPrint(string.format("Intelligent pace: Efficiency %.1f%%, Trash %.1f%%, Boss %d, Deaths %+d",
      progressEfficiency, trashProgress, bossProgress, deathProgress))
  else
    -- No comparison data available yet, provide default values
    PushMaster:DebugPrint("No best time data available for intelligent comparison, using N/A values")
    progressEfficiency = nil -- Or some other indicator for "N/A"
    trashProgress = nil      -- Or some other indicator for "N/A"
    bossProgress = nil       -- Or some other indicator for "N/A"
    deathProgress = nil      -- Or some other indicator for "N/A"
    -- We don't return nil here anymore, so the rest of the function will execute
  end

  -- Calculate time delta and confidence
  local timeDelta, timeConfidence = self:CalculateTimeDelta(currentRun, bestTime, elapsedTime, progressEfficiency)

  -- Prepare values for the return table, applying math.floor only if not nil
  local finalProgressEfficiency = progressEfficiency
  if finalProgressEfficiency ~= nil then
    finalProgressEfficiency = math.floor(finalProgressEfficiency + 0.5)
  end

  local finalTrashProgress = trashProgress
  if finalTrashProgress ~= nil then
    finalTrashProgress = math.floor(finalTrashProgress + 0.5)
  end

  local finalBossProgress = bossProgress
  if finalBossProgress ~= nil then
    finalBossProgress = math.floor(finalBossProgress + 0.5)
  end

  local finalDeathProgress = deathProgress
  if finalDeathProgress ~= nil then
    finalDeathProgress = math.floor(finalDeathProgress + 0.5)
  end

  -- overallSpeed is based on the original progressEfficiency before flooring for this specific calculation
  local finalOverallSpeed = progressEfficiency
  if finalOverallSpeed ~= nil then
    finalOverallSpeed = math.floor(finalOverallSpeed + 0.5)
  end

  return {
    dungeon = instanceData.zoneName or "Unknown",
    level = instanceData.cmLevel or 0,
    elapsedTime = elapsedTime,
    maxTime = instanceData.maxTime,
    timeRemaining = timeRemaining,
    currentPace = currentPace,
    progress = {
      trash = currentRun.progress.trash,
      bosses = currentRun.progress.bosses,
      deaths = currentRun.progress.deaths
    },
    chestTimers = chestTimers,
    bestComparison = nil,
    affixes = instanceData.affixes,
    -- Simplified display metrics
    progressEfficiency = finalProgressEfficiency,
    trashProgress = finalTrashProgress,
    bossProgress = finalBossProgress,
    deathProgress = finalDeathProgress,
    deathTimePenalty = deathTimePenalty,
    -- Keep for backward compatibility
    overallSpeed = finalOverallSpeed,
    timeDelta = timeDelta,
    timeConfidence = timeConfidence
  }
end

---Calculate intelligent pace based on learned patterns from previous runs
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table paceData Calculated pace metrics
function Calculator:CalculateIntelligentPace(currentRun, bestTime, elapsedTime)
  local currentTrash = currentRun.progress.trash
  local currentBosses = currentRun.progress.bosses

  -- BEST RUN LOGIC: What trash % did the best run have at this exact time?
  local trashDelta = self:CalculateTrashDelta(currentRun, bestTime, elapsedTime)

  -- PRECISE BOSS TIMING
  -- Compare actual boss kill timing vs best run
  local bossDelta = self:CalculateBossDelta(currentRun, bestTime, elapsedTime)

  -- PRECISE DEATH COMPARISON
  -- Compare death count at this time vs best run
  local deathDelta = self:CalculateDeathDelta(currentRun, bestTime, elapsedTime)

  -- OVERALL EFFICIENCY CALCULATION
  -- Combine trash and boss performance with learned weights
  local efficiency = self:CalculateOverallEfficiency(trashDelta, bossDelta, currentRun, bestTime, elapsedTime)

  return {
    efficiency = efficiency,
    trashDelta = trashDelta,
    bossDelta = bossDelta,
    deathDelta = deathDelta
  }
end

---Calculate trash progress delta using milestone-based comparison
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number trashDelta Percentage difference in trash progress
function Calculator:CalculateTrashDelta(currentRun, bestTime, elapsedTime)
  local currentTrash = currentRun.progress.trash

  -- PERFORMANCE OPTIMIZATION: Cache trash delta if inputs haven't changed
  if calculationCache.trashDelta.data and
      calculationCache.trashDelta.lastTrash == currentTrash and
      calculationCache.trashDelta.lastTime and
      math.abs(calculationCache.trashDelta.lastTime - elapsedTime) < 0.5 then -- Allow 0.5s tolerance
    return calculationCache.trashDelta.data
  end

  local bestSamples = bestTime.trashSamples or {}

  -- BEST RUN LOGIC: What trash % did the best run have at this exact time?
  local bestRunTrash = 0

  if next(bestSamples) then
    -- Find the two samples that bracket the current time
    local lower = { time = 0, trash = 0 }
    local upper = { time = bestTime.time, trash = 100 }
    for _, sample in ipairs(bestSamples) do
      if sample.time <= elapsedTime and sample.time >= lower.time then
        lower = sample
      elseif sample.time >= elapsedTime and sample.time <= upper.time then
        upper = sample
      end
    end
    -- Interpolate between samples
    if upper.time > lower.time then
      -- SAFETY: Explicit check to prevent division by zero (should never happen due to if condition, but being explicit)
      local timeDiff = upper.time - lower.time
      if timeDiff > 0 then
        local tProg = (elapsedTime - lower.time) / timeDiff
        bestRunTrash = lower.trash + (upper.trash - lower.trash) * tProg
      else
        bestRunTrash = lower.trash
      end
    else
      -- SAFETY: Ensure bestTime.time is not zero before division
      if bestTime.time and bestTime.time > 0 then
        bestRunTrash = (elapsedTime / bestTime.time) * 100
      else
        -- Fallback: assume linear progression if no valid time data
        bestRunTrash = 0
      end
    end
  else
    -- SAFETY: Ensure bestTime.time is not zero before division
    if bestTime.time and bestTime.time > 0 then
      bestRunTrash = (elapsedTime / bestTime.time) * 100
    else
      -- Fallback: assume linear progression if no valid time data
      bestRunTrash = 0
    end
  end

  -- Cap best run trash to reasonable bounds
  bestRunTrash = math.max(0, math.min(100, bestRunTrash))

  -- Calculate delta: positive = current run ahead, negative = current run behind
  local trashDelta = currentTrash - bestRunTrash

  -- PERFORMANCE OPTIMIZATION: Throttle debug messages
  local now = GetTime()
  if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
    PushMaster:DebugPrint(string.format(
      "Best Run Trash: Time %.1fs | Current: %.1f%% | Best Run: %.1f%% | Delta: %+.1f%%",
      elapsedTime, currentTrash, bestRunTrash, trashDelta))
  end

  -- Cache the result
  calculationCache.trashDelta.data = trashDelta
  calculationCache.trashDelta.lastTrash = currentTrash
  calculationCache.trashDelta.lastTime = elapsedTime

  return trashDelta
end

---Calculate boss progress delta using precise timing comparison
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number bossDelta Boss count difference (positive = ahead, negative = behind)
function Calculator:CalculateBossDelta(currentRun, bestTime, elapsedTime)
  local currentBossCount = #currentRun.bossKillTimes

  -- PERFORMANCE OPTIMIZATION: Cache boss delta if inputs haven't changed
  if calculationCache.bossDelta.data and
      calculationCache.bossDelta.lastBossCount == currentBossCount and
      calculationCache.bossDelta.lastTime and
      math.abs(calculationCache.bossDelta.lastTime - elapsedTime) < 0.5 then -- Allow 0.5s tolerance
    return calculationCache.bossDelta.data
  end

  local bestBossKillTimes = bestTime.bossKillTimes or {}

  -- BEST RUN LOGIC: How many bosses did the best run have killed by this exact time?
  local bestRunBossCount = 0
  for i = 1, #bestBossKillTimes do
    -- SAFETY: Check if boss kill data exists and has valid killTime
    local bossKill = bestBossKillTimes[i]
    if bossKill and bossKill.killTime and bossKill.killTime <= elapsedTime then
      bestRunBossCount = bestRunBossCount + 1
    end
  end

  -- Calculate delta: positive = current run ahead, negative = current run behind
  local bossDelta = currentBossCount - bestRunBossCount

  -- PERFORMANCE OPTIMIZATION: Throttle debug messages
  local now = GetTime()
  if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
    PushMaster:DebugPrint(string.format(
      "Best Run Boss: Time %.1fs | Current: %d bosses | Best Run: %d bosses | Delta: %+d",
      elapsedTime, currentBossCount, bestRunBossCount, bossDelta))
  end

  -- Cache the result
  calculationCache.bossDelta.data = bossDelta
  calculationCache.bossDelta.lastBossCount = currentBossCount
  calculationCache.bossDelta.lastTime = elapsedTime

  return bossDelta
end

---Calculate death progress delta using precise timing comparison
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number deathDelta Death count difference (positive = more deaths than best run, negative = fewer deaths)
function Calculator:CalculateDeathDelta(currentRun, bestTime, elapsedTime)
  local currentDeathCount = currentRun.progress.deaths

  -- PERFORMANCE OPTIMIZATION: Cache death delta if inputs haven't changed
  if calculationCache.deathDelta.data and
      calculationCache.deathDelta.lastDeathCount == currentDeathCount and
      calculationCache.deathDelta.lastTime and
      math.abs(calculationCache.deathDelta.lastTime - elapsedTime) < 0.5 then -- Allow 0.5s tolerance
    return calculationCache.deathDelta.data
  end

  -- Get death data from best run - we need to reconstruct this from logged deaths
  local bestDeathTimes = bestTime.deathTimes or {}

  -- BEST RUN LOGIC: How many deaths did the best run have by this exact time?
  local bestRunDeathCount = 0
  for _, deathTime in ipairs(bestDeathTimes) do
    if deathTime <= elapsedTime then
      bestRunDeathCount = bestRunDeathCount + 1
    end
  end

  -- Calculate delta: positive = current run has more deaths, negative = current run has fewer deaths
  local deathDelta = currentDeathCount - bestRunDeathCount

  -- PERFORMANCE OPTIMIZATION: Throttle debug messages
  local now = GetTime()
  if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
    PushMaster:DebugPrint(string.format(
      "Best Run Deaths: Time %.1fs | Current: %d deaths | Best Run: %d deaths | Delta: %+d",
      elapsedTime, currentDeathCount, bestRunDeathCount, deathDelta))
  end

  -- Cache the result
  calculationCache.deathDelta.data = deathDelta
  calculationCache.deathDelta.lastDeathCount = currentDeathCount
  calculationCache.deathDelta.lastTime = elapsedTime

  return deathDelta
end

---Calculate boss timing efficiency based on actual kill times vs best run
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number bossTimingEfficiency Percentage efficiency from boss timing
function Calculator:CalculateBossTimingEfficiency(currentRun, bestTime, elapsedTime)
  local bestBossKillTimes = bestTime.bossKillTimes or {}
  local currentBossKillTimes = currentRun.bossKillTimes or {}

  if #bestBossKillTimes == 0 or #currentBossKillTimes == 0 then
    return 0
  end

  local totalTimingDifference = 0
  local bossesCompared = 0

  -- Compare timing for each boss that has been killed in current run
  for i = 1, #currentBossKillTimes do
    local currentBossKill = currentBossKillTimes[i]
    local bestBossKill = bestBossKillTimes[i]

    if bestBossKill and currentBossKill.killTime and bestBossKill.killTime then
      -- Calculate time difference for this boss
      local timeDifference = currentBossKill.killTime - bestBossKill.killTime
      totalTimingDifference = totalTimingDifference + timeDifference
      bossesCompared = bossesCompared + 1

      PushMaster:DebugPrint(string.format("Boss %d timing: Current %.1fs, Best %.1fs, Diff %.1fs",
        i, currentBossKill.killTime, bestBossKill.killTime, timeDifference))
    end
  end

  -- Convert timing difference to efficiency percentage
  local bossTimingEfficiency = 0
  if bossesCompared > 0 and bestTime.time > 0 then
    -- Negative timing difference = faster = positive efficiency
    local averageTimeDifference = totalTimingDifference / bossesCompared
    bossTimingEfficiency = -(averageTimeDifference / bestTime.time) * 100

    PushMaster:DebugPrint(string.format("Boss timing efficiency: %.1f%% (avg diff %.1fs over %d bosses)",
      bossTimingEfficiency, averageTimeDifference, bossesCompared))
  end

  return bossTimingEfficiency
end

---Calculate dynamic weights based on actual time spent on bosses vs trash
---@param bestTime table Best time data with boss kill times and trash milestones
---@return table weights Table containing bossWeight, trashWeight, and per-boss weights
function Calculator:CalculateDungeonWeights(bestTime)
  -- PERFORMANCE OPTIMIZATION: Cache dungeon weights since they don't change for the same best time
  local bestTimeHash = bestTime.time .. "_" .. #(bestTime.bossKillTimes or {}) .. "_" .. #(bestTime.trashSamples or {})

  if calculationCache.dungeonWeights.data and calculationCache.dungeonWeights.bestTimeHash == bestTimeHash then
    return calculationCache.dungeonWeights.data
  end

  local bossKillTimes = bestTime.bossKillTimes or {}
  local trashSamples = bestTime.trashSamples or {}
  local totalTime = bestTime.time or 1800 -- fallback to 30 minutes

  -- Calculate individual boss fight durations and difficulties
  local bossData = {}
  local totalBossTime = 0
  local previousTime = 0

  for i = 1, #bossKillTimes do
    local bossKill = bossKillTimes[i]
    if bossKill and bossKill.killTime then
      -- Find the trash milestone just before this boss
      local trashTimeBeforeBoss = 0
      for _, sample in ipairs(trashSamples) do
        if sample.time <= bossKill.killTime and sample.time > trashTimeBeforeBoss then
          trashTimeBeforeBoss = sample.time
        end
      end

      -- Estimate boss fight duration (time from when trash was done to boss kill)
      local estimatedBossFightTime = math.max(30, bossKill.killTime - trashTimeBeforeBoss)
      totalBossTime = totalBossTime + estimatedBossFightTime

      -- Calculate relative difficulty weight for this specific boss
      local bossWeight = estimatedBossFightTime / totalTime

      bossData[i] = {
        name = bossKill.name or ("Boss " .. i),
        fightTime = estimatedBossFightTime,
        killTime = bossKill.killTime,
        weight = bossWeight,
        difficultyRating = estimatedBossFightTime / 60 -- Bosses taking longer are "harder"
      }

      -- PERFORMANCE OPTIMIZATION: Throttle debug messages
      local now = GetTime()
      if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
        PushMaster:DebugPrint(string.format(
          "Boss %d (%s): Kill at %.1fs, Fight time %.1fs, Weight %.3f (%.1f%% of total time)",
          i, bossKill.name or "Unknown", bossKill.killTime, estimatedBossFightTime, bossWeight, bossWeight * 100))
      end
    end
  end

  -- Calculate time spent on trash (total time minus boss time)
  local totalTrashTime = totalTime - totalBossTime

  -- Calculate overall category weights
  local overallBossWeight = totalBossTime / totalTime
  local overallTrashWeight = totalTrashTime / totalTime

  -- Ensure weights are reasonable (minimum 10% each, maximum 90% each)
  overallBossWeight = math.max(0.1, math.min(0.9, overallBossWeight))
  overallTrashWeight = math.max(0.1, math.min(0.9, overallTrashWeight))

  -- Normalize weights to sum to 1.0
  local totalWeight = overallBossWeight + overallTrashWeight
  overallBossWeight = overallBossWeight / totalWeight
  overallTrashWeight = overallTrashWeight / totalWeight

  -- Calculate individual boss importance within the boss category
  for i = 1, #bossData do
    if totalBossTime > 0 then
      bossData[i].categoryWeight = bossData[i].fightTime / totalBossTime
      bossData[i].absoluteWeight = bossData[i].weight / totalWeight
    else
      bossData[i].categoryWeight = 1 / #bossData -- Equal weight if no timing data
      bossData[i].absoluteWeight = overallBossWeight / #bossData
    end
  end

  -- PERFORMANCE OPTIMIZATION: Throttle debug messages
  local now = GetTime()
  if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
    PushMaster:DebugPrint(string.format(
      "Dynamic weights calculated: Overall Boss %.1f%% (%.1fs), Trash %.1f%% (%.1fs), Total %.1fs",
      overallBossWeight * 100, totalBossTime, overallTrashWeight * 100, totalTrashTime, totalTime))
    calculationCache.lastDebugTime = now
  end

  local result = {
    bossWeight = overallBossWeight,
    trashWeight = overallTrashWeight,
    totalBossTime = totalBossTime,
    totalTrashTime = totalTrashTime,
    perBossData = bossData,
    hasBossData = #bossData > 0
  }

  -- Cache the result
  calculationCache.dungeonWeights.data = result
  calculationCache.dungeonWeights.bestTimeHash = bestTimeHash

  return result
end

---Calculate boss count impact with dynamic per-boss weighting
---@param bossDelta number Overall boss count delta (ahead/behind)
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param weights table Dynamic weight data with per-boss information
---@return number bossCountImpact Weighted boss count impact
function Calculator:CalculateDynamicBossCountImpact(bossDelta, currentRun, bestTime, elapsedTime, weights)
  if not weights.hasBossData or bossDelta == 0 then
    -- Fallback to simple calculation if no boss data available
    return bossDelta * 25 -- Each boss ahead/behind = 25% impact
  end

  local perBossData = weights.perBossData
  local currentBossCount = #currentRun.bossKillTimes
  local bestBossKillTimes = bestTime.bossKillTimes or {}

  -- Calculate weighted impact based on which specific bosses are ahead/behind
  local weightedImpact = 0

  if bossDelta > 0 then
    -- Ahead on bosses - calculate impact of being ahead on specific bosses
    for i = 1, currentBossCount do
      local bossData = perBossData[i]
      if bossData then
        -- Being ahead on a harder boss (longer fight time) has more impact
        local bossImpact = 50 * bossData.difficultyRating * bossData.categoryWeight
        weightedImpact = weightedImpact + bossImpact

        PushMaster:DebugPrint(string.format(
          "Ahead on %s: difficulty %.1f, weight %.3f, impact %.1f",
          bossData.name, bossData.difficultyRating, bossData.categoryWeight, bossImpact))
      end
    end
  elseif bossDelta < 0 then
    -- Behind on bosses - calculate impact of missing specific upcoming bosses
    local nextBossIndex = currentBossCount + 1
    local bossesStillNeeded = math.abs(bossDelta)

    for i = nextBossIndex, math.min(nextBossIndex + bossesStillNeeded - 1, #perBossData) do
      local bossData = perBossData[i]
      if bossData then
        -- Being behind on a harder boss has more negative impact
        local bossImpact = -50 * bossData.difficultyRating * bossData.categoryWeight
        weightedImpact = weightedImpact + bossImpact

        PushMaster:DebugPrint(string.format(
          "Behind on upcoming %s: difficulty %.1f, weight %.3f, impact %.1f",
          bossData.name, bossData.difficultyRating, bossData.categoryWeight, bossImpact))
      end
    end
  end

  -- Cap the impact to reasonable bounds
  weightedImpact = math.max(-100, math.min(100, weightedImpact))

  PushMaster:DebugPrint(string.format(
    "Dynamic boss count impact: %d boss delta -> %.1f weighted impact",
    bossDelta, weightedImpact))

  return weightedImpact
end

---Calculate overall efficiency combining trash, boss timing, and boss count with dynamic weights
---@param trashDelta number Trash progress delta
---@param bossDelta number Boss count delta
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number efficiency Overall efficiency percentage
function Calculator:CalculateOverallEfficiency(trashDelta, bossDelta, currentRun, bestTime, elapsedTime)
  -- Calculate boss timing efficiency (how fast/slow boss kills are)
  local bossTimingEfficiency = self:CalculateBossTimingEfficiency(currentRun, bestTime, elapsedTime)

  -- Calculate dynamic weights based on actual time spent in this dungeon
  local weights = self:CalculateDungeonWeights(bestTime)

  -- Use fully dynamic weighting system
  local trashWeight = weights.trashWeight * 0.7     -- 70% of trash time weight for milestone progress
  local bossTimingWeight = weights.bossWeight * 0.5 -- 50% of boss time weight for timing efficiency
  local bossCountWeight = weights.bossWeight * 0.5  -- 50% of boss time weight for count ahead/behind

  -- Calculate weighted efficiency
  local efficiency = 0

  -- Trash component (milestone-based, weighted by actual trash time)
  efficiency = efficiency + (trashDelta * trashWeight)

  -- Boss timing component (actual kill speed vs best run, weighted by actual boss time)
  efficiency = efficiency + (bossTimingEfficiency * bossTimingWeight)

  -- Boss count component (ahead/behind on boss kills, dynamically weighted per boss)
  local bossCountImpact = self:CalculateDynamicBossCountImpact(bossDelta, currentRun, bestTime, elapsedTime, weights)
  efficiency = efficiency + (bossCountImpact * bossCountWeight)

  -- Apply death penalty impact - direct time impact, not weighted
  local currentDeathTimePenalty = currentRun.progress.timeLostToDeaths or 0
  local bestRunDeathTimePenalty = 0

  -- Calculate what the death time penalty was for the best run at this elapsed time
  if bestTime.deathTimes then
    for _, deathTime in ipairs(bestTime.deathTimes) do
      if deathTime <= elapsedTime then
        bestRunDeathTimePenalty = bestRunDeathTimePenalty + 15 -- Each death costs 15 seconds
      end
    end
  end

  -- Calculate death time penalty delta (how much more/less time penalty vs best run)
  local deathTimeDelta = currentDeathTimePenalty - bestRunDeathTimePenalty
  local deathImpact = 0
  if bestTime.time > 0 then
    -- Convert time penalty delta directly to efficiency impact (no arbitrary weighting)
    -- If you're 30 seconds behind due to deaths in a 1800s dungeon, that's -1.67% efficiency
    deathImpact = -(deathTimeDelta / bestTime.time) * 100
    efficiency = efficiency + deathImpact
  end

  -- Apply intelligent learning factor
  efficiency = self:ApplyLearningFactor(efficiency, currentRun, bestTime)

  -- Cap to reasonable bounds
  efficiency = math.max(-100, math.min(100, efficiency))

  -- PERFORMANCE OPTIMIZATION: Throttle debug messages
  local now = GetTime()
  if now - calculationCache.lastDebugTime > calculationCache.debugThrottle then
    PushMaster:DebugPrint(string.format(
      "Fully Dynamic Efficiency: Trash %.1f%% (%.1f × %.1f), Boss Timing %.1f%% (%.1f × %.1f), Boss Count %.1f%% (%.1f × %.1f), Death Time Penalty %.1fs vs %.1fs (%.1f%%), Final %.1f%%",
      trashDelta * trashWeight, trashDelta, trashWeight,
      bossTimingEfficiency * bossTimingWeight, bossTimingEfficiency, bossTimingWeight,
      bossCountImpact * bossCountWeight, bossCountImpact, bossCountWeight,
      currentDeathTimePenalty, bestRunDeathTimePenalty, deathImpact,
      efficiency))
  end

  return efficiency
end

---Apply learning factor based on multiple run analysis
---@param baseEfficiency number Base calculated efficiency
---@param currentRun table Current run data
---@param bestTime table Best time data
---@return number adjustedEfficiency Efficiency adjusted by learning
function Calculator:ApplyLearningFactor(baseEfficiency, currentRun, bestTime)
  -- For now, return base efficiency
  -- Future enhancement: Analyze patterns across multiple runs
  -- to detect route changes, group composition effects, etc.

  -- Potential learning factors:
  -- - Route strategy detection (front-load vs back-load trash)
  -- - Time of day performance patterns
  -- - Group composition efficiency
  -- - Dungeon-specific performance trends

  return baseEfficiency
end

---Calculate projected completion time based on current progress
---@return number|nil projectedTime Projected completion time or nil
function Calculator:GetProjectedTime()
  if not currentRun.isActive or currentRun.progress.trash <= 0 then
    return nil
  end

  local elapsedTime = GetTime() - currentRun.startTime
  local progressPercent = currentRun.progress.trash / 100

  -- Simple linear projection based on trash progress
  local projectedTime = elapsedTime / progressPercent

  return projectedTime
end

---Get detailed run statistics
---@return table|nil stats Detailed statistics or nil if not tracking
function Calculator:GetRunStatistics()
  if not currentRun.isActive then
    return nil
  end

  local elapsedTime = GetTime() - currentRun.startTime
  local projectedTime = self:GetProjectedTime()

  return {
    elapsedTime = elapsedTime,
    projectedTime = projectedTime,
    deathCount = currentRun.progress.deaths,
    deathTimes = currentRun.deathTimes,
    trashProgress = currentRun.progress.trash,
    bossProgress = currentRun.progress.bosses,
    progressHistory = currentRun.progressHistory
  }
end

---Export best times data for backup/sharing
---@return table bestTimesData All best times data
function Calculator:ExportBestTimes()
  return bestTimes
end

---Import best times data from backup/sharing
---@param importData table Best times data to import
function Calculator:ImportBestTimes(importData)
  if type(importData) == "table" then
    bestTimes = importData

    -- Save to persistent storage
    if not PushMasterDB then
      PushMasterDB = {}
    end
    PushMasterDB.bestTimes = bestTimes

    PushMaster:DebugPrint("Best times imported successfully")
  end
end

---Clear all best times data
function Calculator:ClearBestTimes()
  if PushMasterDB and PushMasterDB.bestTimes then
    PushMasterDB.bestTimes = {}
    bestTimes = {}
    PushMaster:DebugPrint("All best times cleared")
    return true
  end
  return false
end

---Get all best times data
---@return table bestTimes The best times data
function Calculator:GetBestTimes()
  return bestTimes or {}
end

---Calculate approximate data size for optimization reporting
---@param data table The data to calculate size for
---@return number size Approximate size in bytes
function Calculator:_calculateDataSize(data)
  if not data then
    return 0
  end

  local function calculateTableSize(t, visited)
    visited = visited or {}
    if visited[t] then
      return 0 -- Avoid infinite recursion
    end
    visited[t] = true

    local size = 0
    for k, v in pairs(t) do
      -- Key size
      if type(k) == "string" then
        size = size + #k
      elseif type(k) == "number" then
        size = size + 8
      end

      -- Value size
      if type(v) == "string" then
        size = size + #v
      elseif type(v) == "number" then
        size = size + 8
      elseif type(v) == "table" then
        size = size + calculateTableSize(v, visited)
      elseif type(v) == "boolean" then
        size = size + 1
      end
    end
    return size
  end

  return calculateTableSize(data)
end

---Get saved variables optimization settings
---@return table settings Current optimization settings
function Calculator:GetOptimizationSettings()
  return SAVED_VARS_LIMITS
end

---Get saved variables statistics
---@return table stats Statistics about saved variables usage
function Calculator:GetSavedVariablesStats()
  if not PushMasterDB or not PushMasterDB.bestTimes then
    return {
      totalSize = 0,
      dungeonCount = 0,
      levelCount = 0,
      totalEntries = 0,
      averageTrashSamples = 0,
      averageBossKills = 0
    }
  end

  local stats = {
    totalSize = self:_calculateDataSize(PushMasterDB.bestTimes),
    dungeonCount = 0,
    levelCount = 0,
    totalEntries = 0,
    totalTrashSamples = 0,
    totalBossKills = 0
  }

  for mapID, levels in pairs(PushMasterDB.bestTimes) do
    stats.dungeonCount = stats.dungeonCount + 1

    for level, data in pairs(levels) do
      stats.levelCount = stats.levelCount + 1
      stats.totalEntries = stats.totalEntries + 1

      if data.trashSamples then
        stats.totalTrashSamples = stats.totalTrashSamples + #data.trashSamples
      end

      if data.bossKillTimes then
        stats.totalBossKills = stats.totalBossKills + #data.bossKillTimes
      end
    end
  end

  stats.averageTrashSamples = stats.totalEntries > 0 and (stats.totalTrashSamples / stats.totalEntries) or 0
  stats.averageBossKills = stats.totalEntries > 0 and (stats.totalBossKills / stats.totalEntries) or 0

  return stats
end

---Calculate time delta and confidence
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param progressEfficiency number Calculated progress efficiency
---@return number timeDelta Time difference in seconds (positive = behind, negative = ahead)
---@return number timeConfidence Confidence percentage (0-100)
function Calculator:CalculateTimeDelta(currentRun, bestTime, elapsedTime, progressEfficiency)
  if not bestTime or not progressEfficiency then
    return nil, 0 -- No data available
  end

  -- Method 1: Efficiency-based projection
  -- If we're +15% efficient, we should finish 15% faster
  local projectedTotalTime = bestTime.time * (1 - (progressEfficiency / 100))
  local timeDelta = projectedTotalTime - bestTime.time

  -- Calculate confidence based on run progress and data quality
  local confidence = 0

  -- Base confidence on how far into the run we are
  local progressRatio = elapsedTime / bestTime.time
  progressRatio = math.max(0, math.min(1, progressRatio))

  -- Confidence increases as we progress through the run
  if progressRatio < 0.1 then
    confidence = 30 -- Very early, low confidence
  elseif progressRatio < 0.3 then
    confidence = 50 -- Early run, moderate confidence
  elseif progressRatio < 0.6 then
    confidence = 75 -- Mid run, good confidence
  else
    confidence = 90 -- Late run, high confidence
  end

  -- Reduce confidence if efficiency is extreme (likely inaccurate)
  local efficiencyMagnitude = math.abs(progressEfficiency)
  if efficiencyMagnitude > 50 then
    confidence = confidence * 0.5 -- Very extreme efficiency, reduce confidence
  elseif efficiencyMagnitude > 25 then
    confidence = confidence * 0.8 -- Moderate extreme efficiency
  end

  -- Ensure confidence is within bounds
  confidence = math.max(0, math.min(100, confidence))

  PushMaster:DebugPrint(string.format(
    "Time Delta: %.1f%% efficiency -> %+.0fs delta (%.0f%% confidence)",
    progressEfficiency, timeDelta, confidence))

  return timeDelta, confidence
end
