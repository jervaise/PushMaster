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

-- NEW: Adaptive algorithm state tracking for Phase 4 Learning
local adaptiveState = {
  methodAccuracy = {},      -- Track accuracy of different methods over time
  recentRuns = {},          -- Store recent run data for pattern recognition
  confidenceHistory = {},   -- Track confidence vs actual accuracy
  smoothingWindow = {},     -- Display value smoothing buffer
  lastCalculatedValues = {} -- Previous values for smoothing
}

-- NEW: Phase 1 - Adaptive Method Selection constants
local ADAPTIVE_METHOD_CONFIG = {
  -- Method selection criteria
  trashInterpolation = {
    priority = 1,
    minTrashSamples = 10,
    progressRange = 5, -- Minimum 5% progress span in data
    maxGapSize = 15,   -- Maximum % gap between data points
    confidenceBonus = 15
  },
  weightedInterpolation = {
    priority = 2,
    minTrashSamples = 7,
    progressRange = 3,
    confidenceBonus = 10
  },
  bossCountMethod = {
    priority = 3,
    minBossData = 2,
    confidenceBonus = 5
  },
  proportionalEstimate = {
    priority = 4,
    confidenceBonus = 0
  },

  -- Smoothing configuration
  smoothing = {
    enabled = true,
    windowSize = 3,
    weightDecay = 0.7 -- Recent values get higher weight
  }
}

-- NEW: Phase 2 - Dynamic Efficiency Weight Configuration
local DYNAMIC_WEIGHT_CONFIG = {
  -- Progress-based phases
  earlyPhase = {
    progressThreshold = 30,
    trashWeight = 0.5,
    bossTimingWeight = 0.3,
    bossCountWeight = 0.2
  },
  midPhase = {
    progressThreshold = 70,
    trashWeight = 0.6,
    bossTimingWeight = 0.25,
    bossCountWeight = 0.15
  },
  latePhase = {
    progressThreshold = 100,
    trashWeight = 0.8,
    bossTimingWeight = 0.15,
    bossCountWeight = 0.05
  },

  -- Data quality multipliers
  dataQualityMultipliers = {
    highTrashSamples = { threshold = 15, trashBonus = 0.1 },
    lowTrashSamples = { threshold = 5, trashPenalty = -0.1 },
    consistentBossTiming = { threshold = 0.8, bossBonus = 0.05 }
  }
}

-- NEW: Phase 3 - Adaptive Boss Weighting Configuration
local BOSS_WEIGHT_CONFIG = {
  -- Fight duration based weighting
  durationBased = {
    shortFight = { threshold = 60, weight = 0.8 },
    mediumFight = { threshold = 180, weight = 1.2 },
    longFight = { threshold = 300, weight = 1.5 }
  },

  -- Boss difficulty/importance weighting
  difficultyBased = {
    miniBoss = { weight = 0.6 },
    standardBoss = { weight = 1.0 },
    finalBoss = { weight = 1.8 }
  },

  -- Timing consistency weighting
  consistencyBased = {
    highVariance = { threshold = 30, weight = 0.7 },
    lowVariance = { threshold = 10, weight = 1.3 }
  },

  -- Adaptive adjustments
  adaptiveAdjustments = {
    aheadOfPace = { bossWeightBonus = 0.1 },
    behindPace = { bossWeightPenalty = -0.1 },
    lowKey = { keyLevel = 15, reliabilityBonus = 0.05 },
    highKey = { keyLevel = 20, stressMultiplier = 1.1 }
  }
}

-- NEW: Phase 4 - Learning System Configuration
local LEARNING_CONFIG = {
  methodAccuracy = {
    trackLastNRuns = 20,
    weightRecentRuns = 0.7,
    adjustConfidenceByAccuracy = true
  },

  similarScenarios = {
    dungeonType = true,
    keyLevel = true,
    progressPoint = true
  },

  adaptiveConfidence = {
    baseConfidence = 70,
    accuracyBonus = 30,
    newDataPenalty = -20,
    consistencyBonus = 15
  },

  multiFactorAnalysis = {
    weightedAverage = {
      trashProjection = 0.4,
      bossTimingProjection = 0.3,
      paceProjection = 0.2,
      deathPenaltyProjection = 0.1
    },

    ensembleWeighting = {
      highConfidence = { singleBest = 0.8, ensemble = 0.2 },
      mediumConfidence = { singleBest = 0.5, ensemble = 0.5 },
      lowConfidence = { singleBest = 0.2, ensemble = 0.8 }
    }
  }
}

-- PERFORMANCE CONFIGURATION: Control calculation frequency and complexity in production
local PERFORMANCE_CONFIG = {
  -- Update frequency controls
  maxCalculationsPerSecond = 5,  -- Limit to 5 calculations per second maximum
  minUpdateInterval = 0.2,       -- Minimum 200ms between updates
  adaptiveUpdateInterval = true, -- Scale update frequency based on run progress

  -- Calculation complexity controls
  maxTrashSampleLookup = 10, -- Limit samples examined for interpolation
  maxBossDataProcessing = 5, -- Limit boss data processed per calculation
  maxEnsembleMethods = 3,    -- Limit methods in ensemble to top 3

  -- Cache and memory controls
  cacheValidityDuration = 1.0,  -- Cache results for 1 second
  maxAdaptiveStateHistory = 50, -- Limit learning data to prevent memory bloat
  enableDebugLogging = false,   -- Disable debug logging in production for performance

  -- UI update throttling
  uiUpdateThrottle = 2.0,         -- Minimum 2 seconds between UI updates
  displaySmoothingEnabled = true, -- Enable display smoothing to reduce flickering

  -- Background calculation controls
  enableBackgroundCalculations = false, -- Disable background ensemble calculations
  enableLearningOptimizations = true,   -- Keep learning but optimize aggressively
}

-- PERFORMANCE CACHE: Enhanced caching system for expensive calculations
local performanceCache = {
  -- Method selection cache (rarely changes during a run)
  methodSelection = {
    data = nil,
    bestTimeHash = nil,
    validUntilProgress = 0 -- Cache until significant progress change
  },

  -- Dynamic weights cache (changes slowly)
  dynamicWeights = {
    data = nil,
    lastProgressPhase = 0,
    validityDuration = 2.0 -- Valid for 2 seconds
  },

  -- Boss weighting cache (static for a given best time)
  bossWeighting = {
    data = nil,
    bestTimeHash = nil
  },

  -- Ensemble results cache
  ensembleResults = {
    data = nil,
    lastElapsedTime = 0,
    validityDuration = 1.0 -- Valid for 1 second
  },

  -- Last calculation timestamp for throttling
  lastCalculationTime = 0,

  -- UI update cache to prevent unnecessary recalculations
  lastUIUpdate = {
    data = nil,
    timestamp = 0,
    validityDuration = PERFORMANCE_CONFIG.uiUpdateThrottle
  },

  -- Time delta cache
  timeDelta = {
    data = nil,
    confidence = 0,
    timestamp = 0
  },
}

-- PERFORMANCE MONITORING: Track addon performance impact
local performanceMetrics = {
  calculationsThisSecond = 0,
  lastSecondReset = 0,
  totalCalculationTime = 0,
  calculationCount = 0,
  averageCalculationTime = 0,
  maxCalculationTime = 0,
  frameDropsDetected = 0
}

---PERFORMANCE: Check if we should skip calculations due to performance constraints
---@return boolean shouldSkip True if calculations should be skipped
local function shouldSkipCalculationsForPerformance()
  local now = GetTime()

  -- Reset per-second counter
  if now - performanceMetrics.lastSecondReset >= 1.0 then
    performanceMetrics.calculationsThisSecond = 0
    performanceMetrics.lastSecondReset = now
  end

  -- Check calculations per second limit
  if performanceMetrics.calculationsThisSecond >= PERFORMANCE_CONFIG.maxCalculationsPerSecond then
    return true
  end

  -- Check minimum interval between calculations
  if now - performanceCache.lastCalculationTime < PERFORMANCE_CONFIG.minUpdateInterval then
    return true
  end

  -- Check frame rate impact (skip calculations if FPS is low)
  local frameRate = GetFramerate()
  if frameRate < 30 then                                   -- If FPS drops below 30, reduce calculation frequency
    performanceMetrics.frameDropsDetected = performanceMetrics.frameDropsDetected + 1
    if performanceMetrics.frameDropsDetected % 3 ~= 0 then -- Only calculate every 3rd time
      return true
    end
  else
    performanceMetrics.frameDropsDetected = 0
  end

  return false
end

