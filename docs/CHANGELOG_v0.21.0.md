# Changelog v0.21.0 - Copy Feature & Code Refactoring

## [0.21.0] - 2025-12-28

### 🎨 Enhanced - File Operations & Code Quality

Complete implementation of copy functionality with floating dialog UI, cross-directory selection improvements, and major code refactoring for better maintainability.

### Added

#### Copy Feature
- **`c` key**: Copy selected files to current directory
  - Uses floating confirmation dialog (green border)
  - Shows source and destination paths
  - Supports cross-directory operations
  - Silent completion (no result dialog)
- **`SelectionManager#source_directory`**: Track directory where files were selected
  - Enables selecting files in one directory and copying/moving to another
  - Automatically set on first selection
  - Cleared when all selections are removed
- **Copy confirmation dialog**: Green-bordered floating window
  - Displays source and destination paths with smart truncation
  - Consistent with move/delete confirmation UI
  - `[Y]es` / `[N]o` / `ESC` to cancel

#### Multiple Selection Delete
- **Enhanced `x` key**: Delete multiple selected files
  - Checks for selected items first
  - Falls back to single file deletion if no selection
  - Uses floating confirmation dialog showing source path
  - Red border for warning (dangerous operation)

#### UI Improvements
- **Cross-directory selection display**: Selection marks only show in source directory
  - `is_selected?` method checks current directory matches source directory
  - Prevents confusion when navigating to different directories
  - Selection internally maintained for operations

### Changed

#### File Operations
- **Move operation** (`m` key): Uses source directory from SelectionManager
  - Select files → navigate to destination → press `m` to move
  - Blue-bordered confirmation dialog with paths
  - Silent completion
- **Delete operation** (`x` key):
  - Multiple selection support added
  - Shows source path in confirmation
  - Red-bordered warning dialog
- **All file operations** now use consistent floating dialog pattern:
  - Red: Delete (dangerous)
  - Blue: Move (informational)
  - Green: Copy (safe)

#### Code Quality
- **terminal_ui.rb refactored**: Reduced from 1139 to 1048 lines (-91 lines)
  - Removed duplicate text utility methods
  - Uses `TextUtils` module for all text operations
  - Better separation of concerns
- **TextUtils module enhanced**: Added `wrap_preview_lines` method
  - Centralized text display width calculation
  - Multi-byte character support (Japanese, etc.)
  - Consistent truncation and wrapping logic
- **Method call updates**: All `display_width`, `truncate_to_width` calls use `TextUtils.` prefix
  - Proper module method invocation
  - Fixed runtime errors from refactoring

#### Keybind Handler
- **Removed duplicate method definition**: `show_delete_confirmation`
  - Fixed warning about method redefinition
  - Single source of truth for delete confirmation
- **Unified confirmation methods**:
  - `show_move_confirmation(count, source_path, dest_path)`
  - `show_copy_confirmation(count, source_path, dest_path)`
  - `show_delete_confirmation(count, source_path)`

### Technical Changes

#### SelectionManager Enhancement
- **`@source_directory` tracking**: Remember where files were selected
- **`toggle_selection` updated**: Accepts `current_directory` parameter
  - Sets source directory on first selection
  - Maintains source directory for subsequent selections
  - Clears source when all items deselected
- **Cross-directory operation support**:
  - Select in `/path/A`
  - Navigate to `/path/B`
  - Execute move/copy/delete from original location

#### TextUtils Module
- **New method**: `wrap_preview_lines(lines, max_width)`
  - Intelligent line wrapping for preview pane
  - Preserves empty lines
  - Character-by-character width calculation
- **Improved display width calculation**: Handles full-width and half-width characters
- **Smart truncation**: Adds ellipsis when space permits

#### KeybindHandler Updates
- **`move_selected_to_current`**: Uses `@selection_manager.source_directory`
- **`copy_selected_to_current`**: New method following same pattern as move
- **`delete_current_file_with_confirmation`**: Checks for selected items first
- **`is_selected?(entry_name)`**: Validates current directory matches source
- **Path display helper**: `shorten_path(path, max_length)` for dialog display

### Bug Fixes

- **Fixed undefined method error**: `display_width` in terminal_ui.rb
  - Changed to `TextUtils.display_width`
  - Fixed all text utility method calls
- **Fixed method redefinition warning**: Removed duplicate `show_delete_confirmation`
- **Fixed cross-directory selection display**: Selection marks only show in source directory
  - Prevents showing same filename selected in different directories
  - Internal selection state maintained correctly

### Documentation

- **README.md updated**: Added copy operation documentation
  - Updated File Operations table with Copy row
  - Updated Operation Workflow with `c` key
  - Added copy to File Operations section
- **README_EN.md updated**: Same updates for English documentation

### Key Bindings Summary

#### File Selection & Operations
- `SPACE`: Select/deselect files and directories
- `m`: Move selected items to current directory (blue dialog)
- `c`: Copy selected items to current directory (green dialog)
- `x`: Delete selected items (red dialog)

#### Operation Workflow
```
1. SPACE → Select files/directories (multiple selection possible)
2. Choose operation key:
   - m → Move to current directory
   - c → Copy to current directory
   - x → Delete
3. Floating Dialog → Confirm with Y/N, ESC to cancel
```

#### Cross-Directory Operations
```
1. Navigate to source directory
2. SPACE → Select files
3. Navigate to destination directory (selection marks hidden)
4. m/c → Move or copy from source to current
   OR navigate back to source
5. x → Delete selected files
```

### UI Color Scheme

- **Copy dialog**: Green border (`\e[32m`) - safe operation
- **Move dialog**: Blue border (`\e[34m`) - informational
- **Delete dialog**: Red border (`\e[31m`) - warning/danger
- **Selection mark**: `✓` with green background (`\e[42m\e[30m`)
- **Selection visibility**: Only in source directory

### Code Metrics

- **Lines of code reduction**: terminal_ui.rb: 1139 → 1048 lines (-8%)
- **Test coverage**: 309 runs, 1407 assertions, 0 failures
- **Warnings fixed**: Method redefinition warning eliminated
- **Module organization**: Better separation with TextUtils module

### Migration Notes

- **No breaking changes**: All existing functionality preserved
- **New feature**: `c` key for copy operation
- **Behavior improvement**: Selection display now directory-aware
- **Code quality**: Internal refactoring with no user-facing changes

---

**Full Changelog**: [v0.20.0...v0.21.0](https://github.com/masisz/rufio/compare/v0.20.0...v0.21.0)
