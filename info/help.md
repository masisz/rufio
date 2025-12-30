# rufio Help

**rufio** is a terminal-based file manager inspired by Yazi.

## Table of Contents

- [Basic Operations](#basic-operations)
- [Navigation](#navigation)
- [File Operations](#file-operations)
- [File Selection & Bulk Operations](#file-selection--bulk-operations)
- [Filtering & Search](#filtering--search)
- [Bookmarks](#bookmarks)
- [Other Features](#other-features)

---

## Basic Operations

### Navigation

| Key | Action |
|-----|--------|
| `j` or `↓` | Move down one item |
| `k` or `↑` | Move up one item |
| `h` or `←` | Go to parent directory |
| `l`, `Enter`, or `→` | Enter directory / Select file |
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

### Bookmarks

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `0` | Jump to startup directory |
| `1-9` | Jump to bookmark 1-9 |
| `p` | Enter project mode (browse bookmarks) |

**Project Mode:**
- Browse all bookmarks with normal navigation keys
- Press `Space` to select a bookmark and jump to it
- Press `ESC` to exit project mode

### Other Features

| Key | Action |
|-----|--------|
| `z` | Navigate using zoxide history |
| `:` | Enter command mode |
| `?` | Enter help mode (this mode) |
| `ESC` | Exit help mode / Cancel filter |
| `q` | Quit rufio |

---

## Help Mode

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
5. **Project mode**: Press `p` to see all bookmarks at once

---

For more information, visit: https://github.com/masisz/rufio
