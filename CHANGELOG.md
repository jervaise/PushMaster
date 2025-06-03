# Changelog

All notable changes to PushMaster will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.1] - 2024-12-19

### Changed
- **Interface Version**: Updated TOC interface from 110002 to 110105 for WoW 11.1.5+ compatibility
- **Trash Milestone System**: Replaced trash samples with milestone-based tracking (5% increments)
- **Improved Interpolation**: Enhanced ghost car calculation with milestone-based interpolation
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