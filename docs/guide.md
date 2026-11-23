# rufio User Guide

[日本語](./guide_ja.md) | **English**

This guide covers rufio 1.3 and later. For installation and an overview, see the [README](../README.md).
Inside rufio, press `?` to open the help menu at any time.

## Contents

- [Screen and Modes](#screen-and-modes)
- [Navigation](#navigation)
- [Preview](#preview)
- [File Operations](#file-operations)
- [ZIP Archives](#zip-archives)
- [Filter and Search](#filter-and-search)
- [Search Screen (`/` in the file list)](#search-screen--in-the-file-list)
- [Bookmarks and History](#bookmarks-and-history)
- [Command Mode](#command-mode)
- [Scripts](#scripts)
- [DSL Commands](#dsl-commands)
- [Jobs and Logs](#jobs-and-logs)
- [Config Mode](#config-mode)
- [Shell Integration](#shell-integration)
- [Configuration](#configuration)
- [External Tools](#external-tools)
- [Command-line Options](#command-line-options)
- [Native Engine](#native-engine)

## Screen and Modes

Files mode shows the current path on the top row, the bookmark list, the file list on the left and a preview on the right. The bottom row shows the mode tabs.

| Key | Mode |
|-----|------|
| (start) | **Files** – browse and operate on files |
| `C` | **Config** – browse `~/.config/rufio/` with the same controls as Files |
| `G` | **Search** – search names or contents across all bookmarks |
| `L` | **Logs** – browse command execution logs |
| `J` | **Jobs** – background commands, scripts and ZIP jobs |
| `?` | **Help** – floating help menu over the current screen |

`ESC` leaves the current mode. In modes other than Files and Config, `Shift+Tab` switches to the previous mode.

## Navigation

| Key | Action |
|-----|--------|
| `j` / `Down` | Move down |
| `k` / `Up` | Move up |
| `h` / `Left` | Parent directory |
| `l` / `Right` / `Enter` | Enter directory |
| `g` | First entry |
| `}` | Last entry |
| `R` | Refresh |
| `0` | Back to the directory rufio started in |
| `q` | Quit (with confirmation) |
| `T` | Quit and move the shell to the current directory (see [Shell Integration](#shell-integration)) |

The mouse also works: click to select, and scroll the list or the preview.

## Preview

Text previews read at most the first 64 KiB. PDF bodies are not previewed, keeping file navigation responsive.

The right pane previews the selected file. Code is highlighted when `bat` is installed. `.zip` files show their entry list (size, method, modified time, name) without extracting them.

| Key | Action |
|-----|--------|
| `P` | Fullscreen preview (hides the file list) |
| `j` / `k` | Scroll |
| `Ctrl+D` / `Ctrl+U` | Page down / up |
| `y` | Copy the file path to the clipboard |
| `ESC` | Back to the file list |

### Images

Images (`.png`, `.jpg`, `.gif`, `.bmp`) are drawn in the preview pane by the terminal itself, using the Kitty graphics protocol. kitty, Ghostty, WezTerm and Konsole support it; rufio asks the terminal once at startup and silently falls back when the answer is no.

| Situation | What you see |
|-----------|--------------|
| Supported terminal, `.png` / `.jpg` / `.bmp` up to 32 MiB | The picture, fitted to the pane (split view and `P` both work) |
| No native library (or `RUFIO_NATIVE_IMAGE=0`), PNG up to 8 MiB | The picture, sent as-is and scaled by the terminal |
| `.gif`, progressive JPEG, interlaced PNG | Format, pixel size and file size as text |
| Unsupported terminal, or inside tmux | The same text |

The bundled native library (Zig, no third-party image code) decodes the image, scales it down to the pane's real pixel size and re-encodes it as PNG before sending, so a 12 MP photo reaches the terminal as a few hundred KB in about 30 ms, off the main loop. While it works the pane shows `decoding...`.

In preview mode (`P`) the picture can be zoomed:

| Key | Action |
|-----|--------|
| `+` / `-` | Zoom in 25% steps, up to 4x (the terminal is asked for part of the picture, so nothing is decoded here) |
| `0` | Fit the picture to the pane |
| `h` / `j` / `k` / `l` or arrows | Move around the picture while zoomed |

The cells behind a picture are kept blank so the file list and the status line stay readable, and the picture is removed when you select another file, open the help menu, the search screen or command mode, and when rufio exits. Moving to another file removes the picture immediately and sends the new one about 80 ms later, so holding `j` through a folder of images does not flood the terminal; a picture that was painted over (by a notification, say) is put back; and a file you come back to is not read or encoded again. `RUFIO_IMAGE_PREVIEW=0` turns images off entirely. The design and the remaining phases are in [image_preview_design_ja.md](./image_preview_design_ja.md).

### Searching inside a preview (`/`)

`/` in a preview searches the previewed file. Type to jump to the first match from where you are, `Enter` keeps the search, `n` and `N` move to the next and previous match (wrapping around), and `ESC` clears it (a second `ESC` leaves the preview). Every match is highlighted and the current one is drawn in a different colour. Preview mode reads up to 20,000 lines of the first 64 KiB of the file, so the search covers what the preview can show.

### Tables as a Grid

`.csv`, `.tsv`, `.tab`, `.xlsx`, `.xlsm` and `.ods` files, and SQLite databases when the `sqlite3` command is installed, are shown as rows and columns:

```
 sales.csv [PREVIEW MODE]
 R3C2 price  |  hjkl: move  y: copy  ESC: back
   | A name | B price | C stock |
 1 | apple  | 120     | 30      |
 2 | mikan  | 150     | 8       |
 3 | banana | 80      | 12      |
3 rows  3 cols
```

Column letters sit beside the header names, the header row stays in place while you scroll, and the last line reports the row and column counts, the character encoding that was detected, any limit that was reached and how many columns do not fit the pane.

In preview mode the cell cursor moves:

| Key | Action |
|-----|--------|
| `h` / `j` / `k` / `l` or arrows | Move the cell cursor (the grid scrolls in both directions to follow it) |
| `Ctrl+D` / `Ctrl+U` | Move one screen of rows |
| `g` / `}` | First / last row |
| `0` / `$` | First / last column |
| `Space` | Select / unselect the column under the cursor |
| `/` | Filter the rows (see below) |
| `y` | Copy the cell under the cursor, or the cursor row's selected columns joined with commas |
| `Y` | Copy the whole row as one CSV line |
| `[` / `]` | Previous / next sheet, for a workbook's sheets or a database's tables |
| `t` | Open the list of sheets or tables (`j`/`k` to move, `Enter` to open, `ESC` to close) |
| `ESC` | Back to the file list |

`Space` marks the column under the cursor the way a selected file is marked, and the line under the file name lists the selection (`cols A,C`). With columns selected, `y` copies the cursor row's cells from those columns, in column order, joined with commas as one CSV line (`apple,30`), so a cell holding a comma or a newline is quoted. `Y` still copies the whole row, and switching sheets clears the selection.

### Filtering rows (`/`)

`/` in a table preview filters its rows. Write conditions separated by commas:

| Input | Means |
|-------|-------|
| `price > 100` | A comparison (`=`, `!=`, `<>`, `>`, `>=`, `<`, `<=`); numeric when both sides are numbers |
| `name a%` | `LIKE 'a%'`: `%` is any text, `_` is one character |
| `name apple` | `LIKE '%apple%'`: matches anywhere in the column |
| `note "red, sweet"` | Quote a value to keep its commas and spaces |
| `apple` | No column named: searched in every column |
| `price > 100, name a%` | Several conditions, all of which must match |

Column names ignore case and the column letters (`A`, `B`, …) work too. `Enter` applies the filter, and the line under the file name shows it (`filter: price > 100 (2 rows)`). `ESC` clears the filter; a second `ESC` leaves the preview. Switching sheets clears it as well.

For a SQLite table the conditions become a read-only `SELECT ... WHERE` run inside the database, so the filter finds rows past the preview's row limit. Values are always passed as quoted literals and the column names are resolved against the table's own columns, so the input cannot become SQL of its own. A spreadsheet or CSV is filtered in Ruby over the rows that were read.

`t` lists a workbook's sheets or a database's tables, with `>` beside the one on screen; `Ctrl+D`/`Ctrl+U` page through a long list and `g`/`}` jump to its first and last entry. A file with a single sheet has no list.

Cell movement follows your `move_up` / `move_down` / `navigate_parent` / `navigate_enter` keybinds, so rebinding `hjkl` applies here too.

UTF-8, UTF-16 (with a BOM), CP932 and EUC-JP are decoded automatically, so a Shift_JIS CSV reads as text rather than replacement characters. A `.csv` or `.tsv` is read up to 512 KiB and 1000 rows; only the sheet on screen is read, so a workbook's other sheets and a database's other tables cost nothing until you switch to them. A spreadsheet over 10 MiB, or one that cannot be parsed, falls back to the ZIP entry list.

Copying uses `pbcopy`, `clip`, `wl-copy`, `xclip` or `xsel` when one is available, and OSC 52 otherwise, which works over SSH if your terminal supports it (in tmux, also `set -g set-clipboard on`). `CLIPBOARD_COMMAND` in `config.rb` sets a command of your own, and `rufio -c` reports which one is used. `TABLE_PREVIEW` changes the limits and the header, delimiter and encoding handling.

## File Operations

| Key | Action |
|-----|--------|
| `o` | Open the file with its application (see `APPLICATIONS` in [Configuration](#configuration)) |
| `e` | Open the current directory in the system file explorer |
| `a` | Create a file |
| `A` | Create a directory |
| `r` | Rename |
| `d` | Delete (with confirmation) |
| `Space` | Select / unselect the current item |
| `m` | Move selected items to the current directory |
| `c` | Copy selected items to the current directory |
| `x` | Delete selected items (with confirmation) |

To move or copy, select items with `Space`, go to the destination directory, then press `m` or `c`.
When a copied item's name already exists, the copy is numbered (`name_1.txt`, `dir_1`). A move to an existing name is reported as an error.

## ZIP Archives

Select items with `Space` and press `z`:

- **Every selected item is a `.zip`**: each archive is extracted into `<name>/` in the current directory (`<name> 2/`, `<name> 3/` and so on if the name is taken)
- **Otherwise**: rufio asks for an archive name and compresses the selection into one `.zip` in the current directory. Press `Enter` to accept the suggested name (`<item>.zip` for one item, `Archive.zip` for several)

The work runs as a job. Check progress and cancel it in Jobs mode (`J`, then `x`). A partially extracted folder is removed when extraction fails or is cancelled, and the file list refreshes when the job finishes.

Extraction validates the whole archive before writing anything. It rejects path traversal, absolute paths, overlapping entries, and archives over 16 GiB in total, 100,000 entries or a 1000:1 compression ratio (for entries over 1 MiB). Symlink and encrypted entries are skipped, CRC-32 is verified, and existing files are never overwritten. Stored and Deflate entries are supported.

With nothing selected, `z` opens zoxide history instead.

## Filter and Search

| Key | Action |
|-----|--------|
| `f` | Filter the current list as you type (`Enter` keeps the filter, `ESC` clears it) |
| `/` | Search, scoped to where you are |

`/` is the only search key, and what it searches depends on the mode:

| Where you press `/` | What it searches |
|---------------------|------------------|
| The file list | Every file under the current directory: names (fuzzy) or contents (literal) |
| A preview (`P`) | Inside the previewed file |
| A table preview | Filters the rows of the sheet or table on screen |

## Search Screen (`/` in the file list)

`/` searches recursively under the current directory; bookmarks are not searched. File names are matched with fuzzy matching (best matches first, matched characters highlighted, filtered in the background); content search stays literal and case-insensitive. Hidden files and links to regular files are included, and results appear while the tree is still being scanned.

| Key | Action |
|-----|--------|
| Type | File names: fuzzy search. Content: Literal, case-insensitive search |
| `Tab` | Switch between **File names** and **Content** |
| `Up` / `Down`, `Ctrl+J` / `Ctrl+K`, `Ctrl+N` / `Ctrl+P` | Select a result |
| `Enter` | Go to the file in Files mode |
| `Ctrl+U` | Clear the query |
| `ESC` | Return to Files mode |

- Fuzzy matching means the query characters must appear in order but need not be adjacent (`sctrl` finds `search_controller.rb`). ASCII letters ignore case and Japanese text is matched as is.
- Matches are highlighted. Content results show the file, line number and matching text.
- A yellow `Searching...` indicator animates while scanning and turns into a green `Search complete` when done.
- Inaccessible directories and directory symlinks are skipped. Plain text is read as UTF-8, and files with NUL bytes in the first 8 KB are treated as binary.
- The matching uses the bundled Zig library when available and falls back to Ruby otherwise (`RUFIO_NATIVE_FUZZY=0` forces Ruby).

### Documents

Content search also reads documents, without Python, Microsoft Office or conversion tools:

| File | Searched text | Result location |
|------|---------------|-----------------|
| `.pdf` | Extractable text | Page |
| `.xlsx` | Cell text and saved values | Sheet and cell |
| `.pptx` | Text in slide shapes and tables | Slide |

Extracted text is cached in memory (up to 64 documents, about 16 MiB) and re-extracted when a file changes. Scanned images need OCR, which is not included. Legacy `.xls` / `.ppt` and slide notes are not supported.

### Excluding Extensions and Directories

Add this to `~/.config/rufio/config.rb` and restart rufio. It applies to both file names and contents:

```ruby
SEARCH_EXCLUDED_EXTENSIONS = %w[.png .jpg .zip .tar.gz .log /.git /node_modules /.DS_Store].freeze
```

Extensions ignore case, the leading dot is optional, and the default `[]` excludes nothing. An entry starting with `/` is a name: a directory with that name is skipped with everything under it, and a file with exactly that name is skipped.

## Bookmarks and History

| Key | Action |
|-----|--------|
| `b` | Bookmark the current directory |
| `B` | Bookmark menu |
| `1`–`9` | Jump to bookmark 1–9 |
| `z` | zoxide history (when nothing is selected) |

The `B` menu has four items:

1. Add the current directory to bookmarks
2. Add the current directory to script paths
3. Manage script paths (`d` removes, `Enter` jumps, `ESC` closes)
4. View bookmarks

## Command Mode

Press `:` to open command mode. `Tab` completes, `Up` / `Down` recalls history, `Enter` runs and `ESC` cancels.

| Input | Action |
|-------|--------|
| `@name` | Run a script from script paths or the current directory |
| `rake:task` | Run a task from the `Rakefile` in the current directory |
| `!command` | Run a shell command in the background |
| `cd <path>` | Go to a directory |
| `name` | Run a built-in or DSL command |

```
:@build              # Script (Tab completes the name)
:rake:test           # Rake task (Rakefile, rakefile and Rakefile.rb are supported)
:!git status         # Shell command
:hello               # Built-in sample command
```

### Going to a Path

Paste a path after `:cd` to jump there:

```
:cd ~/projects/app             # Directory
:cd '/path/with space/a.txt'   # File: opens its folder and selects the file
:cd sub                        # Relative to the current directory
:cd -                          # Back to the previous directory
:cd                            # Home directory
```

Surrounding quotes, a trailing newline, `\ ` escapes and `file://` URLs from copied paths are accepted. `Tab` completes directory names. If the path does not exist, rufio stays where it is and shows an error.

## Scripts

Scripts in registered script paths, and in the directory you are browsing, run with `:@name`. They run in the directory you are browsing.

| Extension | Runs with |
|-----------|-----------|
| `.rb` | Ruby |
| `.py` | Python 3 |
| `.sh` | Shell |
| `.js` | Node.js |
| `.ts` | ts-node |
| `.pl` | Perl |
| `.ps1` | PowerShell |

Script paths are searched in this order, and the first matching name wins:

1. `./rufio.yml` in the project
2. `~/.config/rufio/script_paths.yml`
3. `/etc/rufio/script_paths.yml`

To register a directory, open it in rufio and press `B` then `2`.

## DSL Commands

Define your own commands in `~/.config/rufio/commands.rb` (`~/.rufio/commands.rb` also works) and run them with `:name`:

```ruby
command "hello" do
  ruby { "Hello from rufio!" }
  description "Greeting command"
end

command "status" do
  shell "git status"
  description "Git status"
end

command "build" do
  script "~/.config/rufio/scripts/build.rb"
  description "Run build"
end
```

## Jobs and Logs

Shell commands, scripts and ZIP work run in the background while you keep browsing. A notification appears when a job finishes.

**Jobs mode (`J`)**

| Key | Action |
|-----|--------|
| `j` / `k` | Select a job |
| `g` / `G` | First / last job |
| `Space` | View the job's log |
| `x` | Cancel the selected job |
| `ESC` | Back |

**Logs mode (`L`)** lists the execution logs in `~/.config/rufio/logs/`. Press `P` to preview a log, `ESC` to leave the preview and `ESC` again to return to Files.

## Config Mode

`C` opens `~/.config/rufio/`, creating it if needed. Navigation, preview and file operations work as in Files mode, so you can edit settings and scripts directly. Leaving the directory returns to Files mode.

## Shell Integration

`rufio --shell-init` prints a shell function named `rf`. Launch rufio with `rf` and press `T` to quit and move the shell to the directory you were viewing. `q` quits without moving.

```bash
# bash / zsh (~/.bashrc or ~/.zshrc)
eval "$(rufio --shell-init)"

# fish (~/.config/fish/config.fish)
rufio --shell-init fish | source
```

```powershell
# PowerShell ($PROFILE)
Invoke-Expression (& rufio --shell-init powershell | Out-String)
```

Without an argument, rufio prints PowerShell on Windows and your login shell (`bash`, `zsh` or `fish`) elsewhere. To avoid starting Ruby with every shell, append the output once instead, for example `rufio --shell-init >> ~/.bashrc`.

## Configuration

```
~/.config/rufio/
├── config.rb          # Main settings (Ruby constants)
├── script_paths.yml   # Script directories
├── bookmarks.yml      # Bookmarks
├── commands.rb        # DSL commands
├── scripts/           # Your scripts
└── logs/              # Execution logs
```

### config.rb

```ruby
# ~/.config/rufio/config.rb

# 'en' or 'ja' (the RUFIO_LANG environment variable also works)
LANGUAGE = 'ja'

# Colors (HSL)
COLORS = {
  directory: { hsl: [220, 80, 60] },
  file: { hsl: [0, 0, 90] },
  executable: { hsl: [120, 70, 50] },
  selected: { hsl: [50, 90, 70] },
  preview: { hsl: [180, 60, 65] }
}.freeze

# Change keys by action name. Each value is a single key.
KEYBINDS = {
  bottom: 'G',
  global_search: 'S'
}.freeze

# Applications used by `o`, by extension
APPLICATIONS = {
  %w[txt md rb py js json yml] => 'code',
  :default => 'open'
}.freeze

# Extensions (and /names of directories or files) excluded from the / search
SEARCH_EXCLUDED_EXTENSIONS = %w[.log /node_modules].freeze
```

The older name `GLOBAL_SEARCH_EXCLUDED_EXTENSIONS` is still read if `SEARCH_EXCLUDED_EXTENSIONS` is not set.

Action names for `KEYBINDS`:

| Group | Actions (default key) |
|-------|-----------------------|
| Navigation | `move_up` (k), `move_down` (j), `navigate_parent` (h), `navigate_enter` (l), `top` (g), `bottom` (}), `refresh` (R) |
| Files | `open_file` (o), `preview` (P), `rename` (r), `delete` (d), `create_file` (a), `create_dir` (A), `move_selected` (m), `copy_selected` (c), `delete_selected` (x), `open_explorer` (e) |
| Selection and search | `select` (Space), `filter` (f), `search` (/) |
| Bookmarks | `add_bookmark` (b), `bookmark_menu` (B), `zoxide` (z), `start_dir` (0) |
| Modes | `job_mode` (J), `config_mode` (C), `help` (?), `log_viewer` (L), `command_mode` (:), `quit` (q), `quit_cd` (T) |

The former names `fzf_search`, `fzf_search_alt`, `file_search`, `file_search_alt`, `rga_search` and `global_search` are all accepted as aliases of `search`.

### script_paths.yml and bookmarks.yml

```yaml
# ~/.config/rufio/script_paths.yml
- ~/.config/rufio/scripts
- ~/bin
```

```yaml
# ~/.config/rufio/bookmarks.yml
- path: ~/Documents
  name: Documents
- path: ~/projects
  name: Projects
```

### Project Settings

Place `rufio.yml` in a project root to add script paths for that project:

```yaml
# ./rufio.yml
script_paths:
  - ./scripts
  - ./bin
```

## External Tools

All tools are optional. Without them, rufio disables the feature or falls back to built-in behavior. Run `rufio -c` to check what is detected.

| Tool | Used for | Key |
|------|----------|-----|
| zoxide | Directory history | `z` |
| bat | Syntax highlighting in the preview | — |

```bash
# macOS
brew install bat zoxide

# Ubuntu/Debian
apt install bat zoxide
```

## Command-line Options

```bash
rufio [DIRECTORY]          # Start in DIRECTORY (default: current directory)
rufio -c                   # Check dependencies (--check-health)
rufio --shell-init [SHELL] # Print the rf shell function
rufio --yjit               # Enable YJIT (Ruby 3.1+)
rufio --zjit               # Enable ZJIT (Ruby 3.4+)
rufio --native             # Experimental native directory scanner
rufio --test               # Show an FPS counter
rufio -h                   # Help
```

## Native Engine

The gem bundles a Zig library for macOS (arm64/x86_64), Linux (x86_64/aarch64, glibc 2.17+ or musl) and Windows (x64/arm64). Other platforms use the Ruby implementation automatically.

- **Content search**: parallel scanning with an in-memory file cache. Repeated searches are about 10x faster than `rg`. Queries with non-ASCII cased letters use the Ruby search. Set `RUFIO_NATIVE_SEARCH=0` to disable it.
- **ZIP**: decompresses entries and compresses files of 1 MiB or more in parallel (about 4.6x faster to compress and 3.2x faster to extract than Ruby on 8 × 64 MB files with 4 CPUs). Archive validation always stays in Ruby. Set `RUFIO_NATIVE_ZIP=0` to disable it.

To rebuild the bundled binaries (requires Zig 0.17):

```bash
bundle exec rake native:build   # all platforms
bundle exec rake native:check   # verify bundled binaries
```
