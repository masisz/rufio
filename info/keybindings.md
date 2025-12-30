# Keybindings Reference

Complete reference of all keyboard shortcuts in **rufio**.

## Navigation

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `h` / `←` | Go to parent directory |
| `l` / `→` / `Enter` | Enter directory or select file |
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

## Bookmarks

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `0` | Jump to startup directory |
| `1` | Jump to bookmark 1 |
| `2` | Jump to bookmark 2 |
| `3` | Jump to bookmark 3 |
| `4` | Jump to bookmark 4 |
| `5` | Jump to bookmark 5 |
| `6` | Jump to bookmark 6 |
| `7` | Jump to bookmark 7 |
| `8` | Jump to bookmark 8 |
| `9` | Jump to bookmark 9 |
| `p` | Enter project mode (browse all bookmarks) |

## Other

| Key | Action |
|-----|--------|
| `z` | Navigate using zoxide history |
| `:` | Enter command mode |
| `?` | Enter help mode |
| `ESC` | Exit current mode (help/filter/project) |
| `q` | Quit rufio |

---

## Mode-Specific Keys

### Filter Mode
- **Any character**: Add to filter query
- **Backspace**: Remove last character
- **Enter**: Apply filter and exit filter mode
- **ESC**: Cancel filter and exit filter mode

### Project Mode
- **j/k**: Navigate through bookmarks
- **Space**: Select bookmark and jump to directory
- **ESC**: Exit project mode

### Help Mode
- **j/k/h/l**: Navigate help files
- **ESC**: Exit help mode and return to previous directory

---

## Tips

- **Vim users**: Navigation keys (`hjkl`) work exactly like Vim
- **Selection**: Use `Space` to mark multiple files, then operate on all at once
- **Quick access**: Number keys `1-9` provide instant access to bookmarks
- **Filtering**: Press `f` and start typing for real-time filtering

---

*Press `?` anytime to return to help mode*
