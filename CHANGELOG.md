# Changelog

All notable changes to rufio will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.82.0] - 2026-02-28

### Added
- **Bookmark Jump Highlight**: When cycling bookmarks with `Tab` or `Shift+Tab`, or jumping directly with number keys `1`–`9`, the target bookmark in the top bar is highlighted in cyan for 500ms, then automatically fades back to gray
- **`Shift+Tab` backward bookmark cycling**: In Files mode, `Shift+Tab` now cycles backwards through bookmarks (previously it switched tab modes)
- **Number key bookmark highlight**: Pressing `1`–`9` to jump to a bookmark now triggers the same 500ms cyan highlight as `Tab`; subsequent `Tab` presses continue forward from the jumped position

### Changed
- **UI Layout**: Merged mode tabs and title bar into a single combined bottom row
  - **Top bar (y=0)**: Bookmark list `0.start │ 1.name │ 2.name ...`, job status, FPS (test mode)
  - **Bottom bar (y=h-1)**: Mode tabs + current path + version — all in one line
  - Powerline-style separators: active tab gets a `\uE0B0` cyan exit arrow; version section uses `\uE0B2` cyan entry arrow with cyan background and black bold text
- **`Tab` key**: Changed from mode cycling to **bookmark cycling** (Files mode only)
  - In Files mode: jump to next registered bookmark in sequence (wraps to first)
  - In other modes (Logs / Jobs / Help): no action
  - Mode switching is done via `J` / `L` / `?` keys
- **Bookmark cycling state**: `BookmarkController` now tracks `@last_bookmark_idx` to maintain cycling position independently of the current directory — navigating into a subdirectory no longer resets Tab cycling to the first bookmark
- **UIRenderer bookmark source**: Footer display now reads bookmarks via `@keybind_handler.bookmark_list` (same `BookmarkManager` instance as navigation) instead of creating a separate `Bookmark.new` instance pointing to the legacy `bookmarks.json`

### Fixed
- **Tab cycling past 3rd bookmark**: Fixed a bug where Tab always returned to the first bookmark after navigating to a subdirectory (non-bookmark directory), because `find_index` returned `nil` for non-bookmark paths
- **Mismatched bookmark files**: UIRenderer was reading from `~/.config/rufio/bookmarks.json` while navigation used `~/.config/rufio/bookmarks.yml`, causing the footer to display different bookmarks than Tab actually navigated to
- **Navigation blocked by stale bookmarks**: `goto_next_bookmark` and `goto_prev_bookmark` now skip bookmarks whose paths no longer exist (`Dir.exist?`), preventing the cycling from getting stuck on deleted directories
- **Test contamination of real bookmark file**: `test_bookmark_controller.rb` used `Bookmark.new` without arguments, writing test entries into the real `~/.config/rufio/bookmarks.json`; fixed to use a temp file
- **Number key crash**: Pressing `1`–`9` caused a `NoMethodError` crash because `goto_bookmark` was defined after `private` in `KeybindHandler`, making it inaccessible from `TerminalUI`; moved to the public section
- **zoxide 2-digit input**: Fixed a bug where pressing a single digit in the zoxide history dialog immediately navigated, making it impossible to enter 2-digit numbers (e.g., `12`)
- **Jobs mode tab highlight**: Fixed active tab not highlighting when entering Jobs mode from Logs or Help mode
- **Jobs mode navigation**: Fixed inability to switch away from Jobs mode using `L`, `?` keys

### Removed
- Deleted 3 legacy hand-written test scripts that were not part of the Minitest suite and duplicated coverage already in proper test files:
  - `test/test_bookmark_simple.rb` — covered by `test_bookmark.rb`
  - `test/test_filter_reset.rb` — covered by `test_filter_manager.rb`
  - `test/test_rga_search.rb` — obsolete manual script with monkey-patching

## [0.80.0] - 2026-02-21

### Added
- **Syntax Highlighting**: File preview now supports syntax highlighting via `bat`
  - 19 languages supported: Ruby, Python, JS, TS, Go, Rust, Shell, C, C++, Java, SQL, TOML, YAML, JSON, HTML, CSS, Markdown, Dockerfile, Makefile
  - Graceful fallback to plain text when `bat` is not installed
  - mtime-based cache for instant re-display of previously viewed files
  - Health check support (`rufio -c`) now reports `bat` availability
- **New classes**: `AnsiLineParser`, `SyntaxHighlighter`
- **New tests**: `test_ansi_line_parser.rb` (25 tests), `test_syntax_highlighter.rb` (+7 async tests)

### Fixed
- **Cursor flickering** when navigating source directories: Changed `Renderer#render` from per-line `print` (immediate flush) to a single buffered `write` call — terminal updates are now atomic
- **Navigation lag** when moving between source files: `bat` is now executed asynchronously in a background thread; the current frame immediately falls back to plain text, then re-renders with highlighting on completion

