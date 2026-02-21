# CHANGELOG v0.80.0

## Overview

Adds syntax highlighting to the file preview pane. When `bat` is installed, code files
are displayed with full ANSI color highlighting. Environments without `bat` fall back
silently to plain text display.

Also fixes **cursor flickering** and **navigation lag** that occurred when browsing
source code directories with highlighting active.

---

## New Features

### Syntax Highlighting (via `bat`)

The preview pane now renders code files with syntax highlighting using `bat`'s ANSI
color output.

**Supported languages:**

| Language | Extensions |
|----------|------------|
| Ruby | `.rb` |
| Python | `.py` |
| JavaScript | `.js`, `.mjs` |
| TypeScript | `.ts` |
| HTML | `.html`, `.htm` |
| CSS | `.css` |
| JSON | `.json` |
| YAML | `.yml`, `.yaml` |
| Markdown | `.md`, `.markdown` |
| Go | `.go` |
| Rust | `.rs` |
| Shell | `.sh`, `.bash`, `.zsh` |
| TOML | `.toml` |
| SQL | `.sql` |
| C | `.c`, `.h` |
| C++ | `.cpp`, `.cc`, `.cxx`, `.hpp` |
| Java | `.java` |
| Dockerfile | `Dockerfile`, `Dockerfile.*` |
| Makefile | `Makefile`, `GNUmakefile` |

**Behavior:**
- Graceful degradation — plain text display when `bat` is not installed
- Non-UTF-8 files (e.g. Shift_JIS) skip highlighting automatically
- mtime-based cache: second visit to the same file is instant (0 ms)
- Run `rufio -c` to verify `bat` is detected by the health checker

**Installation:**
```bash
# macOS
brew install bat

# Ubuntu/Debian
apt install bat
```

---

## Bug Fixes

### Fix 1: Cursor Flickering (Renderer Atomic Output)

**Symptom:** The preview pane flickered briefly when moving the cursor in source
code directories.

**Root cause:** `Renderer#render` called `print` once per dirty row. With
`STDOUT sync=true`, each `print` flushes immediately, so intermediate states
(highlighted color removed, new color not yet drawn) were visible in the terminal.

**Fix:** All dirty row output is now accumulated into a single string buffer, then
written with one `write` + `flush` call — guaranteeing an atomic terminal update.

```
Before: print row0 → flush → print row1 → flush → ...  (intermediate states visible)
After:  buf = row0 + row1 + ...  →  write(buf) + flush  (single atomic update)
```

### Fix 2: Navigation Lag (Async bat Execution)

**Symptom:** Moving the cursor to a new file in a source directory caused 10–30 ms
of lag, making navigation feel sluggish.

**Root cause:** `SyntaxHighlighter#highlight` called `IO.popen(['bat', ...])` synchronously
inside the main loop. The bat process startup cost blocked the frame on every new file visit.

**Fix:** Added `highlight_async` which runs `bat` in a background Thread.

- The frame immediately after moving to a new file displays plain text (instant fallback)
- When the background thread completes, it sets `@highlight_updated = true`
- The main loop detects the flag and triggers a re-render with highlighting
- A pending guard prevents duplicate threads for the same file path
- A `Mutex` protects all cache reads/writes for thread safety

---

## Technical Details

### New Files

| File | Description |
|------|-------------|
| `lib/rufio/ansi_line_parser.rb` | Parses ANSI SGR escape sequences into token arrays. Full-width character-aware wrapping |
| `lib/rufio/syntax_highlighter.rb` | Wraps the `bat` command. mtime cache, async execution, Mutex protection |
| `test/test_ansi_line_parser.rb` | Unit tests for AnsiLineParser (25 tests) |
| `test/test_syntax_highlighter.rb` | Unit tests for SyntaxHighlighter (16 tests) |

### Modified Files

| File | Change |
|------|--------|
| `lib/rufio/renderer.rb` | Per-line `print` → single `write(buf)` + `flush` |
| `lib/rufio/terminal_ui.rb` | Added `@syntax_highlighter`, highlighting branch in `draw_file_preview_to_buffer`, `@highlight_updated` check in main loop |
| `lib/rufio/file_preview.rb` | Extended `determine_file_type` with Go, Rust, Shell, TOML, SQL, C, C++, Java, Dockerfile, Makefile |
| `lib/rufio/health_checker.rb` | Added `check_bat` method |
| `lib/rufio/config.rb` | Added `health.bat` message key (EN + JA) |
| `lib/rufio.rb` | Added `require` for `ansi_line_parser` and `syntax_highlighter` |
| `test/test_renderer.rb` | Added `OutputSpy` helper, 2 new atomic output tests |

### Architecture

```
bat (external process)
    ↓  IO.popen — background Thread
SyntaxHighlighter#highlight_async
    ↓  callback on completion
@preview_cache[path][:highlighted] = lines   # store ANSI line array
@highlight_updated = true                     # notify main loop
    ↓  next frame
AnsiLineParser.parse(line)                   # ANSI → token array
AnsiLineParser.wrap(tokens, width)           # full-width-aware wrapping
draw_highlighted_line_to_buffer(screen, ...) # per-char fg: color drawing
```

### Preview Cache Structure

```ruby
@preview_cache[file_path] = {
  content:             Array<String>,                # plain text lines
  preview_data:        Hash,                         # type, encoding, etc.
  highlighted:         nil | false | Array<String>,
  #                    nil   = not yet requested
  #                    false = requested, awaiting background result
  #                    Array = ANSI lines ready to render
  wrapped:             Hash,                         # width => wrapped plain lines
  highlighted_wrapped: Hash                          # width => wrapped token arrays
}
```

---

## Tests

All tests pass (pre-existing TestUISnapshot / TestBufferParity snapshot mismatches excluded):

| Test file | Tests | Status |
|-----------|-------|--------|
| `test_ansi_line_parser.rb` | 25 | new |
| `test_syntax_highlighter.rb` | 16 (9 existing + 7 new) | pass |
| `test_renderer.rb` | 12 (10 existing + 2 new) | pass |

**34 new tests** added in this release.

---

## Dependencies

### New Optional External Tool

| Tool | Purpose | Install |
|------|---------|---------|
| `bat` | Syntax highlighting | `brew install bat` / `apt install bat` |

rufio works normally without `bat` — plain text preview is always available as a fallback.

---

## Health Check

Use `rufio -c` to verify `bat` installation:

```
rufio Health Check
  ✓ bat (syntax highlight): bat 0.25.0 (2024-...)
  ✗ bat (syntax highlight): not found
      brew install bat   # optional: enables syntax highlighting
```
