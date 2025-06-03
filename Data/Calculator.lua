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
    elapsedTime = 0
  },
  deathTimes = {},
  playerLastDeathTimestamp = {}, -- NEW: Track last death timestamp per player GUID
  bossKillTimes = {},            -- NEW: Record exact boss kill times
  trashSamples = {},             -- NEW: Record trash progression samples
  progressHistory = {},
  loggedDeaths = {},
  loggedDeathsByGUID = {}
}

-- Best times storage (will be loaded from saved variables)
local bestTimes = {}

---Initialize the Calculator module
function Calculator:Initialize()
  PushMaster:DebugPrint("Calculator module initialized")

  -- Load best times from saved variables
  if PushMasterDB and PushMasterDB.bestTimes then
    bestTimes = PushMasterDB.bestTimes
  end
end

---Start tracking a new Mythic+ run
---@param instanceData table The instance data from EventHandlers
function Calculator:StartNewRun(instanceData)
  if not instanceData then
    PushMaster:DebugPrint("Cannot start run: no instance data")
    return
  end

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
      elapsedTime = 0
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

  local authoritativeElapsedTime
  if progressData.elapsedTime ~= nil then -- Check for nil explicitly
    authoritativeElapsedTime = progressData.elapsedTime
  elseif currentRun.startTime then        -- Fallback ONLY if hook somehow fails AND startTime exists
    authoritativeElapsedTime = GetTime() - currentRun.startTime
    PushMaster:DebugPrint("Warning: Using GetTime() fallback for elapsedTime in Calculator:UpdateProgress.")
  else
    PushMaster:Print("Error: elapsedTime not available in Calculator:UpdateProgress.")
    return -- Cannot proceed without a valid time
  end

  -- Update current progress
  if progressData.trash then
    currentRun.progress.trash = progressData.trash
  end

  currentRun.progress.elapsedTime = authoritativeElapsedTime -- Store the authoritative time
  -- Sample trash progress for ghost-car interpolation
  currentRun.trashSamples = currentRun.trashSamples or {}
  table.insert(currentRun.trashSamples, { time = authoritativeElapsedTime, trash = currentRun.progress.trash })

  -- NEW: Update death count from API
  if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
    local apiDeathCount, apiTimeLost = C_ChallengeMode.GetDeathCount()
    if apiDeathCount and apiDeathCount ~= currentRun.progress.deaths then
      PushMaster:DebugPrint(string.format("API Death Count Updated: %d (was %d). Time lost: %.1fs", apiDeathCount,
        currentRun.progress.deaths, apiTimeLost or 0))
      currentRun.progress.deaths = apiDeathCount
      -- currentRun.progress.timeLostToDeaths = apiTimeLost -- Optional: store this if you want to use it
    end
  end

  -- Store progress history for analysis
  table.insert(currentRun.progressHistory, {
    time = authoritativeElapsedTime, -- Use authoritativeElapsedTime
    trash = currentRun.progress.trash,
    bosses = currentRun.progress.bosses,
    deaths = currentRun.progress.deaths
  })

  PushMaster:DebugPrint(string.format("Progress updated: %.1f%% trash, %.1fs elapsed",
    currentRun.progress.trash, authoritativeElapsedTime))
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
  -- This function, RecordDeath, is now primarily for detailed logging of individual death events.

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

  local actualKillTime = killTime or GetTime() -- killTime is a timestamp from combat log or GetTime() if not provided

  if not currentRun.startTime then
    PushMaster:Print("Error: currentRun.startTime not set, cannot accurately record boss kill time.")
    return
  end
  local elapsedTimeAtKill = actualKillTime - currentRun.startTime

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
  currentRun.completionTimeAbsolute = GetTime() -- Store absolute completion for reference
  currentRun.isActive = false

  local totalTime = currentRun.progress.elapsedTime -- This is the most accurate total time

  PushMaster:DebugPrint("Run completed in " .. string.format("%.1f", totalTime) .. "s")

  -- Store as best time if applicable
  self:UpdateBestTime(currentRun, totalTime) -- Pass totalTime explicitly
end

