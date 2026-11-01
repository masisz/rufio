# rufio Help

**rufio** is a terminal-based file manager and tool runtime environment.

## Table of Contents

- [Basic Operations](#basic-operations)
- [File Operations](#file-operations)
- [File Selection & Bulk Operations](#file-selection--bulk-operations)
- [Filtering & Search](#filtering--search)
- [Bookmarks & Navigation](#bookmarks--navigation)
- [Command Mode](#command-mode)
- [Tool Runtime](#tool-runtime)
- [Global Search & Config Mode](#global-search--config-mode)
- [Modes & Help Menu](#modes--help-menu)

---

## Basic Operations

### Navigation

| Key | Action |
|-----|--------|
| `j` or `Down` | Move down one item |
| `k` or `Up` | Move up one item |
| `h` or `Left` | Go to parent directory |
| `l`, `Enter`, or `Right` | Enter directory |
| `P` | Fullscreen file preview (`Esc` returns to the file list) |
| `g` | Jump to top of list |
| `}` | Jump to bottom of list |

### File Operations

| Key | Action |
|-----|--------|
| `o` | Open file with external editor |
| `e` | Open current directory in file explorer |
| `R` | Refresh directory contents |
| `r` | Rename file or directory |
| `d` | Delete file or directory (with confirmation) |
| `a` | Create new file |
| `A` | Create new directory |

In a preview, `j/k` scroll, `Ctrl+D/U` page down/up and `ESC` returns to the file list.
`.zip` previews list the archive entries (size, method, modified time, name) without extracting them.

### File Selection & Bulk Operations

| Key | Action |
|-----|--------|
| `Space` | Toggle file/directory selection |
| `m` | Move selected items to current directory |
| `c` | Copy selected items to current directory |
| `x` | Delete selected items |
| `z` | With selected items: extract when all are `.zip` files (each into `<name>/`), otherwise compress them into one `.zip` (runs as a job). Without a selection, `z` opens zoxide history |

ZIP jobs show progress in Jobs mode (`J`). `x`: Cancel the selected job there; a partially extracted folder is removed.

### Filtering & Search

| Key | Action |
|-----|--------|
| `f` | Start filter mode |
| `s` | Search file names with fzf |
| `/` | Search file names with fzf (same as `s`) |
| `F` | Search file contents with rga (ripgrep-all) |
| `G` | Global search: file names or contents across all bookmarks |

**Filter Mode:**
- Type characters to filter files in real-time
- Press `Enter` to apply filter and exit filter mode
- Press `ESC` to cancel and clear filter

### Bookmarks & Navigation

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `B` | Bookmark menu (view/add/remove/script paths) |
| `0` | Jump to startup directory |
| `1-9` | Jump to bookmark 1-9 |
| `Tab` | Cycle to next bookmark (Files mode) |
| `Shift+Tab` | Cycle to previous bookmark (Files mode) |
| `z` | Navigate using zoxide history (when nothing is selected) |

---

## Command Mode

Press `:` to enter command mode. Available prefixes:

| Prefix | Function | Example |
|--------|----------|---------|
| `@` | Execute script | `:@build.sh` |
| `rake:` | Execute rake task | `:rake:test` |
| `!` | Shell command | `:!git status` |
| (none) | Built-in command | `:hello` |

### Features

- **Tab completion**: Press `Tab` to auto-complete commands, scripts, and rake tasks
- **Command history**: Use `Up/Down` arrows to navigate previous commands
- **Local scripts**: Scripts in the current directory are automatically available with `@` prefix
- **Rakefile parsing**: Tasks from `Rakefile` in the current directory are available as `rake:task_name`

---

## Tool Runtime

| Key | Action |
|-----|--------|
| `:` | Enter command mode |
| `J` | Job mode (view background jobs) |
| `L` | View execution logs |

### Script Path Management

Press `B` then select script path management to:
- View registered script directories
- Add/remove script paths
- Jump to script directories

### Supported Script Types

| Extension | Language |
|-----------|----------|
| `.rb` | Ruby |
| `.py` | Python |
| `.sh` | Shell (bash/zsh) |
| `.js` | JavaScript |
| `.ts` | TypeScript |
| `.pl` | Perl |
| `.ps1` | PowerShell |

---

## Global Search & Config Mode

### Global Search (`G`)

Search file names or text inside every bookmarked directory.

- `Tab`: Switch between file names and content (literal, case insensitive)
- Content search also reads `.pdf` (page), `.xlsx` (sheet/cell) and `.pptx` (slide)
- `Up/Down` or `Ctrl+N/P`: Select a result | `Enter`: Go to the file in Files mode
- `Ctrl+U`: Clear the query | `ESC`: Return to the previous mode
- Exclude extensions with `GLOBAL_SEARCH_EXCLUDED_EXTENSIONS` in `~/.config/rufio/config.rb`

### Config Mode (`C`)

Opens `~/.config/rufio/` (created if missing) with the same navigation, preview
and file operations as Files mode. Leaving the directory returns to Files mode.

---

## Modes & Help Menu

| Key | Action |
|-----|--------|
| `G` | Global search mode |
| `C` | Config mode: open `~/.config/rufio/` |
| `J` | Job mode |
| `L` | Execution logs |
| `?` | Open the floating help menu |
| `ESC` | Exit current mode |
| `q` | Quit rufio (with confirmation) |
| `T` | Quit rufio and cd the shell to the current directory (requires `rufio --shell-init`) |

In Files mode, `Tab` / `Shift+Tab` cycle bookmarks. In other modes, `Shift+Tab` switches to the previous mode.

### Help Menu

`?` opens a floating menu over the current screen; your mode and directory are kept.

- `1/2/3` or `Tab/Shift+Tab`: Switch section (Controls / Modes / Scripts)
- `j/k`: Scroll | `Ctrl+D/U`: Page down/up | `g/G`: Top / bottom
- `ESC`, `q` or `?`: Close

---

## Tips

1. **Quick navigation**: Use `g` and `G` to jump to top/bottom
2. **Bulk operations**: Select multiple files with `Space`, then use `m/c/x`
3. **Filter + Search**: Use `f` for real-time filtering, `s` for fuzzy search
4. **Bookmarks**: Save frequently used directories with `b`, access with `1-9`
5. **Rake tasks**: If your project has a Rakefile, use `:rake:` with Tab completion
6. **Background jobs**: Long-running commands and ZIP jobs execute in background, view with `J`
7. **Global search**: Press `G` to search names or contents across all bookmarks

---

For more information, visit: https://github.com/masisz/rufio
