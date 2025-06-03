# PushMaster - Real-time Mythic+ Delta Analyzer

**Version**: 0.9.2  
**Author**: Jervaise  
**WoW Version**: 11.1.5+ (The War Within Season 2)

## 🎯 What is PushMaster?

**PushMaster is a real-time Mythic+ delta analyzer** that answers one critical question: **"Am I ahead or behind the pace needed to time this key?"**

Unlike simple timers, PushMaster compares your current run against your personal best times and shows you **live delta analysis** - whether you're gaining or losing time relative to your successful runs. Perfect for pushing higher keys where every second matters.

### 🚀 Core Concept: Delta Analysis

- **Green (+15s)**: You're 15 seconds **ahead** of your best pace
- **Red (-23s)**: You're 23 seconds **behind** your best pace  
- **Intelligent Weighting**: Bosses and trash are weighted based on actual difficulty per dungeon
- **Real-time Updates**: See your pace change as you progress through the dungeon

## ✨ Key Features

- **🎯 Live Delta Display**: Instant feedback on whether you're ahead/behind schedule
- **🧠 Intelligent Analysis**: Dynamic boss weighting based on actual fight difficulty
- **📊 Smart Pacing**: Accounts for trash vs boss time ratios per dungeon
- **⚡ Simplified Design**: Clean, minimal interface focused on the data that matters
- **🔄 Automatic Learning**: Improves accuracy with each completed run

## 🎮 Why Keys +12 and Above?

PushMaster focuses on **serious key pushing** where timing precision matters most. In lower keys, completion is usually guaranteed - but in +12 and above, every second of pace analysis becomes critical for success.

## 📊 How Delta Analysis Works

### **Real-time Pace Comparison**
```
Current Run:  12:34 elapsed
Best Time:    11:50 at this point  
Delta:        -44s (behind pace)
```

### **Intelligent Weight Distribution**
PushMaster analyzes your completed runs to understand each dungeon's difficulty pattern:

```
Example: Ara-Kara Analysis
Boss Fight Durations:
  Avanoxx:    45s (Weight: 18%) - Quick fight
  Anub'zekt:  75s (Weight: 32%) - Major difficulty spike  
  Ki'katal:   52s (Weight: 22%) - Moderate difficulty
  
Dynamic Weights Applied:
  Trash Progress: 65% (majority of time spent)
  Boss Progress:  35% (weighted by individual difficulty)
```

### **Smart Milestone Tracking**
- Tracks progress at 5% dungeon completion increments
- Compares your current pace to your best run at each milestone
- Accounts for route variations and different pull strategies

## 🚀 Getting Started

1. **Install** PushMaster addon
2. **Complete** a few +12 or higher keys to build baseline data
3. **Watch** the real-time delta display during future runs
4. **Push** higher keys with confidence knowing your exact pace!

### **Commands**
- `/pm` - Toggle settings window
- Left-click minimap button - Open settings

## 🔬 Technical Improvements (v0.9.2)

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
- **Version**: 0.9.2
- **Focus**: Real-time Mythic+ delta analysis for serious key pushing

---

**PushMaster** - Because every second matters when pushing keys. Know your pace, push with confidence! 🚀 