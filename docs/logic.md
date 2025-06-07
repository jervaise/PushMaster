# PushMaster Addon Logic Documentation

## **Core Concept**
PushMaster tracks your current Mythic+ run and compares it in real-time against your best previous run to show if you're ahead or behind pace.

---

## **Data Sources**

### **Current Run Tracking:**
- **Trash Progress**: 0-100% from WoW scenario API
- **Boss Kills**: Count of bosses killed (0, 1, 2, 3, etc.)
- **Player Deaths**: Count of deaths by any party member
- **Run Metadata**: Map ID, key level, ~~affixes,~~ start time

### **Historical Data:**
- **Best Runs**: Fastest completion times per dungeon+key level
- **Best Run Timeline**: Trash %, boss kills, deaths at each point in time
- **Extrapolation**: Scale lower key level runs up to current key (optional)
- **Storage Policy**: Only one best run saved per dungeon per key level

---

## **User Interface**

### **Minimap Icon:**
- **Library**: Uses LibDBIcon-1.0 and LibDataBroker-1.1
- **Icon**: Flash icon from Media folder
- **Click Behavior**: Both left and right click open settings GUI
- **Tooltip**: Shows addon status, current run info if active
- **Visibility**: Controlled by checkbox in settings
- **Position**: Saved between sessions

### **Floating Frame:**
- **Dragon Texture**: Background image with 30% opacity
- **Dynamic Borders**: Color changes based on efficiency
  - Green: Ahead of pace (efficiency > 0)
  - Red: Behind pace (efficiency < 0)
  - Yellow: Exactly on pace (efficiency = 0)
- **Timer Frame**: Child frame showing time ahead/behind
- **Scale**: Adjustable via settings (50% - 150%)

### **Settings GUI:**
- **Configuration Tab**: Main settings and performance options
- **Test Mode Tab**: Run simulations without being in M+
- **Author Credit**: "by Jervaise" displayed at bottom

---

## **Debug System**

### **Debug Mode:**
- **Toggle Command**: `/pmdebug` to enable/disable
- **Settings Checkbox**: Also controllable via GUI
- **Debug Messages**: All debug output prefixed with "PushMaster Debug:"
- **Performance**: Debug messages only print when debug mode is enabled

### **Debug Output Includes:**
- Module initialization and enabling
- Run start/end with dungeon and key level
- Progress updates (throttled to every 5 seconds)
- Best run loading and saving
- Extrapolation usage
- Settings changes
- Performance adjustments

### **Debug Module API:**
```lua
Debug:Print(format, ...)  -- Print debug message if enabled
Debug:Toggle()           -- Toggle debug mode on/off
Debug:IsEnabled()        -- Check if debug mode is active
Debug:SetEnabled(bool)   -- Set debug mode state
```

---

## **Comparison Logic**

### **Efficiency Calculation:**
**Efficiency** = Overall % of how efficient we are compared to the best run
- **0%** = Exactly matching best run pace (on pace)
- **+5%** = 5% more efficient than best run
- **-5%** = 5% less efficient than best run

**Note**: Route variations don't need special handling - players can evaluate route success through the efficiency metric.

### **Component Tracking (Flat Differences):**

#### **Trash Progress:**
- **Current**: 45% trash cleared
- **Best Run**: 40% trash cleared at same time point
- **Difference**: +5% (ahead on trash)
- **Weight**: Always same weight in efficiency calculation

#### **Boss Kills:**
- **Current**: 2.75 bosses (2 complete + 3/4 progress on current boss)
- **Best Run**: 2.50 bosses at same time point  
- **Difference**: +0.25 bosses (ahead on current boss fight)
- **Weight**: Longer bosses have more weight in efficiency calculation
- **Gradual Progress**: Bosses credited in quarters (0.25, 0.50, 0.75, 1.00) during fight

#### **Deaths:**
- **Current**: 3 deaths total
- **Best Run**: 1 death at same time point
- **Difference**: +2 deaths (2 more deaths than best run)
- **Penalty**: Flat 15 seconds per death (30 seconds total penalty)
- **Design Decision**: All deaths treated equally with 15 second flat penalty

### **Weighted Efficiency:**
- **Trash Progress**: Base weight (consistent across all dungeons)
- **Boss Kills**: Variable weight based on boss fight duration
  - Short boss (60s): Weight 1.0
  - Long boss (180s): Weight 3.0
  - Very long boss (240s): Weight 4.0
