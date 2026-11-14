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
- [Global Search (G mode)](#global-search-g-mode)
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
| `ESC` | Back to the file list |

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
| `s` or `/` | Search file names with fzf |
| `F` | Search file contents with rga |
| `G` | Global search across all bookmarks (no external tools needed) |

## Global Search (G mode)

`G` searches recursively under every bookmarked directory. Add bookmarks with `b` first.

| Key | Action |
|-----|--------|
| Type | Literal, case-insensitive search |
| `Tab` | Switch between **File names** and **Content** |
| `Up` / `Down`, `Ctrl+J` / `Ctrl+K`, `Ctrl+N` / `Ctrl+P` | Select a result |
| `Enter` | Go to the file in Files mode |
| `Ctrl+U` | Clear the query |
| `ESC` | Return to the previous mode |

- Matches are highlighted. Content results show the file, line number and matching text.
- A yellow `Searching...` indicator animates while scanning and turns into a green `Search complete` when done.
- Inaccessible directories and directory symlinks are skipped. Plain text is read as UTF-8, and files with NUL bytes in the first 8 KB are treated as binary.

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
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.png .jpg .zip .tar.gz .log /.git /node_modules /.DS_Store].freeze
```

Extensions ignore case, the leading dot is optional, and the default `[]` excludes nothing. An entry starting with `/` is a name: a directory with that name is skipped with everything under it, and a file with exactly that name is skipped.

## Bookmarks and History

| Key | Action |
|-----|--------|
| `b` | Bookmark the current directory |
| `B` | Bookmark menu |
| `1`–`9` | Jump to bookmark 1–9 |
| `Tab` / `Shift+Tab` | Next / previous bookmark (Files and Config modes) |
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

# Extensions (and /names of directories or files) excluded from G mode search
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.log /node_modules].freeze
```

Action names for `KEYBINDS`:

| Group | Actions (default key) |
|-------|-----------------------|
| Navigation | `move_up` (k), `move_down` (j), `navigate_parent` (h), `navigate_enter` (l), `top` (g), `bottom` (}), `refresh` (R) |
| Files | `open_file` (o), `preview` (P), `rename` (r), `delete` (d), `create_file` (a), `create_dir` (A), `move_selected` (m), `copy_selected` (c), `delete_selected` (x), `open_explorer` (e) |
| Selection and search | `select` (Space), `filter` (f), `fzf_search` (s), `fzf_search_alt` (/), `rga_search` (F) |
| Bookmarks | `add_bookmark` (b), `bookmark_menu` (B), `zoxide` (z), `start_dir` (0) |
| Modes | `job_mode` (J), `global_search` (G), `config_mode` (C), `help` (?), `log_viewer` (L), `command_mode` (:), `quit` (q), `quit_cd` (T) |

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
| fzf | File name search | `s`, `/` |
| rga | File content search | `F` |
| zoxide | Directory history | `z` |
| bat | Syntax highlighting in the preview | — |

```bash
# macOS
brew install fzf bat rga zoxide

# Ubuntu/Debian
apt install fzf bat zoxide
# rga: https://github.com/phiresky/ripgrep-all
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

- **G mode content search**: parallel scanning with an in-memory file cache. Repeated searches are about 10x faster than `rg`. Queries with non-ASCII cased letters use the Ruby search. Set `RUFIO_NATIVE_SEARCH=0` to disable it.
- **ZIP**: decompresses entries and compresses files of 1 MiB or more in parallel (about 4.6x faster to compress and 3.2x faster to extract than Ruby on 8 × 64 MB files with 4 CPUs). Archive validation always stays in Ruby. Set `RUFIO_NATIVE_ZIP=0` to disable it.

To rebuild the bundled binaries (requires Zig 0.17):

```bash
bundle exec rake native:build   # all platforms
bundle exec rake native:check   # verify bundled binaries
```