---PERFORMANCE: Measure calculation time and update metrics
---@param calculationTime number Time taken for calculation
local function updatePerformanceMetrics(calculationTime)
  performanceMetrics.totalCalculationTime = performanceMetrics.totalCalculationTime + calculationTime
  performanceMetrics.calculationCount = performanceMetrics.calculationCount + 1
  performanceMetrics.averageCalculationTime = performanceMetrics.totalCalculationTime /
      performanceMetrics.calculationCount

  if calculationTime > performanceMetrics.maxCalculationTime then
    performanceMetrics.maxCalculationTime = calculationTime
  end

  performanceMetrics.calculationsThisSecond = performanceMetrics.calculationsThisSecond + 1
  performanceCache.lastCalculationTime = GetTime()
end

---PERFORMANCE: Get optimized update interval based on run progress
---@param progressRatio number Current progress ratio (0-1)
---@return number interval Update interval in seconds
local function getAdaptiveUpdateInterval(progressRatio)
  if not PERFORMANCE_CONFIG.adaptiveUpdateInterval then
    return PERFORMANCE_CONFIG.minUpdateInterval
  end

  -- Early run: Update less frequently (every 2 seconds)
  if progressRatio < 0.2 then
    return 2.0
    -- Mid run: Normal frequency (every second)
  elseif progressRatio < 0.7 then
    return 1.0
    -- Late run: More frequent updates (every 0.5 seconds)
  else
    return 0.5
  end
end

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

---Extrapolate a run from source key level to target key level
---@param sourceRun table The source run data
---@param sourceKeyLevel number The source key level
---@param targetKeyLevel number The target key level
---@return table|nil extrapolatedRun The extrapolated run data or nil if invalid
function Calculator:ExtrapolateRunToKeyLevel(sourceRun, sourceKeyLevel, targetKeyLevel)
  if not sourceRun or not sourceKeyLevel or not targetKeyLevel then
    return nil
  end

  if sourceKeyLevel >= targetKeyLevel then
    return nil -- Can't extrapolate to lower/same level
  end

  -- Get scaling ratio using our Constants module
  local scalingRatio = PushMaster.Core.Constants:GetMythicPlusScalingRatio(sourceKeyLevel, targetKeyLevel)
  if not scalingRatio or scalingRatio <= 1.0 then
    return nil -- Invalid scaling ratio
  end

  -- Create a deep copy of the source run
  local extrapolatedRun = self:_deepCopyTable(sourceRun)

  -- Scale the total time
  extrapolatedRun.totalTime = sourceRun.totalTime * scalingRatio
  extrapolatedRun.keyLevel = targetKeyLevel

  -- Add extrapolation metadata
  extrapolatedRun.isExtrapolated = true
  extrapolatedRun.sourceKeyLevel = sourceKeyLevel
  extrapolatedRun.scalingRatio = scalingRatio
  extrapolatedRun.extrapolationConfidence = self:_calculateExtrapolationConfidence(sourceKeyLevel, targetKeyLevel)

  -- Scale timeline data if it exists
  if extrapolatedRun.timeline then
    for _, timepoint in ipairs(extrapolatedRun.timeline) do
      if timepoint.time then
        timepoint.time = timepoint.time * scalingRatio
      end
    end
  end

  -- Scale boss kill times if they exist
  if extrapolatedRun.bossKillTimes then
    for i, bossTime in ipairs(extrapolatedRun.bossKillTimes) do
      extrapolatedRun.bossKillTimes[i] = bossTime * scalingRatio
    end
  end

  -- Scale trash samples if they exist
  if extrapolatedRun.trashSamples then
    for _, sample in ipairs(extrapolatedRun.trashSamples) do
      if sample.time then
        sample.time = sample.time * scalingRatio
      end
    end
  end

  return extrapolatedRun
end

---Calculate confidence level for extrapolation based on key level gap
---@param sourceLevel number Source key level
---@param targetLevel number Target key level
---@return number confidence Confidence percentage (0-100)
function Calculator:_calculateExtrapolationConfidence(sourceLevel, targetLevel)
  local levelGap = targetLevel - sourceLevel

  -- Base confidence starts at 90% for 1 level gap
  local baseConfidence = 90

  -- Decrease confidence by 15% per additional level gap
  local confidencePenalty = (levelGap - 1) * 15

  -- Minimum confidence of 30%
  local confidence = math.max(30, baseConfidence - confidencePenalty)

  return confidence
end

---Deep copy a table (helper function)
---@param original table The table to copy
---@return table copy The deep copy
function Calculator:_deepCopyTable(original)
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original) do
    if type(value) == "table" then
      copy[key] = self:_deepCopyTable(value)
    else
      copy[key] = value
    end
  end
  return copy
end

---Enhanced GetBestTime function with extrapolation support
---@param dungeonID number|nil Dungeon ID (optional, uses current if nil)
---@param keyLevel number|nil Key level (optional, uses current if nil)
---@return table|nil bestTime The best time data (actual or extrapolated) or nil if none exists
function Calculator:GetBestTimeWithExtrapolation(dungeonID, keyLevel)
  -- Use current run data if parameters not provided
  if not dungeonID or not keyLevel then
    if not currentRun.instanceData then
      return nil
    end
    dungeonID = dungeonID or currentRun.instanceData.dungeonID
    keyLevel = keyLevel or currentRun.instanceData.cmLevel
  end

  -- First try to get exact match
  if bestTimes[dungeonID] and bestTimes[dungeonID][keyLevel] then
    return bestTimes[dungeonID][keyLevel]
  end

  -- If extrapolation is disabled, return nil
  if not PushMasterDB or not PushMasterDB.settings or not PushMasterDB.settings.enableExtrapolation then
    return nil
  end

  -- Try to find a timed run at lower key levels for extrapolation
  if PushMaster.Core.Database then
    local sourceRun, sourceLevel = PushMaster.Core.Database:GetBestRunForExtrapolation(dungeonID, keyLevel)
    if sourceRun and sourceLevel then
      local extrapolatedRun = self:ExtrapolateRunToKeyLevel(sourceRun, sourceLevel, keyLevel)
      if extrapolatedRun then
        PushMaster:DebugPrint(string.format("Extrapolated +%d data from +%d (%.1f%% confidence)",
          keyLevel, sourceLevel, extrapolatedRun.extrapolationConfidence))
        return extrapolatedRun
      end
    end
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

