# rufio

A terminal-based file manager written in Ruby

[日本語版](./README.md) | **English**

## Overview

rufio is a terminal-based file manager inspired by Yazi. It's implemented in Ruby with plugin support, providing lightweight and fast operations for file browsing, management, and searching.

## Features

- **Lightweight & Simple**: A lightweight file manager written in Ruby
- **Intuitive Operation**: Vim-like key bindings
- **Plugin System**: Extensible plugin architecture
- **Powerful Command Mode** (v0.32.0):
  - Shell command execution (`!ls`, `!git status`, etc.)
  - Command history (navigate with arrow keys)
  - Intelligent Tab completion (with candidate list display)
  - Extensible commands via Ruby plugins
- **Background Command Execution** (v0.33.0):
  - Execute shell commands asynchronously with `:!command`
  - rufio remains operational during execution
  - Displays completion notification
  - Automatically saves execution results to log files
- **Execution Log Viewer** (v0.33.0):
  - View command execution logs with `L` key
  - Timestamp-based log file management
  - Intuitive UI similar to help mode
- **File Preview**: View text file contents on the fly
- **File Selection & Operations**: Select multiple files, move, copy, and delete
- **Real-time Filter**: Filter files by name using f key
- **Advanced Search**: Powerful search using fzf and rga
- **Multi-platform**: Runs on macOS, Linux, and Windows
- **External Editor Integration**: Open files with your favorite editor
- **English Interface**: Clean English interface
- **Health Check**: System dependency verification

## Installation

```bash
gem install rufio
```

Or add it to your Gemfile:

```ruby
gem 'rufio'
```

## Usage

### Basic Launch

```bash
rufio           # Launch in current directory
rufio /path/to  # Launch in specified directory
```

### Health Check

```bash
rufio -c                # Check system dependencies
rufio --check-health    # Same as above
rufio --help           # Show help message
```

### Key Bindings

#### Basic Navigation

| Key           | Function                      |
| ------------- | ----------------------------- |
| `j`           | Move down                     |
| `k`           | Move up                       |
| `h`           | Move to parent directory      |
| `l` / `Enter` | Enter directory / Select file |

#### Quick Navigation

| Key | Function               |
| --- | ---------------------- |
| `g` | Move to top of list    |
| `G` | Move to bottom of list |

#### File Operations

| Key | Function                                |
| --- | --------------------------------------- |
| `o` | Open selected file with external editor |
| `e` | Open current directory in file explorer |
| `r` | Refresh directory contents              |
| `a` | Create new file                         |
| `A` | Create new directory                    |

#### File Selection & Operations

| Key     | Function                                    |
| ------- | ------------------------------------------- |
| `Space` | Select/deselect files and directories      |
| `m`     | Move selected items to current directory   |
| `c`     | Copy selected items to current directory   |
| `x`     | Delete selected items                       |

#### Real-time Filter

| Key         | Function                               |
| ----------- | -------------------------------------- |
| `s`         | Start filter mode / Re-edit filter     |
| Text input  | Filter files by name (in filter mode)  |
| `Enter`     | Keep filter and return to normal mode  |
| `ESC`       | Clear filter and return to normal mode |
| `Backspace` | Delete character (in filter mode)      |

#### Search Functions

| Key | Function                                 |
| --- | ---------------------------------------- |
| `f` | File name search with fzf (with preview) |
| `F` | File content search with rga             |

#### Bookmark Functions

| Key     | Function                        |
| ------- | ------------------------------- |
| `b`     | Show bookmark menu              |
| `P`     | Enter project mode (Changed in v0.33.0) |
| `1`-`9` | Go to corresponding bookmark    |

#### zoxide Integration

| Key | Function                           |
| --- | ---------------------------------- |
| `z` | Select directory from zoxide history |

#### Command Mode (v0.32.0 Enhanced)

