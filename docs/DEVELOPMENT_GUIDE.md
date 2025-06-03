# PushMaster Development Guide

**Version**: Dynamic (from TOC)
**Target WoW Version**: 11.1.5+ (The War Within Season 2)

## Overview

PushMaster is a Mythic+ performance tracker for **The War Within Season 2**. This guide explains its technical setup, development practices, and design.

## 🎯 Design Philosophy

### **Centralized Metadata**
- All version and author info is in `PushMaster.toc`.
- Code uses `GetAddOnMetadata()` to get TOC data.
- This avoids issues from multiple version definitions.

### **Intelligent Simplicity**
- Shows lots of info on one line.
- Activates only for keys +12 and up.
- Learns from player data, not assumptions.

### **Data-Driven Approach**
- Boss vs. trash importance is calculated from real run data.
- Uses actual progress points, not linear guesses.
- Each dungeon gets realistic weights based on player performance.

### **Performance Focus**
- Minimal UI impact.
- Efficient calculations.
- Smart caching and data handling.

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
│   ├── Calculator.lua       # Core calculation engine (with dynamic weights)
│   └── EventHandlers.lua    # WoW event processing
└── UI/                      # User interface components
    ├── MainFrame.lua        # Primary display frame
    ├── SettingsPanel.lua    # Settings integration
    ├── SettingsFrame.lua    # Settings UI
    ├── Themes.lua           # Visual themes and styling
    ├── MinimapButton.lua    # Minimap integration
    └── TestMode.lua         # Development testing
```

## 🧮 Core Calculation Engine

### **Dynamic Weight Calculation**

PushMaster's core is its dynamic weight system. It calculates the importance of bosses versus trash using actual run data:

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

PushMaster uses actual progress milestones instead of assuming linear progress:

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

## 🧪 Enhanced Test Mode

### **5x Speed Testing**

Test mode runs at 5x speed for faster validation:

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

Test mode uses the actual calculation logic:

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

Test scenarios check the dynamic weight calculation:

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
            }
        }
    }
    -- ... more test scenarios ...
}
```

## ⚙️ WoW API and Events

PushMaster interacts with the WoW API for:
- Addon metadata (`GetAddOnMetadata`)
- Dungeon information (`C_ChallengeMode.GetMapUIInfo`)
- Player events (combat log, instance changes)

## 📚 Libraries and Dependencies

- No external libraries are used to keep it lightweight.

## 🤝 Contributing

1.  **Fork the repository.**
2.  **Create a feature branch:** `git checkout -b feature/your-feature-name`
3.  **Commit your changes:** `git commit -m 'Add some feature'`
    - Follow conventional commit messages (e.g., `feat:`, `fix:`, `docs:`)
4.  **Push to the branch:** `git push origin feature/your-feature-name`
5.  **Open a pull request.**

### **Code Style**
- Use the existing code style (Lua, 4-space indentation).
- Comment complex logic.

### **Testing**
- Utilize the in-game Test Mode for changes to the calculation engine.
- Test thoroughly in various Mythic+ scenarios.

## 📜 License

This project is licensed under the [MIT License](LICENSE). 