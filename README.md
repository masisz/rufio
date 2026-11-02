# rufio

**Runtime Unified Flow I/O Operator**

A terminal file manager that keeps your everyday script workflow close at hand.
Find files, run Ruby, Python, or PowerShell scripts in the current directory, and check jobs and logs.
Add your own actions in Ruby.

[日本語](./README_ja.md) | **English**

## What Makes rufio Different

rufio brings finding files, running scripts, and checking results together in one interface.

- **Run scripts where your files are**: Register your script directories, then press `:`, type `@` + part of a script name, press `Tab`, and hit `Enter`. Run Ruby, Python, or PowerShell scripts in the directory you are browsing
- **Follow jobs and execution logs**: Keep browsing while scripts run in the background. Press `J` to check jobs and `L` to view execution logs
- **Add your own actions in Ruby**: Define custom commands with a small Ruby DSL in `~/.config/rufio/commands.rb`. `~/.rufio/commands.rb` is also supported
- **Use installed tools without extra configuration**: Search file names with fzf, search contents with rga, highlight previews with bat, and navigate directory history with zoxide
- **Windows support**: Run PowerShell scripts with keyboard input handling adapted to Windows terminals
- **Trace behavior in the source**: The implementation is primarily Ruby, so you can inspect and change the parts you need. Security design is documented in [SECURITY.md](./SECURITY.md)

## Features

### For Script Workflows

- **Multi-language Script Support**: Ruby, Python, PowerShell
- **Script Path Management**: Register and manage multiple script directories
- **Command Completion**: Tab completion for scripts with `@` prefix
- **Job Management**: Run scripts/commands in the background
- **Execution Logs**: Automatically record all execution results

### As a File Manager

- **Vim-like Key Bindings**: Intuitive navigation
- **Real-time Preview**: Instantly display file contents with syntax highlighting (via `bat`), including `.zip` entry lists
- **Fast Search**: Integration with fzf/rga, plus built-in search across all bookmarks that also reads PDF, Excel and PowerPoint
- **ZIP Archives**: Extract or compress selected items as a background job
- **Jump to a Path**: Paste any path into `:cd`
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

The most used keys. See the **[User Guide](./docs/guide.md)** for every key and mode, or press `?` inside rufio.

| Key | Action |
|-----|--------|
| `j/k`, `h/l` | Move / parent directory / enter directory |
| `g/}` | First / last entry |
| `P` | Fullscreen preview |
| `Space` | Select |
| `m/c/x` | Move / copy / delete selected items |
| `z` | Extract or compress selected items (`.zip`); zoxide history when nothing is selected |
| `a/A`, `r`, `d` | Create file / directory, rename, delete |
| `f`, `s`, `F` | Filter, fzf file name search, rga content search |
| `G` | Search names or contents (PDF, Excel, PowerPoint too) across all bookmarks |
| `b`, `B`, `1-9`, `Tab` | Add bookmark, bookmark menu, jump, next bookmark |
| `:` | Command mode (`@script`, `rake:task`, `!shell`, `cd <path>`) |
| `J`, `L`, `C` | Jobs, logs, config directory |
| `?` | Help |
| `q`, `T` | Quit, quit and cd the shell to the current directory |

In G mode, use `Ctrl+J` / `Ctrl+K` to select the next / previous result and `Enter` to open it.

## Documentation

- **[User Guide](./docs/guide.md)**: keys, modes, command mode, scripts, DSL commands, configuration, shell integration and the native engine
- **[CHANGELOG](./CHANGELOG.md)**: release notes
- **[SECURITY.md](./SECURITY.md)**: security design

## Development

### Requirements

- Ruby 2.7.0 or later

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
