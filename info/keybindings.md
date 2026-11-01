# Keybindings Reference

Complete reference of all keyboard shortcuts in **rufio**.

## Navigation

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `h` / `Left` | Go to parent directory |
| `l` / `Right` / `Enter` | Enter directory |
| `g` | Jump to top of list |
| `}` | Jump to bottom of list |

## File Operations

| Key | Action |
|-----|--------|
| `o` | Open file with external editor |
| `e` | Open current directory in file explorer |
| `R` | Refresh directory contents |
| `r` | Rename file or directory |
| `d` | Delete file or directory (with confirmation) |
| `a` | Create new file |
| `A` | Create new directory |

`.zip` previews list the archive entries (size, method, modified time, name) without extracting them.

## File Selection

| Key | Action |
|-----|--------|
| `Space` | Toggle selection on current item |
| `m` | Move selected items to current directory |
| `c` | Copy selected items to current directory |
| `x` | Delete selected items |
| `z` | Extract selected `.zip` files (each into `<name>/`) / compress selected items into one `.zip` |

ZIP extraction and compression run as background jobs. Check progress in Jobs mode (`J`).

## Filtering & Search

| Key | Action |
|-----|--------|
| `f` | Enter filter mode (type to filter) |
| `s` | Search file names with fzf |
| `/` | Search file names with fzf (same as `s`) |
| `F` | Search file contents with rga |
| `G` | Global search: file names or contents across all bookmarks |

## Bookmarks & Navigation

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `B` | Bookmark menu (view/add/remove/script paths) |
| `0` | Jump to startup directory |
| `1-9` | Jump to bookmark 1-9 |
| `Tab` | Cycle to next bookmark (Files mode) |
| `Shift+Tab` | Cycle to previous bookmark (Files mode) |
| `z` | Navigate using zoxide history (when nothing is selected) |

## Modes & Tool Runtime

| Key | Action |
|-----|--------|
| `:` | Enter command mode |
| `G` | Global search mode |
| `C` | Config mode: open `~/.config/rufio/` |
| `J` | Job mode (view background jobs) |
| `L` | View execution logs |
| `?` | Open the floating help menu |
| `q` | Quit rufio (with confirmation) |
| `T` | Quit rufio and cd the shell to the current directory (requires `rufio --shell-init`) |

---

## Mode-Specific Keys

### Preview
- **P**: Open fullscreen file preview (hides the file list)
- **j/k**: Scroll preview
- **Ctrl+D/U**: Page down/up
- **ESC**: Back to the file list

### Filter Mode
- **Any character**: Add to filter query
- **Backspace**: Remove last character
- **Enter**: Apply filter and exit filter mode
- **ESC**: Cancel filter and exit filter mode

### Command Mode
- **Any character**: Add to command input
- **Tab**: Auto-complete (scripts, rake tasks, commands, paths)
- **Up/Down**: Navigate command history
- **Enter**: Execute command
- **Backspace**: Remove last character
- **ESC**: Cancel and exit command mode

### Command Mode Prefixes
- `@script` - Execute a registered or local script
- `rake:task` - Execute a Rakefile task
- `!command` - Execute a shell command
- `command` - Execute a built-in or plugin command

### Global Search (G)
- **Type**: Filter results (literal, case insensitive)
- **Tab**: Switch between file names and content
- **Up/Down** or **Ctrl+N/P**: Select a result
- **Enter**: Go to the selected file in Files mode
- **Ctrl+U**: Clear the query
- **ESC**: Return to the previous mode
- Content search also reads `.pdf`, `.xlsx` and `.pptx`

### Config Mode (C)
- Same navigation, preview and file operations as Files mode
- Leaving `~/.config/rufio/` returns to Files mode

### Job Mode (J)
- **j/k**: Navigate through jobs
- **g/G**: First / last job
- **Space**: View job log
- **`x`: Cancel** the selected job (including ZIP jobs)
- **ESC**: Exit job mode

### Help Menu (?)
- **1/2/3** or **Tab/Shift+Tab**: Switch section (Controls / Modes / Scripts)
- **j/k**: Scroll | **Ctrl+D/U**: Page down/up | **g/G**: Top / bottom
- **ESC**, **q** or **?**: Close and keep your current mode and directory

---

## Tips

- **Vim users**: Navigation keys (`hjkl`) work exactly like Vim
- **Selection**: Use `Space` to mark multiple files, then operate on all at once
- **Quick access**: Number keys `1-9` and `Tab` provide instant access to bookmarks
- **Filtering**: Press `f` and start typing for real-time filtering
- **Rake tasks**: Type `:rake:` then `Tab` to see available tasks
- **Local scripts**: Scripts in the current directory are auto-detected with `@` prefix

---

*Press `?` anytime to open the help menu*
