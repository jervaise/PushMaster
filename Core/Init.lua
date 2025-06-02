---@class PushMasterInit
---Core initialization module for PushMaster addon
---Handles addon loading, initialization, and global setup
---@author Jervaise (from TOC metadata)
---@version Dynamic (from TOC metadata)

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Initialize Core table if it doesn't exist
PushMaster.Core = PushMaster.Core or {}

-- Create the Init module
PushMaster.Core.Init = {}

---Initialize the core system
function PushMaster.Core.Init:Initialize()
  print("PushMaster: Core Init module initialized")
end
