# rufio v0.4.0 Release Notes

## 🎉 Major Features & Improvements

### 🪟 Floating Dialog System
- **New floating confirmation dialogs** for delete operations
- **Visual feedback** with red borders and warning colors for dangerous operations
- **Intuitive keyboard controls**: Y/N confirmation, ESC to cancel
- **Auto-centering** and responsive dialog sizing
- **Modern UI experience** replacing command-line prompts

### 🗑️ Enhanced Delete Operations
- **Comprehensive error handling** with detailed error messages
- **File system verification** to ensure actual deletion before reporting success
- **Real-time result display** showing success/failure counts in floating dialogs
- **Post-deletion verification** with 10ms filesystem sync delay
- **Debug support** with `BENIYA_DEBUG=1` environment variable
- **Atomic operations** with proper rollback on partial failures

### 🌐 English-Only Interface
- **Complete localization cleanup** - removed multi-language support
- **All UI messages converted to English**:
  - `削除確認` → `Delete Confirmation`
  - `移動/コピー` → `Move/Copy`
  - `ファイルが見つかりません` → `File not found`
  - `削除に失敗しました` → `Deletion failed`
- **Cleaner codebase** without language configuration complexity
- **Consistent English terminology** throughout the application

### 🎨 UI/UX Improvements
- **Japanese character width calculation** for proper text rendering
- **HSL color model support** for intuitive color configuration
- **Multi-byte character handling** improvements
- **Better visual hierarchy** with color-coded operation results
- **Screen-aware positioning** for floating dialogs

## 🔧 Technical Improvements

### Code Quality
- **Unified code style** with single quotes throughout
- **Enhanced error handling** patterns
- **Improved file system safety** checks
- **Better separation of concerns** between UI and business logic

### Testing & Debugging
- **New test files**:
  - `test/test_floating_dialog.rb` - Floating dialog system tests
  - `test/debug_delete_timing.rb` - Delete operation timing and verification tests
- **Debug logging system** with detailed operation tracking
- **Environment-based debug controls**

### Architecture
- **Modular floating window system** (`draw_floating_window`, `clear_floating_window_area`)
- **Character width calculation utilities** (`display_width`, `pad_string_to_width`)
- **Screen positioning utilities** (`get_screen_center`)
- **Enhanced deletion workflow** with proper state management

## 📚 Documentation Updates

### README Improvements
- **Removed multi-language configuration** sections
- **Added detailed delete operation documentation**:
  - Floating dialog workflow
  - Safety features
  - Error handling
  - Debug support
- **Updated feature descriptions** to reflect English-only interface
- **Enhanced safety features documentation**

### Both English and Japanese READMEs Updated
- **Consistent documentation** across languages
- **New operation workflow** diagrams
- **Comprehensive feature descriptions**
- **Updated installation and usage instructions**

## 🛠️ Breaking Changes

### Removed Features
- ❌ **Multi-language support** configuration removed
- ❌ **Language setting environment variables** (`BENIYA_LANG`)
- ❌ **Language configuration files** support
- ❌ **Japanese UI messages** (now English-only)

### Configuration Changes
- 🔄 **Simplified configuration** - no more language settings required
- 🔄 **Removed language priority system**
- 🔄 **Streamlined color configuration** (HSL support added)

## 📊 Statistics

### Code Changes
- **+290 lines** in `lib/rufio/keybind_handler.rb` (586 → 876 lines)
- **Multiple files updated** across the codebase
- **New test files** added for quality assurance
- **Documentation updates** in both languages

### Files Modified
- `lib/rufio/keybind_handler.rb` - Core functionality expansion
- `lib/rufio/terminal_ui.rb` - UI message updates
- `lib/rufio/file_opener.rb` - Error message localization
- `README.md` & `README_EN.md` - Documentation updates
- `test/` - New test files added

## 🚀 Migration Guide

### For Users
1. **No action required** - existing installations will work seamlessly
2. **Language settings** in config files will be ignored (no errors)
3. **Environment variables** like `BENIYA_LANG` will have no effect
4. **All UI will be in English** regardless of system locale

### For Developers
1. **Remove language-related configuration** from your setup
2. **Update any scripts** that relied on Japanese output parsing
3. **Use new debug environment variable**: `BENIYA_DEBUG=1`
4. **Test with new floating dialog system**

## 🎯 What's Next

This release establishes rufio as a modern, English-focused file manager with:
- ✅ **Consistent user experience** across all environments
- ✅ **Modern UI patterns** with floating dialogs
- ✅ **Enhanced safety** for file operations
- ✅ **Better debugging capabilities**
- ✅ **Improved maintainability** without multi-language complexity

---

**Release Date**: 2025-01-13  
**Version**: 0.4.0  
**Previous Version**: 0.3.0  
**Compatibility**: Ruby 2.7.0+  

## 📥 Installation

```bash
gem install rufio --version 0.4.0
```

## 🐛 Bug Reports

Please report issues at: https://github.com/masisz/rufio/issues

---

*This release represents a significant step forward in rufio's evolution, focusing on modern UI patterns, safety, and maintainability while streamlining the user experience.*