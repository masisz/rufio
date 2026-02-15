# Keybindings Reference

Complete reference of all keyboard shortcuts in **rufio**.

## Navigation

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `h` / `Left` | Go to parent directory |
| `l` / `Right` / `Enter` | Enter directory or open file |
| `g` | Jump to top of list |
| `G` | Jump to bottom of list |

## File Operations

| Key | Action |
|-----|--------|
| `o` | Open file with external editor |
| `e` | Open in file explorer (system default) |
| `R` | Refresh directory contents |
| `r` | Rename file or directory |
| `d` | Delete file or directory (with confirmation) |
| `a` | Create new file |
| `A` | Create new directory |

## File Selection

| Key | Action |
|-----|--------|
| `Space` | Toggle selection on current item |
| `m` | Move selected items to current directory |
| `c` | Copy selected items to current directory |
| `x` | Delete selected items |

## Filtering & Search

| Key | Action |
|-----|--------|
| `f` | Enter filter mode (type to filter) |
| `s` | Search file names with fzf |
| `F` | Search file contents with rga |

## Bookmarks & Navigation

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `B` | Bookmark menu (view/add/remove/script paths) |
| `0` | Jump to startup directory |
| `1-9` | Jump to bookmark 1-9 |
| `z` | Navigate using zoxide history |

## Command Mode & Tool Runtime

| Key | Action |
|-----|--------|
| `:` | Enter command mode |
| `J` | Job mode (view background jobs) |
| `L` | View execution logs |

## Mode Switching

| Key | Action |
|-----|--------|
| `Tab` | Switch mode: Files -> Logs -> Jobs -> Help |
| `Shift+Tab` | Switch mode (reverse direction) |
| `?` | Enter help mode |
| `ESC` | Exit current mode (help/filter/command) |
| `q` | Quit rufio |

---

## Mode-Specific Keys

### Filter Mode
- **Any character**: Add to filter query
- **Backspace**: Remove last character
- **Enter**: Apply filter and exit filter mode
- **ESC**: Cancel filter and exit filter mode

### Command Mode
- **Any character**: Add to command input
- **Tab**: Auto-complete (scripts, rake tasks, commands)
- **Up/Down**: Navigate command history
- **Enter**: Execute command
- **Backspace**: Remove last character
- **ESC**: Cancel and exit command mode

### Command Mode Prefixes
- `@script` - Execute a registered or local script
- `rake:task` - Execute a Rakefile task
- `!command` - Execute a shell command
- `command` - Execute a built-in or plugin command

### Help Mode
- **j/k/h/l**: Navigate help files
- **ESC**: Exit help mode and return to previous directory

### Job Mode
- **j/k**: Navigate through jobs
- **ESC**: Exit job mode

---

## Tips

- **Vim users**: Navigation keys (`hjkl`) work exactly like Vim
- **Selection**: Use `Space` to mark multiple files, then operate on all at once
- **Quick access**: Number keys `1-9` provide instant access to bookmarks
- **Filtering**: Press `f` and start typing for real-time filtering
- **Rake tasks**: Type `:rake:` then `Tab` to see available tasks
- **Local scripts**: Scripts in the current directory are auto-detected with `@` prefix

---

*Press `?` anytime to return to help mode*
