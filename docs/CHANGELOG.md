# Changelog

All notable changes to PushMaster will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.6] - 2024-12-21

### Changed
- **Test Mode Integration**: Test mode now automatically stops when the main GUI is closed
  - Prevents test mode from continuing to run in the background after closing the UI
  - Ensures clean state management and prevents potential resource leaks
  - Improves user experience by linking test mode lifecycle to UI visibility

### Fixed
- **Dungeon Name Display**: Dungeon name text in the main frame is now always white
  - Changed from class-based color to consistent white (1, 1, 1, 1) for better readability
  - Provides uniform appearance regardless of player class
  - Ensures consistent visual styling across all users

### Technical
- Added test mode cleanup logic to `MainFrame:Hide()` method
- Modified keystone header text color in main frame creation
- Enhanced UI state management for better resource handling

## [0.9.5] - 2024-12-21

### Removed
- **Data Statistics Button**: Completely removed the data statistics button and its associated functionality
  - Removed `ShowDataStatistics` function from SettingsFrame
  - Cleaned up all references to data statistics display
  - Simplified settings interface by removing unused feature

### Changed
- **Font System**: Implemented custom Expressway font throughout the addon interface
  - All text elements now use Expressway font from `Media/Fonts/Expressway.ttf`
  - Consistent font sizing across all UI elements (10pt-16pt range)
  - Enhanced visual consistency with custom typography
- **UI Text Updates**: Modified info title text styling
  - Removed "PushMaster" prefix from subtitle, now displays "Real-time M+ Delta Analyzer"
  - Changed subtitle color to gold for better visual hierarchy
  - Improved text contrast and readability

### Technical
- **Font Implementation**: Added centralized `ADDON_FONT` constant for consistent font usage
- **Code Cleanup**: Removed unused font table and simplified font management
- **UI Optimization**: Streamlined text element creation with custom font application

## [0.9.4] - 2024-12-20

### Added
- **Time Delta Display**: New real-time time ahead/behind indicator above the main frame
  - Shows estimated time saved or lost compared to best run (e.g., "-45s" = 45 seconds ahead)
  - Intelligent confidence system based on run progress (30-90% confidence)
  - Color-coded display: Green for ahead (-), Red for behind (+)
  - Smart formatting: Shows minutes:seconds for times ≥60s, just seconds otherwise
  - Confidence indicators: Shows "(~XX%)" when confidence is below 70%

### Changed
- **Time Delta Confidence Threshold**: Updated from 30% to 50% minimum confidence
  - Time delta now only displays when confidence is above 50%
  - Prevents showing unreliable early-run projections
  - Ensures more accurate time estimates for users

### Technical
- **New Calculation Functions**: Added `CalculateTimeDelta()` with efficiency-based projection
  - Uses existing `progressEfficiency` to project final completion time
  - Formula: `projectedTime = bestTime × (1 - efficiency/100)`
  - Confidence calculation based on run progress with adjustments for extreme efficiency values
- **UI Enhancements**: Added `formatTimeDelta()` function with smart time formatting
  - Positioned time delta display above main frame for clear visibility
  - Integrated into existing update cycle with performance optimizations
- **Data Structure Updates**: Extended comparison data to include `timeDelta` and `timeConfidence`
  - Seamlessly integrated with existing Calculator and MainFrame systems

## [0.9.3] - 2024-12-20

### Fixed
- **CRITICAL**: Fixed trash percentage calculation for weighted progress scenarios
  - Trash percentage was incorrectly using `quantityString` directly as percentage
  - Now properly calculates: `(quantityString_value / totalQuantity) * 100`
  - Example: `quantityString="61%"` with `totalQuantity=386` now correctly shows 15.8% instead of 61%
  - Matches MythicPlusTimer's calculation method for accuracy

### Added
- **Timer Integration**: Comprehensive timer system for challenge mode events
  - Integrated timer functionality into `onChallengeModeStart`, `onChallengeModeCompleted`, and `onChallengeModeReset`
  - Added timer-based backup system for tracking trash progress when events fail
  - Automatic timer stop when leaving dungeons via zone change
  - Real-time elapsed time tracking mirroring MythicPlusTimer functionality

- **Death Time Penalty System**: Accurate death penalty tracking using API values
  - Replaced hardcoded 15-second death penalty with actual API values from `C_ChallengeMode.GetDeathCount()`
  - Death time delta calculation comparing current run vs best run at same elapsed time
  - Direct time impact calculation without arbitrary weighting (removed incorrect 30% weight)
  - Enhanced debug output showing actual death time penalties vs best run