- **Deaths**: Flat 15 second penalty per death (not weighted)

---

## **Key Level Scaling (Extrapolation)**

### **When Used:**
- No best run exists for current key level
- Setting enabled in GUI
- Lower key level run available for same dungeon

### **Scaling Logic:**
```
Source: +15 run completed in 1500 seconds
Target: +18 key
Scaling Ratio = GetMythicPlusScalingRatio(15, 18) = ~1.43
Extrapolated Time = 1500 × 1.43 = 2145 seconds
```

**Note**: Affixes are not considered in scaling as they no longer exist above +12 keys.

### **What Gets Scaled:**
- Total completion time timeline
- Boss kill timings
- Trash clear progression
- Death penalty impact (still 15s flat per death)

### **Depleted Extrapolation Warning:**
- When extrapolated run would exceed timer, show warning in GUI
- Example: `"vs +15 run (would be +2:30 over timer)"`
- Still show the pace comparison data
- Let user decide if comparison is meaningful

---

## **Data Flow Architecture**

```
Recording → API → Calculator → API → GUI
  ↑                ↓
TestMode          DB
```

### **Components:**

#### **Recording (EventHandlers)**
- Listens to WoW events
- Sends raw data to API
- No calculation logic

#### **API (Central Hub)**
- Maintains current run state
- Handles extrapolation logic
- Caches calculation results
- Manages DB save/load

#### **Calculator**
- Pure calculation logic
- Gets data from API
- Returns comparison results
- No external dependencies

#### **GUI**
- Gets all data through API
- Displays efficiency % (uses gradual boss progression internally)
- Shows flat differences with whole numbers:
  - Trash: "+5% ahead" (actual % difference)
  - Bosses: "+1 boss ahead" (actual killed boss count difference)
  - Deaths: "+2 deaths" (actual death count difference)

#### **Database**
- **Storage Policy**: Only store ONE best run per dungeon per key level
- **Best Run Replacement**: At run completion, compare times and replace if faster
- **No Historical Archive**: Previous best runs are overwritten, not archived
- Compress timeline data for storage efficiency
- Clean up invalid data on addon startup

---

## **Live Updates During Run**

### **Trash Progress Updates:**
- Updates every 0.25 seconds (throttled)
- Compares current % vs best run % at same time point
- Shows flat difference: "+5% ahead" or "-3% behind"

### **Boss Fight Updates:**
- **Boss Start**: Begin tracking fight duration, start at 0.00 boss credit (internal)
- **During Fight**: Gradually add boss credit in quarters (internal efficiency calculation):
  - At 25% of expected fight time: +0.25 boss credit
  - At 50% of expected fight time: +0.50 boss credit  
  - At 75% of expected fight time: +0.75 boss credit
  - At 100% (boss death): +1.00 boss credit (full boss)
- **GUI Display**: Always shows actual killed boss count difference (whole numbers)
- **Efficiency Calculation**: Uses gradual boss progress for smooth updates
- **Smooth Updates**: Prevents unrealistic efficiency jumps during long fights

### **Death Handling:**
- **Death Event**: Increment death counter
- **Time Impact**: Each death adds 15 seconds to effective run time for calculations
- **Efficiency Integration**: Deaths affect time baseline, making run effectively slower
- **Comparison**: Current deaths vs best run deaths at same time
- **Display**: Show "+2 deaths" with time penalty
- **Formula Impact**: Death penalty integrated into time calculations, not efficiency percentage

---

## **Calculation Examples**

### **Simple Efficiency Example:**
```
Current State (at 10:00 into run):
- Trash: 60% (best run had 55% at 10:00) = +5% ahead
- Bosses: 2 killed (best run had 2 killed at 10:00) = tied
- Deaths: 1 (best run had 0 at 10:00) = +1 death (-15s penalty)

Internal Efficiency Calculation:
- Effective Time: 10:00 + 15s death penalty = 10:15 effective time
- Boss Progress: 2.50 (best run had 2.25 at 10:15) = +0.25 boss progress
- Overall Efficiency: +3% (3% more efficient than best run at effective time)

GUI Display:
- Trash: "+5% ahead"
- Bosses: "Tied" (2 vs 2 actual kills)
- Deaths: "+1 death (-15s penalty)"
- Efficiency: "+3%"
```

