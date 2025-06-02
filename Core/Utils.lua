---@class PushMasterUtils
---Utility functions module for PushMaster addon
---Provides common helper functions and utilities

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Initialize Core table if it doesn't exist
PushMaster.Core = PushMaster.Core or {}

-- Create Utils module
PushMaster.Core.Utils = {}

---Initialize the utils system
function PushMaster.Core.Utils:Initialize()
  print("PushMaster: Utils module initialized")
  -- TODO: Implement utility initialization
end

-- TODO: Implement utility functions
