# Changelog v0.20.0 - Project Mode Enhancement & UI Unification

## [0.20.0] - 2025-12-28

### 🎨 Enhanced - Project Mode UI Overhaul

Complete UI unification between normal mode and project mode, with improved bookmark management and script execution capabilities.

### Added

#### Script Directory Support
- **Auto-created scripts directory**: `~/.config/rufio/scripts`
  - Automatically created on first run
  - Configurable via `config.rb`
  - Default location: `~/.config/rufio/scripts`
- **Ruby script execution**: Execute custom Ruby scripts from project mode
  - List all `.rb` files in scripts directory
  - Execute scripts with `:` command mode
  - Sample `hello.rb` script included on initialization
- **`ProjectCommand#list_scripts`**: Returns list of available Ruby scripts
- **`ProjectCommand#execute_script`**: Executes selected script in project context

#### Bookmark Rename Feature
- **`r` key in project mode**: Rename bookmark with dialog
- **`Bookmark#rename(old_name, new_name)`**: Rename bookmark method
  - Automatic name trimming (leading/trailing spaces)
  - Duplicate name validation
  - Same name check
- **Rename dialog**: Yellow-bordered input dialog
  - Shows old name in title
  - Input validation
  - No result message (cleaner UX)

#### File Operations Enhancement
- **`r` key in normal mode**: Rename file/directory
- **`d` key in normal mode**: Delete file/directory with confirmation
- **`a` key**: Create file with dialog input (green border)
- **`A` key**: Create directory with dialog input (blue border)
- **`FileOperations#rename`**: Rename files and directories
  - Path separator validation
  - Empty name check
  - Existence validation
  - Conflict detection

#### Bookmark Management
- **`b` key in normal mode**: Direct bookmark addition
  - Shows directory name in title
  - Input dialog for bookmark name
  - Duplicate path detection
  - Green dialog for create operation
- **`r` key in project mode**: Rename bookmark at cursor
- **`d` key in project mode**: Delete bookmark at cursor
- **Unified operation dialogs**:
  - Green: Create operations (file, directory, bookmark)
  - Blue: Directory creation
  - Yellow: Rename operations
  - Red: Delete operations

### Changed

#### UI/UX Unification
- **Project mode selection UI** matches normal mode exactly
  - Selection mark: `✓ ` (checkmark) instead of `*`
  - Selected bookmark: Green background, black text (`\e[42m\e[30m`)
  - Cursor position: Highlighted with selected color from config
- **Separator display**: Added `│` separator between left and right panes in project mode
- **Footer display**: Unified with normal mode
  - Simple reverse video style (`\e[7m`)
  - Compact help text: `SPACE:select l:logs ::cmd r:rename d:delete ESC:exit j/k:move`
  - Log mode footer: `ESC:exit log j/k:move`
- **Right pane layout**: Matches normal mode with separator and content spacing

#### Bookmark Operations
- **Removed bookmark menu**: `b` key now directly adds bookmark
- **Cursor-based operations**: Rename/delete operate on cursor position
  - No selection dialog needed
  - Faster workflow (one less step)
- **Single selection model**: Simplified from multiple selection
  - `SPACE` key selects bookmark as project
  - Selected bookmark shown with checkmark
  - Improved command mode compatibility

#### Dialog Consistency
- **All operations use dialogs**: No status line messages
- **Color coding by operation type**:
  - Create: Green border
  - Directory: Blue border
  - Rename: Yellow border
  - Delete: Red border
- **No result messages**: Cleaner UX after operations complete
- **Input dialogs**: Consistent `show_input_dialog` interface

### Technical Changes

#### Code Organization
- **`KeybindHandler#is_bookmark_selected?`**: Removed (simplified selection model)
- **`KeybindHandler#toggle_bookmark_selection`**: Replaced with `select_bookmark_in_project_mode`
- **`KeybindHandler#select_bookmark_in_project_mode`**: Single selection for project mode
- **`KeybindHandler#add_bookmark`**: Direct bookmark addition without menu
- **`KeybindHandler#rename_bookmark_in_project_mode`**: Cursor-based rename
- **`KeybindHandler#delete_bookmark_in_project_mode`**: Cursor-based delete
- **`TerminalUI#draw_bookmark_list`**: Updated to match normal mode UI
- **`TerminalUI#draw_bookmark_detail`**: Added separator display
- **`TerminalUI#draw_log_preview`**: Added separator display
- **`ProjectMode#clear_selection`**: Clear selected project

#### Configuration
- **`ConfigLoader.scripts_dir`**: New configuration option
- **`ConfigLoader.default_scripts_dir`**: Default scripts directory path

### Removed

- **Bookmark menu**: Removed multi-option bookmark menu
  - `b` → `[A]dd` / `[L]ist` / `[R]emove` menu replaced with direct add
  - Individual operations now mapped to dedicated keys
- **Multiple selection in project mode**: Simplified to single selection
  - Removed `SelectionManager` integration for bookmarks
  - Better command mode compatibility
- **Result message dialogs**: Removed after rename/delete operations
  - Cleaner user experience
  - Operations complete silently on success

### Key Bindings Summary

#### Normal Mode
- `b`: Add bookmark (direct, no menu)
- `r`: Rename file/directory
- `d`: Delete file/directory (with confirmation)
- `a`: Create file
- `A`: Create directory

#### Project Mode
- `SPACE`: Select bookmark as project
- `r`: Rename bookmark at cursor
- `d`: Delete bookmark at cursor
- `l`: View logs
- `:`: Command mode
- `ESC`: Exit project mode

### UI Color Scheme

- **Selection mark**: `✓ ` (green background, black text)
- **Cursor highlight**: Config-defined selected color
- **Create dialogs**: Green border (`\e[32m`)
- **Directory dialogs**: Blue border (`\e[34m`)
- **Rename dialogs**: Yellow border (`\e[33m`)
- **Delete dialogs**: Red border (`\e[31m`)
- **Footer**: Reverse video (`\e[7m`)

### Bug Fixes

- **Fixed private method error**: `is_bookmark_selected?` visibility issue resolved
- **Fixed command mode in project mode**: Single selection model prevents conflicts
- **Fixed separator display**: Added missing `│` separator in project mode
- **Fixed footer positioning**: Unified footer line calculation

### Migration Notes

- **Breaking change**: `b` key no longer shows menu, directly adds bookmark
- **Behavior change**: Bookmark operations are now cursor-based in project mode
- **UI change**: Selection marks changed from `*` to `✓ `
- Scripts directory will be auto-created at `~/.config/rufio/scripts` on first use

---

**Full Changelog**: [v0.19.0...v0.20.0](https://github.com/masisz/rufio/compare/v0.19.0...v0.20.0)
