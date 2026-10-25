# rufio

**Runtime Unified Flow I/O Operator**

A terminal file manager that keeps your everyday script workflow close at hand.
Find files, run Ruby, Python, or PowerShell scripts in the current directory, and check jobs and logs.
Add your own actions in Ruby.

[日本語](./README_ja.md) | **English**

## What Makes rufio Different

rufio brings finding files, running scripts, and checking results together in one interface.

- **Run scripts where your files are**: Register your script directories, then press `:`, type `@` + part of a script name, press `Tab`, and hit `Enter`. Run Ruby, Python, or PowerShell scripts in the directory you are browsing
- **Follow jobs and execution logs**: Keep browsing while scripts run in the background. Press `J` to check jobs and `L` to view execution logs
- **Add your own actions in Ruby**: Define custom commands with a small Ruby DSL in `~/.config/rufio/commands.rb`. `~/.rufio/commands.rb` is also supported
- **Use installed tools without extra configuration**: Search file names with fzf, search contents with rga, highlight previews with bat, and navigate directory history with zoxide
- **Windows support**: Run PowerShell scripts with keyboard input handling adapted to Windows terminals
- **Trace behavior in the source**: The implementation is primarily Ruby, so you can inspect and change the parts you need. Security design is documented in [SECURITY.md](./SECURITY.md)

## Features

### For Script Workflows

- **Multi-language Script Support**: Ruby, Python, PowerShell
- **Script Path Management**: Register and manage multiple script directories
- **Command Completion**: Tab completion for scripts with `@` prefix
- **Job Management**: Run scripts/commands in the background
- **Execution Logs**: Automatically record all execution results

### As a File Manager

- **Vim-like Key Bindings**: Intuitive navigation
- **Real-time Preview**: Instantly display file contents with syntax highlighting (via `bat`)
- **Fast Search**: Integration with fzf/rga
- **Bookmarks**: Quick access to frequently used directories
- **zoxide Integration**: Smart directory history

### Cross-platform

- **macOS**: Native support
- **Linux**: Native support
- **Windows**: PowerShell script support

## Installation

```bash
gem install rufio
```

Or add to your Gemfile:

```ruby
gem 'rufio'
```

## Quick Start

### 1. Launch

```bash
rufio           # Launch in current directory
rufio /path/to  # Launch in specified directory
```

### 2. Register Script Path

1. Navigate to the directory where you want to place scripts
2. `B` → `2` to add to script path

### 3. Execute Script

1. Press `:` to enter command mode
2. Type `@` + part of the script name
3. Press `Tab` to complete
4. Press `Enter` to execute

## Key Bindings

### Basic Operations

| Key | Function |
|-----|----------|
| `j/k` | Move up/down |
| `h/l` | Parent/child directory |
| `g/}` | Top/bottom |
| `Enter` | Enter directory/open file |
| `q` | Quit |

### File Operations

| Key | Function |
|-----|----------|
| `Space` | Select/deselect |
| `o` | Open with external editor |
| `a/A` | Create file/directory |
| `r` | Rename |
| `d` | Delete |
| `m/c/x` | Move/copy/delete (selected) |

### Search & Filter

| Key | Function |
|-----|----------|
| `f` | Filter mode |
| `s` | Search files with fzf |
| `F` | Search file contents with rga |

### Navigation

| Key | Function |
|-----|----------|
| `b` | Add bookmark |
| `B` | Bookmark menu |
| `0` | Return to startup directory |
| `1-9` | Jump to bookmark |
| `Tab` | Cycle to next bookmark (Files mode only) |
| `z` | zoxide history |

### Tool Runtime

| Key | Function |
|-----|----------|
| `:` | Command mode |
| `G` | Search file names or contents across all bookmarked directories |
| `C` | Open ~/.config/rufio/ in Config mode (same controls as Files) |
| `J` | Job mode |
| `L` | View execution logs |
| `?` | Help |
| `Shift+Tab` | Switch mode (reverse) |

### Global Search (G mode)

Press `G` to search recursively across all bookmarked directories. `Tab`
switches between **File names** and **Content**. Type a literal string to
search (case insensitive); content results include the file, line number,
and matching text. Plain text is read as UTF-8; other unsupported files containing
NUL bytes in the first 8 KB are skipped as binary. Use Up/Down or Ctrl+N/P to select a
result, and press Enter to jump to that file in Files mode. `Ctrl+U` clears
the query; `Esc` cancels and returns to your previous view. Scanning runs in
the background and skips inaccessible directories and directory symlinks.
Add bookmarks with `b` before searching. G mode needs no external search tools.
While scanning, a yellow `Searching...` indicator animates even before matches
arrive. It turns green and displays `Search complete` when the scan finishes.

To exclude extensions from both file name and content searches, add this to
`~/.config/rufio/config.rb` and restart Rufio:

```ruby
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.png .jpg .zip .tar.gz .log].freeze
```

Extensions are case insensitive and the leading dot is optional. The default
is `[]` (no extension exclusions). Directory names are unaffected.

#### PDF, Excel and PowerPoint content search (v1.2.0)

Content mode also extracts text from documents using Ruby gems; Python,
Microsoft Office and external conversion tools are not required.

| File | Searchable content | Result location |
|------|--------------------|-----------------|
| `.pdf` | Extractable text | Page number |
| `.xlsx` | Cell text and values | Sheet name and cell address |
| `.pptx` | Text in slide shapes and tables | Slide number |

Search remains literal and case insensitive. Split text runs in a PowerPoint
paragraph are joined, and slides follow the presentation's display order.
Excel formulas use the values saved in the workbook; Rufio does not recalculate them.
Enter locates the original document in Files mode; it does not open Office at a cell or slide.

