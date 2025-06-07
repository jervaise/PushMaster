---@class PushMasterCalculator
---Simple calculation module for PushMaster addon

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

PushMaster.Data = PushMaster.Data or {}
local Calculator = {}
PushMaster.Data.Calculator = Calculator

local Efficiency = nil
local Timeline = nil
local Performance = nil

local currentRun = {
  active = false,
  dungeonID = nil,
  keyLevel = nil,
  startTime = nil,
  elapsedTime = 0,
  bestRun = nil,
  trash = 0,
  bosses = 0,
  deaths = 0,
  activeBoss = nil,
  bossStartTime = nil,
  bossFights = {},
  deathLog = {}
}

local DEATH_PENALTY_SECONDS = 15

function Calculator:Initialize()
  Efficiency = PushMaster.Calculations and PushMaster.Calculations.Efficiency
  Timeline = PushMaster.Data and PushMaster.Data.Timeline
  Performance = PushMaster.Core and PushMaster.Core.Performance
  PushMaster:DebugPrint("Calculator module initialized")
end

function Calculator:StartRun(dungeonID, keyLevel, bestRun)
  currentRun = {
    active = true,
    dungeonID = dungeonID,
    keyLevel = keyLevel,
    startTime = GetTime(),
    elapsedTime = 0,
    bestRun = bestRun,
    trash = 0,
    bosses = 0,
    deaths = 0,
    activeBoss = nil,
    bossStartTime = nil,
    bossFights = {},
    deathLog = {}
  }

  if Timeline then
    Timeline:StartRecording()
  end

  PushMaster:DebugPrint(string.format("Calculator: Started run for dungeon %d +%d", dungeonID, keyLevel))
end

function Calculator:EndRun(completed, inTime, totalTime)
  if not currentRun.active then
    return
  end

  currentRun.active = false
  currentRun.totalTime = totalTime or (GetTime() - currentRun.startTime)

  PushMaster:DebugPrint(string.format("Calculator: Run ended - Completed: %s, In time: %s, Time: %.1fs",
    tostring(completed), tostring(inTime), currentRun.totalTime))
end

function Calculator:UpdateProgress(trash, bosses, deaths)
  if not currentRun.active then
    return
  end

  currentRun.trash = trash or currentRun.trash
  currentRun.bosses = bosses or currentRun.bosses
  currentRun.deaths = deaths or currentRun.deaths
  currentRun.elapsedTime = GetTime() - currentRun.startTime

  if Timeline then
    Timeline:AddSample(currentRun.trash, currentRun.bosses, currentRun.deaths)
  end
end

function Calculator:GetComparison()
  if not currentRun.active then
    return nil
  end

  -- If no best run, return recording state
  if not currentRun.bestRun or not Efficiency then
    return {
      isRecording = true,
      dungeonID = currentRun.dungeonID,
      level = currentRun.keyLevel,
      progress = {
        trash = currentRun.trash,
        bosses = currentRun.bosses,
        deaths = currentRun.deaths
      }
    }
  end

  local current = {
    elapsedTime = currentRun.elapsedTime,
    trash = currentRun.trash,
    bosses = currentRun.bosses + self:GetPartialBossCredit(),
    deaths = currentRun.deaths
  }

  local efficiency = Efficiency:Calculate(current, currentRun.bestRun)
  local trashDiff, bossDiff, deathDiff = Efficiency:GetComponentDifferences(current, currentRun.bestRun)
  local timeDelta, confidence = Efficiency:CalculateTimeDelta(current, currentRun.bestRun)

  local comparison = {
    progressEfficiency = efficiency,
    trashProgress = trashDiff,
    bossProgress = bossDiff,
    deathProgress = deathDiff,
    timeDelta = timeDelta,
    timeConfidence = confidence,
    deathTimePenalty = currentRun.deaths * DEATH_PENALTY_SECONDS,
    progress = {
      trash = currentRun.trash,
      bosses = currentRun.bosses,
      deaths = currentRun.deaths
    },
    dungeonID = currentRun.dungeonID,
    level = currentRun.keyLevel
  }

  return comparison
end