---ENHANCED: Main function called by UI to get current run comparison data
---Uses the complete enhanced algorithm with all optimizations
---@return table comparison data for UI display
function Calculator:GetCurrentComparison()
  -- PERFORMANCE: Check if we should skip calculations
  if shouldSkipCalculationsForPerformance() then
    if performanceCache.lastUIUpdate.data then
      return performanceCache.lastUIUpdate.data
    end
  end

  local startTime = GetTime()

  if not currentRun.isActive then
    return nil
  end

  local instanceData = currentRun.instanceData
  if not instanceData then
    return nil
  end

  -- Get current elapsed time (use stored time for test mode or real-time)
  local elapsedTime = currentRun.progress.elapsedTime
  if not elapsedTime or elapsedTime <= 0 then
    local currentTime = GetTime()
    if currentRun.startTime then
      elapsedTime = currentTime - currentRun.startTime
    else
      elapsedTime = 0
    end
  end

  -- Get best time data for comparison
  local bestTime = self:GetBestTimeWithExtrapolation(instanceData.dungeonID, instanceData.cmLevel)

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
  local timeDelta = 0
  local timeConfidence = 0

  if bestTime then
    -- ENHANCED: Use full adaptive algorithm with method selection
    local selectedMethod = self:GetBestCalculationMethod(currentRun, bestTime, elapsedTime)

    -- ENHANCED: Calculate using ensemble forecasting for maximum accuracy
    local ensembleResult = self:CalculateEnsembleForecast(currentRun, bestTime, elapsedTime)

    if ensembleResult then
      timeDelta = ensembleResult.timeDelta
      timeConfidence = ensembleResult.confidence

      -- Calculate individual progress metrics using adaptive weights
      local dynamicWeights = self:CalculateDynamicEfficiencyWeights(currentRun, bestTime, elapsedTime)
      local adaptiveBossWeights = self:CalculateAdaptiveBossWeighting(bestTime, currentRun, elapsedTime)

      -- Enhanced progress calculations
      trashProgress = self:CalculateTrashDelta(currentRun, bestTime, elapsedTime)
      bossProgress = self:CalculateBossDelta(currentRun, bestTime, elapsedTime)
      deathProgress = self:CalculateDeathDelta(currentRun, bestTime, elapsedTime)

      -- Calculate overall efficiency using enhanced algorithm
      progressEfficiency = self:CalculateOverallEfficiency(trashProgress, bossProgress, currentRun, bestTime, elapsedTime)

      -- Apply learning factor for continuous improvement
      progressEfficiency = self:ApplyEnhancedLearningFactor(progressEfficiency, currentRun, bestTime, elapsedTime)

      -- Apply display smoothing to reduce flickering
      timeDelta = self:ApplyDisplaySmoothing("timeDelta", timeDelta)
      progressEfficiency = self:ApplyDisplaySmoothing("efficiency", progressEfficiency)

      -- Track method performance for learning
      self:TrackMethodPerformance(selectedMethod.name, timeDelta, timeConfidence, currentRun, bestTime)

      -- ENHANCED: Detailed debug logging for the enhanced algorithm
      if PERFORMANCE_CONFIG.enableDebugLogging then
        PushMaster:DebugPrint(string.format(
          "ENHANCED ALGORITHM: Method=%s, Delta=%+.1fs, Confidence=%.0f%%, Efficiency=%.1f%%",
          selectedMethod.name, timeDelta, timeConfidence, progressEfficiency))
        PushMaster:DebugPrint(string.format(
          "  Progress: Trash=%.1f%%, Boss=%d, Deaths=%+d, Weights: T=%.2f B=%.2f D=%.2f",
          trashProgress, bossProgress, deathProgress,
          dynamicWeights.trash or 0, dynamicWeights.boss or 0, dynamicWeights.death or 0))
      end
    else
      -- Fallback to optimized calculation if ensemble fails
      local paceData = self:CalculateIntelligentPaceOptimized(currentRun, bestTime, elapsedTime)

      progressEfficiency = paceData.efficiency or 0
      trashProgress = paceData.trashDelta or 0
      bossProgress = paceData.bossDelta or 0
      deathProgress = paceData.deathDelta or 0

      timeDelta, timeConfidence = self:CalculateTimeDeltaOptimized(currentRun, bestTime, elapsedTime, progressEfficiency)

      if PERFORMANCE_CONFIG.enableDebugLogging then
        PushMaster:DebugPrint("Enhanced algorithm failed, using optimized fallback")
      end
    end
  else
    -- No comparison data available yet, provide default values
    if PERFORMANCE_CONFIG.enableDebugLogging then
      PushMaster:DebugPrint("No best time data available for enhanced comparison, using N/A values")
    end
    progressEfficiency = nil
    trashProgress = nil
    bossProgress = nil
    deathProgress = nil
    timeDelta = nil
    timeConfidence = 0
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

  local finalDeathProgress = deathProgress
  if finalDeathProgress ~= nil then
    finalDeathProgress = math.floor(finalDeathProgress + 0.5)
  end

  local finalOverallSpeed = progressEfficiency
  if finalOverallSpeed ~= nil then
    finalOverallSpeed = math.floor(finalOverallSpeed + 0.5)
  end

  -- Enhanced result structure with additional metadata
  local result = {
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
    bestComparison = bestTime,
    affixes = instanceData.affixes,
    -- Enhanced display metrics
    progressEfficiency = finalProgressEfficiency,
    trashProgress = finalTrashProgress,
    bossProgress = finalBossProgress,
    deathProgress = finalDeathProgress,
    deathTimePenalty = deathTimePenalty,
    -- Enhanced time prediction
    timeDelta = timeDelta,
    timeConfidence = timeConfidence,
    -- Backward compatibility
    overallSpeed = finalOverallSpeed,
    -- Enhanced metadata
    algorithmVersion = "Enhanced v2.0",
    calculationMethod = bestTime and "ensemble_enhanced" or "baseline",
    performanceGrade = performanceMetrics.emergencyModeActive and "Emergency" or "Optimal"
  }

  -- PERFORMANCE: Cache result for UI updates
  performanceCache.lastUIUpdate.data = result
  performanceCache.lastUIUpdate.timestamp = GetTime()

  -- PERFORMANCE: Track calculation time
  local calculationTime = GetTime() - startTime
  updatePerformanceMetrics(calculationTime)

  return result
end