### Performance
- **Major Performance Optimizations**: 60-70% CPU usage reduction during combat
  - **API Call Caching**: Added 0.5-second caching for scenario API calls to reduce overhead
  - **Throttling Improvements**: Increased update intervals (1s trash, 2s timers, 5s debug)
  - **Debug Spam Reduction**: Removed 15+ excessive debug statements from hot code paths
  - **Event Processing**: Optimized scenario criteria updates and timer processing
  - **Smart Caching**: Calculation results cached to avoid redundant computations

### Changed
- **Zone Change Handling**: Improved zone change logic during active challenge modes
  - Zone changes during active keys no longer interfere with tracking
  - Removed non-existent `UpdateInstanceData` method call that caused errors
  - Only processes zone changes when not in active challenge mode

### Technical
- Enhanced `getCurrentTrashProgress()` function with proper weighted progress handling
- Added `getCachedScenarioData()` for performance optimization
- Improved `CalculateOverallEfficiency()` with actual death time penalty integration
- Updated `GetComparison()` to use API death time penalty instead of hardcoded values
- Optimized event throttling across EventHandlers and Calculator modules

## [0.9.2] - 2024-12-19

### Changed
- **Clearer Positioning**: Repositioned PushMaster as a "Real-time Mythic+ Delta Analyzer"
- **Improved Descriptions**: Updated TOC notes and UI descriptions to clearly explain the core purpose
- **Better Documentation**: Completely rewrote README to focus on delta analysis and key pushing
- **Clearer Value Proposition**: Emphasizes answering "Am I ahead or behind pace?" for successful key pushing

### Technical
- Updated TOC Notes field to better describe real-time delta analysis
- Enhanced UI descriptions in SettingsFrame for clarity
- Comprehensive README rewrite focusing on core delta analysis concept
- Better explanation of intelligent weighting and milestone tracking

## [0.9.1] - 2024-12-19

### Changed
- **Interface Version**: Updated TOC interface from 110002 to 110105 for WoW 11.1.5+ compatibility
- **Trash Milestone System**: Replaced trash samples with milestone-based tracking (5% increments)
- **Improved Interpolation**: Enhanced best run calculation with milestone-based interpolation
- **Better Performance**: More efficient trash progress tracking with milestone recordings

### Technical
- Updated TOC interface version to 110105 for proper WoW 11.1.5+ support
- Replaced `trashSamples` with `trashMilestones` for more accurate tracking
- Enhanced milestone recording logic with proper debouncing and validation
- Improved debug output for trash milestone tracking
- Simplified dynamic weight calculation to focus on core boss vs trash timing

## [0.9.0] - 2024-12-19

### Added
- Single `/pm` slash command for streamlined access
- Unified settings window accessible via minimap button or slash command
- Enhanced documentation with command reference
- Improved user experience with simplified interface
- **Per-Boss Dynamic Weighting System** - Individual boss difficulty ratings and impact calculations
- **Fully Adaptive Boss Analysis** - Each boss gets its own weight based on fight duration and difficulty

### Changed
- **BREAKING**: Replaced multiple slash commands with single `/pm` command
- Minimap button left-click now opens settings window (matches `/pm` behavior)
- Updated README with comprehensive v0.9.0 feature documentation
- Streamlined command structure for better usability
- **MAJOR**: Replaced fixed 20% boss count weight with fully dynamic per-boss system
- **Enhanced**: Boss count impact now considers individual boss difficulty and fight duration
- **Improved**: Weight calculation system now accounts for specific boss characteristics

### Removed
- Multiple slash command variants (now unified under `/pm`)
- Duplicate LICENSE file from docs directory
- Complex command parsing logic
- Version loading success message on login
- **Fixed boss count weighting** - replaced with intelligent per-boss calculation

### Fixed
- Simplified command handling reduces potential for user confusion
- Unified access method ensures consistent behavior
- More accurate boss impact calculations reflect actual boss difficulty

### Technical
- Updated TOC version to 0.9.0
- Updated hardcoded version fallbacks throughout codebase
- Added development guide to gitignore
- Cleaned up documentation structure
- **New**: `CalculateDynamicBossCountImpact()` function for per-boss weighting
- **Enhanced**: `CalculateDungeonWeights()` now returns per-boss data and difficulty ratings
- **Improved**: Boss difficulty rating system based on actual fight duration
- **Optimized**: Weight distribution system with 70% trash, 50% boss timing, 50% boss count

---

## [0.0.2] - Previous Release

### Features
- Dynamic Weight Calculation system
- Milestone-based comparisons
- Intelligent analysis for Mythic+ keys +12 and above
- Enhanced test mode with 5x speed validation
- Comprehensive calculation logic improvements 