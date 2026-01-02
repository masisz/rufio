# rufio v0.32.0 - Command Mode Enhancements

**Release Date**: 2026-01-02

## Overview

Version 0.32.0 introduces comprehensive command mode enhancements, including shell command execution, command history, intelligent Tab completion, and the plugin system foundation with a sample Hello plugin. This release focuses on making command mode a powerful interface for daily operations.

## 🎯 Major Features

### 1. Shell Command Execution

Execute shell commands directly from command mode using the `!` prefix.

**Usage:**
```
:!ls -la           # List files with details
:!git status       # Check git status
:!grep pattern *   # Search for patterns
```

**Features:**
- ✅ Safe execution with `Open3.capture3`
- ✅ Separate stdout and stderr display
- ✅ Exit code tracking and error handling
- ✅ Result display in floating window

**Implementation:**
- `lib/rufio/command_mode.rb`: Added `execute_shell_command` method
- `lib/rufio/command_mode_ui.rb`: Hash-based result formatting

### 2. Command History

Navigate through previously executed commands using arrow keys.

**Usage:**
- `↑` (Up Arrow): Previous command
- `↓` (Down Arrow): Next command

**Features:**
- ✅ File persistence (`~/.rufio/command_history.txt`)
- ✅ Duplicate filtering
- ✅ Configurable history size (default: 1000)
- ✅ Automatic save on command execution

**Configuration:**
```ruby
# ~/.config/rufio/config.rb
COMMAND_HISTORY_SIZE = 500  # Default: 1000
```

**Implementation:**
- `lib/rufio/command_history.rb`: History management class
- `lib/rufio/config_loader.rb`: Configuration support
- `lib/rufio/terminal_ui.rb`: Integration with command mode

### 3. Intelligent Tab Completion

Smart Tab completion with multiple behavior modes.

**Behavior:**

1. **Single candidate**: Auto-complete
   ```
   Input: !lsbo [Tab]
   Result: !lsbom
   ```

2. **Multiple candidates with common prefix**: Complete to common prefix
   ```
   Input: !lsap [Tab]
   Result: !lsappinfo
   ```

3. **Multiple candidates, no common prefix**: Display candidate list
   ```
   Input: !l [Tab]
   Result: Shows list of 115 commands starting with 'l'
   ```

**Features:**
- ✅ Internal command completion
- ✅ Shell command completion (PATH-based)
- ✅ File path completion with tilde expansion
- ✅ History-based completion
- ✅ Case-insensitive matching
- ✅ Candidate list display (max 20 items)

**Implementation:**
- `lib/rufio/command_completion.rb`: Main completion logic
- `lib/rufio/shell_command_completion.rb`: Shell-specific completion
- `lib/rufio/terminal_ui.rb`: Tab key handling with candidate display

### 4. Hello Plugin (Ruby Command Example)

Simple example plugin demonstrating how to create custom Ruby commands.

**Usage:**
```
:hello             # Execute the hello command
```

**Output:**
```
Hello, World! 🌍

このコマンドはRubyで実装されています。
```

**Features:**
- ✅ Automatic plugin loading from `lib/rufio/plugins/`
- ✅ Tab completion support
- ✅ Command history integration
- ✅ Comprehensive test coverage

**Creating Your Own Plugin:**
```ruby
# lib/rufio/plugins/my_plugin.rb
module Rufio
  module Plugins
    class MyPlugin < Plugin
      def name
        "MyPlugin"
      end

      def description
        "Description of my plugin"
      end

      def commands
        {
          mycommand: method(:execute_command)
        }
      end

      private

      def execute_command
        "Command result"
      end
    end
  end
end
```

**Implementation:**
- `lib/rufio/plugins/hello.rb`: Hello plugin
- `lib/rufio.rb`: Automatic plugin loading via `PluginManager.load_all`
- `test/test_plugins_hello.rb`: Plugin tests

### 5. Command Mode UI Improvements

Cleaner and more intuitive command mode interface.

**Changes:**
- ✅ Removed "補完候補:" label (candidates shown only on Tab)
- ✅ Floating window for candidate display
- ✅ Better visual feedback for Tab completion
- ✅ Color-coded windows (blue for input, yellow for candidates, green/red for results)

## 📊 Technical Details

### File Changes

**New Files:**
- `lib/rufio/command_history.rb` - Command history management
- `lib/rufio/command_completion.rb` - Command completion logic
- `lib/rufio/shell_command_completion.rb` - Shell command completion
- `lib/rufio/plugins/hello.rb` - Hello plugin example
- `test/test_command_history.rb` - Command history tests
- `test/test_command_completion.rb` - Completion tests
- `test/test_shell_command_completion.rb` - Shell completion tests
- `test/test_plugins_hello.rb` - Hello plugin tests

**Modified Files:**
- `lib/rufio.rb` - Added plugin loading
- `lib/rufio/command_mode.rb` - Shell command execution
- `lib/rufio/command_mode_ui.rb` - UI improvements, Hash result formatting
- `lib/rufio/terminal_ui.rb` - History and completion integration
- `lib/rufio/config_loader.rb` - Command history size configuration

### Test Coverage

```
390 runs, 1663 assertions, 0 failures, 0 errors, 1 skips
```

All features are fully tested with comprehensive test coverage.

### Performance

- Command history: O(1) access for previous/next
- Tab completion: O(n) where n = number of PATH commands
- File path completion: Uses efficient Dir.glob with patterns
- Shell execution: Non-blocking with Open3.capture3

## 🔧 Configuration

### Command History Size

```ruby
# ~/.config/rufio/config.rb
COMMAND_HISTORY_SIZE = 1000  # Default: 1000
```

### History File Location

```
~/.rufio/command_history.txt
```

## 🎓 Usage Examples

### Shell Command Execution
```
:!ls               # List files
:!pwd              # Print working directory
:!git log --oneline # Git log
```

### Tab Completion
```
:h[Tab]            # Complete to 'hello'
:!l[Tab]           # Show list of commands starting with 'l'
:!ls /tm[Tab]      # Complete to '!ls /tmp'
```

### Command History
```
:[↑]               # Previous command
:[↓]               # Next command
```

### Ruby Commands
```
:hello             # Execute hello plugin
:copy              # File operations (future)
:move              # File operations (future)
```

## 🐛 Bug Fixes

- Fixed Tab completion not working for shell commands
- Fixed command input display showing candidates unnecessarily
- Fixed ConfigLoader method access (class method vs instance method)

## 🔄 Migration Guide

No breaking changes. All existing functionality remains compatible.

**New users:**
- Command history will be automatically created on first command execution
- No configuration required for basic usage

**Existing users:**
- Command history feature works automatically
- Previous command mode behavior preserved
- New Tab completion enhances existing workflow

## 📝 Known Limitations

- Command arguments not yet supported for internal commands
- Shell command completion limited to PATH commands
- History limited to command strings (no metadata)

## 🚀 Future Enhancements

- Command arguments support
- Command aliases
- Custom keybindings for command mode
- Command history search (Ctrl+R style)
- More built-in plugins
- Plugin dependency management

## 👏 Credits

Implemented following TDD (Test-Driven Development) methodology:
1. Write tests first
2. Run tests to confirm failures
3. Implement features
4. Verify all tests pass
5. Commit

All features developed with comprehensive test coverage and documentation.

---

For the main changelog, see [CHANGELOG.md](../CHANGELOG.md)
