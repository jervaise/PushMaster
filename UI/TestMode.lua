---@class PushMasterTestMode
---Test mode functionality for PushMaster addon
---Uses actual Calculator logic to test with real or simulated dungeon data

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create TestMode module
local TestMode = {}
if not PushMaster.UI then
  PushMaster.UI = {}
end
PushMaster.UI.TestMode = TestMode

-- Local references
local isTestActive = false
local testStartTime = 0
local testRunData = nil
local currentTestIndex = 1
local lastBossCount = 0
local lastDeathCount = 0
local lastMessage = ""
local testLoopTimer = nil
local lastUpdateTime = nil
local originalDebugMode = false -- Store original debug mode state

-- Sample run data for testing with realistic pace variations
local SAMPLE_RUN_DATA = {
  {
    name = "Priory of the Sacred Flame",
    mapID = 2649,
    keyLevel = 15,
    timeLimit = 1800,            -- 30 minutes
    affixes = { 10, 8, 3, 152 }, -- TWW S2 affixes: Fortified, Sanguine, Volcanic, Challenger's Peril
    bestRunData = {
      time = 1500,               -- 25:00 best time (STRONG best run)
      deaths = 1,
      bossKillTimes = {
        { name = "Captain Dailcry",   killTime = 360,  bossNumber = 1 }, -- 6:00 - FAST
        { name = "Baron Braunpyke",   killTime = 720,  bossNumber = 2 }, -- 12:00 - FAST
        { name = "Prioress Murrpray", killTime = 1440, bossNumber = 3 }  -- 24:00 - FAST
      },
      trashSamples = {
        { time = 150,  trash = 10 },
        { time = 300,  trash = 20 },
        { time = 450,  trash = 30 },
        { time = 600,  trash = 40 },
        { time = 780,  trash = 50 },
        { time = 960,  trash = 60 },
        { time = 1140, trash = 70 },
        { time = 1320, trash = 80 },
        { time = 1440, trash = 90 },
        { time = 1500, trash = 100 }
      }
    },
    testProgression = {
      -- SLOW START - best run ahead
      { time = 0,    trash = 0,   bosses = 0, deaths = 0, milestone = true, message = "Dungeon started - cautious approach" },
      { time = 180,  trash = 6,   bosses = 0, deaths = 0, milestone = true, message = "Slow start - best run pulling ahead!" },
      { time = 300,  trash = 12,  bosses = 0, deaths = 0, milestone = true, message = "Still no boss - best run dominating trash!" },

      -- VERY LATE FIRST BOSS - way behind
      { time = 480,  trash = 18,  bosses = 1, deaths = 0, milestone = true, message = "Captain Dailcry finally down - 2 minutes behind best!" },
      { time = 600,  trash = 22,  bosses = 1, deaths = 0, milestone = true, message = "Best run has massive lead in both trash and bosses" },

      -- DEATH MAKES IT WORSE
      { time = 720,  trash = 25,  bosses = 1, deaths = 1, milestone = true, message = "Death on trash - best run extending lead!" },
      { time = 840,  trash = 30,  bosses = 1, deaths = 1, milestone = true, message = "Best run already has Baron down - we're struggling!" },

      -- LATE SECOND BOSS
      { time = 960,  trash = 38,  bosses = 2, deaths = 1, milestone = true, message = "Baron Braunpyke down slow - best run way ahead on everything" },

      -- RECOVERY PHASE - starting to catch up
      { time = 1080, trash = 52,  bosses = 2, deaths = 1, milestone = true, message = "Fast trash recovery! Closing gap slightly" },
      { time = 1200, trash = 68,  bosses = 2, deaths = 1, milestone = true, message = "Racing to final boss - finally matching best pace" },

      -- STRONG FINISH - but is it enough?
      { time = 1320, trash = 82,  bosses = 2, deaths = 1, milestone = true, message = "Excellent trash pace - overtaking best run!" },
      { time = 1440, trash = 95,  bosses = 3, deaths = 1, milestone = true, message = "Prioress Murrpray down! Racing to finish line!" },
      { time = 1500, trash = 100, bosses = 3, deaths = 1, milestone = true, message = "Finished! Tied best run time despite slow start!" }
    }
  },
  {
    name = "Theater of Pain",
    mapID = 2293,
    keyLevel = 12,
    timeLimit = 1800,            -- 30 minutes
    affixes = { 7, 11, 3, 152 }, -- TWW S2 affixes: Tyrannical, Bursting, Volcanic, Challenger's Peril
    bestRunData = {
      time = 1440,               -- 24:00 best time (VERY STRONG best run)
      deaths = 0,
      bossKillTimes = {
        { name = "An Affront of Challengers", killTime = 360,  bossNumber = 1 }, -- 6:00 - FAST
        { name = "Gorechop",                  killTime = 720,  bossNumber = 2 }, -- 12:00 - FAST
        { name = "Xav the Unfallen",          killTime = 1080, bossNumber = 3 }, -- 18:00 - FAST
        { name = "Kul'tharok",                killTime = 1320, bossNumber = 4 }  -- 22:00 - FAST
      },
      trashSamples = {
        { time = 120,  trash = 10 },
        { time = 300,  trash = 20 },
        { time = 480,  trash = 30 },
        { time = 660,  trash = 40 },
        { time = 840,  trash = 50 },
        { time = 1020, trash = 60 },
        { time = 1200, trash = 70 },
        { time = 1320, trash = 80 },
        { time = 1380, trash = 90 },
        { time = 1440, trash = 100 }
      }
    },
    testProgression = {
      -- DECENT START - but best run is faster
      { time = 0,    trash = 0,   bosses = 0, deaths = 0, milestone = true, message = "Dungeon started - solid group" },
      { time = 180,  trash = 8,   bosses = 0, deaths = 0, milestone = true, message = "Good pace but best run is faster!" },
      { time = 360,  trash = 15,  bosses = 0, deaths = 0, milestone = true, message = "Best run already has first boss - we're behind!" },

      -- SLOW BOSS KILL - falling further behind
      { time = 480,  trash = 22,  bosses = 1, deaths = 0, milestone = true, message = "Challengers down slow - best run extending lead" },
      { time = 600,  trash = 28,  bosses = 1, deaths = 0, milestone = true, message = "Struggling with trash - best run dominating" },

      -- DISASTER - death makes it worse
      { time = 720,  trash = 32,  bosses = 1, deaths = 1, milestone = true, message = "Death! Best run has Gorechop - we're in trouble" },
      { time = 900,  trash = 42,  bosses = 1, deaths = 1, milestone = true, message = "Still no second boss - best run way ahead" },

      -- VERY LATE SECOND BOSS
      { time = 1080, trash = 50,  bosses = 2, deaths = 1, milestone = true, message = "Gorechop finally down - 6 minutes behind best!" },
      { time = 1200, trash = 58,  bosses = 2, deaths = 1, milestone = true, message = "Best run almost finished - we can't catch up" },

      -- TOO LITTLE TOO LATE
      { time = 1320, trash = 68,  bosses = 3, deaths = 1, milestone = true, message = "Xav down but best run already finished!" },
      { time = 1500, trash = 85,  bosses = 4, deaths = 1, milestone = true, message = "Kul'tharok down - but best run won by 1 minute!" },
      { time = 1620, trash = 100, bosses = 4, deaths = 1, milestone = true, message = "Run complete - best run was simply better today" }
    }
  },
  {
    name = "Operation Mechagon: Workshop",
    mapID = 2097,
    keyLevel = 14,
    timeLimit = 1800,            -- 30 minutes
    affixes = { 8, 11, 3, 152 }, -- TWW S2 affixes: Fortified, Bursting, Volcanic, Challenger's Peril
    bestRunData = {
      time = 1680,               -- 28:00 best time (WEAK best run)
      deaths = 3,
      bossKillTimes = {
        { name = "The Platinum Pummeler", killTime = 600,  bossNumber = 1 }, -- 10:00 - SLOW
        { name = "Gnomercy 4.U.",         killTime = 1080, bossNumber = 2 }, -- 18:00 - SLOW
        { name = "Machinist's Garden",    killTime = 1320, bossNumber = 3 }, -- 22:00 - SLOW
        { name = "King Mechagon",         killTime = 1620, bossNumber = 4 }  -- 27:00 - SLOW
      },
      trashSamples = {
        { time = 300,  trash = 10 },
        { time = 540,  trash = 20 },
        { time = 780,  trash = 30 },
        { time = 960,  trash = 40 },
        { time = 1140, trash = 50 },
        { time = 1320, trash = 60 },
        { time = 1440, trash = 70 },
        { time = 1560, trash = 80 },
        { time = 1620, trash = 90 },
        { time = 1680, trash = 100 }
      }
    },
    testProgression = {
      -- FAST START - crushing best run
      { time = 0,    trash = 0,   bosses = 0, deaths = 0, milestone = true, message = "Dungeon started - experienced group!" },
      { time = 180,  trash = 12,  bosses = 0, deaths = 0, milestone = true, message = "Lightning fast trash - destroying best run!" },
      { time = 360,  trash = 25,  bosses = 1, deaths = 0, milestone = true, message = "Platinum Pummeler down early! 4 minutes ahead of best!" },

      -- MAINTAINING LEAD
      { time = 540,  trash = 42,  bosses = 1, deaths = 0, milestone = true, message = "Excellent pace - best run can't keep up!" },
      { time = 720,  trash = 58,  bosses = 2, deaths = 0, milestone = true, message = "Gnomercy down fast! Best run still on first boss!" },

      -- DOMINATING
      { time = 900,  trash = 72,  bosses = 2, deaths = 0, milestone = true, message = "Racing to third boss - best run 6 minutes behind!" },
      { time = 1080, trash = 88,  bosses = 3, deaths = 0, milestone = true, message = "Machinist's Garden down! Almost at King Mechagon!" },

      -- CRUSHING VICTORY
      { time = 1200, trash = 100, bosses = 4, deaths = 0, milestone = true, message = "King Mechagon down! Finished 8 minutes ahead!" },
      { time = 1200, trash = 100, bosses = 4, deaths = 0, milestone = true, message = "Absolute domination! Best run crushed!" }
    }
  }
}

