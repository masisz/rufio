# Changelog - v0.30.0

## Release Date: 2025-12-30

## New Features & Improvements

### Help System Overhaul

#### Help Mode (Press `?`)
- **Full-screen help mode** instead of popup dialog
  - Browse help documentation files in `info/` directory
  - Uses normal file manager UI for navigation
  - Navigation restricted to `info/` directory (cannot go to parent)
  - Press `ESC` to exit help mode and return to previous directory

#### Help Documentation
- Converted all help files to **Markdown format** (`.md`)
- **Unified language**: All documentation now in English
- Created comprehensive help files:
  - `info/welcome.md` - Introduction and quick start guide
  - `info/help.md` - Complete feature documentation with table of contents
  - `info/keybindings.md` - Full keybindings reference organized by category

### Preview Pane Scrolling

#### Enter Key Behavior Change
- Press `Enter` on a **file** to focus preview pane (instead of doing nothing)
- Press `Enter` on a **directory** to navigate into it (unchanged)
- Preview pane shows `[PREVIEW MODE]` indicator when focused

#### Scroll Controls in Preview Mode
- `j` / `↓` : Scroll down one line
- `k` / `↑` : Scroll up one line
- `Ctrl+D` : Scroll down half page (20 lines)
- `Ctrl+U` : Scroll up half page (20 lines)
- `ESC` : Exit preview mode and return focus to directory list

#### Smart Scroll Management
- Scroll position automatically resets when changing files
- Scroll position cannot go below zero
- Works in both **normal mode** and **help mode**

### UI Improvements

#### Footer Enhancements
- **Bookmark list with numbers**: `0.dirname 1.bookmark1 2.bookmark2 ...`
- **Bookmark 0**: Jump to startup directory with `0` key
- **Processing time**: Display render time in milliseconds
- **Help hint**: `?:help` shown on the right side
- Removed time and version display from footer (simplified layout)

#### Project Mode Improvements
- Bookmark list displays with numbers: `1. project1`, `2. project2`, etc.
- Improved consistency with bookmark number navigation

### Header Improvements
- Help mode indicator: `[Help Mode - Press ESC to exit]`
- Version information moved to help dialog

## Technical Changes

### New Methods

**KeybindHandler**:
- `help_mode?` - Check if help mode is active
- `enter_help_mode` - Enter help mode (navigate to `info/` directory)
- `exit_help_mode` - Exit help mode and return to previous directory
- `navigate_parent_with_restriction` - Navigate parent with `info/` directory restriction
- `preview_focused?` - Check if preview pane is focused
- `focus_preview_pane` - Focus preview pane (file only)
- `unfocus_preview_pane` - Unfocus preview pane
- `preview_scroll_offset` - Get current scroll offset
- `scroll_preview_down` - Scroll preview down one line
- `scroll_preview_up` - Scroll preview up one line
- `scroll_preview_page_down` - Scroll preview down half page (Ctrl+D)
- `scroll_preview_page_up` - Scroll preview up half page (Ctrl+U)
- `reset_preview_scroll` - Reset scroll position
- `handle_enter_key` - Handle Enter key (focus preview or navigate)
- `handle_preview_focus_key` - Handle keys in preview mode

**TerminalUI**:
- `draw_header` - Updated to show help mode indicator
- `draw_footer` - Updated to show bookmarks with numbers and processing time
- `draw_file_preview` - Updated to apply scroll offset and show preview mode indicator

### Modified Behavior

**Keybindings**:
- `?` - Enter help mode (was: show help dialog)
- `Enter` - Focus preview pane on files / Navigate on directories (was: navigate only)
- `h` - Navigate parent with restriction in help mode (was: unrestricted)
- `ESC` - Exit help mode or unfocus preview pane (was: clear filter only)

**Directory Navigation**:
- `DirectoryListing#initialize` - Save startup directory as `start_directory`
- `KeybindHandler#goto_start_directory` - Jump to startup directory with `0` key

### Layout Constants
- `HEADER_FOOTER_MARGIN = 3` - Header + Footer (2-line layout)

## Usage Guide

### Help Mode
1. Press `?` to enter help mode
2. Navigate help files using `j/k/h/l` keys
3. Press `Enter` or `l` to view a help file
4. Press `h` to go back (restricted to `info/` directory)
5. Press `ESC` to exit help mode

### Preview Scrolling
1. Select a file with `j/k` keys
2. Press `Enter` to focus preview pane
3. Use `j/k` or arrow keys to scroll line by line
4. Use `Ctrl+D` / `Ctrl+U` for page scrolling
5. Press `ESC` to return to directory list

### Bookmarks
- `b` - Add current directory to bookmarks
- `0` - Jump to startup directory
- `1-9` - Jump to bookmarks 1-9
- `p` - Enter project mode (browse all bookmarks)

## Testing

### New Test Files
- `test/test_help_mode.rb` - Help mode functionality tests
- `test/test_preview_scroll.rb` - Preview scrolling tests

### Test Results
- **329 tests** passing
- **1444 assertions**
- **0 failures**
- **0 errors**

## Compatibility

- Ruby 3.0 or higher
- Maintains compatibility with existing configuration files
- Maintains compatibility with existing bookmark data
- All help files now in English (breaking change for Japanese users)

## Known Issues

None

---

**Full Changelog**: v0.21.0...v0.30.0
