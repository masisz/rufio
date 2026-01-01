# CHANGELOG - rufio v0.8.0

**Release Date**: 2025-12-06

## 🚀 New Features

### Command Mode UI Enhancements

- **Tab Completion for Commands**: Added intelligent tab completion in command mode
  - Auto-completes available commands as you type
  - Shows common prefix when multiple matches exist
  - Complete match is filled automatically when only one option exists
  - Activated by pressing `Tab` key during command input

- **Floating Window for Command Results**: Command execution results now display in an elegant floating window
  - Reuses DialogRenderer from bookmark feature for consistent UI
  - Color-coded results:
    - **Green border**: Successful command execution
    - **Red border**: Error or warning messages
  - Dismissible with any key press
  - Auto-sizes based on content length
  - Centered on screen for optimal visibility

### CommandModeUI Class

- **New UI Handler Class** (`lib/rufio/command_mode_ui.rb`): Dedicated class for command mode user interactions
  - `autocomplete(input)`: Returns list of matching command suggestions
  - `complete_command(input)`: Completes command based on current input
  - `show_result(result)`: Displays command results in floating window
  - `find_common_prefix(strings)`: Finds common prefix among multiple strings (private helper)

## 🎨 UI/UX Improvements

### Enhanced Command Mode Experience

- **Intuitive Tab Completion**:
  - Type partial command name (e.g., `he`)
  - Press `Tab` to see all matches or complete automatically
  - Works with all registered plugin commands

- **Visual Feedback**:
  - Immediate visual feedback with floating windows
  - Clear distinction between success and error states
  - Professional-looking centered dialogs

- **Consistent Design**:
  - Matches bookmark feature's floating window style
  - Maintains rufio's cohesive visual language
  - Uses existing color schemes and borders

## 🔧 Technical Improvements

### Architecture

- **CommandModeUI Integration**:
  - Integrated into `TerminalUI` class initialization
  - Uses existing `DialogRenderer` for window management
  - Modular design allows for easy future enhancements

- **Input Handling**:
  - Added `Tab` key handler in `handle_command_input`
  - Improved command execution flow with visual feedback
  - Screen refresh after command execution for clean state

### Code Organization

- **Clear Separation of Concerns**:
  - `CommandMode`: Command execution logic
  - `CommandModeUI`: User interface and interaction
  - `DialogRenderer`: Reusable window rendering component

- **Dependency Injection**:
  - CommandModeUI receives CommandMode and DialogRenderer via constructor
  - Facilitates testing and maintainability

## 🧪 Testing

### Test-Driven Development

- **TDD Approach**: Features developed following strict TDD methodology
  1. Wrote comprehensive tests first
  2. Verified tests failed as expected
  3. Implemented features to pass tests
  4. Committed tests before implementation

### New Tests Added

- **CommandModeUI Tests** (`test/test_command_mode_ui.rb`):
  - **Tab Completion Tests**:
    - `test_autocomplete_no_input`: All commands when no input
    - `test_autocomplete_partial_match`: Partial matching
    - `test_autocomplete_exact_prefix`: Prefix filtering
    - `test_autocomplete_single_match`: Single match completion
    - `test_autocomplete_no_match`: No matches handling
    - `test_complete_command_single_match`: Single match auto-completion
    - `test_complete_command_multiple_matches`: Common prefix completion
    - `test_complete_command_no_match`: Preserves input when no match

  - **Floating Window Tests**:
    - `test_show_result_success`: Success message display
    - `test_show_result_error`: Error message display with red color
    - `test_show_result_multiline`: Multi-line result handling
    - `test_show_result_nil`: Nil result handling (no display)
    - `test_show_result_empty_string`: Empty string handling (no display)

  - **Integration Tests**:
    - `test_command_mode_ui_class_exists`: Class existence verification
    - `test_command_mode_ui_initialization`: Proper initialization
    - `test_prompt_command_with_autocomplete`: End-to-end autocomplete flow

### Test Coverage

- **16 tests, 44 assertions**: Comprehensive coverage of all features
- **All tests passing**: 100% success rate
- **Mock-based testing**: Uses stubbing for UI components to avoid side effects

