# CHANGELOG - rufio v0.6.0

**Release Date**: 2025-09-28

## 🚀 New Features

### zoxide Integration

- **zoxide History Navigation with z Key**: Press `z` key to display zoxide movement history and quickly navigate to previously visited directories
- **Smart History Display**: Frequently used directories appear at the top of the list
- **Interactive Selection UI**: Floating window displays up to 20 history entries
- **Fast Selection with Number Keys**: Select directories directly using number keys 1-20
- **Abbreviated Path Display**: Home directory displayed as `~` with nicely formatted long paths
- **Graceful Handling**: Proper handling when zoxide is not installed or history is empty

### Health Check Enhancement

- **zoxide Check Addition**: Check zoxide installation status and version with `rufio -c`
- **Installation Instructions**: Detailed platform-specific (macOS/Linux) installation instructions

## 🎨 UI/UX Improvements

### User Interface

- **Footer Help Updates**:
  - English version: Added `z:zoxide` to key binding list
  - Japanese version: Added `z:zoxide` to key binding list
- **zoxide History Selection Dialog**: Intuitive floating window for history selection
- **Improved Error Messages**: Clear guidance when zoxide is not installed

## 📖 Documentation Updates

### README Updates

**Japanese Version (README.md)**:

- New zoxide integration features section
- Added `z:zoxide` to key bindings list
- Detailed explanation of zoxide overview and installation methods
- Added zoxide to required external tools list
- Clarified purpose of each tool

**English Version (README_EN.md)**:

- New zoxide Integration Features section
- Added `z:zoxide integration` to Key Bindings
- Detailed zoxide explanation and installation instructions
- Expanded Required External Tools section
- Clarified Tool Usage

### Added Documentation Content

- **Detailed explanation of zoxide history navigation features**
- **Usage examples and workflows**
- **Overview of zoxide**
- **Platform-specific installation methods**
- **Requirements and limitations**

## 🔧 Technical Improvements

### Architecture

- **KeybindHandler Class Extension**: Added zoxide-related methods
  - `zoxide_available?`: Check zoxide availability
  - `get_zoxide_history`: Get and parse zoxide history
  - `show_zoxide_menu`: Display history in floating window
  - `select_from_zoxide_history`: Interactive history selection
  - `navigate_to_zoxide_directory`: Navigate to selected directory

### HealthChecker Class Extension

- **check_zoxide Method**: Version checking and status verification for zoxide
- **install_instruction_for Method Extension**: Added installation instructions for zoxide

### Configuration System

- **Multi-language Message Support**:
  - `health.zoxide`: Support for both English and Japanese
  - Updated footer help messages

## 🧪 Testing

### New Tests Added

- **zoxide Integration Tests** (`test/test_zoxide_integration.rb`):
  - zoxide availability tests
  - History retrieval functionality tests
  - UI display tests
  - Directory navigation tests
  - Error handling tests

- **Health Check Test Extensions**:
  - `test_check_zoxide`: zoxide check functionality tests
  - `test_install_instruction_for_zoxide`: Installation instruction tests

## 📦 Dependencies

### New Dependencies

- **zoxide**: Directory history functionality (optional)
  - macOS: `brew install zoxide`
  - Ubuntu/Debian: `apt install zoxide`
  - Others: [Official Documentation](https://github.com/ajeetdsouza/zoxide#installation)

### Dependency Updates

- **Shellwords Module**: Used for path escaping (Ruby standard library)

## 🔄 Compatibility

### Backward Compatibility

- **No Impact on Existing Features**: No changes to existing key bindings or functionality
- **Configuration File Compatibility**: Existing configuration files can be used as-is
- **Optional Feature**: All existing features work normally even without zoxide

### Platform Support

- **macOS**: Full support (installation via Homebrew recommended)
- **Linux**: Full support (via package managers)
- **Windows**: Basic compatibility (zoxide installation methods need separate verification)

## ⚡ Performance

### Optimizations

- **Efficient History Retrieval**: Optimal use of zoxide query commands
- **Memory Usage**: History display limited to maximum 20 entries
- **Responsiveness**: Fast floating window rendering

## 🐛 Bug Fixes

### Fixed Issues

- **zoxide Output Format Support**: Correctly retrieve scored output with `zoxide query --list --score`
- **Empty History Handling**: Proper message display when no history exists
- **Path Escaping**: Safe handling of paths with special characters

## 🔮 Future Plans

### Planned for Next Version

- **zoxide Integration Update History Recording**: Automatically record directory movements within rufio to zoxide
- **Customizable History Display Count**: Adjust display count via configuration file
- **History Filtering**: Filter history by specific patterns

## 📝 Usage Examples

### Basic Usage

```bash
# Launch rufio
rufio

# Press z key to display zoxide history
# Enter displayed number (1-20) to navigate to directory
# Press ESC to cancel
```

### Health Check

```bash
# Check all dependencies including zoxide
rufio -c

# Example output:
# ✓ zoxide (directory history) zoxide 0.9.8
```

## 🙏 Acknowledgments

Main contributions in this version:

- **zoxide**: [ajeetdsouza/zoxide](https://github.com/ajeetdsouza/zoxide) - Excellent directory navigation tool
- **Ruby Standard Library**: Utilization of Shellwords module

---

**Note**: This version is the initial implementation of zoxide integration features. We welcome feedback and improvement suggestions.

**GitHub Issues**: [https://github.com/masisz/rufio/issues](https://github.com/masisz/rufio/issues)

