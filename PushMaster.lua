---@class PushMaster
---Main addon file for PushMaster
---A World of Warcraft addon for tracking Mythic+ performance
---Adapted from MythicPlusTimer addon architecture

local addonName, addonTable = ...

-- Create main addon table and make it globally accessible
PushMaster = {}
addonTable.PushMaster = PushMaster

-- Metadata will be loaded after ADDON_LOADED event
PushMaster.version = "0.9.1"
PushMaster.author = "Loading..."

-- Debug mode flag
local debugMode = true

-- CRITICAL FIX: Add retry counter to prevent infinite timer recursion
local metadataRetryCount = 0
local MAX_METADATA_RETRIES = 5

-- CRITICAL FIX: Add initialization guard to prevent double-initialization
local isInitialized = false

---Print a message to chat
---@param message string The message to print
function PushMaster:Print(message)
  print("|cff00ff00PushMaster|r: " .. tostring(message))
end

---Print a debug message (only if debug mode is enabled)
---@param message string The debug message to print
function PushMaster:DebugPrint(message)
  if debugMode then
    print("|cff888888PushMaster Debug|r: " .. tostring(message))
  end
end

---Toggle debug mode
function PushMaster:ToggleDebug()
  debugMode = not debugMode
  self:Print("Debug mode " .. (debugMode and "enabled" or "disabled"))
end

-- Event frame for addon lifecycle events
local eventFrame = CreateFrame("Frame")

---Handle ADDON_LOADED event
---@param loadedAddonName string The name of the loaded addon
local function onAddonLoaded(loadedAddonName)
  if loadedAddonName ~= addonName then
    return
  end

  PushMaster:DebugPrint("Addon loaded, initializing...")

  -- Initialize saved variables (use placeholder version for now)
  if not PushMasterDB then
    PushMasterDB = {
      version = "0.9.1", -- Use hardcoded version for initial setup
      bestTimes = {},
      settings = {
        debugMode = false,
        showMainFrame = true,
        enabled = true,
        framePosition = { x = 100, y = -100 }
      },
      minimap = {
        hide = false,
        minimapPos = 220,
        radius = 80
      }
    }
    PushMaster:Print("First time setup completed")
  else
    -- Migration will be handled in PLAYER_LOGIN after metadata is loaded
    PushMaster:DebugPrint("Existing database found, migration will be handled after login")
  end

  -- Load debug mode setting
  if PushMasterDB.settings and PushMasterDB.settings.debugMode ~= nil then
    debugMode = PushMasterDB.settings.debugMode
  end

  -- Initialize core modules in dependency order (now that all files are loaded)
  PushMaster:InitializeModules()

  PushMaster:DebugPrint("Addon files loaded, waiting for login to complete initialization")
end

---Handle PLAYER_LOGIN event
local function onPlayerLogin()
  -- CRITICAL FIX: Implement retry counter and fallback to prevent infinite recursion
  if not GetAddOnMetadata then
    metadataRetryCount = metadataRetryCount + 1

    if metadataRetryCount <= MAX_METADATA_RETRIES then
      -- Don't show warning during normal retry process - this is expected behavior
      PushMaster:DebugPrint(string.format("Waiting for metadata API (attempt %d/%d)...",
        metadataRetryCount, MAX_METADATA_RETRIES))
      C_Timer.After(1, function()
        onPlayerLogin() -- Retry after 1 second
      end)
      return
    else
      -- Use more informative message - this is normal behavior, not an error
      PushMaster:DebugPrint("Metadata API not available after retries, using built-in values (this is normal)")
      PushMaster.version = "0.9.1"
      PushMaster.author = "Jervaise"
    end
  else
    -- Successfully got GetAddOnMetadata, load real values
    PushMaster.version = GetAddOnMetadata(addonName, "Version") or "0.9.1"
    PushMaster.author = GetAddOnMetadata(addonName, "Author") or "Jervaise"

    -- Only show debug message if we actually loaded from TOC
    if metadataRetryCount > 0 then
      PushMaster:DebugPrint(string.format("Metadata loaded successfully after %d attempts", metadataRetryCount))
    else
      PushMaster:DebugPrint("Metadata loaded successfully on first attempt")
    end
  end

  PushMaster:DebugPrint("Player logged in, starting event tracking...")

  -- Handle database migration now that we have the real version
  if PushMasterDB then
    if not PushMasterDB.version or PushMasterDB.version ~= PushMaster.version then
      PushMaster:DebugPrint("Migrating settings from version " ..
        (PushMasterDB.version or "unknown") .. " to " .. PushMaster.version)
      PushMasterDB.version = PushMaster.version
    end

    -- Add missing settings with defaults
    if not PushMasterDB.settings then
      PushMasterDB.settings = {}
    end
    if PushMasterDB.settings.enabled == nil then
      PushMasterDB.settings.enabled = true
    end

    if not PushMasterDB.minimap then
      PushMasterDB.minimap = {
        hide = false,
        minimapPos = 220,
        radius = 80
      }
    end
  end

  -- Start event tracking
  if PushMaster.Data and PushMaster.Data.EventHandlers then
    PushMaster.Data.EventHandlers:StartTracking()
  end

  -- Check if we're already in a Mythic+ dungeon (for reloads)
  if PushMaster.Data and PushMaster.Data.EventHandlers then
    if PushMaster.Data.EventHandlers:IsInMythicPlus() then
      PushMaster:DebugPrint("Already in Mythic+ dungeon, resuming tracking")
      local instanceData = PushMaster.Data.EventHandlers:GetCurrentInstanceData()
      if instanceData and PushMaster.Data.Calculator then
        PushMaster.Data.Calculator:StartNewRun(instanceData)
      end
    end
  end