### Changed
- **`Renderer#render`**: Replaced row-by-row `print` with single `write(buf)` + `flush` for atomic output
- **`SyntaxHighlighter`**: Added `highlight_async` (Thread + Mutex + pending guard) alongside existing `highlight`
- **`TerminalUI`**: Preview caching extended with `highlighted` / `highlighted_wrapped` keys; `@highlight_updated` flag added for async re-render notification
- **`FilePreview#determine_file_type`**: Added Go, Rust, Shell, TOML, SQL, C, C++, Java, Dockerfile, Makefile language detection

### Technical Details
- **New files**: `lib/rufio/ansi_line_parser.rb`, `lib/rufio/syntax_highlighter.rb`
- **Modified files**: `lib/rufio/renderer.rb`, `lib/rufio/terminal_ui.rb`, `lib/rufio/file_preview.rb`, `lib/rufio/health_checker.rb`, `lib/rufio/config.rb`, `lib/rufio.rb`
- **For details**: [CHANGELOG_v0.80.0.md](./docs/CHANGELOG_v0.80.0.md)

## [0.71.0] - 2026-02-16

### Added
- **Script Arguments**: Pass arguments to scripts via command mode (e.g., `@retag.sh v0.70.0`)
  - Supports both ScriptRunner and LocalScriptScanner
- **Script/Rake Execution Logging**: Log execution results of `@script` and `rake:task` commands to CommandLogger
  - Covers both synchronous and background execution

### Fixed
- **Selection across directories**: Clear selection state when navigating to a different directory
- **Help/Log viewer entries**: Exclude `..` entry in help mode and log viewer mode

## [0.70.0] - 2026-02-14

### Added
- **Local Script Scanning**: Automatically detect script files (`.sh`, `.rb`, `.py`, `.pl`, `.js`, `.ts`, `.ps1`) in the currently browsed directory
  - Displayed and executable as `@script.sh` format in command mode
  - Falls back to local scripts when not found in registered script paths
  - Cached per directory with automatic invalidation on directory change
- **Rakefile Task Execution**: Parse Rakefile to extract task names and execute them
  - `rake:task_name` format in command mode (e.g., `:rake:test`, `:rake:build`)
  - Supports `Rakefile`, `rakefile`, `Rakefile.rb`
  - Recognizes symbol, string, and hash-style task definitions
- **Rake Task Tab Completion**: Full Tab completion support for rake tasks
  - `rake:` prefix triggers task-specific completion
  - Partial input (`r`, `rak`, `rake`) also suggests matching `rake:xxx` commands
  - Common prefix completion (e.g., `rak` → `rake:`)
- **New classes**: `LocalScriptScanner`, `RakefileParser`
- **New tests**: `test_local_script_scanner.rb` (16 tests), `test_rakefile_parser.rb` (19 tests), `test_command_mode_local.rb` (11 tests), `test_command_completion_local.rb` (13 tests), `test_overlay_clearing.rb` (2 tests)

### Fixed
- **Floating window border remnants**: Fixed old dialog borders remaining when switching between overlay dialogs (e.g., command prompt → completion list)
  - Added `@screen.clear_overlay` in `show_overlay_dialog` before drawing new dialog
  - Added overlay clearing before each frame's `draw_command_mode_to_overlay` in main loop
- **CommandResult display artifact**: Fixed command window top border remaining visible when showing command execution results
  - Root cause: `execute_command` called legacy `draw_screen` (direct terminal print) which has a coordinate offset from the overlay-based rendering system
  - Removed `draw_screen` call from `execute_command`, letting the main loop handle re-rendering via the buffer system

### Changed
- **CommandMode**: Added `update_browsing_directory` method, `rake:` routing, local script fallback
- **CommandCompletion**: Added rake task and local script completion integration
- **TerminalUI**: `activate_command_mode` now notifies `CommandMode` of current browsing directory

### Technical Details
- **New files**: `lib/rufio/local_script_scanner.rb`, `lib/rufio/rakefile_parser.rb`, 5 test files
- **Modified files**: `lib/rufio.rb`, `lib/rufio/command_mode.rb`, `lib/rufio/command_completion.rb`, `lib/rufio/terminal_ui.rb`
- **Test coverage**: 821 runs, 2816 assertions, 0 failures

## [0.65.0] - 2026-02-14

### Changed
- **Display version in title bar**: Changed header format from `💎 rufio - /path` to `💎 rufio v0.65.0 - /path`

## [0.64.0] - 2026-02-07

### Added
- **Screen Overlay Layer**: Added overlay layer to Screen class for dialog rendering
  - `enable_overlay` / `disable_overlay` / `clear_overlay` / `overlay_enabled?`
  - Draw to overlay layer with `put_overlay` / `put_overlay_string`
  - `row()` method automatically composites overlay and base layers
  - Automatically marks dirty rows when overlay is disabled (guarantees redraw)
