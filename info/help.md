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
- [Mode Switching](#mode-switching)

---

## Basic Operations

### Navigation

| Key | Action |
|-----|--------|
| `j` or `Down` | Move down one item |
| `k` or `Up` | Move up one item |
| `h` or `Left` | Go to parent directory |
| `l`, `Enter`, or `Right` | Enter directory / Open file |
| `g` | Jump to top of list |
| `G` | Jump to bottom of list |

### File Operations

| Key | Action |
|-----|--------|
| `o` | Open file with external editor |
| `e` | Open in file explorer |
| `R` | Refresh directory contents |
| `r` | Rename file or directory |
| `d` | Delete file or directory (with confirmation) |
| `a` | Create new file |
| `A` | Create new directory |

### File Selection & Bulk Operations

| Key | Action |
|-----|--------|
| `Space` | Toggle file/directory selection |
| `m` | Move selected items to current directory |
| `c` | Copy selected items to current directory |
| `x` | Delete selected items |

### Filtering & Search

| Key | Action |
|-----|--------|
| `f` | Start filter mode |
| `s` | Search file names with fzf |
| `F` | Search file contents with rga (ripgrep-all) |

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
| `z` | Navigate using zoxide history |

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

## Mode Switching

| Key | Action |
|-----|--------|
| `Tab` | Switch mode: Files -> Logs -> Jobs -> Help |
| `Shift+Tab` | Switch mode (reverse) |
| `?` | Enter help mode (this mode) |
| `ESC` | Exit current mode |
| `q` | Quit rufio |

### Help Mode

You are currently in **Help Mode**. In this mode:

- Navigate through help files using normal keys (`j/k/h/l`)
- Press `l` or `Enter` to view a help file
- Press `h` to go back (restricted to `info/` directory)
- Press `ESC` to exit help mode and return to your previous directory

---

## Tips

1. **Quick navigation**: Use `g` and `G` to jump to top/bottom
2. **Bulk operations**: Select multiple files with `Space`, then use `m/c/x`
3. **Filter + Search**: Use `f` for real-time filtering, `s` for fuzzy search
4. **Bookmarks**: Save frequently used directories with `b`, access with `1-9`
5. **Rake tasks**: If your project has a Rakefile, use `:rake:` with Tab completion
6. **Background jobs**: Long-running commands execute in background, view with `J`

---

For more information, visit: https://github.com/masisz/rufio