---Initialize test with real Calculator logic
local function initializeTestData(runIndex)
  runIndex = runIndex or 1
  local selectedRun = SAMPLE_RUN_DATA[runIndex] or SAMPLE_RUN_DATA[1]

  testRunData = {
    name = selectedRun.name,
    mapID = selectedRun.mapID,
    keyLevel = selectedRun.keyLevel,
    timeLimit = selectedRun.timeLimit,
    affixes = selectedRun.affixes,
    progression = selectedRun.testProgression,
    currentStage = 1,
    startTime = GetTime(),
    isActive = true
  }

  -- Store the "best run" data that Calculator would have
  testRunData = selectedRun

  PushMaster:DebugPrint("Test initialized: " .. testRunData.name)
end

---Set up fake best time data for testing
function TestMode:setupFakeBestTime()
  if not testRunData or not testRunData.bestRunData then
    PushMaster:DebugPrint("No test run data available for fake best time setup")
    return
  end

  -- Get reference to Calculator
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    PushMaster:DebugPrint("Calculator module not available")
    return
  end

  -- Access the bestTimes storage directly (we need to inject fake data)
  -- Since bestTimes is local in Calculator, we'll use the import function
  local fakeBestTimes = {}
  fakeBestTimes[testRunData.mapID] = {}

  -- Build fake best-time entry directly using new trashSamples
  local fakeEntry = {
    time = testRunData.bestRunData.time,
    date = date("%Y-%m-%d %H:%M:%S"),
    deaths = testRunData.bestRunData.deaths,
    affixes = testRunData.affixes,
    bossKillTimes = testRunData.bestRunData.bossKillTimes,
    trashSamples = testRunData.bestRunData.trashSamples or {}
  }
  fakeBestTimes[testRunData.mapID][testRunData.keyLevel] = fakeEntry

  -- Import the fake best times into Calculator
  Calculator:ImportBestTimes(fakeBestTimes)

  PushMaster:DebugPrint(string.format("Fake best time set up: %s +%d (%.1fs)",
    testRunData.name, testRunData.keyLevel, testRunData.bestRunData.time))