- **`show_overlay_dialog` helper method**: Added unified overlay dialog display method to TerminalUI, KeybindHandler, BookmarkManager, CommandModeUI, and ZoxideIntegration
  - Uses overlay when `terminal_ui` is available, falls back to direct drawing otherwise
- **`draw_floating_window_to_overlay`**: Added floating window drawing method to DialogRenderer for overlay layer
- **Screen Overlay tests**: Added `test/test_screen_overlay.rb`

### Changed
- **Buffer-based dialog rendering**: Changed all dialog rendering to go through Screen overlay
  - BookmarkManager: bookmark menu, list, rename, delete, and confirmation dialogs
  - KeybindHandler: delete confirmation, copy/move confirmation, exit confirmation, script path management, bookmark operation results
  - CommandModeUI: command execution result display
  - ZoxideIntegration: no history message, history selection dialog
  - TerminalUI: help dialog, announcements, plugin loading errors
- **Overlay-based command mode**: Changed from direct drawing (outside Screen buffer) to overlay-based buffer drawing
  - Integrated into main loop buffer drawing via `draw_command_mode_to_overlay` method
- **Box drawing character width fix**: Fixed `TextUtils.char_width` to treat box drawing characters (U+2500-U+257F) as width 1 (matching actual terminal display width)
- **Code style unification**: Unified `require_relative` in `lib/rufio.rb` from double quotes to single quotes
- **`set_terminal_ui` propagation**: Set `terminal_ui` on BookmarkManager and ZoxideIntegration via KeybindHandler
- **TerminalUI**: Exposed `screen` and `renderer` `attr_reader`

### Technical Details
- **New files**: `test/test_screen_overlay.rb`
- **Modified files**: `lib/rufio.rb`, `lib/rufio/screen.rb`, `lib/rufio/dialog_renderer.rb`, `lib/rufio/terminal_ui.rb`, `lib/rufio/keybind_handler.rb`, `lib/rufio/bookmark_manager.rb`, `lib/rufio/command_mode_ui.rb`, `lib/rufio/text_utils.rb`, `lib/rufio/zoxide_integration.rb`

## [0.63.0] - 2026-02-01

### Added
- **Tab Mode Switching**: Seamless mode navigation via `Tab` / `Shift+Tab` keys
  - New `TabModeManager` class for unified mode management
  - Four modes: Files, Logs, Jobs, Help
  - Mode tabs displayed in header row 2 (cyan highlight for current mode)
  - Circular navigation: Files → Logs → Jobs → Help → Files

### Changed
- **Header UI Overhaul**: Two-row header layout
  - Row 1: Application name and current path
  - Row 2: Interactive mode tabs
  - Header icon changed from 📁 to 💎 (representing Ruby gem)
- **Job Mode Integration**: Unified buffer-based rendering
  - `draw_job_list_to_buffer`, `draw_job_line_to_buffer`, `draw_job_footer_to_buffer`
  - Consistent rendering pipeline with other modes
- **Help/Logs Mode Improvements**:
  - Parent directory (`..`) hidden in Help and Logs modes
  - Directory navigation disabled in these modes

### Technical Details
- **New Files**: `lib/rufio/tab_mode_manager.rb`, `test/test_tab_mode.rb`
- **Modified Files**: `lib/rufio.rb`, `lib/rufio/keybind_handler.rb`, `lib/rufio/terminal_ui.rb`
- **Layout Constants**: `HEADER_HEIGHT` changed from 1 to 2

## [0.62.0] - 2026-01-31

### Changed
- **Configuration File Structure Overhaul**: Separated configuration into multiple files
  - `~/.config/rufio/config.rb` - DSL-style main configuration (colors, keybinds, language)
  - `~/.config/rufio/script_paths.yml` - Script directories (list format)
  - `~/.config/rufio/bookmarks.yml` - Bookmarks (list format)
  - Old `config.yml` format still supported for backward compatibility
- **Config Class Refactoring**: Centralized YAML configuration management
  - All YAML read/write operations now go through `Config` class
  - Added `load_script_paths`, `save_script_paths`, `add_script_path`, `remove_script_path`
  - Added `load_bookmarks_from_yml`, `save_bookmarks_to_yml`, `add_bookmark`, `remove_bookmark`
  - Added `load_config_rb` for DSL configuration loading
  - Added `migrate_from_config_yml` for migration from old format

### Fixed
- **Bookmark Menu**: Fixed "View bookmarks" option (key `4`) not working in bookmark menu (`B` key)

### Deprecated
- **bookmark.json**: JSON bookmark format is deprecated, use `bookmarks.yml` instead
- **config.yml**: Single config file format is deprecated, use separate files instead

