# CHANGELOG - rufio v0.9.0

**Release Date**: 2025-12-13

## 🚀 New Features

### Command Mode Input Floating Window

- **Floating Window for Command Input**: Command mode input now displays in a modern floating window
  - Moved from bottom line to centered floating window
  - Consistent with other UI elements (bookmarks, results)
  - Blue border for clear visual identification
  - Always-visible keyboard shortcuts help text

- **Integrated Completion Suggestions**: Tab completion suggestions display directly in the input window
  - Real-time suggestion list updates as you type
  - Clear visual separation between input and suggestions
  - No need to guess available commands

- **Enhanced Visual Feedback**:
  - Input prompt with cursor indicator
  - Automatic window sizing based on content
  - Clean, uncluttered interface
  - Professional appearance matching rufio's design language

### CommandModeUI Enhancements

- **New Method** (`show_input_prompt`): Displays command input in floating window
  - `show_input_prompt(input, suggestions)`: Shows input prompt with optional completion suggestions
  - Automatic integration with TerminalUI
  - Consistent color scheme (blue border, white content)

## 🎨 UI/UX Improvements

### Modern Command Input Experience

Before (v0.8.0):
```
[File listing...]
[Footer...]
:hello█                    ← Input at bottom of screen
```

After (v0.9.0):
```
[File listing centered behind floating window...]

┌────────────────────────────────────┐
│        コマンドモード              │  (Blue)
├────────────────────────────────────┤
│                                    │
│ hello_                             │
│                                    │
│ 補完候補:                          │
│   hello                            │
│   help                             │
│   health                           │
│                                    │
│ Tab: 補完 | Enter: 実行 | ESC: キャンセル │
└────────────────────────────────────┘
```

### Key Improvements

- **Centered Display**: Input window appears in screen center for better focus
- **Contextual Help**: Keyboard shortcuts always visible
- **Live Suggestions**: Completion suggestions update in real-time
- **Consistent Design**: Matches bookmark and result windows
- **No Screen Clutter**: Floating window doesn't interfere with file listing

## 🔧 Technical Improvements

### Architecture

- **Removed Legacy Methods**:
  - Removed `draw_command_input`: Bottom-line input rendering (obsolete)
  - Removed `draw_command_result`: Bottom-line result display (obsolete)
  - Cleaner codebase with focused responsibilities

- **TextUtils Enhancement**:
  - Added Unicode ranges for box drawing characters (\u2500-\u257F)
  - Added Unicode ranges for block elements (\u2580-\u259F)
  - Improved width calculation for special characters

### Integration

- **Automatic Display**: Command mode floating window shows automatically when activated
- **Suggestion Integration**: Autocomplete suggestions fetched and displayed seamlessly
- **Screen Refresh**: Proper screen redraw after command execution

## 🐛 Bug Fixes

### Display Width Issues

- **Fixed Cursor Symbol Display**: Changed from █ (full-width block) to _ (half-width underscore)
  - Resolved right border misalignment in command input window
  - Full-width block characters (█) have ambiguous width in different terminals
  - Underscore (_) ensures consistent width across all terminal emulators

- **Improved Character Width Detection**:
  - Added support for box drawing characters in TextUtils
  - Added support for block elements in TextUtils
  - More accurate display width calculation

- **Removed Colon Prefix**: Removed redundant `:` from input display
  - Window title already indicates "コマンドモード"
  - Cleaner, less cluttered appearance

## 🧪 Testing

### Test-Driven Development

- **TDD Approach**: All features developed following strict TDD methodology
  1. Wrote comprehensive tests first (4 new tests)
  2. Verified tests failed as expected
  3. Implemented features to pass tests
  4. Committed tests before implementation

### New Tests Added

- **Command Input Floating Window Tests** (`test/test_command_mode_ui.rb`):
  - `test_show_input_prompt_basic`: Basic input prompt display
  - `test_show_input_prompt_empty_input`: Empty input handling
  - `test_show_input_prompt_with_suggestions`: Suggestions display
  - `test_show_input_prompt_color`: Border color verification

### Test Coverage

- **20 tests, 60 assertions**: Comprehensive coverage of CommandModeUI
- **261 total tests, 1137 assertions**: Full test suite
- **All tests passing**: 100% success rate

## 📦 Dependencies

### No New Dependencies

