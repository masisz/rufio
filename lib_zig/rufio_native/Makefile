# Makefile for Zig native library (Ruby ABI 非依存・Fiddle 経由でロード)
#
#   make          現在の環境向けにビルド
#   make install  現在の環境向けだけを Gem 同梱と同じ設定でビルドして lib/rufio/native/<platform>/ に配置
#   make dist     Gem 同梱用に全プラットフォームをクロスコンパイル
#   make test     検索エンジンの単体テスト

ZIG := zig
RUBY := ruby

# コンパイルフラグ
ZIG_FLAGS := -O ReleaseFast -dynamic -lc

# ターゲット
TARGET := librufio_zig.dylib
BENCH := rufio_search
SRC := src/main.zig
SOURCES := src/main.zig src/search.zig src/os.zig src/zip.zig
NATIVE_DIR := ../../lib/rufio/native
BUILD_DIR := zig-out/dist

# Gem 同梱プラットフォーム（ディレクトリ名:Zig ターゲット:ファイル名）
# Linux は glibc 2.17（CentOS 7 世代）以降で動くようにリンクする
PLATFORMS := \
	aarch64-macos:aarch64-macos.11.0:librufio_zig.dylib \
	x86_64-macos:x86_64-macos.10.15:librufio_zig.dylib \
	x86_64-linux-gnu:x86_64-linux-gnu.2.17:librufio_zig.so \
	aarch64-linux-gnu:aarch64-linux-gnu.2.17:librufio_zig.so \
	x86_64-linux-musl:x86_64-linux-musl:librufio_zig.so \
	aarch64-linux-musl:aarch64-linux-musl:librufio_zig.so \
	x86_64-windows:x86_64-windows-gnu:rufio_zig.dll \
	aarch64-windows:aarch64-windows-gnu:rufio_zig.dll

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(ZIG) build-lib $(SRC) $(ZIG_FLAGS) -femit-bin=$@

# ripgrep との比較用 CLI
$(BENCH): src/cli.zig src/search.zig src/os.zig
	$(ZIG) build-exe src/cli.zig -O ReleaseFast -lc -femit-bin=$@

test:
	$(ZIG) test src/search_test.zig

bench: $(BENCH)
	./bench.sh

# ONLY=<platform> で 1 つだけビルドする
dist: $(SOURCES)
	@for entry in $(PLATFORMS); do \
		dir=$${entry%%:*}; rest=$${entry#*:}; triple=$${rest%%:*}; file=$${rest#*:}; \
		if [ -n "$(ONLY)" ] && [ "$(ONLY)" != "$$dir" ]; then continue; fi; \
		echo "==> $$dir ($$triple)"; \
		mkdir -p $(BUILD_DIR)/$$dir $(NATIVE_DIR)/$$dir || exit 1; \
		$(ZIG) build-lib $(SRC) -target $$triple $(ZIG_FLAGS) -fstrip \
			-femit-bin=$(BUILD_DIR)/$$dir/$$file || exit 1; \
		cp $(BUILD_DIR)/$$dir/$$file $(NATIVE_DIR)/$$dir/$$file || exit 1; \
	done

clean:
	rm -rf $(TARGET) $(BENCH) *.o $(BUILD_DIR)

# 現在の環境のプラットフォーム名は Ruby 側の判定（NativeScannerZigFFI.platform_dir）に合わせ、
# Gem 同梱と同じ設定でビルドする
install:
	@platform=$$($(RUBY) -I../../lib -rrufio/native_scanner -rrufio/native_scanner_zig -e 'print Rufio::NativeScannerZigFFI.platform_dir.to_s' 2>/dev/null); \
	if [ -z "$$platform" ]; then echo "unsupported platform"; exit 1; fi; \
	$(MAKE) --no-print-directory dist ONLY=$$platform

.PHONY: all clean install test bench dist