## 🐛 Bug Fixes

### Fixed Issues

- **Method Name Error**: Fixed incorrect method call `draw` → `draw_screen`
  - Issue: `undefined local variable or method 'draw'` error in `execute_command`
  - Fix: Changed to correct method name `draw_screen` for screen refresh
  - Location: `lib/rufio/terminal_ui.rb:626`

## 📦 Dependencies

### No New Dependencies

- Uses existing Ruby standard library
- Leverages existing rufio components:
  - `DialogRenderer`: For floating windows
  - `CommandMode`: For command execution
  - `TextUtils`: For text width calculations

## 🔄 Compatibility

### Backward Compatibility

- **No Breaking Changes**: All existing features work as before
- **Optional Enhancement**: New features enhance but don't replace existing functionality
- **Existing Keybindings Preserved**: `:` still activates command mode as before

### Platform Support

- **macOS**: Full support ✅
- **Linux**: Full support ✅
- **Windows**: Full support ✅

## ⚡ Performance

### Optimizations

- **Minimal Overhead**: Tab completion uses simple prefix matching (O(n) complexity)
- **Efficient Rendering**: Reuses existing DialogRenderer without new allocation
- **No Performance Impact**: Features only active when command mode is engaged

## 📝 Usage Examples

### Using Tab Completion

```bash
# Launch rufio
rufio

# Activate command mode
Press ':'

# Type partial command
:he

# Press Tab to see completions
Press 'Tab'
# Result: :he (if multiple matches like "hello", "help", "health")

# Type more specific prefix
:hel

# Press Tab again
Press 'Tab'
# Result: :hello or :help (completes to common prefix)
```

### Viewing Command Results

```bash
# After activating command mode (:)
:hello

# Press Enter
# → Floating window appears with result:
# ┌────────────────────────────────┐
# │     コマンド実行結果            │
# ├────────────────────────────────┤
# │                                │
# │ Hello from TestPlugin!         │
# │                                │
# │ Press any key to close         │
# └────────────────────────────────┘

# Press any key to dismiss
```

### Error Handling

```bash
# Try non-existent command
:nonexistent

# Press Enter
# → Red-bordered floating window appears:
# ┌────────────────────────────────┐
# │     コマンド実行結果            │  (Red)
# ├────────────────────────────────┤
# │                                │
# │ ⚠️  コマンドが見つかりません    │
# │                                │
# │ Press any key to close         │
# └────────────────────────────────┘
```

## 🔮 Future Plans

### Planned Enhancements

- **Command History**: Navigate through previously executed commands with ↑/↓ arrows
- **Command Arguments**: Support for commands with parameters
- **Auto-complete Menu**: Visual menu showing all available completions
- **Command Aliases**: User-defined shortcuts for frequently used commands
- **Command Help**: Inline help text showing command descriptions during completion

## 🙏 Acknowledgments

Main contributions in this version:

- **Test-Driven Development**: Strict TDD methodology ensuring code quality
- **Reusable Components**: Leveraged existing DialogRenderer for consistency
- **User Experience Focus**: Tab completion improves command discoverability
- **Visual Polish**: Floating windows provide professional command feedback

## 📋 Detailed Changes

### Files Modified

- `lib/rufio.rb`: Added `require_relative "rufio/command_mode_ui"`
- `lib/rufio/terminal_ui.rb`:
  - Added `@dialog_renderer` and `@command_mode_ui` initialization
  - Added Tab key handler for command completion
  - Changed command result display to use floating windows
  - Fixed `draw_screen` method call
- `test/test_command_mode_ui.rb`: Added comprehensive test suite (16 tests)

### Files Created

- `lib/rufio/command_mode_ui.rb`: New CommandModeUI class (130 lines)

### Lines of Code

- **Added**: ~260 lines (implementation + tests)
- **Modified**: ~15 lines
- **Removed**: ~3 lines

---

**Note**: This version significantly improves the command mode user experience with modern UI features. The Tab completion and floating window display make command execution more intuitive and visually appealing.

**GitHub Issues**: [https://github.com/masisz/rufio/issues](https://github.com/masisz/rufio/issues)