- Uses existing Ruby standard library
- Leverages existing rufio components:
  - `DialogRenderer`: For floating window rendering
  - `CommandMode`: For command execution
  - `TextUtils`: For text width calculations

## 🔄 Compatibility

### Backward Compatibility

- **No Breaking Changes**: All existing features work as before
- **Enhanced UI**: Command mode now has better UX without changing functionality
- **Existing Keybindings Preserved**: `:` still activates command mode

### Platform Support

- **macOS**: Full support ✅
- **Linux**: Full support ✅
- **Windows**: Full support ✅

## ⚡ Performance

### Optimizations

- **No Performance Impact**: Floating window rendering is fast and efficient
- **Cached Calculations**: Window dimensions calculated once per render
- **Minimal Overhead**: Features only active when command mode is engaged

## 📝 Usage Examples

### Using the New Command Input

```bash
# Launch rufio
rufio

# Activate command mode
Press ':'

# Floating window appears in center:
┌────────────────────────────────────┐
│        コマンドモード              │
├────────────────────────────────────┤
│                                    │
│ _                                  │
│                                    │
│ Tab: 補完 | Enter: 実行 | ESC: キャンセル │
└────────────────────────────────────┘

# Type partial command
Type "he"

# Window updates with suggestions:
┌────────────────────────────────────┐
│        コマンドモード              │
├────────────────────────────────────┤
│                                    │
│ he_                                │
│                                    │
│ 補完候補:                          │
│   hello                            │
│   help                             │
│   health                           │
│                                    │
│ Tab: 補完 | Enter: 実行 | ESC: キャンセル │
└────────────────────────────────────┘

# Press Tab to complete
# Press Enter to execute
# Press ESC to cancel
```

### Visual Improvements

**Before (v0.8.0)**: Input at bottom of screen, suggestions not visible
**After (v0.9.0)**: Input in centered floating window, suggestions always visible

## 🔮 Future Plans

### Planned Enhancements

- **Command History**: Navigate through previously executed commands with ↑/↓ arrows
- **Command Arguments**: Support for commands with parameters
- **Auto-complete Menu**: Visual menu showing all available completions
- **Command Aliases**: User-defined shortcuts for frequently used commands
- **Inline Help**: Show command descriptions during completion

## 🙏 Acknowledgments

Main contributions in this version:

- **Test-Driven Development**: Strict TDD methodology ensuring code quality
- **Consistent UI/UX**: Unified floating window design across all features
- **User Experience Focus**: Improved command discoverability and feedback
- **Cross-platform Compatibility**: Cursor symbol fix for all terminal emulators

## 📋 Detailed Changes

### Files Modified

- `lib/rufio/command_mode_ui.rb`:
  - Added `show_input_prompt` method
  - Removed obsolete display code
- `lib/rufio/terminal_ui.rb`:
  - Integrated floating window for command input
  - Removed `draw_command_input` method
  - Removed `draw_command_result` method
- `lib/rufio/text_utils.rb`:
  - Enhanced character width detection
  - Added box drawing and block element ranges
- `test/test_command_mode_ui.rb`:
  - Added 4 new tests for input prompt display

### Files Created

- None (all changes to existing files)

### Lines of Code

- **Added**: ~50 lines (implementation)
- **Modified**: ~10 lines
- **Removed**: ~30 lines (obsolete methods)
- **Net Change**: ~30 lines added

### Commit History

```
478971b fix: カーソル記号を█から_に変更して表示崩れを修正
d09831f fix: 罫線文字とブロック要素の表示幅を修正
2ba2785 refactor: コマンドモード入力からコロンを削除
f89693a feat: コマンド入力をフローティングウィンドウに変更
3ab01af test: コマンド入力フローティングウィンドウのテストを追加
```

## 🎯 Summary

Version 0.9.0 brings a significant UI/UX improvement to command mode by introducing a modern floating window interface for command input. This change provides better visual feedback, integrates completion suggestions directly into the input window, and maintains consistency with other rufio features. All changes were developed using TDD methodology and are fully tested with 100% test pass rate.

---

**Note**: This version focuses on UI/UX polish and consistency. The command mode functionality remains the same, but the user experience is significantly enhanced with the new floating window interface.

**GitHub Issues**: [https://github.com/masisz/rufio/issues](https://github.com/masisz/rufio/issues)
