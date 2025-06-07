---@class PushMasterConstants
---Centralized constants and metadata for PushMaster addon
---All addon information should be referenced from here

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Initialize Core table if it doesn't exist
PushMaster.Core = PushMaster.Core or {}

-- Create the Constants module
PushMaster.Core.Constants = {}

-- Addon Metadata (Will be loaded during initialization)
PushMaster.Core.Constants.ADDON_NAME = addonName
PushMaster.Core.Constants.ADDON_TITLE = "PushMaster"
PushMaster.Core.Constants.ADDON_AUTHOR = "Unknown"
PushMaster.Core.Constants.ADDON_VERSION = "0.0.0"
PushMaster.Core.Constants.WOW_VERSION = "11.1.5+"
PushMaster.Core.Constants.DESCRIPTION = "Track and compare Mythic+ key performance in real-time"

-- Database version for migrations
PushMaster.Core.Constants.DB_VERSION = 1

-- UI Constants
PushMaster.Core.Constants.UI = {
  DEFAULT_WINDOW_WIDTH = 300,
  DEFAULT_WINDOW_HEIGHT = 60,
  DEFAULT_OPACITY = 0.9,
  UPDATE_FREQUENCY = 5, -- seconds
  THEME_DEFAULT = "elvui"
}

-- Performance Constants
PushMaster.Core.Constants.PERFORMANCE = {
  DEATH_PENALTY_SECONDS = 15,    -- Time penalty per death at high keys
  MIN_KEY_LEVEL_FOR_PENALTY = 15,
  TIMELINE_UPDATE_INTERVAL = 30, -- seconds
  MAX_STORED_RUNS = 50           -- per dungeon/key level combination
}

-- Color Constants (for UI theming)
PushMaster.Core.Constants.COLORS = {
  BETTER = { r = 0, g = 1, b = 0, a = 1 },       -- Green
  WORSE = { r = 1, g = 0, b = 0, a = 1 },        -- Red
  NEUTRAL = { r = 1, g = 1, b = 0, a = 1 },      -- Yellow
  NO_DATA = { r = 0.5, g = 0.5, b = 0.5, a = 1 } -- Gray
}

-- Mythic+ Scaling Constants
PushMaster.Core.Constants.MYTHIC_PLUS_SCALING = {
  -- Known health/damage modifiers from Blizzard data
  HEALTH_DAMAGE_MODIFIERS = {
    [2] = 1.07,  -- +7%
    [3] = 1.14,  -- +14%
    [4] = 1.23,  -- +23%
    [5] = 1.31,  -- +31%
    [6] = 1.40,  -- +40%
    [7] = 1.50,  -- +50%
    [8] = 1.61,  -- +61%
    [9] = 1.72,  -- +72%
    [10] = 1.84, -- +84%
    [11] = 2.02, -- +102%
    [12] = 2.22, -- +122%
    [13] = 2.45, -- +145%
    [14] = 2.69, -- +169%
    [15] = 2.96  -- +196%
  },

  -- Scaling constants for levels above the known table
  SCALING_BASE_LEVEL = 12,      -- Level 12 is our base for extrapolation
  SCALING_BASE_MODIFIER = 2.22, -- Level 12 modifier value
  SCALING_MULTIPLIER = 1.10,    -- ~10% increase per level above 12
  MAX_SUPPORTED_LEVEL = 35      -- Reasonable upper limit
}

-- Debug Constants
PushMaster.Core.Constants.DEBUG = {
  ENABLED = false,
  LOG_LEVEL = "INFO" -- DEBUG, INFO, WARN, ERROR
}

-- Initialize function - Metadata will be loaded when needed
function PushMaster.Core.Constants:Initialize()
  print("PushMaster: Constants module initialized (metadata will be loaded when accessed)")
end

-- Load metadata from TOC file when first accessed
function PushMaster.Core.Constants:LoadMetadata()
  if not self._metadataLoaded then
    -- Check if GetAddOnMetadata is available
    if not GetAddOnMetadata then
      print("PushMaster: GetAddOnMetadata not available yet, using defaults")
      return
    end

    -- Now we can safely get metadata from TOC file
    self.ADDON_TITLE = GetAddOnMetadata(addonName, "Title") or "PushMaster"
    self.ADDON_AUTHOR = GetAddOnMetadata(addonName, "Author") or "Unknown"
    self.ADDON_VERSION = GetAddOnMetadata(addonName, "Version") or "1.1.0"
    self.DESCRIPTION = GetAddOnMetadata(addonName, "Notes") or
        "Track and compare Mythic+ key performance in real-time"

    self._metadataLoaded = true
    print("PushMaster: Constants metadata loaded from TOC")
  end
end

-- Helper function to get formatted version string
function PushMaster.Core.Constants:GetVersionString()
  self:LoadMetadata()
  return string.format("%s v%s", self.ADDON_TITLE, self.ADDON_VERSION)
end

-- Helper function to get full addon info
function PushMaster.Core.Constants:GetAddonInfo()
  self:LoadMetadata()
  return {
    name = self.ADDON_NAME,
    title = self.ADDON_TITLE,
    author = self.ADDON_AUTHOR,
    version = self.ADDON_VERSION,
    wowVersion = self.WOW_VERSION,
    description = self.DESCRIPTION
  }
end

-- Calculate mythic+ health/damage scaling modifier for any key level
-- @param keyLevel number The mythic+ key level
-- @return number The scaling modifier (e.g., 2.45 for +145% at level 13)
function PushMaster.Core.Constants:GetMythicPlusScalingModifier(keyLevel)
  if not keyLevel or keyLevel < 2 then
    return 1.0 -- No scaling below level 2
  end

  local scaling = self.MYTHIC_PLUS_SCALING

  -- Use known values for levels 2-15
  if scaling.HEALTH_DAMAGE_MODIFIERS[keyLevel] then
    return scaling.HEALTH_DAMAGE_MODIFIERS[keyLevel]
  end

  -- For levels above our known table, use the scaling formula
  if keyLevel > scaling.SCALING_BASE_LEVEL and keyLevel <= scaling.MAX_SUPPORTED_LEVEL then
    local levelsAboveBase = keyLevel - scaling.SCALING_BASE_LEVEL
    -- Apply compound 10% scaling: base * (1.10)^levels
    return scaling.SCALING_BASE_MODIFIER * (scaling.SCALING_MULTIPLIER ^ levelsAboveBase)
  end

  -- Fallback for extremely high keys (above MAX_SUPPORTED_LEVEL)
  if keyLevel > scaling.MAX_SUPPORTED_LEVEL then
    local levelsAboveBase = scaling.MAX_SUPPORTED_LEVEL - scaling.SCALING_BASE_LEVEL
    return scaling.SCALING_BASE_MODIFIER * (scaling.SCALING_MULTIPLIER ^ levelsAboveBase)
  end

  -- Fallback for edge cases
  return 1.0
end

-- Helper function to calculate scaling ratio between two key levels
-- @param sourceLevel number The source key level
-- @param targetLevel number The target key level
-- @return number The scaling ratio (targetModifier / sourceModifier)
function PushMaster.Core.Constants:GetMythicPlusScalingRatio(sourceLevel, targetLevel)
  local sourceModifier = self:GetMythicPlusScalingModifier(sourceLevel)
  local targetModifier = self:GetMythicPlusScalingModifier(targetLevel)

  if sourceModifier == 0 then
    return 1.0 -- Avoid division by zero
  end

  return targetModifier / sourceModifier
end

return PushMaster.Core.Constants
