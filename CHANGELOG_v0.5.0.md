# rufio v0.5.0 - Release Notes

## Added
- **Bookmark System**: Complete bookmark functionality for quick directory navigation
- **Interactive Bookmark Menu**: Floating dialog accessed via `b` key with Add/List/Remove operations
- **Quick Navigation**: Number keys (1-9) for instant bookmark jumping
- **Persistent Storage**: Automatic save/load bookmarks to `~/.config/rufio/bookmarks.json`
- **Bookmark Management**: Add current directory with custom names, list all bookmarks, remove by selection
- **Safety Features**: Duplicate name/path checking, directory existence validation, maximum 9 bookmarks limit
- **Multi-language Support**: English and Japanese bookmark interface messages
- **Comprehensive Test Suite**: Full TDD implementation with 15+ test cases covering all bookmark operations
- **Error Handling**: Graceful handling of non-existent paths, permission errors, and invalid inputs

## Changed
- **Help Messages Updated**: Latest keybinding information including bookmark operations in footer
- **KeybindHandler Enhanced**: Integrated bookmark menu and direct navigation functionality
- **DirectoryListing Improved**: Added `navigate_to_path` method for bookmark-based navigation
- **UI Layout Optimized**: Removed 3rd header row displaying bookmark shortcuts for cleaner interface
- **Documentation Updated**: Comprehensive README updates with bookmark usage examples and workflows

## Technical Implementation
- New `Bookmark` class with full CRUD operations and JSON persistence
- Floating window system for bookmark management dialogs
- Integration with existing terminal UI components and color system
- Automatic bookmark sorting by name for consistent display
- File system verification and path expansion for reliability