### Technical Details
- **New Constants in Config**:
  - `CONFIG_DIR`, `CONFIG_RB_PATH`, `SCRIPT_PATHS_YML`, `BOOKMARKS_YML`
- **Backward Compatibility**:
  - `YamlBookmarkStorage` supports both new (list format) and old (section format)
  - `ScriptPathManager` supports both `script_paths.yml` and legacy `config.yml`
- **New Example Files**: Added `examples/config.rb`, `examples/script_paths.yml`, `examples/bookmarks.yml`

## [0.61.0] - 2026-01-25

### Changed
- **🎯 Rebranding**: Redefined rufio as "Runtime Unified Flow I/O Operator"
  - Emphasized the concept as a "tool runtime environment" rather than just a file manager
  - Updated gemspec summary and description to reflect new concept
- **📖 README.md Overhaul**: Restructured for clarity with the new concept
  - Organized features around tool runtime and file manager axes
  - Simplified keybinding tables by category
  - Added Quick Start section
- **🌐 Unified English UI Messages**: Standardized all UI messages to English
  - Converted command mode, result display, and completion candidate messages to English
  - Japanese setting now displays English messages (internal language setting preserved)

### Added
- **💾 Bookmark Storage Abstraction**: Introduced `BookmarkStorage` interface
  - `JsonBookmarkStorage`: Legacy JSON file format
  - `YamlBookmarkStorage`: New YAML file format (integrated into config.yml)
  - `BookmarkMigrator`: Automatic migration from JSON to YAML
  - Support for storage dependency injection (improved testability)

### Technical Details
- **New Files**: `lib/rufio/bookmark_storage.rb`, `test/test_bookmark_storage.rb`
- **Affected Files**: `bookmark.rb`, `bookmark_manager.rb`, `config_loader.rb`, `command_mode.rb`, `command_mode_ui.rb`, `terminal_ui.rb`, `config.rb`
- **Test Updates**: Modified test cases to match English messages

## [0.60.0] - 2026-01-24

### Added
- **⌨️ Script Tab Completion**: Tab completion for scripts in command mode
  - `@` prefix for script-specific completion (e.g., `@bu` + Tab → `@build.sh`)
  - Registered scripts also appear in regular completion candidates
  - `CommandCompletion` works with `CommandMode` to retrieve script candidates

### Removed
- **🗑️ Project Mode Removal**: Removed project mode launched by `P` key
  - `lib/rufio/project_mode.rb` - ProjectMode class
  - `lib/rufio/project_command.rb` - ProjectCommand class
  - `lib/rufio/project_log.rb` - ProjectLog class
  - Related UI drawing methods (`draw_project_mode_screen`, etc.)
  - Related key handling (`handle_project_mode_key`, etc.)
  - Related test files

### Changed
- **📋 Help Display Update**: Added `J` key (Job mode) to help dialog
- **🧹 Code Cleanup**: Removed unused code related to project mode

### Technical Details
- **Test coverage**: 684 tests, 2474 assertions (all passing)
- **Deleted files**: 7 files (3 library, 4 test)
- **Affected files**: `keybind_handler.rb`, `terminal_ui.rb`, `rufio.rb`

## [0.41.0] - 2026-01-13

### Changed
- **⚡ FPS Optimization**: Changed target frame rate from 60 FPS to 30 FPS (33.33ms/frame)
  - Reduced CPU usage while maintaining smooth UI responsiveness
  - More efficient for terminal-based applications
  - Consistent frame pacing with `min_sleep_interval = 0.0333`

### Fixed
- **🐛 Exit Confirmation Bug**: Fixed confirmation dialog not preventing exit when selecting "No"
  - `terminal_ui.rb`: Now checks `exit_request` return value before setting `@running = false`
  - Selecting "No" or pressing ESC properly cancels the exit operation
  - Fixed in both `handle_input_nonblocking` and `handle_input` methods

- **📊 FPS Display Bug**: Fixed FPS counter showing incorrect 1 FPS value
  - FPS calculation now updates every frame instead of every second
  - `frame_time` and `last_frame_time` updated on each loop iteration
  - Display update throttled to once per second to prevent flicker

### Added
- **🎮 Experimental Async UI**: Initial implementation of asynchronous UI rendering
  - Non-blocking input processing with IO.select (1ms timeout)
  - Frame-based rendering with differential updates
  - FPS counter display with `--test` flag for performance monitoring

## [0.40.0] - 2026-01-11

