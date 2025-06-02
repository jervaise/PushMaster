# PushMaster Development Guide

**Version**: Dynamic (from TOC)  
**Last Updated**: December 2024  
**Target WoW Version**: 11.1.5+ (The War Within Season 2)

## Overview

PushMaster is a simplified yet intelligent Mythic+ performance tracker designed for **The War Within Season 2**. This guide covers the technical architecture, development patterns, and design philosophy behind the addon.

## 🎯 Design Philosophy

### **Centralized Metadata**
- **Single Source of Truth**: All version and author information stored in `PushMaster.toc`
- **Dynamic References**: Code uses `GetAddOnMetadata()` to access TOC data
- **No Duplication**: Eliminates maintenance issues from multiple version definitions

### **Intelligent Simplicity**
- **One-line display** with maximum information density
- **Smart activation** - only for keys +12 and above where analysis matters
- **Dynamic intelligence** - learns from actual player data instead of assumptions

### **Data-Driven Approach (v0.0.2)**
- **Dynamic Weight Calculation** - Boss vs trash importance calculated from real run data
- **Milestone-based Analysis** - Uses actual progress points instead of linear assumptions
- **Dungeon-specific Intelligence** - Each dungeon gets realistic weights based on player performance

### **Performance Focus**
- Minimal UI overhead
- Efficient calculation algorithms
- Smart caching and data management

## 🏗️ Architecture Overview

```
PushMaster/
├── PushMaster.lua              # Main addon initialization
├── PushMaster.toc              # Addon metadata
├── Core/                     # Core functionality
│   ├── Constants.lua         # Global constants and configuration
│   ├── Config.lua           # Configuration management
│   ├── Utils.lua            # Utility functions
│   ├── Database.lua         # Data persistence and migration
│   └── Init.lua             # Initialization and startup
├── Data/                    # Data processing and analysis
│   ├── DungeonData.lua      # Dungeon definitions and metadata
│   ├── Calculator.lua       # Core calculation engine (NEW: Dynamic weights)
│   └── EventHandlers.lua    # WoW event processing
└── UI/                      # User interface components
    ├── MainFrame.lua        # Primary display frame
    ├── SettingsPanel.lua    # Settings integration
    ├── SettingsFrame.lua    # Settings UI
    ├── Themes.lua           # Visual themes and styling
    ├── MinimapButton.lua    # Minimap integration
    └── TestMode.lua         # Development testing (ENHANCED in v0.0.2)
```

## 🧮 Core Calculation Engine (v0.0.2)

### **Dynamic Weight Calculation**

The heart of PushMaster's intelligence is the dynamic weight system that calculates realistic importance of bosses vs trash based on actual run data:

```lua
-- Example: Necrotic Wake +15 Analysis
local function CalculateDungeonWeights(bestRunData)
    -- Calculate actual boss fight time from milestone data
    local totalBossTime = 0
    for _, boss in ipairs(bestRunData.bosses) do
        local bossTime = EstimateBossFightDuration(boss, bestRunData.milestones)
        totalBossTime = totalBossTime + bossTime
    end
    
    -- Calculate trash time (total - boss time)
    local totalTime = bestRunData.completionTime
    local trashTime = totalTime - totalBossTime
    
    -- Calculate dynamic weights
    local trashWeight = (trashTime / totalTime) * 0.8  -- 80% of weight pool
    local bossWeight = (totalBossTime / totalTime) * 0.8
    
    return {
        trashProgress = trashWeight,
        bossTimingEfficiency = bossWeight,
        bossCountImpact = 0.2  -- Fixed 20% for ahead/behind tracking
    }
end
```

### **Milestone-Based Analysis**

Instead of linear assumptions, PushMaster uses actual progress milestones:

```lua
-- Real milestone data from best runs
bestRunData = {
    milestones = {
        { progress = 15.2, time = 180 },  -- 15.2% at 3 minutes
        { progress = 32.8, time = 420 },  -- 32.8% at 7 minutes
        { progress = 58.1, time = 720 },  -- 58.1% at 12 minutes
        -- ... more milestones
    }
}
```

### **Boss Timing Intelligence**

Precise boss analysis with individual tracking:

