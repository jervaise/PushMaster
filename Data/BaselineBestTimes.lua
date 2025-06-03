---@class PushMasterBaselineBestTimes
---Baseline best times data for Season 2 dungeons
---Provides realistic reference times for +12 keys to help with calculations

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Create BaselineBestTimes module
local BaselineBestTimes = {}
if not PushMaster.Data then
  PushMaster.Data = {}
end
PushMaster.Data.BaselineBestTimes = BaselineBestTimes

-- Season 2 dungeon map IDs (from MDT data)
local SEASON_2_MAP_IDS = {
  [506] = "Cinderbrew Meadery",           -- Cinderbrew Meadery
  [504] = "Darkflame Cleft",              -- Darkflame Cleft
  [500] = "The Rookery",                  -- The Rookery
  [2649] = "Priory of Sacred Flame",      -- Priory of Sacred Flame (already exists in test data)
  [247] = "The MOTHERLODE!!",             -- The MOTHERLODE!!
  [525] = "Operation: Floodgate",         -- Operation: Floodgate
  [382] = "Theater of Pain",              -- Theater of Pain (already exists in test data)
  [2097] = "Operation Mechagon: Workshop" -- Operation Mechagon: Workshop (already exists in test data)
}

-- Baseline best times for +12 keys - realistic but achievable times
-- These represent solid runs that most groups can aspire to
local BASELINE_BEST_TIMES = {
  -- Cinderbrew Meadery
  [506] = {
    [12] = {
      time = 1620, -- 27:00 - moderate difficulty
      date = "2025-01-01 12:00:00",
      deaths = 2,
      affixes = { 10, 8, 3, 152 },                                        -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Brew Master Aldryr", killTime = 420,  bossNumber = 1 }, -- 7:00
        { name = "I'pa",               killTime = 900,  bossNumber = 2 }, -- 15:00
        { name = "Benk Buzzbee",       killTime = 1380, bossNumber = 3 }  -- 23:00
      },
      trashSamples = {
        { time = 180,  trash = 10 },
        { time = 360,  trash = 20 },
        { time = 540,  trash = 30 },
        { time = 720,  trash = 40 },
        { time = 900,  trash = 50 },
        { time = 1080, trash = 60 },
        { time = 1260, trash = 70 },
        { time = 1440, trash = 80 },
        { time = 1560, trash = 90 },
        { time = 1620, trash = 100 }
      }
    }
  },

  -- Darkflame Cleft
  [504] = {
    [12] = {
      time = 1560, -- 26:00 - moderate difficulty
      date = "2025-01-01 12:00:00",
      deaths = 1,
      affixes = { 10, 8, 3, 152 },                                     -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Ol' Waxbeard",    killTime = 360,  bossNumber = 1 }, -- 6:00
        { name = "Blazikon",        killTime = 780,  bossNumber = 2 }, -- 13:00
        { name = "The Candle King", killTime = 1320, bossNumber = 3 }  -- 22:00
      },
      trashSamples = {
        { time = 180,  trash = 10 },
        { time = 300,  trash = 20 },
        { time = 480,  trash = 30 },
        { time = 660,  trash = 40 },
        { time = 840,  trash = 50 },
        { time = 1020, trash = 60 },
        { time = 1200, trash = 70 },
        { time = 1320, trash = 80 },
        { time = 1440, trash = 90 },
        { time = 1560, trash = 100 }
      }
    }
  },

  -- The Rookery
  [500] = {
    [12] = {
      time = 1680, -- 28:00 - higher difficulty
      date = "2025-01-01 12:00:00",
      deaths = 3,
      affixes = { 10, 8, 3, 152 },                                           -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Kyrioss",               killTime = 480,  bossNumber = 1 }, -- 8:00
        { name = "Stormguard Gorren",     killTime = 960,  bossNumber = 2 }, -- 16:00
        { name = "Voidstone Monstrosity", killTime = 1440, bossNumber = 3 }  -- 24:00
      },
      trashSamples = {
        { time = 240,  trash = 10 },
        { time = 420,  trash = 20 },
        { time = 600,  trash = 30 },
        { time = 780,  trash = 40 },
        { time = 960,  trash = 50 },
        { time = 1140, trash = 60 },
        { time = 1320, trash = 70 },
        { time = 1500, trash = 80 },
        { time = 1620, trash = 90 },
        { time = 1680, trash = 100 }
      }
    }
  },

  -- Priory of Sacred Flame (already exists in test data, but adding baseline)
  [2649] = {
    [12] = {
      time = 1620, -- 27:00 - moderate difficulty
      date = "2025-01-01 12:00:00",
      deaths = 2,
      affixes = { 10, 8, 3, 152 },                                       -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Captain Dailcry",   killTime = 420,  bossNumber = 1 }, -- 7:00
        { name = "Baron Braunpyke",   killTime = 840,  bossNumber = 2 }, -- 14:00
        { name = "Prioress Murrpray", killTime = 1500, bossNumber = 3 }  -- 25:00
      },
      trashSamples = {
        { time = 180,  trash = 10 },
        { time = 360,  trash = 20 },
        { time = 540,  trash = 30 },
        { time = 720,  trash = 40 },
        { time = 900,  trash = 50 },
        { time = 1080, trash = 60 },
        { time = 1260, trash = 70 },
        { time = 1440, trash = 80 },
        { time = 1560, trash = 90 },
        { time = 1620, trash = 100 }
      }
    }
  },

  -- The MOTHERLODE!!
  [247] = {
    [12] = {
      time = 1740, -- 29:00 - higher difficulty
      date = "2025-01-01 12:00:00",
      deaths = 4,
      affixes = { 10, 8, 3, 152 },                                                  -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Coin-Operated Crowd Pummeler", killTime = 480,  bossNumber = 1 }, -- 8:00
        { name = "Azerokk",                      killTime = 960,  bossNumber = 2 }, -- 16:00
        { name = "Rixxa Fluxflame",              killTime = 1560, bossNumber = 3 }  -- 26:00
      },
      trashSamples = {
        { time = 240,  trash = 10 },
        { time = 420,  trash = 20 },
        { time = 600,  trash = 30 },
        { time = 780,  trash = 40 },
        { time = 1020, trash = 50 },
        { time = 1200, trash = 60 },
        { time = 1380, trash = 70 },
        { time = 1560, trash = 80 },
        { time = 1680, trash = 90 },
        { time = 1740, trash = 100 }
      }
    }
  },

  -- Operation: Floodgate
  [525] = {
    [12] = {
      time = 1500, -- 25:00 - lower difficulty
      date = "2025-01-01 12:00:00",
      deaths = 1,
      affixes = { 10, 8, 3, 152 },                                      -- Fortified, Sanguine, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "Speaker Brokk",    killTime = 360,  bossNumber = 1 }, -- 6:00
        { name = "E.D.N.A",          killTime = 720,  bossNumber = 2 }, -- 12:00
        { name = "The Coaglamation", killTime = 1260, bossNumber = 3 }  -- 21:00
      },
      trashSamples = {
        { time = 150,  trash = 10 },
        { time = 300,  trash = 20 },
        { time = 450,  trash = 30 },
        { time = 600,  trash = 40 },
        { time = 780,  trash = 50 },
        { time = 960,  trash = 60 },
        { time = 1140, trash = 70 },
        { time = 1260, trash = 80 },
        { time = 1380, trash = 90 },
        { time = 1500, trash = 100 }
      }
    }
  },

  -- Theater of Pain (already exists in test data, but adding baseline)
  [382] = {
    [12] = {
      time = 1560, -- 26:00 - moderate difficulty
      date = "2025-01-01 12:00:00",
      deaths = 1,
      affixes = { 7, 11, 3, 152 },                                               -- Tyrannical, Bursting, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "An Affront of Challengers", killTime = 420,  bossNumber = 1 }, -- 7:00
        { name = "Gorechop",                  killTime = 780,  bossNumber = 2 }, -- 13:00
        { name = "Xav the Unfallen",          killTime = 1140, bossNumber = 3 }, -- 19:00
        { name = "Kul'tharok",                killTime = 1440, bossNumber = 4 }  -- 24:00
      },
      trashSamples = {
        { time = 180,  trash = 10 },
        { time = 360,  trash = 20 },
        { time = 540,  trash = 30 },
        { time = 720,  trash = 40 },
        { time = 900,  trash = 50 },
        { time = 1080, trash = 60 },
        { time = 1260, trash = 70 },
        { time = 1380, trash = 80 },
        { time = 1500, trash = 90 },
        { time = 1560, trash = 100 }
      }
    }
  },

  -- Operation Mechagon: Workshop (already exists in test data, but adding baseline)
  [2097] = {
    [12] = {
      time = 1800, -- 30:00 - highest difficulty
      date = "2025-01-01 12:00:00",
      deaths = 5,
      affixes = { 8, 11, 3, 152 },                                           -- Fortified, Bursting, Volcanic, Challenger's Peril
      bossKillTimes = {
        { name = "The Platinum Pummeler", killTime = 660,  bossNumber = 1 }, -- 11:00
        { name = "Gnomercy 4.U.",         killTime = 1140, bossNumber = 2 }, -- 19:00
        { name = "Machinist's Garden",    killTime = 1440, bossNumber = 3 }, -- 24:00
        { name = "King Mechagon",         killTime = 1740, bossNumber = 4 }  -- 29:00
      },
      trashSamples = {
        { time = 300,  trash = 10 },
        { time = 540,  trash = 20 },
        { time = 780,  trash = 30 },
        { time = 1020, trash = 40 },
        { time = 1200, trash = 50 },
        { time = 1380, trash = 60 },
        { time = 1560, trash = 70 },
        { time = 1680, trash = 80 },
        { time = 1740, trash = 90 },
        { time = 1800, trash = 100 }
      }
    }
  }
}