### Added
- **🎮 Game Loop Architecture**: Transition from event-driven to game loop + double buffering
  - **Phase 1: Foundation**
    - Screen class (back buffer) with multibyte character support
    - Renderer class (front buffer) with differential rendering
    - Demo PoC with 10 FPS game loop
  - **Phase 2: Main Loop Migration**
    - Non-blocking input handling with IO.select (1ms timeout)
    - UPDATE → DRAW → RENDER → SLEEP pattern
    - FPS control (10 FPS default, configurable)
    - Arrow key support (↑↓←→ mapped to kjhl)
  - **Phase 3: Screen/Renderer Integration**
    - Complete drawing method migration to Screen buffer
    - Header, footer, directory list, file preview buffer rendering
    - Differential rendering for optimized updates
    - Color and ANSI code preservation in buffer
  - **Phase 4: Dialog Renderer Update**
    - `draw_floating_window_to_buffer` for Screen buffer support
    - Command mode display integration
    - Floating window compatibility maintained
- **📺 Screen Buffer**: Back buffer implementation
  - Cell-based architecture with character, fg/bg color, width info
  - Multibyte character support (Japanese, emoji)
  - Full-width character handling (2-cell occupation)
  - ANSI color code preservation
  - `put`, `put_string`, `clear`, `row` methods
- **🖥️ Renderer**: Front buffer with diff rendering
  - Differential update (only changed lines rendered)
  - ANSI escape code positioning
  - Resize and clear support
  - Flush control for consistent display
- **⚡ Performance Improvements**
  - Diff rendering reduces terminal I/O by ~90% in static screens
  - Non-blocking input eliminates blocking wait
  - FPS control ensures consistent frame pacing

### Changed
- **Architecture**: Event-driven → Game loop pattern
  - Main loop now runs at fixed FPS (10 FPS)
  - Input processing is non-blocking
  - Rendering is differential
- **Drawing Pipeline**: Direct print → Screen buffer → Renderer
  - All drawing operations go through Screen buffer
  - Renderer applies differential updates
  - Reduces terminal flicker and improves responsiveness

### Technical Details
- **Test Coverage**: 513 tests, 1983 assertions (all passing)
- **Compatibility**: Maintains full backward compatibility
- **Project Mode**: Temporarily uses legacy rendering (Phase 5 planned)
- **Command Mode**: Floating windows rendered post-buffer (Phase 5 planned)

## [0.34.0] - 2026-01-10

### Added
- **🚀 Async Scanner Architecture**: Complete async/parallel scanning implementation
  - **Phase 1: Basic Async Scan**
    - Zig pthread-based threading implementation
    - State management (idle → scanning → done/cancelled/failed)
    - Polling-based completion with progress tracking
  - **Phase 2: Progress Reporting**
    - Real-time progress API with mutex protection
    - Thread-safe cancellation support
    - Timeout handling for scan operations
  - **Phase 3: Advanced Features**
    - Promise-style interface with method chaining
    - Fiber integration with Async library
    - Parallel scanner with thread pool optimization
- **💎 AsyncScannerPromise**: Promise-style interface
  - Method chaining with `.then()` callbacks
  - Automatic resource cleanup on completion
  - Works with both Ruby and Zig backends
- **🧵 AsyncScannerFiberWrapper**: Async/Fiber integration
  - Non-blocking I/O with Ruby's Async library
  - Concurrent scanning support
  - Progress reporting with fiber-aware sleep
- **⚡ ParallelScanner**: Parallel scanning optimization
  - Thread pool management (configurable max_workers)
  - Batch directory scanning with result merging
  - Error handling with partial failure support
  - Backend switching (Ruby/Zig)
- **⚡ Zig Native Scanner**: Experimental implementation with minimal binary size (52.6 KB)
  - Direct Ruby C API integration (no FFI overhead)
  - Competitive performance (within 6% of fastest implementations)
  - 5.97x smaller than Rust/Magnus implementation
  - Async-ready handle-based design
- **📊 YJIT Performance Analysis**: Comprehensive benchmarking of JIT compiler impact
  - Pure Ruby: 2-5% improvement with YJIT
  - Native extensions: No significant impact
- **📈 Performance Documentation**: Extensive benchmarking suite and analysis
  - 7 new benchmark scripts
  - 4 detailed performance reports
  - Complete implementation comparison

### Fixed
- **🚨 CRITICAL: File Preview Performance Bug**: Fixed severe rendering delays (80ms → 1-2ms)
  - Root cause: Redundant processing inside rendering loop (38x per frame)
  - Impact: 97-99% improvement, 40-86x faster file preview
  - All text file previews now render in < 2ms
- **🔧 Zig Cancellation Handling**: Fixed cancelled state not properly propagating
  - Changed error handling to preserve cancellation state
  - Prevents "failed" state when scan is intentionally cancelled

### Changed
- **Ruby 4.0 Compatibility**: Added `fiddle` gem dependency (required in Ruby 4.0+)
- **Async Library Integration**: Deprecated API warnings resolved
  - Updated to use `Kernel#sleep` instead of `Async::Task#sleep`

