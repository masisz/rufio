# Changelog - v0.31.0

## 🚀 New Features

### Experimental Native Scanner Implementation

Added high-performance directory scanning with Rust/Go implementations. By default, uses stable Ruby implementation with optional native implementations available via command-line options.

#### Implementation Languages
- **Rust implementation** (`lib_rust/scanner/`): Fastest, memory-safe
- **Go implementation** (`lib_go/scanner/`): Fast, excellent concurrency
- **Ruby implementation** (default): Stable, no dependencies

#### NativeScanner Abstraction Layer
- `lib/rufio/native_scanner.rb`: Unified interface independent of implementation
- Automatic fallback (falls back to Ruby if native implementation unavailable)

#### Launch Options
```bash
# Default (Ruby implementation)
rufio

# Enable native implementation (auto-detect: Rust > Go > Ruby)
rufio --native
rufio --native=auto

# Force Rust implementation
rufio --native=rust

# Force Go implementation
rufio --native=go

# Environment variable control
RUFIO_NATIVE=rust rufio
```

#### Priority
- **Default**: Ruby (stability focused)
- **`--native=auto`**: Rust > Go > Ruby
- **`--native=rust`**: Rust (fallback to Ruby if unavailable)
- **`--native=go`**: Go (fallback to Ruby if unavailable)

## 🔧 Improvements

### GitHub Actions CI/CD
- **Build**: Automatically build native libraries on 3 OSes (Linux, macOS, Windows)
- **Test**: Run tests on all platforms (both Ruby fallback and native implementations)
- **Release**: Auto-build and publish gem on tag push, attach binaries

### Development Environment
- `.gitignore`: Ignore build artifacts (`target/`, `*.dylib`, `*.so`, `*.dll`, etc.)
- gemspec: Configure to include native libraries in gem (optional)

### Command-Line Argument Processing
- Added `--native` option
- Improved argument parser (accurate path and option discrimination)
- Added native scanner description to `--help`

## 📦 Dependencies

### Ruby Dependencies (unchanged)
- io-console ~> 0.6
- pastel ~> 0.8
- tty-cursor ~> 0.7
- tty-screen ~> 0.8
- ffi (only when using native scanner)

### Build-time Dependencies (optional)
- **Rust**: cargo, rustc (to build Rust implementation)
- **Go**: go 1.21+ (to build Go implementation)

## 🧪 Tests

Added new tests:
- `test/test_rust_scanner.rb`: Rust scanner tests
- `test/test_go_scanner.rb`: Go scanner tests
- `test/test_native_scanner.rb`: NativeScanner abstraction layer tests
  - Verify default mode is Ruby
  - Mode switching tests
  - Auto-detection tests
  - Fallback behavior tests

All tests passing: 279+ runs, 1299+ assertions, 0 failures, 0 errors

## 📝 Documentation

- README.md: Added launch options documentation
- Help message: Detailed `--native` option description

## 🔒 Compatibility

- **Backward compatibility**: Fully maintained (default is Ruby implementation)
- **Native libraries**: Optional (works without them)
- **Platforms**: Linux, macOS, Windows supported

## 📌 Notes

### Experimental Feature
Rust/Go implementations are experimental:
- Not used by default (requires `--native` option)
- Thorough testing recommended for production use
- Use default Ruby implementation if issues occur

### Build Instructions

#### Rust Implementation
```bash
cd lib_rust/scanner
cargo build --release
make install
```

#### Go Implementation
```bash
cd lib_go/scanner
make install
```

## 🙏 Acknowledgments

Native Rust/Go implementations enable faster scanning of large directories. We welcome your feedback.

---

Release Date: 2026-01-01
