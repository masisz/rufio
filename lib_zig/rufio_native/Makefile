# Makefile for Zig Ruby extension

RUBY := ruby
ZIG := zig

# Rubyの設定を取得
RUBY_INCLUDE := $(shell $(RUBY) -e "puts RbConfig::CONFIG['rubyhdrdir']")
RUBY_ARCH_INCLUDE := $(shell $(RUBY) -e "puts RbConfig::CONFIG['rubyarchhdrdir']")
RUBY_LIB_DIR := $(shell $(RUBY) -e "puts RbConfig::CONFIG['libdir']")
RUBY_VERSION := $(shell $(RUBY) -e "puts RbConfig::CONFIG['MAJOR'] + '.' + RbConfig::CONFIG['MINOR']")

# コンパイルフラグ
ZIG_FLAGS := -O ReleaseFast -dynamic -lc
ZIG_FLAGS += -I$(RUBY_INCLUDE)
ZIG_FLAGS += -I$(RUBY_ARCH_INCLUDE)
ZIG_FLAGS += -L$(RUBY_LIB_DIR)
ZIG_FLAGS += -lruby.$(RUBY_VERSION)

# ターゲット
TARGET := librufio_zig.dylib
SRC := src/main.zig

all: $(TARGET)

$(TARGET): $(SRC)
	$(ZIG) build-lib $(SRC) $(ZIG_FLAGS) -femit-bin=$@

clean:
	rm -f $(TARGET) *.o

install: $(TARGET)
	cp $(TARGET) ../../lib/rufio/native/rufio_zig.bundle

.PHONY: all clean install
