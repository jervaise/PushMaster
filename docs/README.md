# PushMaster - Intelligent Mythic+ Performance Tracker

**Version**: 0.9.0  
**Author**: Jervaise  
**WoW Version**: 11.1.5+ (The War Within Season 2)

A simplified yet intelligent addon for tracking Mythic+ dungeon performance in **The War Within Season 2** (11.1.5+). PushMaster provides precise, actionable feedback without overwhelming users with information.

## ✨ Key Features

### 🎯 **Simplified Design**
- **One-line display** with essential metrics only
- **Smart activation** - only shows for keys +12 and above
- **Clean interface** - no clutter, just what you need
- **Streamlined commands** - single `/pm` command for easy access

### 🧠 **Intelligent Analysis**
- **Dynamic Weight Calculation** - Automatically calculates boss vs trash importance based on YOUR best run data
- **Milestone-based comparisons** instead of linear assumptions
- **Learns from your actual performance patterns**
- **Dungeon-specific intelligence** - each dungeon gets its own realistic weights

### 📊 **Core Metrics**
- **⚡ Progress Efficiency**: Overall performance vs best run patterns (dynamically weighted)
- **🗑️ Trash Progress**: Milestone-based trash comparison  
- **👹 Boss Progress**: Precise boss timing difference
- **💀 Death Impact**: Clear death penalty tracking

### 🖱️ **Easy Access**
- **Minimap Button**: Left-click to open settings
- **Slash Command**: Type `/pm` to toggle settings window
- **Auto-positioning**: Drag displays to move them

## 🎮 Why Keys +12 and Above?

In **The War Within Season 2**, affixes no longer rotate at higher key levels, making performance more predictable and meaningful for comparison. PushMaster focuses on this range where:
- Performance patterns are consistent
- Intelligent analysis provides real value
- Comparisons are meaningful and actionable

## 🔧 How It Works

### **Dynamic Weight Calculation**
PushMaster analyzes your best run data to calculate how much time is actually spent on bosses vs trash in each specific dungeon:

```
Example: Necrotic Wake +15
- Boss fights: 7 minutes (25.5% of total time)
- Trash clearing: 20.5 minutes (74.5% of total time)

Dynamic Weights:
- Trash Progress: 59.6% weight (reflects actual time spent)
- Boss Timing: 20.4% weight (reflects actual boss difficulty)
- Boss Count: 20% weight (fixed for ahead/behind tracking)
```

This means:
- **Trash-heavy dungeons** weight trash performance more heavily
- **Boss-heavy dungeons** weight boss timing more heavily  
- **Each dungeon gets realistic weights** based on YOUR data

### **Intelligent Pace Calculation**
- **Milestone Interpolation**: Uses actual progress points from your best run
- **Boss Timing Analysis**: Compares individual boss kill speeds
- **Context-Aware**: Understands dungeon flow and pacing

### **Display Format**
```
[⚡][🟢+8%] [🗑️][🟡-2%] [👹][🟢+1] [💀][🔴2(+30s)]
```

## 🚀 Installation

1. Download and extract to your `Interface/AddOns/` folder
2. Restart World of Warcraft
3. Start running keys +12 and above
4. PushMaster automatically learns and provides intelligent feedback

## ⚙️ Configuration

PushMaster works automatically with minimal configuration needed:
- **Settings Access**: Click minimap button or type `/pm`
- **Auto-positioning**: Drag the display to move it
- **Smart tooltips**: Hover for detailed information
- **Automatic learning**: Improves accuracy with each run

## 🔬 Technical Improvements (v0.9.0)

### **Streamlined Interface**
- **Single Command**: `/pm` command replaces multiple slash commands
- **Unified Access**: Both minimap and command open the same settings window
- **Clean Design**: Removed unnecessary commands and complexity

### **Dynamic Weight System**
- Calculates actual time spent on bosses vs trash from best run data
- Estimates boss fight duration using milestone interpolation
- Applies realistic weights to pace calculation components
- Adapts to different dungeon types automatically

### **Enhanced Test Mode**
- **5x speed testing** for rapid validation
- **Multiple test scenarios** with realistic pace changes
- **Real Calculator integration** - uses actual calculation logic
- **Dynamic weight validation** - see how weights change per dungeon

### **Improved Calculation Logic**
- **Milestone-based trash comparison** instead of linear assumptions
- **Precise boss timing analysis** with individual boss tracking
- **Intelligent efficiency calculation** with dungeon-specific weights
- **Enhanced debug output** for development and validation

## 🧪 Testing & Validation

PushMaster includes a comprehensive test mode for validating calculations:

```lua
-- Start dynamic weight validation test
PushMaster.UI.TestMode:StartTest(1)  -- Necrotic Wake with pace changes
PushMaster.UI.TestMode:StartTest(2)  -- Mists with consistency test

-- Stop test
PushMaster.UI.TestMode:StopTest()
```

Test scenarios include:
- **Fast starts** with excellent pace
- **Slowdown phases** with deaths and struggles  
- **Recovery phases** with improved performance
- **Strong finishes** with fast boss kills

## 💻 Commands

- **`/pm`** - Toggle settings window

## 🔮 Future Enhancements

- **Multi-run learning** for improved predictions
- **Route-aware calculations** for different strategies
- **Group composition factors** for specialized analysis
- **Confidence intervals** for prediction accuracy

## 🔧 Compatibility

- **WoW Version**: 11.1.5+ (The War Within Season 2)
- **Key Levels**: +12 and above (intelligent analysis range)
- **Dependencies**: None required (self-contained)

## 📞 Support

For issues, suggestions, or contributions:
- **Author**: Jervaise
- **Version**: 0.9.0
- **Focus**: Simplified intelligence for serious key pushers

---

PushMaster: **Simple interface. Intelligent analysis. Better performance.** 