---Initialize baseline best times in the Calculator
function BaselineBestTimes:Initialize()
  PushMaster:DebugPrint("BaselineBestTimes module initialized - baseline data available as fallback only")

  -- Baseline data is now kept only in code and used as fallback
  -- No longer importing baseline data into saved variables to reduce file size
  PushMaster:DebugPrint("Baseline data available for " .. table.getn(SEASON_2_MAP_IDS) .. " Season 2 dungeons")

  -- Clean up any existing baseline data from saved variables
  self:CleanupBaselineFromSavedVars()
end

---Clean up baseline data from saved variables to reduce file size
function BaselineBestTimes:CleanupBaselineFromSavedVars()
  local Calculator = PushMaster.Data.Calculator
  if not Calculator then
    return
  end

  local existingBestTimes = Calculator:GetBestTimes()
  local cleanedData = {}
  local removedCount = 0

  -- Copy only non-baseline data (data that differs from baseline)
  for mapID, levels in pairs(existingBestTimes) do
    for level, data in pairs(levels) do
      local baselineData = self:GetBaselineTime(mapID, level)

      -- Keep the data if it's not baseline data (different time, date, etc.)
      local isBaseline = false
      if baselineData then
        -- Check if this matches baseline data exactly
        if data.time == baselineData.time and
            data.date == baselineData.date and
            data.deaths == baselineData.deaths then
          isBaseline = true
          removedCount = removedCount + 1
        end
      end

      if not isBaseline then
        if not cleanedData[mapID] then
          cleanedData[mapID] = {}
        end
        cleanedData[mapID][level] = data
      end
    end
  end

  if removedCount > 0 then
    Calculator:ImportBestTimes(cleanedData)
    PushMaster:Print(string.format("Cleaned up %d baseline entries from saved variables", removedCount))
  else
    PushMaster:DebugPrint("No baseline data found in saved variables to clean up")
  end