### Technical Details
- **Test Coverage**: 483 tests, 1899 assertions (100% pass rate)
- **Async Scanner Tests**: 8 fiber tests, 10 promise tests, 10 parallel tests
- **Ruby ABI Independence**: Handle-based design (u64) avoids Ruby ABI coupling
- **Thread Safety**: Pthread mutex protection for all shared state
- **GVL Freedom**: Native threads run independently of Ruby's GVL

For detailed information, see [CHANGELOG_v0.34.0.md](./docs/CHANGELOG_v0.34.0.md)

## [0.32.0] - 2026-01-02

### Added
- **🎯 Shell Command Execution**: Execute shell commands with `!` prefix (e.g., `:!ls`, `:!git status`)
- **📜 Command History**: Navigate command history with arrow keys, persistent storage
- **⌨️ Intelligent Tab Completion**: Smart completion with candidate list display
- **🔌 Hello Plugin**: Example Ruby plugin demonstrating command implementation
- **⚙️ Command History Configuration**: Configurable history size (default: 1000)

### Changed
- Command mode UI improvements: cleaner interface, better visual feedback
- Tab completion now shows candidate list when multiple matches exist
- Plugin system now auto-loads from `lib/rufio/plugins/`

### Fixed
- Tab completion not working for shell commands
- Command input display showing candidates unnecessarily

For detailed information, see [CHANGELOG_v0.32.0.md](./docs/CHANGELOG_v0.32.0.md)

## [0.31.0] - 2026-01-01

### Added
- **🚀 Experimental Native Scanner**: High-performance directory scanning with Rust/Go implementations
- **Rust implementation** (`lib_rust/scanner/`): Fastest, memory-safe implementation
- **Go implementation** (`lib_go/scanner/`): Fast with excellent concurrency
- **NativeScanner abstraction layer**: Unified interface with automatic fallback to Ruby
- **Launch options**: `--native`, `--native=rust`, `--native=go` for performance optimization
- **Environment variable**: `RUFIO_NATIVE` for configuration

### Changed
- Default scanner remains Ruby implementation for stability
- Auto-detection priority: Rust > Go > Ruby

For detailed information, see [CHANGELOG_v0.31.0.md](./docs/CHANGELOG_v0.31.0.md)

## [0.30.0] - 2025-12-30

### Added
- **📚 Help System Overhaul**: Full-screen help mode with Markdown documentation
- **Preview Pane Scrolling**: `Enter` on files focuses preview pane, `j/k` for scrolling
- **Help documentation**: `info/welcome.md`, `info/help.md`, `info/keybindings.md`
- **Enhanced file preview**: `.docx`, `.xlsx`, `.pptx` preview support via `pandoc`

### Changed
- All help documentation converted to English and Markdown format
- Help mode uses full file manager UI for browsing
- Preview pane shows `[PREVIEW MODE]` indicator when focused

For detailed information, see [CHANGELOG_v0.30.0.md](./docs/CHANGELOG_v0.30.0.md)

## [0.21.0] - 2025-12-29

### Added
- **📋 Copy Feature**: `c` key to copy selected files with floating dialog UI
- **Cross-directory selection**: Select files in one directory and copy/move to another
- **Multiple selection delete**: Enhanced `x` key for deleting multiple files
- **Code refactoring**: Extracted dialog confirmation logic to shared methods

### Changed
- Improved SelectionManager with source directory tracking
- Unified confirmation dialog UI across copy/move/delete operations

For detailed information, see [CHANGELOG_v0.21.0.md](./docs/CHANGELOG_v0.21.0.md)

## [0.20.0] - 2025-12-28

### Added
- **🎯 Project Mode UI Unification**: Consistent UI between normal and project modes
- **Script directory support**: Execute custom Ruby scripts from `~/.config/rufio/scripts`
- **Bookmark rename feature**: `r` key in project mode to rename bookmarks
- **Enhanced command mode**: `:` command with script execution

### Changed
- Project mode shows bookmark list with consistent UI
- Improved bookmark management with rename capability

For detailed information, see [CHANGELOG_v0.20.0.md](./docs/CHANGELOG_v0.20.0.md)

## [0.10.0] - 2025-12-21

### 🎨 Enhanced - Bookmark UI Overhaul
- **Floating input dialogs**: All bookmark operations now use modern floating window interface
- **Add Bookmark dialog**: Blue-bordered floating input with automatic whitespace trimming
- **List Bookmark dialog**: Interactive selection with direct navigation support
- **Remove Bookmark dialog**: Two-stage confirmation with color-coded warnings
- **Improved input handling**: Better cursor positioning, no border overlap, proper padding

