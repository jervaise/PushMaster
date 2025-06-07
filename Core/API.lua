---@class PushMasterAPI
---Central API for PushMaster addon
---Manages current run state and provides clean interface for all modules

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create API module
PushMaster.Core = PushMaster.Core or {}
local API = {}
PushMaster.Core.API = API

-- Local references
local Calculator = nil
local Database = nil
local Performance = nil
local Extrapolation = nil

-- Current run state
local currentRun = {
  active = false,
  dungeonID = nil,
  keyLevel = nil,
  startTime = nil,
  bestRun = nil,
  lastComparison = nil,
  lastCalculationTime = 0
}

-- Cache for comparison results
local comparisonCache = {
  data = nil,
  timestamp = 0,
  validityDuration = 1.0 -- 1 second cache
}

---Initialize API module
function API:Initialize()
  -- Get module references after initialization
  Calculator = PushMaster.Data and PushMaster.Data.Calculator
  Database = PushMaster.Core.Database
  Performance = PushMaster.Core.Performance
  Extrapolation = PushMaster.Data and PushMaster.Data.Extrapolation

  PushMaster:DebugPrint("API module initialized")
end

---Start tracking a new run
---@param dungeonID number Dungeon/map ID
---@param keyLevel number Mythic+ key level
---@param affixes table Affix IDs (unused but kept for compatibility)
function API:StartNewRun(dungeonID, keyLevel, affixes)
  if not dungeonID or not keyLevel then
    PushMaster:DebugPrint("API: Invalid run parameters")
    return false
  end

  -- Reset state
  currentRun.active = true
  currentRun.dungeonID = dungeonID
  currentRun.keyLevel = keyLevel
  currentRun.startTime = GetTime()
  currentRun.lastComparison = nil
  currentRun.lastCalculationTime = 0

  -- Clear cache
  comparisonCache.data = nil
  comparisonCache.timestamp = 0

  -- Get best run for comparison (with extrapolation if enabled)
  currentRun.bestRun = self:GetBestRunForComparison(dungeonID, keyLevel)

  -- Initialize calculator with run data
  if Calculator then
    Calculator:StartRun(dungeonID, keyLevel, currentRun.bestRun)
  end

  PushMaster:DebugPrint(string.format("API: Started tracking %s +%d", self:GetDungeonName(dungeonID), keyLevel))
  return true
end

---Stop tracking current run
---@param completed boolean Whether the run was completed
---@param inTime boolean Whether the run was completed in time
function API:StopRun(completed, inTime)
  if not currentRun.active then
    return
  end

  local runTime = GetTime() - currentRun.startTime

  if Calculator then
    Calculator:EndRun(completed, inTime, runTime)
  end

  -- Save run if completed and in time
  if completed and inTime and Database then
    local runData = self:GetCurrentRunData()
    if runData then
      Database:SaveRun(currentRun.dungeonID, currentRun.keyLevel, runData)
    end
  end

  -- Reset state
  currentRun.active = false
  currentRun.dungeonID = nil
  currentRun.keyLevel = nil
  currentRun.startTime = nil
  currentRun.bestRun = nil

  PushMaster:DebugPrint("API: Stopped tracking run")
end

---Update current progress
---@param trash number Current trash percentage (0-100)
---@param bosses number Bosses killed
---@param deaths number Total deaths
function API:UpdateProgress(trash, bosses, deaths)
  if not currentRun.active or not Calculator then
    return
  end

  -- Check performance throttling
  if Performance and not Performance:CanUpdateCalculation(currentRun.lastCalculationTime) then
    return
  end

  currentRun.lastCalculationTime = GetTime()

  -- Update calculator
  Calculator:UpdateProgress(trash, bosses, deaths)

  -- Invalidate cache
  comparisonCache.data = nil
end

---Get current comparison data for UI
---@return table|nil comparison Comparison data or nil
function API:GetCurrentComparison()
  if not currentRun.active then
    return nil
  end

  -- Check cache first
  local now = GetTime()
  if comparisonCache.data and (now - comparisonCache.timestamp) < comparisonCache.validityDuration then
    return comparisonCache.data
  end

  -- Get fresh calculation
  if not Calculator then
    return nil
  end

  local comparison = Calculator:GetComparison()
  if not comparison then
    return nil
  end

  -- Add metadata
  comparison.dungeon = self:GetDungeonName(currentRun.dungeonID)
  comparison.level = currentRun.keyLevel
  comparison.isExtrapolated = currentRun.bestRun and currentRun.bestRun.isExtrapolated or false

  -- Cache result
  comparisonCache.data = comparison
  comparisonCache.timestamp = now

  return comparison
end

---Get best run for comparison (with extrapolation if needed)
---@param dungeonID number Dungeon ID
---@param keyLevel number Key level
---@return table|nil bestRun Best run data or nil
function API:GetBestRunForComparison(dungeonID, keyLevel)
  if not Database then
    return nil
  end

  -- Try exact match first
  local bestRun = Database:GetBestRun(dungeonID, keyLevel)
  if bestRun then
    return bestRun
  end

  -- Check if extrapolation is enabled
  if not self:IsExtrapolationEnabled() then
    return nil
  end

  -- Try extrapolation
  if Extrapolation then
    local sourceRun, sourceLevel = Database:GetBestRunForExtrapolation(dungeonID, keyLevel)
    if sourceRun and sourceLevel then
      local extrapolatedRun = Extrapolation:ExtrapolateRun(sourceRun, sourceLevel, keyLevel)
      if extrapolatedRun then
        extrapolatedRun.isExtrapolated = true
        extrapolatedRun.sourceLevel = sourceLevel
        return extrapolatedRun
      end
    end
  end

  return nil
end

---Check if currently tracking a run
---@return boolean isTracking
function API:IsTrackingRun()
  return currentRun.active
end

---Get current run data for saving
---@return table|nil runData
function API:GetCurrentRunData()
  if not currentRun.active or not Calculator then
    return nil
  end

  local runData = Calculator:GetRunData()
  if not runData then
    return nil
  end

  -- Add metadata
  runData.dungeonID = currentRun.dungeonID
  runData.keyLevel = currentRun.keyLevel
  runData.timestamp = time()
  runData.date = date("%Y-%m-%d %H:%M:%S")

  return runData
end

---Check if extrapolation is enabled
---@return boolean enabled
function API:IsExtrapolationEnabled()
  return PushMasterDB and PushMasterDB.settings and PushMasterDB.settings.enableExtrapolation or false
end

---Get dungeon name
---@param dungeonID number
---@return string name
function API:GetDungeonName(dungeonID)
  -- TODO: Implement proper dungeon name lookup
  local dungeonNames = {
    [399] = "Ruby Life Pools",
    [400] = "The Nokhud Offensive",
    [401] = "The Azure Vault",
    [402] = "Algeth'ar Academy",
    [403] = "Uldaman: Legacy of Tyr",
    [404] = "Neltharus",
    [405] = "Brackenhide Hollow",
    [406] = "Halls of Infusion",
    -- Add more as needed
  }
  return dungeonNames[dungeonID] or ("Dungeon " .. dungeonID)
end

---Reset current run (for testing or manual reset)
function API:ResetCurrentRun()
  if currentRun.active then
    self:StopRun(false, false)
  end

  if Calculator then
    Calculator:Reset()
  end

  comparisonCache.data = nil
  comparisonCache.timestamp = 0

  PushMaster:DebugPrint("API: Current run reset")
end

return API
