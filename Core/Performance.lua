---@class PushMasterPerformance
---Performance control module for PushMaster addon
---Allows users to adjust CPU impact vs accuracy

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create Performance module
PushMaster.Core = PushMaster.Core or {}
local Performance = {}
PushMaster.Core.Performance = Performance

-- Performance profiles
local PROFILES = {
  LOW = {                     -- Minimal CPU usage
    trashUpdateRate = 0.5,    -- 2 updates per second
    bossUpdateRate = 0.5,     -- 2 updates per second
    calculationRate = 2.0,    -- Calculate every 2 seconds
    interpolationSamples = 5, -- Use fewer data points
    enableSmoothing = false,  -- No display smoothing
    name = "Low"
  },
  BALANCED = {                 -- Default balanced performance
    trashUpdateRate = 0.25,    -- 4 updates per second
    bossUpdateRate = 0.5,      -- 2 updates per second
    calculationRate = 1.0,     -- Calculate every second
    interpolationSamples = 10, -- Moderate data points
    enableSmoothing = true,    -- Basic smoothing
    name = "Balanced"
  },
  HIGH = {                     -- Maximum accuracy, higher CPU
    trashUpdateRate = 0.1,     -- 10 updates per second
    bossUpdateRate = 0.25,     -- 4 updates per second
    calculationRate = 0.5,     -- Calculate every 0.5 seconds
    interpolationSamples = 20, -- Maximum data points
    enableSmoothing = true,    -- Full smoothing
    name = "High"
  }
}

-- Current settings
local currentProfile = "BALANCED"
local customSettings = nil
local lastUpdate = {
  trash = 0,
  boss = 0,
  calculation = 0
}

---Initialize Performance module
function Performance:Initialize()
  -- Load saved performance settings
  if PushMasterDB and PushMasterDB.settings then
    currentProfile = PushMasterDB.settings.performanceProfile or "BALANCED"
    customSettings = PushMasterDB.settings.customPerformance
  end

  PushMaster:DebugPrint("Performance module initialized with profile: " .. currentProfile)
end

---Get current performance settings
---@return table settings Current performance configuration
function Performance:GetSettings()
  if customSettings then
    return customSettings
  end
  return PROFILES[currentProfile] or PROFILES.BALANCED
end

---Set performance profile
---@param profile string Profile name (LOW, BALANCED, HIGH)
function Performance:SetProfile(profile)
  if PROFILES[profile] then
    currentProfile = profile
    customSettings = nil
    self:SaveSettings()
    PushMaster:DebugPrint("Performance profile changed to: " .. profile)
  end
end

---Set custom performance settings
---@param settings table Custom settings table
function Performance:SetCustomSettings(settings)
  customSettings = settings
  currentProfile = "CUSTOM"
  self:SaveSettings()
end

---Check if trash update is allowed based on throttling
---@param lastUpdateTime number Last update timestamp
---@return boolean canUpdate Whether update is allowed
function Performance:CanUpdateTrash(lastUpdateTime)
  local settings = self:GetSettings()
  local now = GetTime()
  return (now - lastUpdateTime) >= settings.trashUpdateRate
end

---Check if boss update is allowed based on throttling
---@param lastUpdateTime number Last update timestamp
---@return boolean canUpdate Whether update is allowed
function Performance:CanUpdateBoss(lastUpdateTime)
  local settings = self:GetSettings()
  local now = GetTime()
  return (now - lastUpdateTime) >= settings.bossUpdateRate
end

---Check if calculation update is allowed based on throttling
---@param lastUpdateTime number Last update timestamp
---@return boolean canUpdate Whether update is allowed
function Performance:CanUpdateCalculation(lastUpdateTime)
  local settings = self:GetSettings()
  local now = GetTime()
  return (now - lastUpdateTime) >= settings.calculationRate
end

---Get interpolation sample limit
---@return number maxSamples Maximum samples to use for interpolation
function Performance:GetInterpolationSamples()
  local settings = self:GetSettings()
  return settings.interpolationSamples or 10
end

---Check if display smoothing is enabled
---@return boolean enabled Whether smoothing is enabled
function Performance:IsSmoothingEnabled()
  local settings = self:GetSettings()
  return settings.enableSmoothing or false
end

---Get update intervals
---@return number, number, number trash, boss, calculation intervals
function Performance:GetUpdateIntervals()
  local settings = self:GetSettings()
  return settings.trashUpdateRate, settings.bossUpdateRate, settings.calculationRate
end

---Save performance settings
function Performance:SaveSettings()
  if PushMasterDB and PushMasterDB.settings then
    PushMasterDB.settings.performanceProfile = currentProfile
    PushMasterDB.settings.customPerformance = customSettings
  end
end

---Get available profiles
---@return table profiles List of profile names and descriptions
function Performance:GetProfiles()
  local profiles = {}
  for key, profile in pairs(PROFILES) do
    table.insert(profiles, {
      id = key,
      name = profile.name,
      description = string.format("Trash: %.1f/s, Boss: %.1f/s, Calc: %.1f/s",
        1 / profile.trashUpdateRate, 1 / profile.bossUpdateRate, 1 / profile.calculationRate)
    })
  end
  return profiles
end

return Performance