end

---Get baseline best times data
---@return table baselineData The baseline best times data
function BaselineBestTimes:GetBaselineData()
  return BASELINE_BEST_TIMES
end

---Get Season 2 dungeon map IDs
---@return table mapIDs The Season 2 dungeon map IDs
function BaselineBestTimes:GetSeason2MapIDs()
  return SEASON_2_MAP_IDS
end

---Check if a dungeon is part of Season 2
---@param mapID number The map ID to check
---@return boolean isS2 True if the dungeon is part of Season 2
function BaselineBestTimes:IsSeason2Dungeon(mapID)
  return SEASON_2_MAP_IDS[mapID] ~= nil
end

---Get dungeon name by map ID
---@param mapID number The map ID
---@return string|nil dungeonName The dungeon name or nil if not found
function BaselineBestTimes:GetDungeonName(mapID)
  return SEASON_2_MAP_IDS[mapID]
end

---Get baseline time for a specific dungeon and key level
---@param mapID number The map ID
---@param keyLevel number The key level
---@return table|nil baselineTime The baseline time data or nil if not found
function BaselineBestTimes:GetBaselineTime(mapID, keyLevel)
  if BASELINE_BEST_TIMES[mapID] and BASELINE_BEST_TIMES[mapID][keyLevel] then
    return BASELINE_BEST_TIMES[mapID][keyLevel]
  end
  return nil
end
