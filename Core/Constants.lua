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
    self.ADDON_VERSION = GetAddOnMetadata(addonName, "Version") or "0.9.3"
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

return PushMaster.Core.Constants