```lua
-- Boss timing comparison
local function CalculateBossTimingEfficiency(currentRun, bestRun)
    local timeDifferences = {}
    local totalBestTime = 0
    
    for i, currentBoss in ipairs(currentRun.bosses) do
        local bestBoss = bestRun.bosses[i]
        if bestBoss then
            local timeDiff = currentBoss.killTime - bestBoss.killTime
            table.insert(timeDifferences, timeDiff)
            totalBestTime = totalBestTime + bestBoss.killTime
        end
    end
    
    -- Calculate efficiency as percentage
    local avgTimeDiff = CalculateAverage(timeDifferences)
    return (avgTimeDiff / bestRun.completionTime) * 100
end
```

## 🧪 Enhanced Test Mode (v0.0.2)

### **5x Speed Testing**

The test mode now runs at 5x speed for rapid validation:

```lua
local function testLoop()
    if not self.testActive then return end
    
    local speedMultiplier = 5  -- 5x speed for quick testing
    local deltaTime = 1 * speedMultiplier
    self.testTime = self.testTime + deltaTime
    
    -- Process test progression with real Calculator logic
    self:processTestProgression(deltaTime)
    self:updateTestDisplay(self.testTime)
    
    -- Schedule next update
    C_Timer.After(0.2, function() self:testLoop() end)
end
```

### **Real Calculator Integration**

Test mode now uses actual calculation logic instead of simulated data:

```lua
-- Start test with real Calculator integration
function TestMode:StartRun(mapID, keyLevel, affixes)
    if not PushMaster.Data.Calculator then
        PushMaster:Print("Calculator module not available")
        return
    end
    
    -- Create fake instance data for testing
    local fakeInstanceData = {
        mapID = mapID,
        keyLevel = keyLevel,
        affixes = affixes or {},
        startTime = GetTime()
    }
    
    -- Start run in Calculator with real logic
    PushMaster.Data.Calculator:StartRun(fakeInstanceData)
    PushMaster:Print("Test run started: " .. (mapID or "Unknown") .. " +" .. (keyLevel or 0))
end
```

### **Dynamic Weight Validation**

Test scenarios validate the dynamic weight calculation:

```lua
-- Test scenario with realistic pace changes
SAMPLE_RUN_DATA = {
    {
        name = "Necrotic Wake +15 - Pace Validation",
        mapID = 2286,
        keyLevel = 15,
        timeLimit = 1800,  -- 30 minutes
        bestRunData = {
            completionTime = 1620,  -- 27 minutes best time
            milestones = {
                { progress = 12.5, time = 150 },   -- Fast start
                { progress = 28.3, time = 380 },   -- Steady pace
                { progress = 45.7, time = 680 },   -- Slowdown phase
                { progress = 67.2, time = 1020 },  -- Recovery
                { progress = 89.4, time = 1380 },  -- Strong finish
                { progress = 100, time = 1620 }    -- Completion
            },
            bosses = {
                { name = "Blightbone", killTime = 420 },
                { name = "Amarth", killTime = 780 },
                { name = "Surgeon Stitchflesh", killTime = 1140 },
                { name = "Nalthor the Rimebinder", killTime = 1560 }
            }
        }
    }
}
```

## 📊 Data Flow

### **1. Event Detection**
```lua
-- Challenge mode start detection
CHALLENGE_MODE_START -> EventHandlers:OnChallengeStart()
```

### **2. Data Collection**
```lua
-- Progress tracking
SCENARIO_CRITERIA_UPDATE -> Calculator:UpdateProgress()
COMBAT_LOG_EVENT -> Calculator:ProcessCombatEvent()
```

### **3. Dynamic Analysis**
```lua
-- Real-time calculation with dynamic weights
Calculator:CalculateOverallEfficiency() -> {
    weights = CalculateDungeonWeights(bestRunData),
    trashProgress = CalculateTrashProgress(),
    bossEfficiency = CalculateBossTimingEfficiency(),
    deathImpact = CalculateDeathImpact()
}
```

### **4. UI Update**
```lua
-- Display update with intelligent formatting
MainFrame:UpdateDisplay(comparisonData)
```

## 🔧 Development Patterns

### **Centralized Metadata Access**

All addon metadata is stored in the TOC file and accessed dynamically:

