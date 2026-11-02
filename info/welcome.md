# Welcome to rufio!

**Runtime Unified Flow I/O Operator**

A TUI file manager that executes and coordinates tools and scripts from files.

## Key Features

- **Tool Runtime** - Execute scripts and rake tasks from command mode
- **Vim-like Keybindings** - Navigate with `j/k/h/l` keys
- **Real-time Filtering** - Press `f` to filter files instantly
- **Advanced Search** - Use `fzf` for file names and `rga` for content search
- **Global Search** - Press `G` to search names or contents (including PDF/Excel/PowerPoint) across all bookmarks
- **ZIP Support** - Preview `.zip` contents, extract or compress selected items with `z`
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
| `Tab` | Next bookmark |
| `z` | zoxide history / extract or compress selected items |
| `G` | Global search across bookmarks |
| `C` | Config mode |
| `:` | Command mode |
| `J` | Job mode |
| `L` | Execution logs |
| `?` | Help menu |
| `q` | Quit |
| `T` | Quit and cd to the current directory |

In G mode, use `Ctrl+J` / `Ctrl+K` to select the next / previous result and `Enter` to open it.

## Command Mode

Press `:` to enter command mode:

- `@script.sh` - Execute a script
- `rake:test` - Execute a rake task
- `!git status` - Run a shell command
- `cd ~/projects` - Go to a pasted path
- `Tab` - Auto-complete commands

## Getting Help

Press `?` to open the floating **Help Menu** (Controls / Modes / Scripts).
Switch sections with `1/2/3` or `Tab`, scroll with `j/k`, and close with `ESC`.

## More Information

Visit the GitHub repository for detailed documentation:
- **Repository**: https://github.com/masisz/rufio
- **Issues**: https://github.com/masisz/rufio/issues

---

*Happy file managing!*
