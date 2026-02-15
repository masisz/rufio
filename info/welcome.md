# Welcome to rufio!

**Runtime Unified Flow I/O Operator**

A TUI file manager that executes and coordinates tools and scripts from files.

## Key Features

- **Tool Runtime** - Execute scripts and rake tasks from command mode
- **Vim-like Keybindings** - Navigate with `j/k/h/l` keys
- **Real-time Filtering** - Press `f` to filter files instantly
- **Advanced Search** - Use `fzf` for file names and `rga` for content search
- **Bookmark Support** - Quick access to favorite directories
- **Job Management** - Run commands in the background
- **Plugin System** - Extend functionality with custom plugins

## Quick Start

| Key | Action |
|-----|--------|
| `j/k` | Move down/up |
| `h/l` | Go to parent / Enter directory |
| `f` | Filter files |
| `s` | Search with fzf |
| `b` | Add bookmark |
| `B` | Bookmark menu |
| `z` | zoxide history |
| `:` | Command mode |
| `J` | Job mode |
| `?` | Help mode |
| `Tab` | Switch mode (Files / Logs / Jobs / Help) |
| `q` | Quit |

## Command Mode

Press `:` to enter command mode:

- `@script.sh` - Execute a script
- `rake:test` - Execute a rake task
- `!git status` - Run a shell command
- `Tab` - Auto-complete commands

## Getting Help

Press `?` to enter **Help Mode** where you can browse all documentation files.
Press `ESC` to exit Help Mode.

## More Information

Visit the GitHub repository for detailed documentation:
- **Repository**: https://github.com/masisz/rufio
- **Issues**: https://github.com/masisz/rufio/issues

---

*Happy file managing!*
