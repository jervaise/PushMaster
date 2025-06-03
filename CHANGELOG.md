# Changelog

All notable changes to PushMaster will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2024-12-19

### Added
- Single `/pm` slash command for streamlined access
- Unified settings window accessible via minimap button or slash command
- Enhanced documentation with command reference
- Improved user experience with simplified interface

### Changed
- **BREAKING**: Replaced multiple slash commands with single `/pm` command
- Minimap button left-click now opens settings window (matches `/pm` behavior)
- Updated README with comprehensive v0.9.0 feature documentation
- Streamlined command structure for better usability

### Removed
- Multiple slash command variants (now unified under `/pm`)
- Duplicate LICENSE file from docs directory
- Complex command parsing logic
- Version loading success message on login

### Fixed
- Simplified command handling reduces potential for user confusion
- Unified access method ensures consistent behavior

### Technical
- Updated TOC version to 0.9.0
- Updated hardcoded version fallbacks throughout codebase
- Added development guide to gitignore
- Cleaned up documentation structure

---

## [0.0.2] - Previous Release

### Features
- Dynamic Weight Calculation system
- Milestone-based comparisons
- Intelligent analysis for Mythic+ keys +12 and above
- Enhanced test mode with 5x speed validation
- Comprehensive calculation logic improvements 