function Calculator:GetPartialBossCredit()
  if not currentRun.activeBoss or not currentRun.bossStartTime then
    return 0
  end

  local expectedDuration = self:GetExpectedBossDuration(currentRun.activeBoss)
  if not expectedDuration or expectedDuration <= 0 then
    expectedDuration = 120
  end

  local fightDuration = GetTime() - currentRun.bossStartTime
  local progress = math.min(1, fightDuration / expectedDuration)

  if progress < 0.25 then
    return 0
  elseif progress < 0.5 then
    return 0.25
  elseif progress < 0.75 then
    return 0.5
  elseif progress < 1 then
    return 0.75
  else
    return 1
  end
end

function Calculator:GetExpectedBossDuration(bossName)
  if not currentRun.bestRun or not currentRun.bestRun.bossFights then
    return nil
  end

  for _, fight in ipairs(currentRun.bestRun.bossFights) do
    if fight.name == bossName then
      return fight.duration
    end
  end

  return nil
end

function Calculator:StartBossFight(bossName)
  if not currentRun.active then
    return
  end

  currentRun.activeBoss = bossName
  currentRun.bossStartTime = GetTime()

  PushMaster:DebugPrint("Calculator: Started boss fight - " .. bossName)
end

function Calculator:EndBossFight(bossName)
  if not currentRun.active or not currentRun.activeBoss then
    return
  end

  if currentRun.activeBoss ~= bossName then
    PushMaster:DebugPrint("Calculator: Boss name mismatch on end")
    return
  end

  local duration = GetTime() - currentRun.bossStartTime

  table.insert(currentRun.bossFights, {
    name = bossName,
    duration = duration,
    killTime = currentRun.elapsedTime
  })

  currentRun.activeBoss = nil
  currentRun.bossStartTime = nil
  currentRun.bosses = currentRun.bosses + 1

  PushMaster:DebugPrint(string.format("Calculator: Boss killed - %s (%.1fs)", bossName, duration))
end

function Calculator:RecordDeath(playerName)
  if not currentRun.active then
    return
  end

  currentRun.deaths = currentRun.deaths + 1

  table.insert(currentRun.deathLog, {
    player = playerName,
    time = currentRun.elapsedTime
  })

  PushMaster:DebugPrint(string.format("Calculator: Death recorded - %s at %.1fs", playerName, currentRun.elapsedTime))
end

function Calculator:GetRunData()
  if not currentRun.active then
    return nil
  end

  local runData = {
    totalTime = currentRun.totalTime or currentRun.elapsedTime,
    timeLimit = 1800,
    timeline = Timeline and Timeline:CreateForStorage() or {},
    bossFights = currentRun.bossFights,
    deaths = currentRun.deaths,
    deathLog = currentRun.deathLog,
    finalTrash = currentRun.trash,
    finalBosses = currentRun.bosses
  }

  return runData
end

function Calculator:Reset()
  currentRun = {
    active = false,
    dungeonID = nil,
    keyLevel = nil,
    startTime = nil,
    elapsedTime = 0,
    bestRun = nil,
    trash = 0,
    bosses = 0,
    deaths = 0,
    activeBoss = nil,
    bossStartTime = nil,
    bossFights = {},
    deathLog = {}
  }

  if Timeline then
    Timeline:Reset()
  end

  PushMaster:DebugPrint("Calculator: Reset")
end

function Calculator:IsTrackingRun()
  return currentRun.active
end

function Calculator:GetCurrentState()
  return {
    active = currentRun.active,
    dungeonID = currentRun.dungeonID,
    keyLevel = currentRun.keyLevel,
    elapsedTime = currentRun.elapsedTime,
    trash = currentRun.trash,
    bosses = currentRun.bosses,
    deaths = currentRun.deaths,
    activeBoss = currentRun.activeBoss,
    hasBestRun = currentRun.bestRun ~= nil
  }
end

-- Compatibility methods
function Calculator:StartNewRun(instanceData)
  if not instanceData then
    return
  end

  local dungeonID = instanceData.currentMapID or instanceData.mapID
  local keyLevel = instanceData.cmLevel or instanceData.keyLevel

  local API = PushMaster.Core and PushMaster.Core.API
  local bestRun = nil
  if API then
    bestRun = API:GetBestRunForComparison(dungeonID, keyLevel)
  end

  self:StartRun(dungeonID, keyLevel, bestRun)
end

function Calculator:GetCurrentComparison()
  return self:GetComparison()
end

function Calculator:ResetCurrentRun()
  self:Reset()
end

return Calculator