### Added
- **DialogRenderer#show_input_dialog**: Unified floating input interface with ESC support
- **Color-coded feedback dialogs**: 🔵 Blue (info), 🔴 Red (warning/error), 🟡 Yellow (confirm), 🟢 Green (success)
- **Automatic input trimming**: Leading/trailing spaces removed from bookmark names
- **Path truncation**: Long paths display with `~` for home directory

### Fixed
- **Input field positioning**: Text no longer overlaps with dialog borders
- **Bookmark list navigation**: Users can now navigate to bookmarks from list view
- **Dialog layout**: Proper spacing between all dialog elements

### Technical Details
- New input dialog system with multi-byte character support
- Enhanced BookmarkManager with private helper methods for dialogs
- Improved cursor positioning calculations
- **Detailed changelog**: [CHANGELOG_v0.10.0.md](./docs/CHANGELOG_v0.10.0.md)

## [0.9.0] - 2025-12-13

### Added
- **Escape key support for file/directory creation**: Press `Esc` to cancel file (`a`) or directory (`A`) creation prompts and return to the main view
- **Interactive input improvements**: Backspace support and better character handling for Japanese input

### Fixed
- **Module loading order**: Fixed `LoadError` for filter_manager and related dependencies
- **Required dependencies**: Added proper require statements for all keybind_handler dependencies

### Technical Details
- New `read_line_with_escape` method for cancelable input handling
- Comprehensive test suite for escape key functionality
- Support for multi-byte characters (Japanese, etc.) in filename/directory input
- **Detailed changelog**: [CHANGELOG_v0.9.0.md](./docs/CHANGELOG_v0.9.0.md)

## [0.8.0] - 2025-12-06

For detailed information, see [CHANGELOG_v0.8.0.md](./docs/CHANGELOG_v0.8.0.md)

## [0.7.0] - 2025-11-29

### Added
- **🔌 Plugin System**: Complete extensible plugin architecture for rufio
- **Plugin Base Class**: Simple API for creating plugins with automatic registration
- **Plugin Manager**: Automatic plugin discovery and loading from built-in and user directories
- **Plugin Configuration**: Enable/disable plugins via `~/.rufio/config.yml`
- **Dependency Management**: Plugins can declare gem dependencies with automatic checking
- **Built-in Plugins**: FileOperations plugin for basic file operations
- **Error Handling**: Graceful degradation when plugin dependencies are missing
- **Plugin Distribution**: Support for GitHub Gist and repository-based plugin sharing

### Changed
- **Documentation Updates**: Comprehensive plugin system documentation in README.md and README_EN.md
- **Test Suite**: Complete TDD implementation with full test coverage for plugin system

### Technical Details
- New `Plugin` base class with auto-registration mechanism
- New `PluginManager` for plugin lifecycle management
- New `PluginConfig` for configuration file handling
- Plugin directory structure: `lib/rufio/plugins/` and `~/.rufio/plugins/`
- Case-insensitive plugin name matching in configuration
- **Detailed changelog**: [CHANGELOG_v0.7.0.md](./docs/CHANGELOG_v0.7.0.md)

## [0.6.0] - 2025-09-28

### Added
- **🚀 zoxide Integration**: Complete zoxide directory history navigation functionality
- **z Key Navigation**: Press `z` key to display zoxide movement history and navigate to frequently used directories
- **Smart History Display**: Frequency-based directory sorting with up to 20 history entries
- **Interactive Selection UI**: Modern floating window for intuitive history selection
- **Fast Number Key Selection**: Direct directory selection using number keys 1-20
- **Health Check Enhancement**: zoxide installation status and version checking with `rufio -c`
- **Multi-platform Installation Support**: Automated installation instructions for macOS and Linux
- **Graceful Fallback**: Proper handling when zoxide is not installed or history is empty

### Changed
- **Footer Help Updates**: Added `z:zoxide` to key binding display in both English and Japanese
- **External Tools Documentation**: Updated README with zoxide installation and usage instructions
- **Health Check System**: Extended to include zoxide as optional dependency with platform-specific guidance
- **Error Messaging**: Improved user guidance for zoxide-related issues

### Technical Details
- New zoxide integration methods in `KeybindHandler` class
- Extended `HealthChecker` with zoxide version checking
- Comprehensive test suite for zoxide functionality
- Safe path escaping using Ruby's Shellwords module
- **Detailed changelog**: [CHANGELOG_v0.6.0.md](./docs/CHANGELOG_v0.6.0.md)

## [0.5.0] - 2025-09-20

### Added
- **🔖 Bookmark System**: Complete bookmark functionality with persistent storage
- **Interactive Bookmark Menu**: Floating dialog with Add/List/Remove operations (`b` key)
- **Quick Navigation**: Number keys (1-9) for instant bookmark jumping
- **Persistent Storage**: Automatic save/load to `~/.config/rufio/bookmarks.json`
- **Comprehensive Test Suite**: Full TDD implementation with 15+ test cases
- **Multi-language Support**: English and Japanese bookmark interface
- **Safety Features**: Duplicate checking, path validation, error handling

