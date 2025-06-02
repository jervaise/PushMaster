-- PushMasterDatabase - Database management module
-- Handles saved variables, data persistence, and database operations

local addonName, addonTable = ...
local PushMaster = addonTable.PushMaster

-- Initialize Core table if it doesn't exist
PushMaster.Core = PushMaster.Core or {}

-- Create the Database module
PushMaster.Core.Database = {}

-- Database schema version for migrations
local SCHEMA_VERSION = 1

-- Default database structure
local DEFAULT_DB = {
  version = SCHEMA_VERSION,
  runs = {},
  settings = {
    windowPosition = { x = 100, y = 100 },
    windowSize = { width = 300, height = 60 },
    displayMode = "compact",
    updateFrequency = 5,
    showInCombat = true,
    theme = "elvui",
    opacity = 0.9,
    locked = false
  },
  statistics = {
    totalRuns = 0,
    totalTime = 0,
    bestOverallTime = nil,
    worstOverallTime = nil
  }
}

-- Character-specific default data
local DEFAULT_CHAR_DB = {
  version = SCHEMA_VERSION,
  preferences = {
    firstRun = true,
    showTutorial = true,
    lastDungeon = nil,
    lastKeyLevel = nil
  }
}

---Initialize the database system
function PushMaster.Core.Database:Initialize()
  print("PushMaster: Initializing database...")

  -- Initialize global database
  if not PushMasterDB then
    PushMasterDB = self:_deepCopy(DEFAULT_DB)
    print("PushMaster: Created new database")
  else
    self:_validateAndMigrate(PushMasterDB, DEFAULT_DB)
  end

  -- Initialize character-specific database
  if not PushMasterCharDB then
    PushMasterCharDB = self:_deepCopy(DEFAULT_CHAR_DB)
    print("PushMaster: Created new character database")
  else
    self:_validateAndMigrate(PushMasterCharDB, DEFAULT_CHAR_DB)
  end

  print("PushMaster: Database initialized successfully")
end

---Get the global database
function PushMaster.Core.Database:GetDB()
  return PushMasterDB
end

---Get the character-specific database
function PushMaster.Core.Database:GetCharDB()
  return PushMasterCharDB
end

---Save a completed run to the database
function PushMaster.Core.Database:SaveRun(dungeonID, keyLevel, runData)
  if not self:_validateRunData(runData) then
    print("PushMaster: Error: Invalid run data")
    return false
  end

  local db = self:GetDB()

  -- Initialize dungeon data if it doesn't exist
  if not db.runs[dungeonID] then
    db.runs[dungeonID] = {}
  end

  if not db.runs[dungeonID][keyLevel] then
    db.runs[dungeonID][keyLevel] = {
      bestRun = nil,
      allRuns = {}
    }
  end

  -- Add to all runs history
  table.insert(db.runs[dungeonID][keyLevel].allRuns, runData)

  -- Check if this is a new best run
  local currentBest = db.runs[dungeonID][keyLevel].bestRun
  if not currentBest or runData.totalTime < currentBest.totalTime then
    db.runs[dungeonID][keyLevel].bestRun = self:_deepCopy(runData)
    print(string.format("PushMaster: New best time for %s +%d!",
      self:_getDungeonName(dungeonID), keyLevel))
    return true
  end

  return true
end

---Get the best run data for a specific dungeon and key level
function PushMaster.Core.Database:GetBestRun(dungeonID, keyLevel)
  local db = self:GetDB()

  if db.runs[dungeonID] and
      db.runs[dungeonID][keyLevel] and
      db.runs[dungeonID][keyLevel].bestRun then
    return db.runs[dungeonID][keyLevel].bestRun
  end

  return nil
end

---Get all runs for a specific dungeon and key level
function PushMaster.Core.Database:GetAllRuns(dungeonID, keyLevel)
  local db = self:GetDB()

  if db.runs[dungeonID] and
      db.runs[dungeonID][keyLevel] and
      db.runs[dungeonID][keyLevel].allRuns then
    return db.runs[dungeonID][keyLevel].allRuns
  end

  return {}
end

---Update addon settings
function PushMaster.Core.Database:UpdateSettings(settings)
  local db = self:GetDB()

  for key, value in pairs(settings) do
    if db.settings[key] ~= nil then
      db.settings[key] = value
    end
  end
end

---Get addon settings
function PushMaster.Core.Database:GetSettings()
  return self:GetDB().settings
end

---Reset all data with optional confirmation
function PushMaster.Core.Database:ResetAllData(confirmed)
  if not confirmed then
    return false
  end

  PushMasterDB = self:_deepCopy(DEFAULT_DB)
  PushMasterCharDB = self:_deepCopy(DEFAULT_CHAR_DB)

  print("PushMaster: All data has been reset")
  return true
end

-- Private helper functions

---Validate run data structure
function PushMaster.Core.Database:_validateRunData(runData)
  if type(runData) ~= "table" then
    return false
  end

  -- Required fields
  local requiredFields = { "totalTime", "timeline", "dungeonID", "keyLevel", "timestamp" }
  for _, field in ipairs(requiredFields) do
    if runData[field] == nil then
      print("PushMaster: Missing required field: " .. field)
      return false
    end
  end

  -- Validate timeline structure
  if type(runData.timeline) ~= "table" then
    return false
  end

  return true
end

---Validate and migrate database structure
function PushMaster.Core.Database:_validateAndMigrate(db, defaultDB)
  -- Check version and perform migrations if needed
  -- Handle both string and number versions
  local currentVersion = db.version
  local targetVersion = SCHEMA_VERSION

  -- Convert string version to number if needed
  if type(currentVersion) == "string" then
    -- If it's a semantic version like "0.0.1", treat as version 0 for migration
    currentVersion = 0
  elseif not currentVersion then
    currentVersion = 0
  end

  if currentVersion < targetVersion then
    print("PushMaster: Migrating database from version " .. tostring(db.version or "unknown") .. " to " .. targetVersion)
    self:_migrateDatabase(db, defaultDB)
    db.version = targetVersion
  end

  -- Ensure all default keys exist
  self:_ensureDefaultKeys(db, defaultDB)
end

---Migrate database from older version
function PushMaster.Core.Database:_migrateDatabase(db, defaultDB)
  -- TODO: Implement specific migration logic for different versions
  print("PushMaster: Database migration completed")
end

---Ensure all default keys exist in database
function PushMaster.Core.Database:_ensureDefaultKeys(db, defaultDB)
  for key, value in pairs(defaultDB) do
    if db[key] == nil then
      db[key] = self:_deepCopy(value)
    elseif type(value) == "table" and type(db[key]) == "table" then
      self:_ensureDefaultKeys(db[key], value)
    end
  end
end

---Create a deep copy of a table
function PushMaster.Core.Database:_deepCopy(original)
  -- Handle non-table types
  if type(original) ~= "table" then
    return original
  end

  local copy = {}
  for key, value in pairs(original) do
    if type(value) == "table" then
      copy[key] = self:_deepCopy(value)
    else
      copy[key] = value
    end
  end
  return copy
end

---Get dungeon name by ID (placeholder)
function PushMaster.Core.Database:_getDungeonName(dungeonID)
  -- TODO: Implement proper dungeon name lookup
  return "Unknown Dungeon"
end
