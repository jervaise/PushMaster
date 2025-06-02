---@class PushMasterMinimapButton
---Minimap button module for PushMaster addon
---Provides minimap icon functionality using LibDBIcon-1.0
---Styled to match DotMaster addon visual consistency

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create MinimapButton module
local MinimapButton = {}
if not PushMaster.UI then
  PushMaster.UI = {}
end
PushMaster.UI.MinimapButton = MinimapButton

-- Local references
local isInitialized = false

---Handle minimap button clicks
local function onMinimapButtonClick(self, button)
  if button == "LeftButton" then
    -- Left click opens the settings menu
    if PushMaster.UI.SettingsFrame then
      if PushMaster.UI.SettingsFrame:IsShown() then
        PushMaster.UI.SettingsFrame:Hide()
      else
        PushMaster.UI.SettingsFrame:Show()
      end
    end
  end
  -- Removed right-click functionality and main frame toggle
end

---Initialize the minimap button
function MinimapButton:Initialize()
  if isInitialized then
    return
  end

  PushMaster:DebugPrint("MinimapButton module initialized")

  -- Check if required WoW API functions exist
  if not CreateFrame then
    PushMaster:Print("Error: CreateFrame API not available. Minimap functionality disabled.")
    return
  end

  -- Check for required libraries
  if not LibStub then
    PushMaster:Print("Error: LibStub not found. Minimap functionality disabled.")
    return
  end

  -- Try to create required library objects
  local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
  if not LDB then
    PushMaster:Print("Error: LibDataBroker-1.1 not found. Minimap functionality disabled.")
    return
  end

  local LibDBIcon = LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not LibDBIcon then
    PushMaster:Print("Error: LibDBIcon-1.0 not found. Minimap functionality disabled.")
    return
  end

  -- Initialize saved variables for minimap
  if not PushMasterDB.minimap then
    PushMasterDB.minimap = {
      hide = false,     -- Default to showing the icon
      minimapPos = 220, -- Default angle around minimap (220 degrees)
      radius = 80,      -- Default distance from minimap center
      lock = false
    }
  end

  -- Use PushMaster lightning icon from Media folder
  local iconPath = "Interface\\AddOns\\PushMaster\\Media\\flash"

  -- Create LDB object for minimap button
  PushMaster.minimapLDB = LDB:NewDataObject("PushMaster", {
    type = "launcher",
    text = "PushMaster",
    icon = iconPath,
    OnClick = function(self, button)
      onMinimapButtonClick(self, button)
    end,
    OnTooltipShow = function(tooltip)
      MinimapButton:OnTooltipShow(tooltip)
    end
  })

  -- Safety check to ensure the object was created
  if not PushMaster.minimapLDB then
    PushMaster:Print("Error: Failed to create minimap button data")
    return
  end

  -- Register with LibDBIcon
  LibDBIcon:Register("PushMaster", PushMaster.minimapLDB, PushMasterDB.minimap)

  -- Apply saved visibility state immediately
  if PushMasterDB.minimap.hide then
    LibDBIcon:Hide("PushMaster")
  else
    LibDBIcon:Show("PushMaster")
  end

  isInitialized = true
  PushMaster:DebugPrint("Minimap button created successfully")
end

---Show tooltip on hover
function MinimapButton:OnTooltipShow(tooltip)
  if not tooltip then return end

  tooltip:AddLine("PushMaster v" .. PushMaster:GetVersion())
  tooltip:AddLine("Track your Mythic+ performance", 1, 1, 1)
  tooltip:AddLine(" ")
  tooltip:AddLine("Left Click: Open settings", 0.7, 0.7, 0.7)

  -- Show current tracking status
  if PushMaster.Data and PushMaster.Data.Calculator then
    local isTracking = PushMaster.Data.Calculator:IsTrackingRun()
    if isTracking then
      local currentRun = PushMaster.Data.Calculator:GetCurrentRun()
      if currentRun and currentRun.instanceData then
        tooltip:AddLine(" ")
        tooltip:AddLine("Currently tracking:", 0, 1, 0)
        tooltip:AddLine(currentRun.instanceData.zoneName .. " +" .. currentRun.instanceData.cmLevel, 1, 1, 0)
      end
    end
  end

  -- Show test mode status
  if PushMaster.UI and PushMaster.UI.TestMode and PushMaster.UI.TestMode:IsActive() then
    tooltip:AddLine(" ")
    tooltip:AddLine("Test Mode Active", 1, 0.5, 0)
  end
end

---Toggle minimap icon visibility
function MinimapButton:Toggle()
  local LibDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not LibDBIcon then
    PushMaster:Print("Error: LibDBIcon-1.0 not available for toggle")
    return
  end

  -- Toggle visibility state
  PushMasterDB.minimap.hide = not PushMasterDB.minimap.hide

  -- Apply to minimap icon
  if PushMasterDB.minimap.hide then
    LibDBIcon:Hide("PushMaster")
    PushMaster:Print("Minimap icon hidden")
  else
    LibDBIcon:Show("PushMaster")
    PushMaster:Print("Minimap icon shown")
  end
end

---Show minimap icon
function MinimapButton:Show()
  local LibDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not LibDBIcon then
    return
  end

  PushMasterDB.minimap.hide = false
  LibDBIcon:Show("PushMaster")
end

---Hide minimap icon
function MinimapButton:Hide()
  local LibDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
  if not LibDBIcon then
    return
  end

  PushMasterDB.minimap.hide = true
  LibDBIcon:Hide("PushMaster")
end

---Check if minimap icon is visible
---@return boolean isVisible True if the minimap icon is visible
function MinimapButton:IsVisible()
  return not PushMasterDB.minimap.hide
end

---Lock/unlock minimap button position
function MinimapButton:SetLocked(locked)
  if not isInitialized then return end

  PushMasterDB.minimap.lock = locked
  if locked then
    LibDBIcon:Lock("PushMaster")
  else
    LibDBIcon:Unlock("PushMaster")
  end
end

---Check if minimap button is locked
function MinimapButton:IsLocked()
  if not isInitialized then return false end

  return PushMasterDB.minimap.lock
end

---Reset confirmation popup (moved from SettingsFrame)
StaticPopupDialogs["PUSHMASTER_RESET_CONFIRM"] = {
  text = "Are you sure you want to clear all best times?\n\n|cffff0000This action cannot be reversed!|r",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function()
    if PushMaster.Data.Calculator then
      if PushMaster.Data.Calculator:ClearBestTimes() then
        PushMaster:Print("All best times have been cleared.")
      else
        PushMaster:Print("No best times data to clear.")
      end
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
