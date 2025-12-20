# Changelog v0.10.0 - Bookmark UI Enhancement

## [0.10.0] - 2025-01-XX

### 🎨 Enhanced - Bookmark UI Overhaul

Complete redesign of bookmark operations with modern floating window dialogs for improved user experience and consistency.

### Added

#### Floating Input Dialog System
- **New `DialogRenderer#show_input_dialog` method**: Unified floating window input interface
  - Centered floating dialog with customizable colors
  - Real-time character input with visual feedback
  - Multi-byte character support (Japanese, Chinese, etc.)
  - Automatic input trimming (leading/trailing spaces)
  - ESC key support for cancellation
  - Input width validation to prevent overflow

#### Enhanced Bookmark Operations

**Add Bookmark (`b` → `[A]`)**
- Floating input dialog with blue border
- Clear prompt: "Enter bookmark name:"
- Input indicator: `> ` for better visibility
- Automatic whitespace trimming
- Success/error feedback with colored dialogs
  - Green border for success
  - Red border for errors

**List Bookmarks (`b` → `[L]`)**
- Interactive selection from floating dialog
- Blue-bordered bookmark list
- Path truncation with `~` for home directory
- 1-9 number key selection
- Direct navigation to selected bookmark
- ESC key to cancel

**Remove Bookmark (`b` → `[R]`)**
- Two-stage confirmation process for safety
- Red-bordered selection dialog (warning color)
- Yellow-bordered confirmation dialog (caution color)
- Displays bookmark name in confirmation
- Success/error feedback dialogs
- ESC key support at all stages

### Changed

#### UI/UX Improvements
- **Consistent floating window interface** across all bookmark operations
- **Color-coded dialogs** for different operation types:
  - 🔵 Blue: Information and input (Add, List)
  - 🔴 Red: Warning and removal (Remove selection)
  - 🟡 Yellow: Confirmation (Remove confirmation)
  - 🟢 Green: Success messages
  - 🔴 Red: Error messages

#### Input Handling
- **Improved cursor positioning** in input dialogs
  - Proper padding from dialog borders
  - Correct vertical alignment accounting for title and separators
- **Better input field layout**
  - Input line positioned with `> ` prompt indicator
  - Adequate spacing between prompt and input area
  - No text overlapping with dialog borders

### Fixed

- **Input field positioning**: Text no longer overlaps with dialog borders
  - Fixed `input_y` calculation: `y + 4` → `y + 6`
  - Fixed `input_x` calculation: `x + 2` → `x + 4`
  - Fixed `max_input_width`: `dialog_width - 4` → `dialog_width - 8`
- **Bookmark list navigation**: Users can now navigate to bookmarks from the list view
- **Input trimming**: Leading and trailing spaces automatically removed from bookmark names
- **Dialog height**: Adjusted to prevent input line from touching bottom border

### Technical Details

#### New Components
```ruby
# DialogRenderer enhancements
- show_input_dialog(title, prompt, options)
- read_input_in_dialog(x, y, width, height, input_x, input_y, options)

# BookmarkManager enhancements
- show_result_dialog(title, message, type)
- show_remove_confirmation(bookmark_name)
```

#### Dialog Layout Improvements
```
Old layout (7 lines):
┌─────────────────────┐
│   Add Bookmark      │
├─────────────────────┤
│ Enter bookmark name:│ ← overlapped with border
└─────────────────────┘

New layout (8 lines):
┌─────────────────────┐
│   Add Bookmark      │
├─────────────────────┤
│                     │
│ Enter bookmark name:│
│                     │
│ >                   │ ← proper spacing
│                     │
└─────────────────────┘
```

#### Code Quality
- Removed unused variable warnings
- Consistent error handling across all bookmark operations
- Proper screen refresh after dialog operations
- All tests passing (261 runs, 1141 assertions, 0 failures)

### Migration Notes

**User-facing changes:**
- All bookmark operations now use floating dialogs
- No more bottom-of-screen input prompts
- Improved visual feedback for all operations
- More intuitive navigation and selection

**Developer notes:**
- `BookmarkManager` methods now return different types:
  - `add_interactive`: Still returns `Boolean`
  - `list_interactive`: Now returns `Hash` (selected bookmark) or `nil`
  - `remove_interactive`: Still returns `Boolean`
- `KeybindHandler` updated to handle new return types
- Dialog renderer supports input fields via `show_input_dialog`

### Dependencies

No new dependencies added. All changes use existing gems:
- `io-console` for character input
- Existing `dialog_renderer` infrastructure

---

**Full Diff Stats:**
- Modified: `lib/rufio/dialog_renderer.rb`
- Modified: `lib/rufio/bookmark_manager.rb`
- Modified: `lib/rufio/keybind_handler.rb`
- Tests: All passing ✅
