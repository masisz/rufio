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
- [Search & Config Mode](#search--config-mode)
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
| `y` | Copy the current or selected paths to the clipboard |

In a preview, `j/k` scroll, `Ctrl+D/U` page down/up and `ESC` returns to the file list.

In a table preview, `h/j/k/l` and the arrow keys move a cell cursor instead, `g/}` jump to the first and last row, `0/$` to the first and last column, `Space` selects the column under the cursor (its cells are marked like a selected file), `y` copies the cell under the cursor, or the cursor row's selected columns joined with commas when any column is selected, `Y` the whole row as a CSV line, `[`/`]` switch between a workbook's sheets or a database's tables, `t` opens the list of sheets or tables (`j`/`k` to move, `Enter` to open the selected one, `ESC` to close), and the line under the file name shows the cell address and column name (`R3C2 price`). The grid scrolls in both directions to keep the cursor visible.

Copying uses `pbcopy`, `clip`, `wl-copy`, `xclip` or `xsel` when available and OSC 52 otherwise; `CLIPBOARD_COMMAND` in `config.rb` overrides it and `rufio -c` shows which one is used.

Text previews read at most the first 64 KiB. PDF bodies are not previewed, keeping file navigation responsive.

`.zip` previews list the archive entries (size, method, modified time, name) without extracting them.

`.csv`, `.tsv`, `.tab`, `.xlsx`, `.xlsm` and `.ods` files, and SQLite databases when the `sqlite3` command is installed (recognised by the file's own signature, whatever its extension), are shown as a grid with column letters, the header row kept in place while you scroll, and a last line reporting the row and column counts, the detected character encoding and any truncation. UTF-8, UTF-16 (with BOM), CP932 and EUC-JP files are decoded automatically. A `.csv` or `.tsv` is read up to 512 KiB.

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
| `/` | Search, scoped to where you are |

**Search (`/`):**
- `/` is the only search key. What it searches depends on the mode: the file list searches the current directory tree, a preview searches inside the file, and a table preview filters its rows
- In the file list it opens the search screen over every file under the current directory (hidden files included); no external tools are needed. Bookmarks are not searched
- `Tab`: Switch between fuzzy (in-order, non-contiguous) file names and literal, case insensitive contents. Matched characters are highlighted
- `Up/Down` or `Ctrl+J/K or Ctrl+N/P`: Select | `Enter`: Go to the file in Files mode | `Ctrl+U`: Clear | `ESC`: Back
- Content results show the file, the line number and the matching text, and also read `.pdf` (page), `.xlsx` (sheet/cell) and `.pptx` (slide)

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
| `z` | Navigate using zoxide history (when nothing is selected) |

---

## Command Mode

Press `:` to enter command mode. Available prefixes:

| Prefix | Function | Example |
|--------|----------|---------|
| `@` | Execute script | `:@build.sh` |
| `rake:` | Execute rake task | `:rake:test` |
| `!` | Shell command | `:!git status` |
| `cd` | Go to a pasted path (file paths select the file, `cd -` goes back) | `:cd ~/projects/app` |
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

## Search & Config Mode

### Search (`/`)

Search file names or text under the current directory.

- `Tab`: Switch between fuzzy file names (best matches first) and literal content (case insensitive)
- Content search also reads `.pdf` (page), `.xlsx` (sheet/cell) and `.pptx` (slide)
- `Up/Down` or `Ctrl+J/K or Ctrl+N/P`: Select a result | `Enter`: Go to the file in Files mode
- `Ctrl+U`: Clear the query | `ESC`: Return to Files mode
- Exclude extensions (or `/name` directories and files) with `SEARCH_EXCLUDED_EXTENSIONS` in `~/.config/rufio/config.rb` (the older `GLOBAL_SEARCH_EXCLUDED_EXTENSIONS` is still read)

### Config Mode (`C`)

Opens `~/.config/rufio/` (created if missing) with the same navigation, preview
and file operations as Files mode. Leaving the directory returns to Files mode.

---

## Modes & Help Menu

| Key | Action |
|-----|--------|
| `C` | Config mode: open `~/.config/rufio/` |
| `J` | Job mode |
| `L` | Execution logs |
| `?` | Open the floating help menu |
| `ESC` | Exit current mode |
| `q` | Quit rufio (with confirmation) |
| `T` | Quit rufio and cd the shell to the current directory (requires `rufio --shell-init`) |

In modes other than Files and Config, `Shift+Tab` switches to the previous mode.

### Help Menu

`?` opens a floating menu over the current screen; your mode and directory are kept.

- `1/2/3` or `Tab/Shift+Tab`: Switch section (Controls / Modes / Scripts)
- `j/k`: Scroll | `Ctrl+D/U`: Page down/up | `g/G`: Top / bottom
- `ESC`, `q` or `?`: Close

---

## Tips

1. **Quick navigation**: Use `g` and `G` to jump to top/bottom
2. **Bulk operations**: Select multiple files with `Space`, then use `m/c/x`
3. **Filter + Search**: Use `f` for real-time filtering, `/` to search the directory tree
4. **Bookmarks**: Save frequently used directories with `b`, access with `1-9`
5. **Rake tasks**: If your project has a Rakefile, use `:rake:` with Tab completion
6. **Background jobs**: Long-running commands and ZIP jobs execute in background, view with `J`
7. **Search**: Press `/` to search names or contents under the current directory

---

For more information, visit: https://github.com/masisz/rufio