| Key     | Function                                  |
| ------- | ----------------------------------------- |
| `:`     | Activate command mode                     |
| `Tab`   | Command completion / Show candidate list  |
| `↑`     | Previous command (in command mode)        |
| `↓`     | Next command (in command mode)            |
| `Enter` | Execute command (in command mode)         |
| `ESC`   | Cancel command mode (in command mode)     |

**Shell Command Execution** (v0.32.0):
```
:!ls -la          # List files with details
:!git status      # Check git status
:!pwd             # Print working directory
```

**Background Execution** (v0.33.0):
- Execute shell commands asynchronously with `:!command`
- rufio remains operational during execution
- Displays completion notification for 3 seconds
- Execution results automatically saved to `~/.config/rufio/log/`

**Ruby Commands** (v0.32.0):
```
:hello            # Execute Hello plugin
```

#### Log Viewer (v0.33.0)

| Key   | Function                     |
| ----- | ---------------------------- |
| `L`   | View command execution logs  |
| `ESC` | Exit log viewer mode         |

Command execution logs are saved to `~/.config/rufio/log/` and can be viewed with the `L` key.

#### System Operations

| Key | Function    |
| --- | ----------- |
| `q` | Quit rufio |

### File Selection & Operations

#### File and Directory Selection (`Space`)

- **Select/Deselect**: Use `Space` key to select or deselect files and directories
- **Multiple Selection**: Select multiple files and directories simultaneously
- **Visual Display**: Selected items are marked with ✓ and highlighted in green

#### File Operations

| Operation | Key | Function                                |
| --------- | --- | --------------------------------------- |
| **Move**  | `m` | Move selected items to current directory |
| **Copy**  | `c` | Copy selected items to current directory |
| **Delete** | `x` | Delete selected items                   |

#### Delete Operation Details

- **Floating Dialog Confirmation**: Modern floating window with clear options
- **Visual Feedback**: Red border and warning colors for attention
- **Safe Operation**: Double confirmation before deletion
- **Comprehensive Error Handling**: Detailed error messages for failed deletions
- **Real-time Result Display**: Shows success/failure count in floating dialog
- **File System Verification**: Confirms actual deletion before reporting success
- **Debug Support**: Optional debug logging with BENIYA_DEBUG=1

#### Operation Workflow

```
1. Space → Select files/directories (multiple selection possible)
2. Choose operation key:
   - m → Move to current directory
   - c → Copy to current directory
   - x → Delete
3. Floating Dialog → Confirm with Y/N, ESC to cancel
4. Result Display → Review operation results in floating window
```

#### Safety Features

- **Floating Confirmation Dialog**: Modern floating window interface for confirmations
- **Visual Warning System**: Red borders and colors for dangerous operations
- **Duplicate Check**: Automatically skip files with same names
- **Error Handling**: Proper handling of permission errors and other issues
- **Operation Log**: Detailed display of operation results in floating dialogs
- **Post-deletion Verification**: Confirms files are actually deleted from filesystem

### Filter Feature

#### Real-time Filter (`s`)

- **Start Filter**: Press `s` to enter filter mode
- **Text Input Filtering**: Supports Japanese, English, numbers, and symbols
- **Real-time Updates**: Display updates with each character typed
- **Keep Filter**: Press `Enter` to maintain filter while returning to normal operations
- **Clear Filter**: Press `ESC` to clear filter and return to normal display
- **Re-edit**: Press `s` again while filter is active to re-edit
- **Character Deletion**: Use `Backspace` to delete characters, auto-clear when empty

#### Usage Example

```
1. s → Start filter mode
2. ".rb" → Show only Ruby files
3. Enter → Keep filter, return to normal operations
4. j/k → Navigate within filtered results
5. s → Re-edit filter
6. ESC → Clear filter
```

### Search Features

#### File Name Search (`f`)

- Interactive file name search using `fzf`
- Real-time preview display
- Selected files automatically open in external editor

#### File Content Search (`F`)

- Advanced file content search using `rga` (ripgrep-all)
- Searches PDFs, Word documents, text in images, and more
- Filter results with fzf and jump to specific lines