```lua
-- ✅ CORRECT: Access metadata from TOC file
local version = GetAddOnMetadata(addonName, "Version")
local author = GetAddOnMetadata(addonName, "Author")
local title = GetAddOnMetadata(addonName, "Title")
local notes = GetAddOnMetadata(addonName, "Notes")

-- ✅ CORRECT: Use centralized constants
local Constants = PushMaster.Core.Constants
local version = Constants.ADDON_VERSION  -- Gets from TOC
local author = Constants.ADDON_AUTHOR    -- Gets from TOC

-- ✅ CORRECT: Use main addon references
local version = PushMaster.version  -- Set from TOC in PushMaster.lua
local author = PushMaster.author    -- Set from TOC in PushMaster.lua

-- ❌ WRONG: Hardcoded values
local version = "0.0.2"  -- Don't do this!
local author = "Jervaise"  -- Don't do this!
```

### **TOC File as Single Source of Truth**

The `PushMaster.toc` file contains all metadata:

```toc
## Interface: 110002
## Title: PushMaster
## Notes: Mythic+ Keystone Performance Tracker
## Author: Jervaise
## Version: 0.0.2
## SavedVariables: PushMasterDB
```

**To update version/author:**
1. ✅ **Only edit `PushMaster.toc`**
2. ✅ **All code automatically uses new values**
3. ❌ **Never edit version in code files**

### **Module Structure**
Each module follows a consistent pattern:
```lua
local ModuleName = {}
PushMaster.ModuleName = ModuleName

-- Private variables
local privateVar = {}

-- Public interface
function ModuleName:PublicMethod()
    -- Implementation
end

-- Initialization
function ModuleName:Initialize()
    -- Setup code
end
```

### **Error Handling**
```lua
-- Defensive programming with graceful degradation
local function safeCalculation()
    if not self.bestRunData or not self.currentRun then
        return self:GetDefaultComparison()
    end
    
    local success, result = pcall(function()
        return self:CalculateComplexMetric()
    end)
    
    if success then
        return result
    else
        PushMaster:Debug("Calculation failed: " .. tostring(result))
        return self:GetFallbackComparison()
    end
end
```

### **Performance Optimization**
```lua
-- Efficient caching and lazy evaluation
local calculationCache = {}
local lastCacheTime = 0

function Calculator:GetCachedComparison()
    local currentTime = GetTime()
    if currentTime - lastCacheTime < 0.5 then  -- 500ms cache
        return calculationCache
    end
    
    calculationCache = self:CalculateComparison()
    lastCacheTime = currentTime
    return calculationCache
end
```

## 🧪 Testing Strategy

### **Unit Testing with Test Mode**
```lua
-- Start comprehensive test
PushMaster.UI.TestMode:StartTest(1)  -- Necrotic Wake validation

-- Watch for dynamic weight calculations
-- Expected output:
-- "Dynamic weights calculated: Trash=59.6%, Boss=20.4%, Count=20%"
-- "Progress efficiency: +8.5% (ahead of best pace)"

-- Stop test
PushMaster.UI.TestMode:StopTest()
```

### **Real-World Validation**
1. **Run actual keys +12 and above**
2. **Compare predictions vs reality**
3. **Validate weight calculations**
4. **Test edge cases (deaths, route changes)**

## 🔮 Future Development

### **Planned Enhancements**
- **Multi-run learning** for improved accuracy
- **Route detection** for strategy-specific analysis
- **Group composition factors** for specialized calculations
- **Confidence intervals** for prediction reliability

### **Technical Debt**
- Refactor event handling for better performance
- Implement more sophisticated caching strategies
- Add comprehensive error recovery mechanisms
- Optimize memory usage for long sessions

## 📝 Version History

### **v0.0.2** (Current)
- ✅ **Dynamic Weight Calculation** - Boss vs trash importance from real data
- ✅ **Enhanced Test Mode** - 5x speed testing with real Calculator integration
- ✅ **Improved Calculation Logic** - Milestone-based analysis with dungeon-specific weights
- ✅ **Better Debug Output** - Comprehensive validation and development tools

### **v0.0.1** (Previous)
- ✅ Basic milestone-based analysis
- ✅ Simple boss timing comparison
- ✅ Fixed weight system
- ✅ Basic test mode

---

**PushMaster Development**: Building intelligent simplicity for serious key pushers. 