### **Boss Weighting & Gradual Progress Example:**
```
Dungeon has 3 bosses:
- Boss 1: 60 second fight = weight 1.0
- Boss 2: 180 second fight = weight 3.0  
- Boss 3: 240 second fight = weight 4.0

Boss 3 Gradual Progress (240s expected duration):
- At 60s (25%): +0.25 boss credit
- At 120s (50%): +0.50 boss credit  
- At 180s (75%): +0.75 boss credit
- At 240s (100%): +1.00 boss credit

Being ahead 0.25 boss progress on Boss 3 affects efficiency 4x more than Boss 1
```

### **Death Penalty Example:**
```
Current run: 3 deaths
Best run: 1 death (at same time point)
Difference: +2 deaths
Penalty: 2 × 15 seconds = 30 seconds added to run time
```

---

## **Success Criteria**

### **Run Completion:**
- **Successful**: Timer completion (in time)
- **Failed**: Timer expired or key not completed

### **Best Run Save:**
- Only save if successful AND faster than current best for that key level
- **Storage**: One run per dungeon per key level (overwrites previous best)
- Include timeline data: trash % at each time point, gradual boss progress, death times
- Store boss fight durations for gradual progress calculations
- Update DB immediately after completion

---

## **Test Mode**

### **Purpose:**
- Test calculations with realistic scenarios
- Validate flat difference calculations work correctly
- Debug without running actual keys

### **Data Generation:**
- Sends same format data to API as Recording
- Realistic progression: trash %, boss kills, deaths over time
- Multiple scenarios: ahead/behind on different metrics

### **Validation:**
- Same calculation logic as real runs
- Verifies extrapolation works correctly
- Tests edge cases (no deaths, all bosses, etc.)

---

## **Performance Considerations**

### **Centralized Performance Configuration:**
- All update frequencies controlled by `Core/Performance.lua`
- User-configurable settings in GUI with slider interface
- Performance profiles: High/Balanced/Low
- Single point of control for all throttling/updates
- Easy optimization without code changes
- **Debug messages for performance changes**

### **Update Frequency Control:**
- **Trash Updates**: User-configurable via slider (default: 4/second)
- **Boss Updates**: User-configurable via slider (default: 2/second)  
- **Calculation Updates**: User-configurable via slider (default: 1/second)
- **Performance Modes**: Preset combinations for easy switching
- **GUI Slider**: Allows fine-tuning of update frequencies

### **Caching:**
- API caches calculation results
- Only recalculate when data changes
- Calculation frequency controlled by performance settings

### **Database:**
- **Storage Policy**: Only store ONE best run per dungeon per key level
- **Best Run Replacement**: At run completion, compare times and replace if faster
- **No Historical Archive**: Previous best runs are overwritten, not archived
- Compress timeline data for storage efficiency
- Clean up invalid data on addon startup

### **Event Handling:**
- Throttle all updates based on performance settings
- Batch updates where possible
- Configurable throttling intervals

---

## **Error Handling**

### **Invalid Data:**
- API reports: "Recording sent invalid data"
- Fix source module, not API
- Continue with last valid data

### **Missing Best Run:**
- Try extrapolation if enabled
- Show "No comparison data" in GUI
- Continue tracking current run

### **Calculation Errors:**
- Return last valid result
- Log error with context
- Don't crash addon 

## **Design Decisions & Rationale**

### **Route Agnostic:**
- No route detection or tracking needed
- Players evaluate route effectiveness through efficiency metric
- Simplifies comparison logic and storage

### **Affix Handling:**
- Affixes not tracked or considered (don't exist above +12)
- Simplifies extrapolation and comparison logic
- No need for affix-specific adjustments

### **Death Penalty:**
- Fixed 15 second penalty for all deaths
- No role-based or situational adjustments
- Consistent and predictable impact on efficiency

### **Performance Control:**
- User-controlled update frequencies via GUI slider
- No automatic performance metrics or monitoring
- Trust users to adjust based on their system

### **Data Retention:**
- Minimal storage: one best run per key level
- No run history or analytics
- Focus on current performance vs best performance 

## **Slash Commands**

### **Main Commands:**
- `/pm` or `/pushmaster` - Toggle settings GUI
- `/pmdebug` - Toggle debug mode

### **Debug Mode Usage:**
- Enable to see detailed addon operation
- Useful for troubleshooting issues
- Performance impact is minimal
- All modules support debug output 