### Changed
- **Updated Help Messages**: Latest keybindings including bookmark operations
- **Enhanced KeybindHandler**: Integrated bookmark menu and navigation
- **Improved DirectoryListing**: Added `navigate_to_path` method for bookmark jumps
- **UI Layout Optimization**: Removed 3rd header row for cleaner interface
- **Documentation Updates**: Comprehensive README updates with bookmark usage

### Technical Details
- New `Bookmark` class with full CRUD operations
- Maximum 9 bookmarks with automatic sorting
- Floating window system for bookmark management
- Integration with existing terminal UI components
- **Detailed changelog**: [CHANGELOG_v0.5.0.md](./docs/CHANGELOG_v0.5.0.md)

## [0.4.0] - 2025-09-13

### Added
- **Floating Dialog System**: Modern floating confirmation dialogs for delete operations
- **Enhanced Delete Operations**: Comprehensive error handling with file system verification
- **English-Only Interface**: Complete localization to English, removing multi-language complexity
- **Character Width Calculation**: Proper Japanese character width handling for UI rendering
- **Debug Support**: `BENIYA_DEBUG=1` environment variable for detailed logging
- **Real-time Result Display**: Success/failure counts in floating dialogs
- **Post-deletion Verification**: File system checks to ensure actual deletion
- **HSL Color Model Support**: Intuitive color configuration with HSL values

### Changed
- **All UI messages converted to English** from Japanese
- **Delete confirmation workflow** now uses floating dialogs instead of command-line prompts
- **Error messages standardized** to English across all components
- **Documentation updated** to reflect English-only interface
- **Code style unified** with single quotes throughout

### Removed
- **Multi-language support** configuration and related code
- **Language setting environment variables** (`BENIYA_LANG`)
- **Language configuration files** support
- **Japanese UI messages** and localization infrastructure

### Technical
- **+290 lines** of new functionality in core keybind handler
- **New test files** for floating dialog system and delete operations
- **Enhanced error handling** patterns throughout codebase
- **Improved file system safety** checks and validation

For detailed information, see [CHANGELOG_v0.4.0.md](./docs/CHANGELOG_v0.4.0.md)

## [0.3.0] - 2025-09-06

### Added
- Enhanced file operations and management features
- Improved user interface and navigation
- Additional configuration options

### Changed
- Performance improvements
- Bug fixes and stability enhancements

## [0.2.0] - 2025-08-26

### Added
- New features and functionality improvements
- Enhanced file management capabilities

### Changed
- User interface improvements
- Performance optimizations

## [0.1.0] - 2025-08-17

### Added
- Initial release of rufio
- Basic file manager functionality
- Vim-like key bindings
- File preview capabilities
- Multi-platform support

---

## Release Links

### Detailed Release Notes

- [v0.80.0](./docs/CHANGELOG_v0.80.0.md) - Syntax Highlighting & Rendering Fixes
- [v0.31.0](./docs/CHANGELOG_v0.31.0.md) - Experimental Native Scanner Implementation
- [v0.30.0](./docs/CHANGELOG_v0.30.0.md) - Help System Overhaul
- [v0.21.0](./docs/CHANGELOG_v0.21.0.md) - Copy Feature & Code Refactoring
- [v0.20.0](./docs/CHANGELOG_v0.20.0.md) - Project Mode Enhancement & UI Unification
- [v0.10.0](./docs/CHANGELOG_v0.10.0.md) - Bookmark UI Overhaul
- [v0.9.0](./docs/CHANGELOG_v0.9.0.md) - Escape Key Support & Input Improvements
- [v0.8.0](./docs/CHANGELOG_v0.8.0.md) - Additional Features
- [v0.7.0](./docs/CHANGELOG_v0.7.0.md) - Plugin System
- [v0.6.0](./docs/CHANGELOG_v0.6.0.md) - zoxide Integration
- [v0.5.0](./docs/CHANGELOG_v0.5.0.md) - Bookmark System Implementation
- [v0.4.0](./docs/CHANGELOG_v0.4.0.md) - Floating Dialog System & English Interface

### External Links

- [GitHub Releases](https://github.com/masisz/rufio/releases) - Download releases and view release history
- [Installation Guide](./README.md#installation) - How to install rufio
- [Usage Documentation](./README.md#usage) - Complete usage guide

## Version Numbering

rufio follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions  
- **PATCH** version for backwards-compatible bug fixes

## Contributing

When contributing to rufio:

1. Update the **[Unreleased]** section with your changes
2. Follow the existing changelog format
3. Link to detailed release notes for major versions
4. Include migration notes for breaking changes

For more information, see [Contributing Guidelines](./README.md#contributing).
