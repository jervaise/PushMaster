# PushMaster v0.9.6 - Test Mode & UI Improvements

## New Features & Changes

### Test Mode Integration
- **Automatic Test Stop**: Test mode now automatically stops when the main GUI is closed
- Prevents test mode from running in the background after closing the UI
- Improves resource management and prevents potential memory leaks
- Better user experience with linked test mode lifecycle to UI visibility

### UI Improvements
- **Consistent Dungeon Name Display**: Dungeon name text is now always white for all players
- Changed from class-based color to uniform white for better readability
- Consistent visual styling regardless of player class
- Enhanced overall UI consistency

### Technical Improvements
- Enhanced UI state management for better resource handling
- Added test mode cleanup logic to main frame hide method
- Improved lifecycle management for background processes

## Installation & Usage

Simply install and use `/pm` to access all features. The addon automatically shows when you enter Mythic+ dungeons and provides real-time delta analysis compared to your best runs.

Perfect for key pushers who want to know if they're ahead or behind pace for successful completion!

---

## About PushMaster

PushMaster is a **Real-time Mythic+ Delta Analyzer** that shows whether you're ahead or behind your best pace for successful key pushing. Perfect for players who want to improve their Mythic+ performance by tracking real-time progress against their personal best times.

### Key Features
- Real-time pace analysis during Mythic+ runs
- Time delta display showing if you're ahead/behind your best time
- Intelligent confidence system based on run progress
- Dynamic weighting system for accurate comparisons
- Clean, customizable interface with class-colored theming

### Installation
1. Download and extract to your `Interface/AddOns/` folder
2. Restart World of Warcraft
3. Use `/pm` command or click the minimap button to configure

### Support
- **Commands**: `/pm` (settings), `/pm debug` (toggle debug), `/pm help` (show commands)
- **Compatibility**: WoW 11.1.5+ (The War Within)
- **GitHub**: [PushMaster Repository](https://github.com/jervaise/PushMaster)

---

*This update focuses on visual improvements and code cleanup to provide a better user experience with the custom Expressway font and simplified interface.* 