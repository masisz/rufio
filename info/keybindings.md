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
| `y` | Copy the path of the current file to the clipboard |

`.zip` previews list the archive entries (size, method, modified time, name) without extracting them.

Image previews (`.png`, `.jpg`, `.bmp`) use the Kitty graphics protocol when the terminal supports it; the bundled native library decodes and scales the picture down to the pane first. Otherwise the format, size and dimensions are shown as text. `RUFIO_IMAGE_PREVIEW=0` disables images, `RUFIO_NATIVE_IMAGE=0` only the decoding (PNG is then sent as-is).

### Preview of an image
- **+** / **-**: Zoom in 25% steps, up to 4x
- **0**: Fit the picture to the pane
- **h/j/k/l** or the **arrow keys**: Move around the picture while zoomed
- **y**: Copy the file path | **ESC**: Back to the file list

`.csv`, `.tsv`, `.tab`, `.xlsx`, `.xlsm` and `.ods` previews, and SQLite databases when the `sqlite3` command is installed, show the file as a grid: column letters with the header row, row numbers, a fixed header while scrolling, and a last line with the row/column counts, the detected encoding and any truncation. `TABLE_PREVIEW` in `config.rb` changes the limits (`max_bytes`, up to 4 MiB, `max_rows`, `max_columns`, `max_column_width`) and the `header`, `delimiter` and `encoding` handling.

Text previews read at most the first 64 KiB. PDF bodies are not previewed, keeping file navigation responsive.

## File Selection

| Key | Action |
|-----|--------|
| `Space` | Toggle selection on current item |
| `m` | Move selected items to current directory |
| `c` | Copy selected items to current directory |
| `x` | Delete selected items |
| `y` | Copy every selected path to the clipboard (one per line) |
| `z` | Extract selected `.zip` files (each into `<name>/`) / compress selected items into one `.zip` |

ZIP extraction and compression run as background jobs. Check progress in Jobs mode (`J`).

## Filtering & Search

| Key | Action |
|-----|--------|
| `f` | Enter filter mode (type to filter) |
| `/` | Search under the current directory (file names or contents) |

`/` is the only search key, and what it searches depends on where you are: the file list searches the directory tree, a preview searches inside the file, and a table preview filters its rows. In the file list it opens the search screen, where you type to filter, **Tab** switches between fuzzy file names and literal contents, **Up/Down** or **Ctrl+J/K** select, **Enter** goes to the file and **ESC** returns.

## Bookmarks & Navigation

| Key | Action |
|-----|--------|
| `b` | Add current directory to bookmarks |
| `B` | Bookmark menu (view/add/remove/script paths) |
| `0` | Jump to startup directory |
| `1-9` | Jump to bookmark 1-9 |
| `z` | Navigate using zoxide history (when nothing is selected) |

## Modes & Tool Runtime

| Key | Action |
|-----|--------|
| `:` | Enter command mode |
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
- **y**: Copy the file path to the clipboard
- **j/k**: Scroll preview
- **Ctrl+D/U**: Page down/up
- **/**: Search inside the file. Type to jump to the first match, `Enter` keeps it, **n** / **N** move to the next / previous match (wrapping around), `ESC` clears the search. Matches are highlighted, the current one in a different colour
- **ESC**: Back to the file list (clears a search first)

### Preview of a table (`.csv` / `.tsv` / `.tab` / `.xlsx` / `.xlsm` / `.ods` / SQLite)
- **h/j/k/l** or the **arrow keys**: Move the cell cursor. The grid scrolls, horizontally as well, to keep the cursor in view and the header row in place
- **Ctrl+D/U**: Move one screen of rows
- **g/}**: First / last row
- **0/$**: First / last column of the row
- **Space**: Select / unselect the column under the cursor. The selected columns' cells are marked, and the line under the file name lists them (`cols A,C`). Switching sheets clears the selection
- **y**: Copy the cell under the cursor to the clipboard (the raw value, including any newlines inside it). With columns selected, it copies the cursor row's selected columns instead, joined with commas as one CSV line (`apple,30`), in column order
- **Y**: Copy the whole row as one CSV line
- **[/]**: Previous / next sheet, for a workbook's sheets or a database's tables
- **/**: Filter the rows. `price > 100, name a%` means price over 100 and a name starting with `a`; a term without a column is searched in every column. `Enter` applies it, `ESC` clears it. A SQLite table is filtered with a read-only `SELECT ... WHERE` inside the database, so rows past the preview's row limit are found too
- **t**: Open the list of sheets or tables. `j`/`k` or the arrow keys move, `Ctrl+D/U` page, `g/}` jump to the first and last entry, `Enter` opens the selected one, `ESC` or `/` closes the list. `>` marks the sheet on screen. A single-sheet file has no list
- The line under the file name shows the cell address and the column name, e.g. `R3C2 price`, and the result of a copy
- **ESC**: Back to the file list

Cell movement follows the `move_up` / `move_down` / `navigate_parent` / `navigate_enter` keybinds, so rebinding `hjkl` applies here too.

A `.csv` or `.tsv` is read up to 512 KiB, and only `max_rows` rows of it are parsed, so a wider limit costs no more parsing. Only the sheet being shown is read, so a workbook's other sheets and a database's other tables cost nothing until you switch to them. A SQLite database is recognised by the file's own signature, whatever its extension. A spreadsheet over 10 MiB, or one that cannot be read, falls back to the ZIP entry list.

Copying uses `pbcopy`, `clip`, `wl-copy`, `xclip` or `xsel` when one is available, and OSC 52 otherwise, which also works over SSH if the terminal supports it (in tmux, `set -g set-clipboard on`). `CLIPBOARD_COMMAND` in `config.rb` sets your own command, and `rufio -c` reports which one is used.

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
- `cd <path>` - Go to a directory (paste a path; a file path selects the file, `cd -` goes back, `Tab` completes directories)
- `command` - Execute a built-in or plugin command

### Search (`/`) in the file list
- **Type**: Filter results (fuzzy for file names, literal and case insensitive for contents)
- **Tab**: Switch between file names and content
- **Up/Down** or **Ctrl+J/K or Ctrl+N/P**: Select a result
- **Enter**: Go to the selected file in Files mode
- **Ctrl+U**: Clear the query
- **ESC**: Return to Files mode
- Only the current directory tree is searched; bookmarks are not
- Content search also reads `.pdf`, `.xlsx` and `.pptx`
- `SEARCH_EXCLUDED_EXTENSIONS` in `config.rb` skips extensions, or `/name` directories and files

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
- **Quick access**: Number keys `1-9` provide instant access to bookmarks
- **Filtering**: Press `f` and start typing for real-time filtering
- **Rake tasks**: Type `:rake:` then `Tab` to see available tasks
- **Local scripts**: Scripts in the current directory are auto-detected with `@` prefix

---

*Press `?` anytime to open the help menu*
