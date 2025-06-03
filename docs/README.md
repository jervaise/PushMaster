# PushMaster - Intelligent Mythic+ Performance Tracker

**Version**: 0.9.1  
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
- **Per-Boss Intelligence** - Each boss gets its own difficulty rating and impact weight
- **Milestone-based comparisons** instead of linear assumptions
- **Learns from your actual performance patterns**
- **Dungeon-specific intelligence** - each dungeon gets its own realistic weights

### 📊 **Core Metrics**
- **⚡ Progress Efficiency**: Overall performance vs best run patterns (dynamically weighted)
- **🗑️ Trash Progress**: Milestone-based trash comparison  
- **👹 Boss Progress**: Precise boss timing difference with per-boss difficulty weighting
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
PushMaster analyzes your best run data to calculate how much time is actually spent on bosses vs trash in each specific dungeon, with **individual boss difficulty ratings**:

```
Example: Necrotic Wake +15
- Boss 1 (Blightbone): 1.2 min fight, Difficulty 2.0, Weight 4.3%
- Boss 2 (Amarth): 2.1 min fight, Difficulty 3.5, Weight 7.6%  
- Boss 3 (Surgeon): 1.8 min fight, Difficulty 3.0, Weight 6.5%
- Boss 4 (Nalthor): 2.4 min fight, Difficulty 4.0, Weight 8.7%
- Trash clearing: 20.5 minutes (72.9% of total time)

Dynamic Weights:
- Trash Progress: 51.1% weight (reflects actual time spent)
- Boss Timing: 13.1% weight (reflects actual boss fight time)  
- Boss Count: 13.1% weight (per-boss difficulty weighted)
- Individual Boss Impact: Harder bosses = higher impact when ahead/behind
```

This means:
- **Each boss** gets its own difficulty rating based on fight duration
- **Harder bosses** (longer fights) have more impact when you're ahead/behind
- **Trash-heavy dungeons** weight trash performance more heavily
- **Boss-heavy dungeons** weight boss performance more heavily
- **Every component** adapts to YOUR actual run data

### **Intelligent Pace Calculation**
- **Milestone Interpolation**: Uses actual progress points from your best run
- **Per-Boss Timing Analysis**: Compares individual boss kill speeds with difficulty weighting
- **Context-Aware**: Understands dungeon flow and pacing
- **Boss Difficulty Learning**: Identifies which bosses are hardest for your group

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

## 🔬 Technical Improvements (v0.9.1)

### **Streamlined Interface**
- **Single Command**: `/pm` command replaces multiple slash commands
- **Unified Access**: Both minimap and command open the same settings window
- **Clean Design**: Removed unnecessary commands and complexity

### **Fully Dynamic Boss System**
- **Individual Boss Analysis**: Each boss gets its own difficulty rating and weight
- **Fight Duration Learning**: Longer boss fights = higher difficulty rating
- **Per-Boss Impact Calculation**: Being ahead/behind on harder bosses has more impact
- **Adaptive Weighting**: Boss vs trash weights calculated from YOUR actual time investment
- **No Fixed Weights**: Everything adapts based on real performance data

### **Enhanced Test Mode**
- **5x speed testing** for rapid validation
- **Multiple test scenarios** with realistic pace changes
- **Real Calculator integration** - uses actual calculation logic
- **Dynamic weight validation** - see how weights change per dungeon and per boss

### **Improved Calculation Logic**
- **Milestone-based trash comparison** instead of linear assumptions
- **Precise boss timing analysis** with individual boss tracking and difficulty weighting
- **Intelligent efficiency calculation** with fully dynamic weights
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
- **Per-boss difficulty validation** with varying boss kill speeds

## 💻 Commands

- **`/pm`** - Toggle settings window

## 🔮 Future Enhancements

- **Multi-run learning** for improved predictions
- **Route-aware calculations** for different strategies
- **Group composition factors** for specialized analysis
- **Confidence intervals** for prediction accuracy
- **Boss mechanic difficulty** weighting beyond just time investment

## 🔧 Compatibility

- **WoW Version**: 11.1.5+ (The War Within Season 2)
- **Key Levels**: +12 and above (intelligent analysis range)
- **Dependencies**: None required (self-contained)

## 📞 Support

For issues, suggestions, or contributions:
- **Author**: Jervaise
- **Version**: 0.9.1
- **Focus**: Simplified intelligence for serious key pushers

---

PushMaster: **Simple interface. Intelligent analysis. Better performance.** 