# Makefile for Zig native library (Ruby ABI 非依存・Fiddle 経由でロード)
#
#   make          現在の環境向けにビルド
#   make install  現在の環境向けだけを Gem 同梱と同じ設定でビルドして lib/rufio/native/<platform>/ に配置
#   make dist     Gem 同梱用に全プラットフォームをクロスコンパイル
#   make test     検索エンジンの単体テスト
#   make sync-nvim 共通コア (search/os/fuzzy とテスト) を usurai.nvim に同期してビルド

ZIG := zig
RUBY := ruby

# コンパイルフラグ（外部ファイル解析の境界・オーバーフロー検証を保つため ReleaseSafe）
ZIG_FLAGS := -O ReleaseSafe -dynamic -lc

# ターゲット
TARGET := librufio_zig.dylib
BENCH := rufio_search
SRC := src/main.zig
IMAGE_SOURCES := src/image.zig src/image_png.zig src/image_jpeg.zig src/image_bmp.zig src/image_resize.zig
SOURCES := src/main.zig src/search.zig src/os.zig src/zip.zig src/fuzzy.zig $(IMAGE_SOURCES)
SHARED_SOURCES := src/search.zig src/os.zig src/search_test.zig src/fuzzy.zig src/fuzzy_test.zig
NVIM_ZIG_DIR ?= ../../../usurai.nvim/zig
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
	$(ZIG) test src/fuzzy_test.zig
	$(ZIG) test src/image_test.zig -lc

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
		rm -f $(NATIVE_DIR)/$$dir/$$file && cp $(BUILD_DIR)/$$dir/$$file $(NATIVE_DIR)/$$dir/$$file || exit 1; \
	done

clean:
	rm -rf $(TARGET) $(BENCH) *.o $(BUILD_DIR)

# 現在の環境のプラットフォーム名は Ruby 側の判定（NativeScannerZigFFI.platform_dir）に合わせ、
# Gem 同梱と同じ設定でビルドする
install:
	@platform=$$($(RUBY) -I../../lib -rrufio/native_scanner -rrufio/native_scanner_zig -e 'print Rufio::NativeScannerZigFFI.platform_dir.to_s' 2>/dev/null); \
	if [ -z "$$platform" ]; then echo "unsupported platform"; exit 1; fi; \
	$(MAKE) --no-print-directory dist ONLY=$$platform

# 共通の検索・ファジーコアを usurai.nvim に同期してテスト・ビルドする
sync-nvim: $(SHARED_SOURCES)
	@if [ ! -d "$(NVIM_ZIG_DIR)/src" ]; then \
		echo "usurai.nvim Zig directory not found: $(NVIM_ZIG_DIR)/src"; \
		exit 1; \
	fi
	cp $(SHARED_SOURCES) "$(NVIM_ZIG_DIR)/src/"
	cd "$(NVIM_ZIG_DIR)" && $(ZIG) build test && $(ZIG) build -Doptimize=ReleaseFast
	@echo "==> Synced $(SHARED_SOURCES) to $(NVIM_ZIG_DIR)/src and rebuilt librufio_zig"

.PHONY: all clean install test bench dist sync-nvim