### Bookmark Features

#### Bookmark Operations (`b`)

- **Add Bookmark**: `[A]` - Add current directory to bookmarks
- **List Bookmarks**: `[L]` - Display registered bookmarks
- **Remove Bookmark**: `[R]` - Remove a bookmark
- **Number Jump**: `1-9` - Jump directly to corresponding bookmark

#### Quick Navigation (`1`-`9`)

- Jump directly to bookmarks without going through the bookmark menu
- Supports up to 9 bookmarks
- Bookmark information is displayed at the top of the screen

#### Bookmark Persistence

- Bookmark information is automatically saved to `~/.config/rufio/bookmarks.json`
- Bookmark information is preserved after rufio restarts
- JSON file can be edited directly

### zoxide Integration Features

#### zoxide History Navigation (`z`)

- **Smart History**: Display directory navigation history recorded by zoxide
- **Frequency Order**: More frequently used directories appear higher in the list
- **Interactive Selection**: Select from history using floating window
- **Quick Navigation**: Select directories directly with number keys
- **Abbreviated Path Display**: Home directory shown as `~` for readability

#### Usage Example

```
1. z → Display zoxide history menu
2. 1-20 → Select directory by displayed number
3. ESC → Cancel and return to original screen
```

#### About zoxide

[zoxide](https://github.com/ajeetdsouza/zoxide) is a smart cd command that learns your directory navigation habits.

```bash
# Installing zoxide
# macOS (Homebrew)
brew install zoxide

# Ubuntu/Debian
apt install zoxide

# For other installation methods, see official documentation
# https://github.com/ajeetdsouza/zoxide#installation
```

#### Requirements

- zoxide must be installed on the system
- Appropriate message is displayed when zoxide is not available
- Empty history is handled gracefully

### Required External Tools

The following tools are required for search and history functionality:

```bash
# macOS (Homebrew)
brew install fzf rga zoxide

# Ubuntu/Debian
apt install fzf zoxide
# rga requires separate installation: https://github.com/phiresky/ripgrep-all

# Other Linux distributions
# Installation via package manager or manual installation required
```

#### Tool Usage

- **fzf**: File name search functionality (`f` key)
- **rga**: File content search functionality (`F` key)
- **zoxide**: Directory history navigation functionality (`z` key)

## Configuration

### Color Configuration (Customization)

rufio allows you to customize colors for file types and UI elements. It supports intuitive color specification using the HSL color model.

#### Supported Color Formats

```ruby
# HSL (Hue, Saturation, Lightness) - Recommended format
{hsl: [220, 80, 60]}  # Hue 220°, Saturation 80%, Lightness 60%

# RGB (Red, Green, Blue)
{rgb: [100, 150, 200]}

# HEX (Hexadecimal)
{hex: "#6496c8"}

# Traditional symbols
:blue, :red, :green, :yellow, :cyan, :magenta, :white, :black

# ANSI color codes
"34" or 34
```

#### Configuration Example

```ruby
# ~/.config/rufio/config.rb
COLORS = {
  # HSL color specification (intuitive and easy to adjust)
  directory: {hsl: [220, 80, 60]},    # Blue-ish for directories
  file: {hsl: [0, 0, 90]},            # Light gray for regular files
  executable: {hsl: [120, 70, 50]},   # Green-ish for executable files
  selected: {hsl: [50, 90, 70]},      # Yellow for selected items
  preview: {hsl: [180, 60, 65]},      # Cyan for preview panel

  # You can also mix different formats
  # directory: :blue,                 # Symbol
  # file: {rgb: [200, 200, 200]},     # RGB
  # executable: {hex: "#00aa00"},     # HEX
}
```

#### About HSL Color Model

- **Hue**: 0-360 degrees (0=red, 120=green, 240=blue)
- **Saturation**: 0-100% (0=gray, 100=vivid)
- **Lightness**: 0-100% (0=black, 50=normal, 100=white)

#### Configurable Items

- `directory`: Directory color
- `file`: Regular file color
- `executable`: Executable file color
- `selected`: Selected item color
- `preview`: Preview panel color

## Plugin System

rufio features an extensible plugin system that allows you to easily add custom functionality.

### Plugin Locations

#### 1. Built-in Plugins
```
lib/rufio/plugins/*.rb
```
Plugins included with rufio by default. Provides basic functionality without external gem dependencies.

#### 2. User Plugins
```
~/.rufio/plugins/*.rb
```
Plugins you can freely add. Can be obtained from GitHub Gist or raw URLs.

### Creating Plugins

#### Simple Plugin Example

```ruby
# ~/.rufio/plugins/hello.rb
module Rufio
  module Plugins
    class Hello < Plugin
      def name
        'Hello'
      end

      def description
        'Simple greeting plugin'
      end

      def commands
        {
          hello: method(:say_hello)
        }
      end

      private

      def say_hello
        puts "Hello from rufio!"
      end
    end
  end
end
```

#### Plugin with External Gem Dependencies

```ruby
# ~/.rufio/plugins/ai_helper.rb
module Rufio
  module Plugins
    class AiHelper < Plugin
      requires 'anthropic'  # Declare gem dependency

      def name
        'AiHelper'
      end

      def description
        'AI assistant using Claude API'
      end

      def commands
        {
          ai: method(:ask_ai)
        }
      end

      def initialize
        super  # Run dependency check
        @client = Anthropic::Client.new(
          api_key: ENV['ANTHROPIC_API_KEY']
        )
      end

      private

      def ask_ai(question)
        # AI processing
      end
    end
  end
end
```

### Plugin Management

#### Enable/Disable Plugins

You can control plugin activation in `~/.rufio/config.yml`:

```yaml
plugins:
  fileoperations:
    enabled: true
  ai_helper:
    enabled: true
  my_custom:
    enabled: false
```

#### Default Behavior

- No `config.yml` → All plugins enabled
- Plugin not in config → Enabled by default
- `enabled: false` explicitly set → Disabled

### Plugin Distribution

#### Share via GitHub Gist

```bash
# Plugin author
1. Upload .rb file to GitHub Gist
2. Share Raw URL with users

# User
$ mkdir -p ~/.rufio/plugins
$ curl -o ~/.rufio/plugins/my_plugin.rb [RAW_URL]
$ rufio
✓ my_plugin loaded successfully
```

#### Share via GitHub Repository

```bash
# Plugin author
rufio-plugins/
  ├── plugin1.rb
  └── plugin2.rb

# User
$ curl -o ~/.rufio/plugins/plugin1.rb https://raw.githubusercontent.com/user/rufio-plugins/main/plugin1.rb
```

### Plugin Key Features

#### Required Methods

- `name`: Plugin name (required)
- `description`: Plugin description (optional, default: "")
- `version`: Plugin version (optional, default: "1.0.0")
- `commands`: Command definitions (optional, default: {})

#### Dependency Management

- `requires 'gem_name'`: Declare gem dependencies
- If dependencies are missing, displays warning and disables plugin
- rufio continues to start normally

#### Auto-registration

- Inheriting from `Plugin` class automatically registers with `PluginManager`
- No complex registration process needed

## Development

### Requirements

- Ruby 2.7.0 or later
- Required gems: io-console, pastel, tty-cursor, tty-screen

### Running Development Version

```bash
git clone https://github.com/masisz/rufio
cd rufio
bundle install
./exe/rufio
```

### Running Tests

```bash
bundle exec rake test
```

## Supported Platforms

- **macOS**: Native support
- **Linux**: Native support
- **Windows**: Basic functionality supported

## Contributing

Bug reports and feature requests are welcome at [GitHub Issues](https://github.com/masisz/rufio/issues).

Pull requests are also welcome!

### Development Guidelines

1. Follow existing code style and conventions
2. Add tests for new features
3. Update documentation as needed
4. Test on multiple platforms when possible

## License

MIT License

