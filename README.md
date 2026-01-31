# rufio

**Runtime Unified Flow I/O Operator**

A TUI file manager that executes and coordinates tools and scripts from files.
Supports Ruby/Python/PowerShell and integrates your development workflow in one place.

[日本語](./README_ja.md) | **English**

## Concept

rufio is not just a file manager. It's a **tool runtime execution environment**.

```
┌─────────────────────────────────────────────────────────┐
│                        rufio                            │
│         Runtime Unified Flow I/O Operator               │
├─────────────────────────────────────────────────────────┤
│  Files ──→ Scripts ──→ Tools ──→ Output                 │
│    ↑                                   │                │
│    └───────────── Feedback ────────────┘                │
└─────────────────────────────────────────────────────────┘
```

- **File Operations**: Traditional file manager functionality
- **Script Execution**: Run Ruby/Python/PowerShell scripts in file context
- **Tool Integration**: Seamless integration with external tools (git, fzf, rga, etc.)
- **Unified I/O**: Manage all input/output in a single flow

## Features

### As a Tool Runtime

- **Multi-language Script Support**: Ruby, Python, PowerShell
- **Script Path Management**: Register and manage multiple script directories
- **Command Completion**: Tab completion for scripts with `@` prefix
- **Job Management**: Run scripts/commands in the background
- **Execution Logs**: Automatically record all execution results

### As a File Manager

- **Vim-like Key Bindings**: Intuitive navigation
- **Real-time Preview**: Instantly display file contents
- **Fast Search**: Integration with fzf/rga
- **Bookmarks**: Quick access to frequently used directories
- **zoxide Integration**: Smart directory history

### Cross-platform

- **macOS**: Native support
- **Linux**: Native support
- **Windows**: PowerShell script support

## Installation

```bash
gem install rufio
```

Or add to your Gemfile:

```ruby
gem 'rufio'
```

## Quick Start

### 1. Launch

```bash
rufio           # Launch in current directory
rufio /path/to  # Launch in specified directory
```

### 2. Register Script Path

1. Navigate to the directory where you want to place scripts
2. `B` → `2` to add to script path

### 3. Execute Script

1. Press `:` to enter command mode
2. Type `@` + part of the script name
3. Press `Tab` to complete
4. Press `Enter` to execute

## Key Bindings

### Basic Operations

| Key | Function |
|-----|----------|
| `j/k` | Move up/down |
| `h/l` | Parent/child directory |
| `g/G` | Top/bottom |
| `Enter` | Enter directory/open file |
| `q` | Quit |

### File Operations

| Key | Function |
|-----|----------|
| `Space` | Select/deselect |
| `o` | Open with external editor |
| `a/A` | Create file/directory |
| `r` | Rename |
| `d` | Delete |
| `m/c/x` | Move/copy/delete (selected) |

### Search & Filter

| Key | Function |
|-----|----------|
| `f` | Filter mode |
| `s` | Search files with fzf |
| `F` | Search file contents with rga |

### Navigation

| Key | Function |
|-----|----------|
| `b` | Add bookmark |
| `B` | Bookmark menu |
| `0` | Return to startup directory |
| `1-9` | Jump to bookmark |
| `z` | zoxide history |

### Tool Runtime

| Key | Function |
|-----|----------|
| `:` | Command mode |
| `J` | Job mode |
| `L` | View execution logs |
| `?` | Help |

## Command Mode

Press `:` to enter command mode and execute various commands.

### Script Execution

```
:@build           # @ prefix triggers script completion
:@deploy.rb       # Execute registered script
```

### Shell Commands

```
:!git status      # ! prefix for shell commands
:!ls -la          # Execute in background
```

### Built-in Commands

```
:hello            # Greeting message
:stop             # Quit rufio
```

## Script Path

### What is Script Path?

A feature to register directories containing script files. Scripts in registered directories can be executed using the `@` prefix in command mode.

### Management

Press `B` → `3` to open the script path management menu:

- View registered paths
- `d`: Remove path
- `Enter`: Jump to directory
- `ESC`: Close menu

### Supported Scripts

| Extension | Language |
|-----------|----------|
| `.rb` | Ruby |
| `.py` | Python |
| `.ps1` | PowerShell |
| `.sh` | Shell (bash/zsh) |

## DSL Commands

Define custom commands in `~/.config/rufio/commands.rb`:

```ruby
command "hello" do
  ruby { "Hello from rufio!" }
  description "Greeting command"
end

command "status" do
  shell "git status"
  description "Git status"
end

command "build" do
  script "~/.config/rufio/scripts/build.rb"
  description "Run build"
end
```

## Configuration

### Configuration File Structure

```
~/.config/rufio/
├── config.rb          # DSL-style main configuration
├── script_paths.yml   # Script directories (list format)
├── bookmarks.yml      # Bookmarks (list format)
├── commands.rb        # DSL command definitions
├── scripts/           # Script files
└── logs/              # Execution logs
```

### config.rb (DSL Configuration)

```ruby
# ~/.config/rufio/config.rb

# Language setting: 'en' or 'ja'
LANGUAGE = 'ja'

# Color settings (HSL format)
COLORS = {
  directory: { hsl: [220, 80, 60] },
  file: { hsl: [0, 0, 90] },
  executable: { hsl: [120, 70, 50] },
  selected: { hsl: [50, 90, 70] },
  preview: { hsl: [180, 60, 65] }
}.freeze

# Keybind settings
KEYBINDS = {
  quit: %w[q ESC],
  up: %w[k UP],
  down: %w[j DOWN]
}.freeze
```

### script_paths.yml

```yaml
# ~/.config/rufio/script_paths.yml
- ~/.config/rufio/scripts
- ~/bin
- ~/scripts
```

### bookmarks.yml

```yaml
# ~/.config/rufio/bookmarks.yml
- path: ~/Documents
  name: Documents
- path: ~/projects
  name: Projects
```

### Local Configuration

Place `rufio.yml` in your project root for project-specific script paths:

```yaml
# ./rufio.yml (project root)
script_paths:
  - ./scripts
  - ./bin
```

## External Tool Integration

rufio integrates with the following external tools to extend functionality:

| Tool | Purpose | Key |
|------|---------|-----|
| fzf | File name search | `s` |
| rga | File content search | `F` |
| zoxide | Directory history | `z` |

### Installation

```bash
# macOS
brew install fzf rga zoxide

# Ubuntu/Debian
apt install fzf zoxide
# rga requires separate installation: https://github.com/phiresky/ripgrep-all
```

## Advanced Features

### Native Scanner (Experimental)

Support for native implementation for fast directory scanning:

```bash
rufio --native        # Auto-detect
rufio --native=zig    # Zig implementation
```

### JIT Compiler

```bash
rufio --yjit   # Ruby 3.1+ YJIT
rufio --zjit   # Ruby 3.4+ ZJIT
```

### Health Check

```bash
rufio -c              # Check system dependencies
rufio --check-health  # Same as above
```

## Development

### Requirements

- Ruby 2.7.0 or later
- io-console, pastel, tty-cursor, tty-screen gems

### Running Development Version

```bash
git clone https://github.com/masisz/rufio
cd rufio
bundle install
./bin/rufio
```

### Testing

```bash
bundle exec rake test
```

## License

MIT License

## Contributing

Bug reports and feature requests are welcome at [GitHub Issues](https://github.com/masisz/rufio/issues).
Pull requests are also welcome!