---NEW: Phase 1 - Get the best calculation method based on available data
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table methodInfo Information about the selected method
function Calculator:GetBestCalculationMethod(currentRun, bestTime, elapsedTime)
  local availableMethods = {}

  -- Check trash interpolation method
  local trashSamples = bestTime.trashSamples or {}
  if #trashSamples >= ADAPTIVE_METHOD_CONFIG.trashInterpolation.minTrashSamples then
    local progressSpan = 0
    local maxGap = 0
    local lastTrash = 0

    for _, sample in ipairs(trashSamples) do
      if sample.trash > lastTrash then
        local gap = sample.trash - lastTrash
        if gap > maxGap then maxGap = gap end
        lastTrash = sample.trash
      end
    end

    progressSpan = lastTrash - (trashSamples[1] and trashSamples[1].trash or 0)

    if progressSpan >= ADAPTIVE_METHOD_CONFIG.trashInterpolation.progressRange and
        maxGap <= ADAPTIVE_METHOD_CONFIG.trashInterpolation.maxGapSize then
      table.insert(availableMethods, {
        name = "trash_interpolation",
        priority = ADAPTIVE_METHOD_CONFIG.trashInterpolation.priority,
        confidence = ADAPTIVE_METHOD_CONFIG.trashInterpolation.confidenceBonus,
        quality = progressSpan / maxGap -- Higher is better
      })
    end
  end

  -- Check weighted interpolation method
  if #trashSamples >= ADAPTIVE_METHOD_CONFIG.weightedInterpolation.minTrashSamples then
    table.insert(availableMethods, {
      name = "weighted_interpolation",
      priority = ADAPTIVE_METHOD_CONFIG.weightedInterpolation.priority,
      confidence = ADAPTIVE_METHOD_CONFIG.weightedInterpolation.confidenceBonus,
      quality = #trashSamples / 20 -- Normalize to 0-1 range
    })
  end

  -- Check boss count method
  local bossKillTimes = bestTime.bossKillTimes or {}
  if #bossKillTimes >= ADAPTIVE_METHOD_CONFIG.bossCountMethod.minBossData then
    table.insert(availableMethods, {
      name = "boss_count",
      priority = ADAPTIVE_METHOD_CONFIG.bossCountMethod.priority,
      confidence = ADAPTIVE_METHOD_CONFIG.bossCountMethod.confidenceBonus,
      quality = math.min(1, #bossKillTimes / 4) -- Assume 4 bosses max
    })
  end

  -- Always have proportional estimate as fallback
  table.insert(availableMethods, {
    name = "proportional_estimate",
    priority = ADAPTIVE_METHOD_CONFIG.proportionalEstimate.priority,
    confidence = ADAPTIVE_METHOD_CONFIG.proportionalEstimate.confidenceBonus,
    quality = 0.3 -- Low quality fallback
  })

  -- Sort by priority (lower number = higher priority)
  table.sort(availableMethods, function(a, b)
    if a.priority == b.priority then
      return a.quality > b.quality -- If same priority, prefer higher quality
    end
    return a.priority < b.priority
  end)

  local selectedMethod = availableMethods[1]

  PushMaster:DebugPrint(string.format("Selected calculation method: %s (priority %d, quality %.2f)",
    selectedMethod.name, selectedMethod.priority, selectedMethod.quality))

  return selectedMethod
end

---NEW: Phase 2 - Calculate dynamic efficiency weights based on progress and data quality
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table weights Dynamic weight configuration
function Calculator:CalculateDynamicEfficiencyWeights(currentRun, bestTime, elapsedTime)
  local currentTrash = currentRun.progress.trash
  local trashSamples = bestTime.trashSamples or {}
  local bossKillTimes = bestTime.bossKillTimes or {}

  -- Determine phase based on progress
  local phase
  if currentTrash < DYNAMIC_WEIGHT_CONFIG.earlyPhase.progressThreshold then
    phase = DYNAMIC_WEIGHT_CONFIG.earlyPhase
  elseif currentTrash < DYNAMIC_WEIGHT_CONFIG.midPhase.progressThreshold then
    phase = DYNAMIC_WEIGHT_CONFIG.midPhase
  else
    phase = DYNAMIC_WEIGHT_CONFIG.latePhase
  end

  -- Start with base weights from current phase
  local weights = {
    trashWeight = phase.trashWeight,
    bossTimingWeight = phase.bossTimingWeight,
    bossCountWeight = phase.bossCountWeight
  }

  -- Apply data quality multipliers
  local multipliers = DYNAMIC_WEIGHT_CONFIG.dataQualityMultipliers

  -- High trash samples bonus
  if #trashSamples >= multipliers.highTrashSamples.threshold then
    weights.trashWeight = weights.trashWeight + multipliers.highTrashSamples.trashBonus
  end

  -- Low trash samples penalty
  if #trashSamples <= multipliers.lowTrashSamples.threshold then
    weights.trashWeight = weights.trashWeight + multipliers.lowTrashSamples.trashPenalty
  end

  -- Consistent boss timing bonus
  if #bossKillTimes >= 2 then
    local consistency = self:CalculateBossTimingConsistency(bossKillTimes)
    if consistency >= multipliers.consistentBossTiming.threshold then
      weights.bossTimingWeight = weights.bossTimingWeight + multipliers.consistentBossTiming.bossBonus
    end
  end

  -- Normalize weights to ensure they sum to 1.0
  local totalWeight = weights.trashWeight + weights.bossTimingWeight + weights.bossCountWeight
  if totalWeight > 0 then
    weights.trashWeight = weights.trashWeight / totalWeight
    weights.bossTimingWeight = weights.bossTimingWeight / totalWeight
    weights.bossCountWeight = weights.bossCountWeight / totalWeight
  end

  PushMaster:DebugPrint(string.format(
    "Dynamic weights: Trash %.2f, BossTiming %.2f, BossCount %.2f (phase: %.0f%% progress)",
    weights.trashWeight, weights.bossTimingWeight, weights.bossCountWeight, currentTrash))

  return weights
end

---NEW: Phase 3 - Calculate adaptive boss weighting based on fight characteristics
---@param bestTime table Best time data
---@param currentRun table Current run data
---@param elapsedTime number Current elapsed time
---@return table bossWeights Adaptive boss weights
function Calculator:CalculateAdaptiveBossWeighting(bestTime, currentRun, elapsedTime)
  local bossKillTimes = bestTime.bossKillTimes or {}
  local instanceData = currentRun.instanceData
  local bossWeights = {}

  if #bossKillTimes == 0 then
    return { defaultWeight = 1.0 }
  end

  for i, bossKill in ipairs(bossKillTimes) do
    local weight = 1.0

    -- Duration-based weighting
    local fightDuration = self:EstimateBossFightDuration(bossKill, bossKillTimes, i)
    if fightDuration <= BOSS_WEIGHT_CONFIG.durationBased.shortFight.threshold then
      weight = weight * BOSS_WEIGHT_CONFIG.durationBased.shortFight.weight
    elseif fightDuration <= BOSS_WEIGHT_CONFIG.durationBased.mediumFight.threshold then
      weight = weight * BOSS_WEIGHT_CONFIG.durationBased.mediumFight.weight
    else
      weight = weight * BOSS_WEIGHT_CONFIG.durationBased.longFight.weight
    end

    -- Difficulty-based weighting
    local difficulty = self:EstimateBossDifficulty(i, #bossKillTimes)
    if difficulty == "final" then
      weight = weight * BOSS_WEIGHT_CONFIG.difficultyBased.finalBoss.weight
    elseif difficulty == "mini" then
      weight = weight * BOSS_WEIGHT_CONFIG.difficultyBased.miniBoss.weight
    else
      weight = weight * BOSS_WEIGHT_CONFIG.difficultyBased.standardBoss.weight
    end

    -- Consistency-based weighting
    local variance = self:CalculateBossTimingVariance(bossKill, bossKillTimes)
    if variance <= BOSS_WEIGHT_CONFIG.consistencyBased.lowVariance.threshold then
      weight = weight * BOSS_WEIGHT_CONFIG.consistencyBased.lowVariance.weight
    elseif variance >= BOSS_WEIGHT_CONFIG.consistencyBased.highVariance.threshold then
      weight = weight * BOSS_WEIGHT_CONFIG.consistencyBased.highVariance.weight
    end

    -- Adaptive adjustments based on current performance
    local currentEfficiency = self:GetCurrentPaceEfficiency(currentRun, bestTime, elapsedTime)
    if currentEfficiency > 0 then     -- Ahead of pace
      weight = weight + BOSS_WEIGHT_CONFIG.adaptiveAdjustments.aheadOfPace.bossWeightBonus
    elseif currentEfficiency < 0 then -- Behind pace
      weight = weight + BOSS_WEIGHT_CONFIG.adaptiveAdjustments.behindPace.bossWeightPenalty
    end

    -- Key level adjustments
    if instanceData and instanceData.cmLevel then
      if instanceData.cmLevel <= BOSS_WEIGHT_CONFIG.adaptiveAdjustments.lowKey.keyLevel then
        weight = weight + BOSS_WEIGHT_CONFIG.adaptiveAdjustments.lowKey.reliabilityBonus
      elseif instanceData.cmLevel >= BOSS_WEIGHT_CONFIG.adaptiveAdjustments.highKey.keyLevel then
        weight = weight * BOSS_WEIGHT_CONFIG.adaptiveAdjustments.highKey.stressMultiplier
      end
    end

    bossWeights[i] = math.max(0.1, weight) -- Ensure minimum weight
  end

  return bossWeights
end

---NEW: Phase 4 - Enhanced Calculate Time Delta with Learning and Ensemble Methods
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param progressEfficiency number Calculated progress efficiency
---@return number timeDelta Time difference in seconds (positive = behind, negative = ahead)
---@return number timeConfidence Enhanced confidence percentage (0-100)
function Calculator:CalculateTimeDelta(currentRun, bestTime, elapsedTime, progressEfficiency)
  if not bestTime then
    return nil, 0
  end

  -- Phase 1: Select best calculation method adaptively
  local methodInfo = self:GetBestCalculationMethod(currentRun, bestTime, elapsedTime)

  -- Calculate using selected method
  local timeDelta, baseConfidence = self:CalculateTimeDeltaUsingMethod(
    methodInfo.name, currentRun, bestTime, elapsedTime)

  -- Phase 4: Apply learning-based confidence adjustment
  local enhancedConfidence = self:CalculateEnhancedConfidence(
    baseConfidence, methodInfo, currentRun, bestTime, elapsedTime)

  -- Phase 4: Apply ensemble forecasting for high accuracy
  if enhancedConfidence >= 60 then
    local ensembleResults = self:CalculateEnsembleForecast(currentRun, bestTime, elapsedTime)
    if ensembleResults then
      -- Blend results based on confidence level
      local blendRatio = (enhancedConfidence - 60) / 40 -- 0 to 1 scale
      timeDelta = timeDelta * (1 - blendRatio) + ensembleResults.timeDelta * blendRatio
      enhancedConfidence = math.min(100, enhancedConfidence + ensembleResults.confidenceBonus)
    end
  end

  -- Phase 1: Apply display smoothing
  if ADAPTIVE_METHOD_CONFIG.smoothing.enabled then
    timeDelta = self:ApplyDisplaySmoothing("timeDelta", timeDelta)
    enhancedConfidence = self:ApplyDisplaySmoothing("confidence", enhancedConfidence)
  end

  -- Track method performance for learning
  self:TrackMethodPerformance(methodInfo.name, timeDelta, enhancedConfidence, currentRun)

  PushMaster:DebugPrint(string.format(
    "Enhanced Time Delta: %s method -> %+.0fs delta (%.0f%% confidence, ensemble applied: %s)",
    methodInfo.name, timeDelta, enhancedConfidence,
    enhancedConfidence >= 60 and "yes" or "no"))

  return timeDelta, enhancedConfidence
end

---NEW: Phase 2 - Enhanced Calculate Intelligent Pace with Dynamic Weights
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table paceData Enhanced pace calculation data
function Calculator:CalculateIntelligentPace(currentRun, bestTime, elapsedTime)
  -- Calculate individual deltas
  local trashDelta = self:CalculateTrashDelta(currentRun, bestTime, elapsedTime)
  local bossDelta = self:CalculateBossDelta(currentRun, bestTime, elapsedTime)
  local deathDelta = self:CalculateDeathDelta(currentRun, bestTime, elapsedTime)
  local bossTimingEfficiency = self:CalculateBossTimingEfficiency(currentRun, bestTime, elapsedTime)

  -- Phase 2: Calculate dynamic weights instead of static weights
  local dynamicWeights = self:CalculateDynamicEfficiencyWeights(currentRun, bestTime, elapsedTime)

  -- Phase 3: Calculate adaptive boss weighting
  local adaptiveBossWeights = self:CalculateAdaptiveBossWeighting(bestTime, currentRun, elapsedTime)

  -- Calculate weighted efficiency using dynamic weights
  local efficiency = 0

  -- Trash component with dynamic weighting
  efficiency = efficiency + (trashDelta * dynamicWeights.trashWeight)

  -- Boss timing component with dynamic weighting
  efficiency = efficiency + (bossTimingEfficiency * dynamicWeights.bossTimingWeight)

  -- Boss count component with adaptive weighting
  local adaptiveBossCountImpact = self:CalculateAdaptiveBossCountImpact(
    bossDelta, currentRun, bestTime, elapsedTime, adaptiveBossWeights)
  efficiency = efficiency + (adaptiveBossCountImpact * dynamicWeights.bossCountWeight)

  -- Apply death penalty impact
  local currentDeathTimePenalty = currentRun.progress.timeLostToDeaths or 0
  local bestRunDeathTimePenalty = self:CalculateBestRunDeathPenalty(bestTime, elapsedTime)

  local deathTimeDelta = currentDeathTimePenalty - bestRunDeathTimePenalty
  local deathImpact = 0
  if bestTime.time > 0 then
    deathImpact = -(deathTimeDelta / bestTime.time) * 100
    efficiency = efficiency + deathImpact
  end

  -- Phase 4: Apply learning factor
  efficiency = self:ApplyEnhancedLearningFactor(efficiency, currentRun, bestTime, elapsedTime)

  -- Cap to reasonable bounds
  efficiency = math.max(-100, math.min(100, efficiency))

  PushMaster:DebugPrint(string.format(
    "Enhanced Intelligent Pace: Trash %.1f%% (w=%.2f), BossTiming %.1f%% (w=%.2f), BossCount %.1f%% (w=%.2f), Deaths %.1f%%, Final %.1f%%",
    trashDelta, dynamicWeights.trashWeight,
    bossTimingEfficiency, dynamicWeights.bossTimingWeight,
    adaptiveBossCountImpact, dynamicWeights.bossCountWeight,
    deathImpact, efficiency))

  return {
    efficiency = efficiency,
    trashDelta = trashDelta,
    bossDelta = bossDelta,
    deathDelta = deathDelta,
    bossTimingEfficiency = bossTimingEfficiency,
    adaptiveBossCountImpact = adaptiveBossCountImpact,
    deathImpact = deathImpact,
    weights = dynamicWeights,
    bossWeights = adaptiveBossWeights
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

---NEW: Helper function to calculate time delta using specific method
---@param method string The calculation method to use
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number timeDelta Time difference in seconds
---@return number confidence Base confidence level
function Calculator:CalculateTimeDeltaUsingMethod(method, currentRun, bestTime, elapsedTime)
  local currentTrash = currentRun.progress.trash
  local currentBosses = currentRun.progress.bosses
  local bestRunTimeAtSimilarProgress = nil
  local confidence = 50 -- Base confidence

  if method == "trash_interpolation" then
    -- Enhanced interpolation with better precision
    local trashSamples = bestTime.trashSamples or {}
    local lower = { time = 0, trash = 0 }
    local upper = { time = bestTime.time, trash = 100 }

    for _, sample in ipairs(trashSamples) do
      if sample.trash <= currentTrash and sample.trash >= lower.trash then
        lower = sample
      elseif sample.trash >= currentTrash and sample.trash <= upper.trash then
        upper = sample
      end
    end

    if upper.time > lower.time and upper.trash > lower.trash then
      local trashProgress = (currentTrash - lower.trash) / (upper.trash - lower.trash)
      bestRunTimeAtSimilarProgress = lower.time + (upper.time - lower.time) * trashProgress
      confidence = 85
    end
  elseif method == "weighted_interpolation" then
    -- Time-weighted average of nearby trash points
    local trashSamples = bestTime.trashSamples or {}
    local totalWeight = 0
    local weightedTime = 0

    for _, sample in ipairs(trashSamples) do
      local trashDiff = math.abs(sample.trash - currentTrash)
      if trashDiff <= 10 then              -- Within 10% trash difference
        local weight = 1 / (trashDiff + 1) -- Higher weight for closer matches
        totalWeight = totalWeight + weight
        weightedTime = weightedTime + (sample.time * weight)
      end
    end

    if totalWeight > 0 then
      bestRunTimeAtSimilarProgress = weightedTime / totalWeight
      confidence = 75
    end
  elseif method == "boss_count" then
    -- Boss count method
    if currentBosses > 0 and bestTime.bossKillTimes and currentBosses <= #bestTime.bossKillTimes then
      local bossKill = bestTime.bossKillTimes[currentBosses]
      if bossKill and bossKill.killTime then
        bestRunTimeAtSimilarProgress = bossKill.killTime
        confidence = 60
      end
    end
  else -- proportional_estimate
    local estimatedProgress = math.max(currentTrash / 100, currentBosses / 4)
    estimatedProgress = math.min(estimatedProgress, 0.95)
    bestRunTimeAtSimilarProgress = bestTime.time * estimatedProgress
    confidence = 30
  end

  if not bestRunTimeAtSimilarProgress then
    return nil, 0
  end

  local timeDelta = elapsedTime - bestRunTimeAtSimilarProgress
  return timeDelta, confidence
end

---NEW: Calculate enhanced confidence using learning data
---@param baseConfidence number Base confidence from method
---@param methodInfo table Information about selected method
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number enhancedConfidence Enhanced confidence level
function Calculator:CalculateEnhancedConfidence(baseConfidence, methodInfo, currentRun, bestTime, elapsedTime)
  local confidence = baseConfidence

  -- Base confidence on run progress
  local progressRatio = elapsedTime / bestTime.time
  progressRatio = math.max(0, math.min(1, progressRatio))

  -- Progress-based confidence scaling
  if progressRatio < 0.1 then
    confidence = confidence * 0.6 -- Very early, reduce confidence
  elseif progressRatio < 0.3 then
    confidence = confidence * 0.8 -- Early run
  elseif progressRatio > 0.7 then
    confidence = confidence * 1.2 -- Late run, boost confidence
  end

  -- Method quality bonus
  confidence = confidence + (methodInfo.confidence or 0)

  -- Historical accuracy adjustment (Phase 4 Learning)
  local methodAccuracy = adaptiveState.methodAccuracy[methodInfo.name]
  if methodAccuracy and methodAccuracy.avgAccuracy then
    local accuracyBonus = (methodAccuracy.avgAccuracy - 0.7) * 30 -- Scale 70%+ accuracy to bonus
    confidence = confidence + accuracyBonus
  end

  -- Data quality considerations
  local trashSamples = bestTime.trashSamples or {}
  if #trashSamples > 15 then
    confidence = confidence + 10 -- Good data quality bonus
  elseif #trashSamples < 5 then
    confidence = confidence - 15 -- Poor data quality penalty
  end

  return math.max(10, math.min(100, confidence))
end

---NEW: Calculate ensemble forecast combining multiple methods
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table|nil ensembleResults Combined forecast results
function Calculator:CalculateEnsembleForecast(currentRun, bestTime, elapsedTime)
  local methods = { "trash_interpolation", "weighted_interpolation", "boss_count", "proportional_estimate" }
  local results = {}
  local totalWeight = 0

  -- Calculate results from multiple methods
  for _, method in ipairs(methods) do
    local timeDelta, confidence = self:CalculateTimeDeltaUsingMethod(method, currentRun, bestTime, elapsedTime)
    if timeDelta and confidence > 20 then -- Only use reasonable confidence methods
      local weight = confidence / 100
      table.insert(results, {
        timeDelta = timeDelta,
        weight = weight,
        method = method
      })
      totalWeight = totalWeight + weight
    end
  end

  if #results < 2 or totalWeight == 0 then
    return nil -- Need at least 2 methods for ensemble
  end

  -- Calculate weighted average
  local weightedTimeDelta = 0
  for _, result in ipairs(results) do
    weightedTimeDelta = weightedTimeDelta + (result.timeDelta * result.weight / totalWeight)
  end

  -- Calculate ensemble confidence bonus
  local agreementBonus = 0
  local deltaVariance = 0
  for _, result in ipairs(results) do
    deltaVariance = deltaVariance + math.abs(result.timeDelta - weightedTimeDelta)
  end
  deltaVariance = deltaVariance / #results

  -- Lower variance = higher agreement = higher confidence bonus
  if deltaVariance < 30 then -- Methods agree within 30 seconds
    agreementBonus = 15
  elseif deltaVariance < 60 then
    agreementBonus = 8
  else
    agreementBonus = 2
  end

  return {
    timeDelta = weightedTimeDelta,
    confidenceBonus = agreementBonus,
    methodCount = #results,
    variance = deltaVariance
  }
end

---NEW: Apply display smoothing to reduce flickering
---@param valueType string Type of value being smoothed
---@param newValue number New calculated value
---@return number smoothedValue Smoothed value
function Calculator:ApplyDisplaySmoothing(valueType, newValue)
  if not ADAPTIVE_METHOD_CONFIG.smoothing.enabled then
    return newValue
  end

  local smoothingWindow = adaptiveState.smoothingWindow[valueType] or {}
  local lastValues = adaptiveState.lastCalculatedValues[valueType] or {}

  -- Add new value to window
  table.insert(smoothingWindow, newValue)

  -- Maintain window size
  local windowSize = ADAPTIVE_METHOD_CONFIG.smoothing.windowSize
  while #smoothingWindow > windowSize do
    table.remove(smoothingWindow, 1)
  end

  -- Calculate weighted average with decay
  local totalWeight = 0
  local weightedSum = 0
  local decay = ADAPTIVE_METHOD_CONFIG.smoothing.weightDecay

  for i = #smoothingWindow, 1, -1 do
    local weight = math.pow(decay, #smoothingWindow - i)
    totalWeight = totalWeight + weight
    weightedSum = weightedSum + (smoothingWindow[i] * weight)
  end

  local smoothedValue = totalWeight > 0 and (weightedSum / totalWeight) or newValue

  -- Store for next iteration
  adaptiveState.smoothingWindow[valueType] = smoothingWindow
  adaptiveState.lastCalculatedValues[valueType] = smoothedValue

  return smoothedValue
end

---NEW: Track method performance for learning
---@param methodName string Name of the method used
---@param timeDelta number Calculated time delta
---@param confidence number Confidence level
---@param currentRun table Current run data
function Calculator:TrackMethodPerformance(methodName, timeDelta, confidence, currentRun)
  if not adaptiveState.methodAccuracy[methodName] then
    adaptiveState.methodAccuracy[methodName] = {
      uses = 0,
      totalAccuracy = 0,
      avgAccuracy = 0,
      lastUpdated = GetTime()
    }
  end

  local method = adaptiveState.methodAccuracy[methodName]
  method.uses = method.uses + 1
  method.lastUpdated = GetTime()

  -- For now, just track usage. In a full implementation, this would
  -- compare predictions against actual outcomes at run completion

  -- Placeholder accuracy calculation based on confidence
  -- In practice, this would be calculated after run completion
  if confidence and confidence > 0 then
    local estimatedAccuracy = confidence / 100
    method.totalAccuracy = method.totalAccuracy + estimatedAccuracy
    method.avgAccuracy = method.totalAccuracy / method.uses
  else
    -- If no confidence data, don't update accuracy metrics
    -- Just track usage count
  end
end

---NEW: Calculate boss timing consistency for dynamic weighting
---@param bossKillTimes table Boss kill times data
---@return number consistency Consistency score (0-1)
function Calculator:CalculateBossTimingConsistency(bossKillTimes)
  if #bossKillTimes < 2 then
    return 0
  end

  -- Calculate variance in boss spacing
  local spacings = {}
  for i = 2, #bossKillTimes do
    local spacing = bossKillTimes[i].killTime - bossKillTimes[i - 1].killTime
    table.insert(spacings, spacing)
  end

  if #spacings == 0 then
    return 0
  end

  local avgSpacing = 0
  for _, spacing in ipairs(spacings) do
    avgSpacing = avgSpacing + spacing
  end
  avgSpacing = avgSpacing / #spacings

  local variance = 0
  for _, spacing in ipairs(spacings) do
    variance = variance + math.pow(spacing - avgSpacing, 2)
  end
  variance = variance / #spacings

  local stdDev = math.sqrt(variance)
  local consistency = math.max(0, 1 - (stdDev / avgSpacing))

  return consistency
end

---NEW: Estimate boss fight duration for adaptive weighting
---@param bossKill table Boss kill data
---@param allBossKills table All boss kill times
---@param bossIndex number Index of this boss
---@return number duration Estimated fight duration
function Calculator:EstimateBossFightDuration(bossKill, allBossKills, bossIndex)
  local killTime = bossKill.killTime
  local startTime = 0

  -- Estimate when fight started (previous boss kill time or start of run)
  if bossIndex > 1 and allBossKills[bossIndex - 1] then
    startTime = allBossKills[bossIndex - 1].killTime
  end

  -- Assume 80% of time between bosses is travel/trash, 20% is fight
  local timeBetween = killTime - startTime
  local estimatedFightDuration = timeBetween * 0.2

  -- Clamp to reasonable bounds (10s minimum, 300s maximum)
  return math.max(10, math.min(300, estimatedFightDuration))
end

---NEW: Estimate boss difficulty for adaptive weighting
---@param bossIndex number Index of boss (1-based)
---@param totalBosses number Total number of bosses
---@return string difficulty Difficulty level ("mini", "standard", "final")
function Calculator:EstimateBossDifficulty(bossIndex, totalBosses)
  if bossIndex == totalBosses then
    return "final"
  elseif totalBosses >= 4 and bossIndex == 1 then
    return "mini" -- First boss in 4+ boss dungeon often easier
  else
    return "standard"
  end
end

---NEW: Calculate boss timing variance for consistency weighting
---@param bossKill table Specific boss kill data
---@param allBossKills table All boss kill times
---@return number variance Timing variance score
function Calculator:CalculateBossTimingVariance(bossKill, allBossKills)
  -- Simple implementation: return fixed variance based on position
  -- In practice, this would analyze historical data for this boss
  local avgVariance = 15 -- Assume 15 second average variance
  return avgVariance
end

---NEW: Get current pace efficiency for adaptive adjustments
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number efficiency Current efficiency vs best run
function Calculator:GetCurrentPaceEfficiency(currentRun, bestTime, elapsedTime)
  local expectedTime = (currentRun.progress.trash / 100) * bestTime.time
  local efficiency = (expectedTime - elapsedTime) / bestTime.time * 100
  return efficiency
end

---NEW: Calculate adaptive boss count impact using boss weights
---@param bossDelta number Raw boss count delta
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param bossWeights table Adaptive boss weights
---@return number impact Weighted boss count impact
function Calculator:CalculateAdaptiveBossCountImpact(bossDelta, currentRun, bestTime, elapsedTime, bossWeights)
  if bossDelta == 0 then
    return 0
  end

  -- Use average boss weight if specific weights not available
  local avgWeight = 1.0
  if bossWeights and type(bossWeights) == "table" then
    local totalWeight = 0
    local weightCount = 0
    for _, weight in pairs(bossWeights) do
      if type(weight) == "number" then
        totalWeight = totalWeight + weight
        weightCount = weightCount + 1
      end
    end
    if weightCount > 0 then
      avgWeight = totalWeight / weightCount
    end
  end

  -- Each boss ahead/behind has impact scaled by average weight
  local baseImpact = bossDelta * 5 -- 5% impact per boss difference
  return baseImpact * avgWeight
end

---NEW: Calculate best run death penalty at elapsed time
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number penalty Total death time penalty from best run
function Calculator:CalculateBestRunDeathPenalty(bestTime, elapsedTime)
  local penalty = 0
  local deathTimes = bestTime.deathTimes or {}

  for _, deathTime in ipairs(deathTimes) do
    if deathTime <= elapsedTime then
      penalty = penalty + 15 -- 15 second penalty per death
    end
  end

  return penalty
end

---NEW: Apply enhanced learning factor with pattern recognition
---@param baseEfficiency number Base calculated efficiency
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return number adjustedEfficiency Learning-adjusted efficiency
function Calculator:ApplyEnhancedLearningFactor(baseEfficiency, currentRun, bestTime, elapsedTime)
  -- For now, return base efficiency with minimal learning adjustment
  -- Future enhancement: Pattern recognition for route changes, etc.

  local learningAdjustment = 0

  -- Simple learning: slightly boost confidence if we have historical data
  if adaptiveState.recentRuns and #adaptiveState.recentRuns > 5 then
    learningAdjustment = 2 -- Small bonus for having learning data
  end

  return baseEfficiency + learningAdjustment
end

---Calculate time delta and confidence
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param progressEfficiency number Calculated progress efficiency
---@return number timeDelta Time difference in seconds (positive = behind, negative = ahead)
---@return number timeConfidence Confidence percentage (0-100)
function Calculator:CalculateTimeDelta_Legacy(currentRun, bestTime, elapsedTime, progressEfficiency)
  if not bestTime then
    return nil, 0 -- No data available
  end

  -- Method: Direct pace comparison based on current progress
  -- Find what time the best run had at our current progress level
  local currentTrash = currentRun.progress.trash
  local currentBosses = currentRun.progress.bosses

  -- Find the best run's time when it had similar progress
  local bestRunTimeAtSimilarProgress = nil
  local calculationMethod = "none"
  local methodDetails = ""

  -- First try to match by trash percentage (most accurate for most of the run)
  if bestTime.trashSamples and #bestTime.trashSamples > 0 then
    -- Use interpolation for more accurate results instead of just finding first match
    local lower = { time = 0, trash = 0 }
    local upper = { time = bestTime.time, trash = 100 }

    for _, sample in ipairs(bestTime.trashSamples) do
      if sample.trash <= currentTrash and sample.trash >= lower.trash then
        lower = sample
      elseif sample.trash >= currentTrash and sample.trash <= upper.trash then
        upper = sample
      end
    end

    -- Interpolate between samples for smoother calculation
    if upper.time > lower.time and upper.trash > lower.trash then
      local trashProgress = (currentTrash - lower.trash) / (upper.trash - lower.trash)
      bestRunTimeAtSimilarProgress = lower.time + (upper.time - lower.time) * trashProgress
      calculationMethod = "trash_interpolation"
      methodDetails = string.format("%.1f%% between samples at %.1fs-%.1fs", currentTrash, lower.time, upper.time)
    elseif lower.trash == currentTrash then
      bestRunTimeAtSimilarProgress = lower.time
      calculationMethod = "trash_exact"
      methodDetails = string.format("%.1f%% exact match at %.1fs", currentTrash, lower.time)
    end
  end

  -- If we couldn't match by trash, try to match by boss count
  if not bestRunTimeAtSimilarProgress and bestTime.bossKillTimes then
    if currentBosses > 0 and currentBosses <= #bestTime.bossKillTimes then
      local bossKill = bestTime.bossKillTimes[currentBosses]
      if bossKill and bossKill.killTime then
        bestRunTimeAtSimilarProgress = bossKill.killTime
        calculationMethod = "boss_count"
        methodDetails = string.format("%d bosses at %.1fs", currentBosses, bossKill.killTime)
      end
    end
  end

  -- If we still don't have a comparison point, fall back to proportional estimate
  if not bestRunTimeAtSimilarProgress then
    -- Estimate based on overall completion percentage
    local estimatedProgress = math.max(currentTrash / 100, currentBosses / 4) -- Assume 4 bosses max
    estimatedProgress = math.min(estimatedProgress, 0.95)                     -- Cap at 95% to avoid division issues
    bestRunTimeAtSimilarProgress = bestTime.time * estimatedProgress
    calculationMethod = "proportional"
    methodDetails = string.format("%.1f%% estimated progress", estimatedProgress * 100)
  end

  -- Calculate direct time difference at this progress point
  local timeDelta = elapsedTime - bestRunTimeAtSimilarProgress

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

  -- Adjust confidence based on calculation method
  if calculationMethod == "trash_interpolation" then
    confidence = math.min(100, confidence + 15) -- Highest confidence
  elseif calculationMethod == "trash_exact" then
    confidence = math.min(100, confidence + 10) -- High confidence
  elseif calculationMethod == "boss_count" then
    confidence = math.max(20, confidence - 10)  -- Lower confidence
  else                                          -- proportional
    confidence = math.max(10, confidence - 20)  -- Lowest confidence
  end

  -- Boost confidence if we have good trash sample data
  if bestTime.trashSamples and #bestTime.trashSamples > 10 then
    confidence = math.min(100, confidence + 5)
  end

  -- Reduce confidence if time delta is extremely large (likely inaccurate)
  local deltaMinutes = math.abs(timeDelta) / 60
  if deltaMinutes > 10 then
    confidence = confidence * 0.3 -- Very extreme delta, likely calculation error
  elseif deltaMinutes > 5 then
    confidence = confidence * 0.7 -- Large delta, reduce confidence
  end

  -- Ensure confidence is within bounds
  confidence = math.max(0, math.min(100, confidence))

  -- Enhanced debug logging with method information
  PushMaster:DebugPrint(string.format(
    "Time Delta: %s method (%s) -> %+.0fs delta vs best run (%.0f%% confidence)",
    calculationMethod, methodDetails, timeDelta, confidence))

  return timeDelta, confidence
end

---PERFORMANCE OPTIMIZED: Calculate intelligent pace with enhanced caching
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@return table paceData Pace calculation result
function Calculator:CalculateIntelligentPaceOptimized(currentRun, bestTime, elapsedTime)
  -- PERFORMANCE: Check dynamic weights cache first
  local cacheKey = string.format("weights_%d_%.1f_%.1f",
    currentRun.progress.trash, currentRun.progress.bosses, elapsedTime)

  local cached = performanceCache.dynamicWeights[cacheKey]
  if cached and (GetTime() - cached.timestamp) < 5.0 then -- 5 second cache
    -- Use cached weights to calculate deltas
    local trashDelta = cached.trashWeight > 0 and self:CalculateTrashDelta(currentRun, bestTime) or 0
    local bossDelta = cached.bossWeight > 0 and self:CalculateBossDelta(currentRun, bestTime) or 0
    local deathDelta = cached.deathWeight > 0 and self:CalculateDeathDelta(currentRun, bestTime) or 0

    local efficiency = (trashDelta * cached.trashWeight) +
        (bossDelta * cached.bossWeight) +
        (deathDelta * cached.deathWeight)

    return {
      efficiency = efficiency,
      trashDelta = trashDelta,
      bossDelta = bossDelta,
      deathDelta = deathDelta,
      weights = cached.weights
    }
  end

  -- PERFORMANCE: Simplified dynamic weights calculation
  local progressRatio = math.min(currentRun.progress.trash / 100, 1.0)
  local weights = {
    trash = 0.4 + (progressRatio * 0.3), -- 40% to 70% based on progress
    boss = 0.3 - (progressRatio * 0.1),  -- 30% to 20% based on progress
    death = 0.3                          -- Constant 30%
  }

  -- Normalize weights to sum to 1.0
  local total = weights.trash + weights.boss + weights.death
  weights.trash = weights.trash / total
  weights.boss = weights.boss / total
  weights.death = weights.death / total

  -- Calculate deltas
  local trashDelta = self:CalculateTrashDelta(currentRun, bestTime)
  local bossDelta = self:CalculateBossDelta(currentRun, bestTime)
  local deathDelta = self:CalculateDeathDelta(currentRun, bestTime)

  local efficiency = (trashDelta * weights.trash) +
      (bossDelta * weights.boss) +
      (deathDelta * weights.death)

  -- Cache the result
  performanceCache.dynamicWeights[cacheKey] = {
    trashWeight = weights.trash,
    bossWeight = weights.boss,
    deathWeight = weights.death,
    weights = weights,
    timestamp = GetTime()
  }

  return {
    efficiency = efficiency,
    trashDelta = trashDelta,
    bossDelta = bossDelta,
    deathDelta = deathDelta,
    weights = weights
  }
end

---PERFORMANCE OPTIMIZED: Calculate time delta with enhanced performance
---@param currentRun table Current run data
---@param bestTime table Best time data
---@param elapsedTime number Current elapsed time
---@param efficiency number|nil Current efficiency score
---@return number, number timeDelta, confidence
function Calculator:CalculateTimeDeltaOptimized(currentRun, bestTime, elapsedTime, efficiency)
  if not bestTime or not bestTime.progress then
    return 0, 0
  end

  -- PERFORMANCE: Check cache first
  local cacheKey = string.format("delta_%.1f_%.1f_%d",
    elapsedTime, currentRun.progress.trash, currentRun.progress.bosses)

  local cached = performanceCache.timeDelta[cacheKey]
  if cached and (GetTime() - cached.timestamp) < 3.0 then -- 3 second cache
    return cached.delta, cached.confidence
  end

  local currentProgress = currentRun.progress.trash
  local currentBosses = currentRun.progress.bosses

  -- Simple interpolation method for performance
  local bestProgress = bestTime.progress
  local interpolatedTime = 0
  local confidence = 50 -- Base confidence

  if bestProgress and #bestProgress > 0 then
    -- Find closest progress points
    local closestBefore, closestAfter = nil, nil

    for _, sample in ipairs(bestProgress) do
      if sample.trash <= currentProgress then
        if not closestBefore or sample.trash > closestBefore.trash then
          closestBefore = sample
        end
      else
        if not closestAfter or sample.trash < closestAfter.trash then
          closestAfter = sample
        end
      end
    end

    -- Interpolate between closest points
    if closestBefore and closestAfter then
      local ratio = (currentProgress - closestBefore.trash) / (closestAfter.trash - closestBefore.trash)
      interpolatedTime = closestBefore.time + (ratio * (closestAfter.time - closestBefore.time))
      confidence = 75 -- Good interpolation
    elseif closestBefore then
      interpolatedTime = closestBefore.time
      confidence = 60 -- Extrapolation
    elseif closestAfter then
      interpolatedTime = closestAfter.time
      confidence = 40 -- Early extrapolation
    end
  end

  local timeDelta = elapsedTime - interpolatedTime

  -- Apply efficiency adjustment if available
  if efficiency and efficiency ~= 0 then
    local efficiencyFactor = 1.0 + ((efficiency - 100) / 200) -- Convert efficiency to multiplier
    timeDelta = timeDelta * efficiencyFactor
    confidence = math.min(confidence + 10, 95)                -- Bonus confidence for efficiency data
  end

  -- Cache the result
  performanceCache.timeDelta[cacheKey] = {
    delta = timeDelta,
    confidence = confidence,
    timestamp = GetTime()
  }

  return timeDelta, confidence
end

---PERFORMANCE OPTIMIZED: Calculate boss timing efficiency with limited processing
---@param currentRun table Current run data
---@param bestTime table Best time data
---@return number efficiency Timing efficiency percentage
function Calculator:CalculateBossTimingEfficiencyOptimized(currentRun, bestTime)
  if not bestTime or not bestTime.bosses or not currentRun.bosses then
    return 100
  end

  local totalEfficiency = 0
  local bossCount = 0
  local maxBossesToProcess = 3 -- PERFORMANCE: Limit processing to 3 bosses

  for i = 1, math.min(#currentRun.bosses, #bestTime.bosses, maxBossesToProcess) do
    local currentBoss = currentRun.bosses[i]
    local bestBoss = bestTime.bosses[i]

    if currentBoss.killTime and bestBoss.killTime then
      local timeDiff = currentBoss.killTime - bestBoss.killTime
      local efficiency = 100 - (timeDiff / bestBoss.killTime * 100)
      totalEfficiency = totalEfficiency + math.max(0, math.min(200, efficiency))
      bossCount = bossCount + 1
    end
  end

  return bossCount > 0 and totalEfficiency / bossCount or 100
end

---PERFORMANCE OPTIMIZED: Calculate dynamic efficiency weights with simplified logic
---@param currentRun table Current run data
---@param bestTime table Best time data
---@return table weights Dynamic weight configuration
function Calculator:CalculateDynamicEfficiencyWeightsOptimized(currentRun, bestTime)
  local progressRatio = math.min(currentRun.progress.trash / 100, 1.0)

  -- Simplified weight determination based on progress
  local baseWeights
  if progressRatio < 0.3 then
    -- Early run: Focus on trash and boss timing
    baseWeights = { trash = 0.5, boss = 0.4, death = 0.1 }
  elseif progressRatio < 0.7 then
    -- Mid run: Balanced approach
    baseWeights = { trash = 0.4, boss = 0.3, death = 0.3 }
  else
    -- Late run: Focus on completion and deaths
    baseWeights = { trash = 0.3, boss = 0.2, death = 0.5 }
  end

  -- PERFORMANCE: Simple data quality adjustment
  local dataQuality = 1.0
  if bestTime and bestTime.totalTime then
    dataQuality = math.min(1.2, 1.0 + (bestTime.completionCount or 0) * 0.1)
  end

  -- Apply data quality factor
  for key, weight in pairs(baseWeights) do
    baseWeights[key] = weight * dataQuality
  end

  -- Normalize to sum to 1.0
  local total = baseWeights.trash + baseWeights.boss + baseWeights.death
  for key, weight in pairs(baseWeights) do
    baseWeights[key] = weight / total
  end

  return baseWeights
end

---PERFORMANCE: Clean up old cache entries to prevent memory leaks
---@param maxAge number Maximum age in seconds for cache entries
local function cleanupPerformanceCache(maxAge)
  local currentTime = GetTime()
  maxAge = maxAge or 300 -- Default 5 minutes

  -- Known configuration keys that should not be cleaned up
  local configKeys = {
    data = true,
    validityDuration = true,
    lastProgressPhase = true,
    bestTimeHash = true,
    validUntilProgress = true,
    lastElapsedTime = true,
    timestamp = true,
    confidence = true
  }

  -- Clean up dynamic weights cache
  for key, entry in pairs(performanceCache.dynamicWeights) do
    if not configKeys[key] and type(entry) == "table" and entry.timestamp and currentTime - entry.timestamp > maxAge then
      performanceCache.dynamicWeights[key] = nil
    end
  end

  -- Clean up time delta cache
  for key, entry in pairs(performanceCache.timeDelta) do
    if not configKeys[key] and type(entry) == "table" and entry.timestamp and currentTime - entry.timestamp > maxAge then
      performanceCache.timeDelta[key] = nil
    end
  end

  -- Clean up boss weighting cache
  for key, entry in pairs(performanceCache.bossWeighting) do
    if not configKeys[key] and type(entry) == "table" and entry.timestamp and currentTime - entry.timestamp > maxAge then
      performanceCache.bossWeighting[key] = nil
    end
  end

  -- Clean up ensemble cache
  for key, entry in pairs(performanceCache.ensembleResults) do
    if not configKeys[key] and type(entry) == "table" and entry.timestamp and currentTime - entry.timestamp > maxAge then
      performanceCache.ensembleResults[key] = nil
    end
  end

  -- Clean up method selection cache
  for key, entry in pairs(performanceCache.methodSelection) do
    if not configKeys[key] and type(entry) == "table" and entry.timestamp and currentTime - entry.timestamp > maxAge then
      performanceCache.methodSelection[key] = nil
    end
  end
end

---PERFORMANCE: Monitor and report performance metrics
local function reportPerformanceMetrics()
  if not PERFORMANCE_CONFIG.enablePerformanceMonitoring then
    return
  end

  local metrics = performanceMetrics
  local avgCalculationTime = metrics.totalCalculationTime / math.max(1, metrics.calculationsThisSecond)

  -- Report if performance is concerning
  if avgCalculationTime > 0.01 or metrics.frameDropsDetected > 0 then
    PushMaster:DebugPrint(string.format("PERFORMANCE WARNING: Avg calc time: %.3fms, Frame drops: %d, Calcs/sec: %d",
      avgCalculationTime * 1000, metrics.frameDropsDetected, metrics.calculationsThisSecond))
  end

  -- Reset metrics for next period
  metrics.calculationsThisSecond = 0
  metrics.totalCalculationTime = 0
  metrics.frameDropsDetected = 0
  metrics.lastResetTime = GetTime()
end

---PERFORMANCE: Initialize performance monitoring
local function initializePerformanceMonitoring()
  -- Set up cleanup timer
  local cleanupFrame = CreateFrame("Frame")
  cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer >= 60 then       -- Clean up every minute
      cleanupPerformanceCache(300) -- Remove entries older than 5 minutes
      self.timer = 0
    end
  end)

  -- Set up performance reporting timer
  local reportFrame = CreateFrame("Frame")
  reportFrame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer >= 30 then -- Report every 30 seconds
      reportPerformanceMetrics()
      self.timer = 0
    end
  end)

  PushMaster:DebugPrint("Performance monitoring initialized")
end

---PERFORMANCE: Emergency performance mode when frame rate drops
local function activateEmergencyPerformanceMode()
  if performanceMetrics.emergencyModeActive then
    return -- Already active
  end

  performanceMetrics.emergencyModeActive = true

  -- Reduce calculation frequency
  PERFORMANCE_CONFIG.maxCalculationsPerSecond = 2
  PERFORMANCE_CONFIG.minUpdateInterval = 0.5

  -- Disable debug logging
  PERFORMANCE_CONFIG.enableDebugLogging = false

  -- Clear all caches to free memory
  performanceCache.dynamicWeights = {}
  performanceCache.timeDelta = {}
  performanceCache.bossWeighting = {}
  performanceCache.ensemble = {}
  performanceCache.methodSelection = {}

  PushMaster:DebugPrint("EMERGENCY PERFORMANCE MODE ACTIVATED - calculations reduced")

  -- Schedule deactivation after 2 minutes
  C_Timer.After(120, function()
    performanceMetrics.emergencyModeActive = false
    PERFORMANCE_CONFIG.maxCalculationsPerSecond = 5
    PERFORMANCE_CONFIG.minUpdateInterval = 0.2
    PERFORMANCE_CONFIG.enableDebugLogging = true
    PushMaster:DebugPrint("Emergency performance mode deactivated")
  end)
end

-- Initialize performance monitoring when the module loads
initializePerformanceMonitoring()

return Calculator