end

---Handle PLAYER_LOGOUT event
local function onPlayerLogout()
  PushMaster:DebugPrint("Player logging out, saving settings...")

  -- Save debug mode setting
  if PushMasterDB and PushMasterDB.settings then
    PushMasterDB.settings.debugMode = debugMode
  end

  -- Stop event tracking
  if PushMaster.Data and PushMaster.Data.EventHandlers then
    PushMaster.Data.EventHandlers:StopTracking()
  end
end

-- Register addon lifecycle events
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    onAddonLoaded(...)
  elseif event == "PLAYER_LOGIN" then
    onPlayerLogin()
  elseif event == "PLAYER_LOGOUT" then
    onPlayerLogout()
  end
end)

---Initialize all addon modules in proper dependency order
function PushMaster:InitializeModules()
  -- CRITICAL FIX: Prevent double-initialization
  if isInitialized then
    self:DebugPrint("Modules already initialized, skipping")
    return
  end

  self:DebugPrint("Initializing modules...")

  -- Initialize Core modules first (Constants, Utils)
  if self.Core then
    if self.Core.Init then
      self.Core.Init:Initialize()
      self:DebugPrint("Init module initialized")
    end
    if self.Core.Database then
      self.Core.Database:Initialize()
      self:DebugPrint("Database module initialized")
    end
    if self.Core.Constants then
      self.Core.Constants:Initialize()
      self:DebugPrint("Constants module initialized")
    else
      self:DebugPrint("Constants module not found, skipping")
    end
    if self.Core.Utils then
      self.Core.Utils:Initialize()
      self:DebugPrint("Utils module initialized")
    end
  end

  -- Initialize Data modules (DungeonData, Calculator, EventHandlers)
  if self.Data then
    if self.Data.DungeonData then
      self.Data.DungeonData:Initialize()
      self:DebugPrint("DungeonData module initialized")
    end
    if self.Data.Calculator then
      self.Data.Calculator:Initialize()
      self:DebugPrint("Calculator module initialized")
    end
    if self.Data.EventHandlers then
      self.Data.EventHandlers:Initialize()
      self:DebugPrint("EventHandlers module initialized")
    end
  end

  -- Initialize UI modules last
  if self.UI then
    if self.UI.MainFrame then
      self.UI.MainFrame:Initialize()
      self:DebugPrint("MainFrame module initialized")
    end
    if self.UI.MinimapButton then
      self.UI.MinimapButton:Initialize()
      self:DebugPrint("MinimapButton module initialized")
    end
    if self.UI.SettingsFrame then
      self.UI.SettingsFrame:Initialize()
      self:DebugPrint("SettingsFrame module initialized")
    end
    if self.UI.TestMode then
      self.UI.TestMode:Initialize()
      self:DebugPrint("TestMode module initialized")
    end
  end

  -- Mark as initialized
  isInitialized = true
  self:DebugPrint("All modules initialized")
end

---Get addon version
---@return string version The addon version
function PushMaster:GetVersion()
  return self.version
end

---Get addon author
---@return string author The addon author
function PushMaster:GetAuthor()
  return self.author
end

---Check if debug mode is enabled
---@return boolean debugEnabled True if debug mode is enabled
function PushMaster:IsDebugEnabled()
  return debugMode
end

---Set debug mode state
---@param enabled boolean True to enable debug mode
function PushMaster:SetDebugMode(enabled)
  debugMode = enabled
  if PushMasterDB and PushMasterDB.settings then
    PushMasterDB.settings.debugMode = debugMode
  end
  self:DebugPrint("Debug mode " .. (debugMode and "enabled" or "disabled"))
end

-- Make PushMaster globally accessible for debugging
_G.PushMaster = PushMaster

-- Register slash commands
SLASH_PUSHMASTER1 = "/pm"

SlashCmdList["PUSHMASTER"] = function(msg)
  -- Toggle settings frame on /pm (same as minimap left-click)
  if PushMaster.UI and PushMaster.UI.SettingsFrame then
    local settings = PushMaster.UI.SettingsFrame
    if settings:IsShown() then
      settings:Hide()
    else
      settings:Show()
    end
  end
end