end

---Update test display with real Calculator comparison data
---@param currentTime number Current test time
function TestMode:updateTestDisplay(currentTime)
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    return
  end

  -- Get real comparison data from Calculator
  local comparison = Calculator:GetCurrentComparison()
  if not comparison then
    return
  end

  -- Ensure the main UI frame is shown during test mode
  if PushMaster.UI.MainFrame then
    if not PushMaster.UI.MainFrame:IsShown() then
      PushMaster.UI.MainFrame:Show()
    end

    -- Force immediate update during test mode (bypass combat lockdown)
    PushMaster.UI.MainFrame:UpdateDisplay(comparison)
  end
end

---Main test loop - processes test progression and updates display
function TestMode:testLoop()
  if not testRunData or not testRunData.testProgression then
    return
  end

  -- Speed up the test progression (10x faster for quick validation)
  local speedMultiplier = 10
  local currentTime = (GetTime() - testStartTime) * speedMultiplier

  -- Find the two stages to interpolate between
  local prevStage = nil
  local nextStage = nil

  for i = 1, #testRunData.testProgression do
    local stage = testRunData.testProgression[i]
    if currentTime >= stage.time then
      prevStage = stage
      nextStage = testRunData.testProgression[i + 1]
    else
      nextStage = stage
      break
    end
  end

  -- If we haven't started yet, use the first stage
  if not prevStage then
    prevStage = testRunData.testProgression[1]
    nextStage = testRunData.testProgression[2]
  end

  -- If we're past the end, use the last stage
  if not nextStage then
    prevStage = testRunData.testProgression[#testRunData.testProgression]
    nextStage = nil

    -- If we've reached the end of the test progression, complete the test
    if currentTime >= prevStage.time then
      -- Show final comparison only
      local Calculator = PushMaster.Data.Calculator
      if Calculator then
        local comparison = Calculator:GetCurrentComparison()
        if comparison then
          PushMaster:Print(string.format("Run complete! Efficiency %+d%% | Trash %+d%% | Boss %+d | Deaths %d",
            comparison.progressEfficiency,
            comparison.trashProgress,
            comparison.bossProgress,
            comparison.progress.deaths))
        end
      end

      -- Stop the test
      self:StopTest()
      return
    end
  end

  local currentStage = nil

  if nextStage and prevStage.time ~= nextStage.time then
    -- Interpolate between stages
    local timeProgress = (currentTime - prevStage.time) / (nextStage.time - prevStage.time)
    timeProgress = math.max(0, math.min(1, timeProgress)) -- Clamp to 0-1

    currentStage = {
      time = currentTime,
      trash = prevStage.trash + (nextStage.trash - prevStage.trash) * timeProgress,
      bosses = prevStage.bosses, -- Bosses don't interpolate - they're discrete events
      deaths = prevStage.deaths, -- Deaths don't interpolate - they're discrete events
      milestone = false,         -- Interpolated stages are not milestones
      message = ""
    }

    -- Check if we've crossed a boss kill threshold
    if nextStage.bosses > prevStage.bosses and timeProgress >= 0.5 then
      currentStage.bosses = nextStage.bosses
    end

    -- Check if we've crossed a death threshold
    if nextStage.deaths > prevStage.deaths and timeProgress >= 0.5 then
      currentStage.deaths = nextStage.deaths
    end
  else
    -- Use the previous stage directly
    currentStage = prevStage
  end

  if currentStage then
    -- Record boss kills when they happen
    if currentStage.bosses > (lastBossCount or 0) then
      for bossNum = (lastBossCount or 0) + 1, currentStage.bosses do
        -- Use a generic boss name since we're testing the timing, not the specific boss
        local bossName = "Boss " .. bossNum
        PushMaster:DebugPrint(string.format("Recording boss kill: %s at stage time %.1fs", bossName, currentStage.time))
        self:RecordBossKill(bossName, currentStage.time)
      end
      lastBossCount = currentStage.bosses
    end

    -- Update Calculator with current progress using our method
    self:UpdateProgress(currentStage.trash, currentStage.bosses, currentStage.deaths, currentStage.time)

    -- Show ONLY milestone messages from actual progression stages
    if prevStage and prevStage.milestone and prevStage.message and prevStage.message ~= lastMessage and prevStage.message ~= "" then
      -- Only show milestone if we've reached or passed the exact time
      if currentTime >= prevStage.time then
        PushMaster:Print(prevStage.message)

        -- Show comprehensive debug information only at milestones
        local Calculator = PushMaster.Data.Calculator
        if Calculator then
          local comparison = Calculator:GetCurrentComparison()
          if comparison then
            -- Show the detailed breakdown with full descriptive words for clarity
            PushMaster:Print(string.format("  * Time %.0fs | Current Run: Trash:%.0f%% Bosses:%d Deaths:%d",
              currentStage.time, currentStage.trash, currentStage.bosses, currentStage.deaths))

            -- The best run values are calculated internally by the Calculator
            PushMaster:Print(string.format("  * Best Run vs Current: Efficiency:%+d%% Trash:%+d%% Bosses:%+d",
              comparison.progressEfficiency,
              comparison.trashProgress,
              comparison.bossProgress))
          end
        end

        lastMessage = prevStage.message
      end
    end

    -- Update display with real Calculator data (silently)
    self:updateTestDisplay(currentTime)
  end
end

---Start test mode with a random scenario
function TestMode:StartTest()
  -- Pick a random scenario from 1 to 3
  local runIndex = math.random(1, 3)

  if runIndex < 1 or runIndex > #SAMPLE_RUN_DATA then
    PushMaster:Print("Invalid run index. Available runs: 1-" .. #SAMPLE_RUN_DATA)
    return
  end

  -- Stop any existing test
  self:StopTest()

  -- Explicitly reset Calculator to ensure clean state
  local Calculator = PushMaster.Data.Calculator
  if Calculator then
    Calculator:ResetCurrentRun()
  end

  testRunData = SAMPLE_RUN_DATA[runIndex]
  currentTestIndex = runIndex

  PushMaster:Print("TEST MODE: " .. testRunData.name .. " (10x speed)")
  PushMaster:Print("Watch for milestone events and calculation changes...")

  -- Ensure MainFrame is initialized and shown for test mode
  if PushMaster.UI.MainFrame then
    if not PushMaster.UI.MainFrame:GetFrame() then
      PushMaster.UI.MainFrame:Initialize()
    end
    PushMaster.UI.MainFrame:Show()

    -- Reset MainFrame to default state before starting test
    local defaultData = {
      progressEfficiency = 0,
      trashProgress = 0,
      bossProgress = 0,
      progress = { deaths = 0 },
      deathTimePenalty = 0
    }
    PushMaster.UI.MainFrame:UpdateDisplay(defaultData)
  end

  -- Temporarily disable debug mode to reduce spam
  originalDebugMode = PushMaster:IsDebugEnabled()
  if originalDebugMode then
    PushMaster:SetDebugMode(false)
  end

  -- Initialize test state
  isTestActive = true
  testStartTime = GetTime()
  lastBossCount = 0
  lastDeathCount = 0
  lastMessage = ""

  -- Set up fake best time data in Calculator
  self:setupFakeBestTime()

  -- Initialize current run in Calculator
  self:StartRun(testRunData.mapID, testRunData.keyLevel, testRunData.affixes)

  -- Start the test loop
  self:scheduleTestLoop()
end

---Schedule the next test loop iteration
function TestMode:scheduleTestLoop()
  if not isTestActive then
    return
  end

  -- Cancel any existing timer
  if testLoopTimer then
    testLoopTimer:Cancel()
    testLoopTimer = nil
  end

  -- CRITICAL PERFORMANCE FIX: Reduced from 0.1s to 1.0s to prevent high-frequency CPU load
  -- This reduces timer frequency from 10 FPS to 1 FPS, dramatically improving performance
  testLoopTimer = C_Timer.NewTimer(1.0, function()
    if isTestActive then
      self:testLoop()
      self:scheduleTestLoop() -- Schedule next iteration
    end
  end)
end

---Stop test mode
function TestMode:StopTest()
  if not isTestActive then
    return -- Silent if no test running
  end

  isTestActive = false
  testRunData = nil

  -- CRITICAL FIX: Ensure timer is properly cleaned up to prevent memory leaks
  if testLoopTimer then
    testLoopTimer:Cancel()
    testLoopTimer = nil
  end

  -- Reset Calculator state
  self:ResetCalculator()

  -- Restore original debug mode
  if originalDebugMode then
    PushMaster:SetDebugMode(true)
  end

  PushMaster:Print("Test mode stopped")
end

---Check if test mode is active
---@return boolean isActive True if test mode is running
function TestMode:IsActive()
  return isTestActive
end

---Load custom run data for testing
---@param customRunData table Custom run data to add to test scenarios
function TestMode:LoadCustomRunData(customRunData)
  if not customRunData then
    PushMaster:Print("No custom run data provided")
    return
  end

  -- Validate required fields
  local required = { "name", "mapID", "keyLevel", "timeLimit", "bestRunData", "testProgression" }
  for _, field in ipairs(required) do
    if not customRunData[field] then
      PushMaster:Print("Missing required field: " .. field)
      return
    end
  end

  -- Add to sample data
  table.insert(SAMPLE_RUN_DATA, customRunData)

  PushMaster:Print("Custom run data loaded: " .. customRunData.name)
  PushMaster:Print("Use TestMode:StartTest(" .. #SAMPLE_RUN_DATA .. ") to test with this data")
end

---Get available test runs
---@return table testRuns List of available test runs
function TestMode:GetAvailableRuns()
  local runs = {}
  for i, run in ipairs(SAMPLE_RUN_DATA) do
    table.insert(runs, {
      index = i,
      name = run.name,
      keyLevel = run.keyLevel,
      timeLimit = run.timeLimit
    })
  end
  return runs
end

---Initialize the TestMode module
function TestMode:Initialize()
  PushMaster:DebugPrint("TestMode module initialized with real Calculator integration")
end

---Update progress in Calculator with test data
---@param trash number Current trash percentage
---@param bosses number Current boss count
---@param deaths number Current death count
---@param stageTime number Current stage time in the test progression
function TestMode:UpdateProgress(trash, bosses, deaths, stageTime)
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    return
  end

  -- Update progress data structure using the stage time, not real elapsed time
  local progressData = {
    trash = trash,
    elapsedTime = stageTime -- Use the simulated stage time
  }

  -- Update Calculator with current progress
  Calculator:UpdateProgress(progressData)

  -- Update deaths if changed
  if deaths > lastDeathCount then
    for i = lastDeathCount + 1, deaths do
      Calculator:RecordDeath(testStartTime + stageTime) -- Use stage time for death recording too
    end
    lastDeathCount = deaths                             -- Update the counter to prevent duplicate recordings
  end
end

---Start a new run in Calculator for testing
---@param mapID number Map ID of the dungeon
---@param keyLevel number Key level
---@param affixes table Affix data
function TestMode:StartRun(mapID, keyLevel, affixes)
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    PushMaster:DebugPrint("Calculator module not available")
    return
  end

  -- Create fake instance data for Calculator
  local instanceData = {
    zoneName = testRunData.name,
    currentMapID = mapID,
    cmLevel = keyLevel,
    affixes = affixes,
    maxTime = testRunData.timeLimit
  }

  -- Start new run in Calculator
  Calculator:StartNewRun(instanceData)

  PushMaster:DebugPrint(string.format("Test run started in Calculator: %s +%d",
    instanceData.zoneName, keyLevel))
end

---Record a boss kill in Calculator
---@param bossName string Name of the boss
---@param killTime number Time when boss was killed (elapsed time from test start)
function TestMode:RecordBossKill(bossName, killTime)
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    return
  end

  -- killTime is already elapsed time, so just pass it directly
  Calculator:RecordBossKill(bossName, testStartTime + killTime)

  PushMaster:DebugPrint(string.format("Test mode recorded boss kill: %s at %.1fs elapsed", bossName, killTime))
end

---Reset Calculator state
function TestMode:ResetCalculator()
  local Calculator = PushMaster.Data.Calculator
  if Calculator then
    Calculator:ResetCurrentRun()
  end
end