---Reset the current run
function Calculator:ResetCurrentRun()
  currentRun = {
    isActive = false,
    instanceData = nil,
    startTime = nil,
    completionTime = nil,
    progress = {
      trash = 0,
      bosses = 0,
      deaths = 0,
      elapsedTime = 0
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

  if not bestTimes[instanceData.currentMapID][instanceData.cmLevel] then
    bestTimes[instanceData.currentMapID][instanceData.cmLevel] = {
      time = totalTime,
      date = date("%Y-%m-%d %H:%M:%S"),
      deaths = runData.progress.deaths,
      affixes = instanceData.affixes,
      bossKillTimes = runData.bossKillTimes or {}, -- NEW: Store exact boss kill times
      trashSamples = runData.trashSamples or {}    -- NEW: Store trash progression samples
    }
    PushMaster:DebugPrint("New best time recorded: " .. string.format("%.1f", totalTime) .. "s")
  elseif totalTime < bestTimes[instanceData.currentMapID][instanceData.cmLevel].time then
    bestTimes[instanceData.currentMapID][instanceData.cmLevel] = {
      time = totalTime,
      date = date("%Y-%m-%d %H:%M:%S"),
      deaths = runData.progress.deaths,
      affixes = instanceData.affixes,
      bossKillTimes = runData.bossKillTimes or {}, -- NEW: Store exact boss kill times
      trashSamples = runData.trashSamples or {}    -- NEW: Store trash progression samples
    }
    PushMaster:DebugPrint("Best time improved: " .. string.format("%.1f", totalTime) .. "s")
  end

  -- Save to persistent storage
  if not PushMasterDB then
    PushMasterDB = {}
  end
  PushMasterDB.bestTimes = bestTimes
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
  local deathTimePenalty = currentRun.progress.deaths * 15 -- 15 seconds per death

  if bestTime then
    -- INTELLIGENT PACE CALCULATION - Learn from actual run patterns
    local paceData = self:CalculateIntelligentPace(currentRun, bestTime, elapsedTime)

    progressEfficiency = paceData.efficiency
    trashProgress = paceData.trashDelta
    bossProgress = paceData.bossDelta

    PushMaster:DebugPrint(string.format("Intelligent pace: Efficiency %.1f%%, Trash %.1f%%, Boss %d",
      progressEfficiency, trashProgress, bossProgress))
  else
    -- No comparison data available yet, provide default values
    PushMaster:DebugPrint("No best time data available for intelligent comparison, using N/A values")
    progressEfficiency = nil -- Or some other indicator for "N/A"
    trashProgress = nil      -- Or some other indicator for "N/A"
    bossProgress = nil       -- Or some other indicator for "N/A"
    -- We don't return nil here anymore, so the rest of the function will execute
  end

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
    deathTimePenalty = deathTimePenalty,
    -- Keep for backward compatibility
    overallSpeed = finalOverallSpeed
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

  -- MILESTONE-BASED TRASH COMPARISON
  -- Instead of linear assumptions, use actual milestone data
  local trashDelta = self:CalculateTrashDelta(currentRun, bestTime, elapsedTime)

  -- PRECISE BOSS TIMING
  -- Compare actual boss kill timing vs best run
  local bossDelta = self:CalculateBossDelta(currentRun, bestTime, elapsedTime)

  -- OVERALL EFFICIENCY CALCULATION
  -- Combine trash and boss performance with learned weights
  local efficiency = self:CalculateOverallEfficiency(trashDelta, bossDelta, currentRun, bestTime, elapsedTime)

  return {
    efficiency = efficiency,
    trashDelta = trashDelta,
    bossDelta = bossDelta
  }
end

---Calculate trash progress delta using milestone-based comparison
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number trashDelta Percentage difference in trash progress
function Calculator:CalculateTrashDelta(currentRun, bestTime, elapsedTime)
  local currentTrash = currentRun.progress.trash
  local bestSamples = bestTime.trashSamples or {}

  -- GHOST CAR LOGIC: What trash % did the best run have at this exact time?
  local ghostCarTrash = 0

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
      local tProg = (elapsedTime - lower.time) / (upper.time - lower.time)
      ghostCarTrash = lower.trash + (upper.trash - lower.trash) * tProg
    else
      ghostCarTrash = lower.trash
    end
  else
    ghostCarTrash = (elapsedTime / bestTime.time) * 100
  end

  -- Cap ghost car trash to reasonable bounds
  ghostCarTrash = math.max(0, math.min(100, ghostCarTrash))

  -- Calculate delta: positive = current run ahead, negative = current run behind
  local trashDelta = currentTrash - ghostCarTrash

  -- Debug: Show ghost car logic for trash
  PushMaster:DebugPrint(string.format(
    "Ghost Car Trash: Time %.1fs | Current: %.1f%% | Ghost Car: %.1f%% | Delta: %+.1f%%",
    elapsedTime, currentTrash, ghostCarTrash, trashDelta))

  return trashDelta
end

---Calculate boss progress delta using precise timing comparison
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number bossDelta Boss count difference (positive = ahead, negative = behind)
function Calculator:CalculateBossDelta(currentRun, bestTime, elapsedTime)
  local currentBossCount = #currentRun.bossKillTimes
  local bestBossKillTimes = bestTime.bossKillTimes or {}

  -- GHOST CAR LOGIC: How many bosses did the best run have killed by this exact time?
  local ghostCarBossCount = 0
  for i = 1, #bestBossKillTimes do
    if bestBossKillTimes[i].killTime <= elapsedTime then
      ghostCarBossCount = ghostCarBossCount + 1
    end
  end

  -- Calculate delta: positive = current run ahead, negative = current run behind
  local bossDelta = currentBossCount - ghostCarBossCount

  -- Debug: Show ghost car logic
  PushMaster:DebugPrint(string.format(
    "Ghost Car Boss: Time %.1fs | Current: %d bosses | Ghost Car: %d bosses | Delta: %+d",
    elapsedTime, currentBossCount, ghostCarBossCount, bossDelta))

  -- DETAILED DEBUG: Show every minute comparison (commented out to reduce spam)
  -- PushMaster:Print(string.format(
  --   "DEBUG - Time %.0fs | Real Car: %d bosses | Ghost Car: %d bosses | Delta: %+d",
  --   elapsedTime, currentBossCount, ghostCarBossCount, bossDelta))

  return bossDelta
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
---@return table weights Table containing bossWeight and trashWeight
function Calculator:CalculateDungeonWeights(bestTime)
  local bossKillTimes = bestTime.bossKillTimes or {}
  local trashSamples = bestTime.trashSamples or {}
  local totalTime = bestTime.time or 1800 -- fallback to 30 minutes

  -- Calculate total time spent on bosses
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
      -- This is an approximation since we don't have exact boss start times
      local estimatedBossFightTime = math.max(30, bossKill.killTime - trashTimeBeforeBoss)
      totalBossTime = totalBossTime + estimatedBossFightTime

      PushMaster:DebugPrint(string.format(
        "Boss %d (%s): Kill at %.1fs, Trash before at %.1fs, Estimated fight time %.1fs",
        i, bossKill.name or "Unknown", bossKill.killTime, trashTimeBeforeBoss, estimatedBossFightTime))
    end
  end

  -- Calculate time spent on trash (total time minus boss time)
  local totalTrashTime = totalTime - totalBossTime

  -- Calculate weights as percentages of total time
  local bossWeight = totalBossTime / totalTime
  local trashWeight = totalTrashTime / totalTime

  -- Ensure weights are reasonable (minimum 10% each, maximum 90% each)
  bossWeight = math.max(0.1, math.min(0.9, bossWeight))
  trashWeight = math.max(0.1, math.min(0.9, trashWeight))

  -- Normalize weights to sum to 1.0
  local totalWeight = bossWeight + trashWeight
  bossWeight = bossWeight / totalWeight
  trashWeight = trashWeight / totalWeight

  PushMaster:DebugPrint(string.format(
    "Dynamic weights calculated: Boss %.1f%% (%.1fs), Trash %.1f%% (%.1fs), Total %.1fs",
    bossWeight * 100, totalBossTime, trashWeight * 100, totalTrashTime, totalTime))

  return {
    bossWeight = bossWeight,
    trashWeight = trashWeight,
    totalBossTime = totalBossTime,
    totalTrashTime = totalTrashTime
  }
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

  -- Use dynamic weights instead of arbitrary ones
  local trashWeight = weights.trashWeight * 0.8     -- 80% of trash time weight for milestone progress
  local bossTimingWeight = weights.bossWeight * 0.8 -- 80% of boss time weight for timing efficiency
  local bossCountWeight = 0.2                       -- 20% fixed for boss count ahead/behind

  -- Calculate weighted efficiency
  local efficiency = 0

  -- Trash component (milestone-based, weighted by actual trash time)
  efficiency = efficiency + (trashDelta * trashWeight)

  -- Boss timing component (actual kill speed vs best run, weighted by actual boss time)
  efficiency = efficiency + (bossTimingEfficiency * bossTimingWeight)

  -- Boss count component (ahead/behind on boss kills, fixed weight)
  local bossCountImpact = bossDelta * 25 -- Each boss ahead/behind = 25% impact
  efficiency = efficiency + (bossCountImpact * bossCountWeight)

  -- Apply death penalty impact
  local deathPenalty = currentRun.progress.deaths * 15 -- 15 seconds per death
  local deathImpact = 0
  if bestTime.time > 0 then
    deathImpact = -(deathPenalty / bestTime.time) * 100
    efficiency = efficiency + deathImpact
  end

  -- Apply intelligent learning factor
  efficiency = self:ApplyLearningFactor(efficiency, currentRun, bestTime)

  -- Cap to reasonable bounds
  efficiency = math.max(-100, math.min(100, efficiency))

  PushMaster:DebugPrint(string.format(
    "Dynamic Efficiency Breakdown: Trash %.1f%% (%.1f × %.1f), Boss Timing %.1f%% (%.1f × %.1f), Boss Count %.1f%% (%.1f × %.1f), Deaths %.1f%%, Final %.1f%%",
    trashDelta * trashWeight, trashDelta, trashWeight,
    bossTimingEfficiency * bossTimingWeight, bossTimingEfficiency, bossTimingWeight,
    bossCountImpact * bossCountWeight, bossCountImpact, bossCountWeight,
    deathImpact,
    efficiency))

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
