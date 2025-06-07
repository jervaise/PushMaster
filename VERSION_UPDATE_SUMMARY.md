# PushMaster Version 1.2.0 Update Summary

## Version Information
- **Previous Version**: 1.1.0
- **New Version**: 1.2.0
- **Release Date**: 2025-01-05
- **WoW Compatibility**: 11.1.5 (The War Within)

## Files Updated

### 1. **PushMaster.toc**
- Updated `## Version:` from `1.1.0` to `1.2.0`
- Interface version remains `110105` (correct for WoW 11.1.5)

### 2. **PushMaster.lua**
- Updated all version references (4 instances) from `1.1.0` to `1.2.0`
- Lines: 13, 88, 155, 160

### 3. **Core/Constants.lua**
- Updated fallback version from `1.1.0` to `1.2.0`
- Line: 99

### 4. **UI/SettingsFrame.lua**
- Updated version display fallbacks (2 instances) from `1.1.0` to `1.2.0`
- Lines: 464, 794

### 5. **README.md**
- Updated version badge from `1.1.0` to `1.2.0`
- Updated footer version reference

### 6. **CHANGELOG.md**
- Added new entry for version 1.2.0 with all fixes and changes

## Key Changes in v1.2.0

### Fixes
1. **Test Mode Reset Issue**: Fixed the bug where stopping test mode would show "Recording" instead of default state
2. **Recording Mode Detection**: Fixed UpdateDisplay logic to properly respect explicit isRecording flag
3. **Settings GUI Spacing**: Improved layout with more space for sliders

### UI Improvements
- Settings frame height increased: 450px → 520px
- Content boxes height increased: 270px → 340px
- Better vertical spacing between UI elements

### Technical Improvements
- Added MainFrame timer control methods
- Improved default state management
- Enhanced cache clearing sequence

## Git Release Process

1. All files have been updated with version 1.2.0
2. Use the commands in `RELEASE_COMMANDS.txt` to:
   - Commit changes
   - Create version tag v1.2.0
   - Push to both current and main branches
   - Create GitHub release

## Testing Checklist
- [ ] Verify addon loads without errors
- [ ] Check version displays correctly in settings
- [ ] Confirm test mode stops properly (shows default state, not "Recording")
- [ ] Test settings GUI has proper spacing
- [ ] Verify compatibility with WoW 11.1.5 