Extracted text is cached in memory across searches within the running app.
The cache keeps up to 64 documents and approximately 16 MiB of text and metadata;
larger extracted documents remain searchable without being cached. Updated or
replaced files are re-extracted. No document text cache is written to disk.

Extension exclusions apply to documents too. Damaged, unsupported or encrypted
documents may report errors while other files continue to be searched.
Scanned images need OCR, which is not included. Legacy `.xls`/`.ppt`, slide notes,
and text embedded only in images or charts are not supported by this implementation.
PDF text extraction depends on the document's font and character mappings.

### Config Mode (C)

Press `C` to open `~/.config/rufio/`, creating it if needed. Navigation, previews,
and file operations work as in Files mode. Browse settings and scripts directly;
leaving the config directory returns the mode display to Files.

## Command Mode

Press `:` to enter command mode and execute various commands.

### Script Execution

```
:@build           # @ prefix triggers script completion
:@deploy.rb       # Execute registered script
:@local.sh        # Scripts in current directory are also available
```

### Rake Task Execution

```
:rake:test        # Execute rake task
:rake:build       # Tab completion supported
```

Rakefile in the current directory is automatically parsed. Supports `Rakefile`, `rakefile`, `Rakefile.rb`.

### Shell Commands

```
:!git status      # ! prefix for shell commands
:!ls -la          # Execute in background
```

### Built-in Commands

```
:hello            # Greeting message
:stop             # Quit rufio
```

## Script Path

### What is Script Path?

A feature to register directories containing script files. Scripts in registered directories can be executed using the `@` prefix in command mode.

### Management

Press `B` → `3` to open the script path management menu:

- View registered paths
- `d`: Remove path
- `Enter`: Jump to directory
- `ESC`: Close menu

### Supported Scripts

| Extension | Language |
|-----------|----------|
| `.rb` | Ruby |
| `.py` | Python |
| `.sh` | Shell (bash/zsh) |
| `.js` | JavaScript (Node.js) |
| `.ts` | TypeScript (ts-node/deno) |
| `.pl` | Perl |
| `.ps1` | PowerShell |

## DSL Commands

Define custom commands in `~/.config/rufio/commands.rb`:

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

## Configuration

### Configuration File Structure

```
~/.config/rufio/
├── config.rb          # DSL-style main configuration
├── script_paths.yml   # Script directories (list format)
├── bookmarks.yml      # Bookmarks (list format)
├── commands.rb        # DSL command definitions
├── scripts/           # Script files
└── logs/              # Execution logs
```

### config.rb (DSL Configuration)

```ruby
# ~/.config/rufio/config.rb

# Language setting: 'en' or 'ja'
LANGUAGE = 'ja'

# Color settings (HSL format)
COLORS = {
  directory: { hsl: [220, 80, 60] },
  file: { hsl: [0, 0, 90] },
  executable: { hsl: [120, 70, 50] },
  selected: { hsl: [50, 90, 70] },
  preview: { hsl: [180, 60, 65] }
}.freeze

# Keybind settings
KEYBINDS = {
  quit: %w[q ESC],
  up: %w[k UP],
  down: %w[j DOWN]
}.freeze
```

### script_paths.yml

```yaml
# ~/.config/rufio/script_paths.yml
- ~/.config/rufio/scripts
- ~/bin
- ~/scripts
```

### bookmarks.yml

```yaml
# ~/.config/rufio/bookmarks.yml
- path: ~/Documents
  name: Documents
- path: ~/projects
  name: Projects
```

### Local Configuration

Place `rufio.yml` in your project root for project-specific script paths:

```yaml
# ./rufio.yml (project root)
script_paths:
  - ./scripts
  - ./bin
```

## External Tool Integration

rufio integrates with the following external tools to extend functionality.
All tools are **optional** — rufio works without them, falling back to built-in behavior.

| Tool | Purpose | Key | Required? |
|------|---------|-----|-----------|
| fzf | File name search | `s` | Optional |
| rga | File content search | `F` | Optional |
| zoxide | Directory history | `z` | Optional |
| bat | Syntax highlighting in preview | — | Optional |

### bat — Syntax Highlighting

When `bat` is installed, code files in the preview pane are displayed with full syntax
highlighting (Ruby, Python, Go, Rust, TypeScript, and 15+ more languages).

Highlighting is loaded asynchronously — navigation stays fast even on large source trees.

```bash
# macOS
brew install bat

# Ubuntu/Debian
apt install bat
```

Run `rufio -c` to verify bat is detected correctly.

### Installation (all tools)

```bash
# macOS
brew install fzf bat rga zoxide

# Ubuntu/Debian
apt install fzf bat zoxide
# rga requires separate installation: https://github.com/phiresky/ripgrep-all
```

## Advanced Features

### Native Scanner (Experimental)

Support for native implementation for fast directory scanning:

```bash
rufio --native        # Auto-detect
rufio --native=zig    # Zig implementation
```

### JIT Compiler

```bash
rufio --yjit   # Ruby 3.1+ YJIT
rufio --zjit   # Ruby 3.4+ ZJIT
```

### Health Check

```bash
rufio -c              # Check system dependencies
rufio --check-health  # Same as above
```

## Development

### Requirements

- Ruby 2.7.0 or later
- io-console, pastel, tty-cursor, tty-screen gems

### Running Development Version

```bash
git clone https://github.com/masisz/rufio
cd rufio
bundle install
./bin/rufio
```

### Testing

```bash
bundle exec rake test
```

## License

MIT License

## Contributing

Bug reports and feature requests are welcome at [GitHub Issues](https://github.com/masisz/rufio/issues).
Pull requests are also welcome!
