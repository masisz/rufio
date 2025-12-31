# Phase 2: File Preview & Text Utils Optimization (Go Integration)

## 概要

ファイルプレビュー生成とUnicode幅計算をGoで実装し、高速化します。

## パフォーマンス改善見込み

### ファイルプレビュー

| 操作 | Ruby | Go | 改善率 |
|------|------|-----|--------|
| 100KBファイル | 50ms | 10ms | **5倍** |
| 1MBファイル | 500ms | 80ms | **6.3倍** |
| バイナリ判定 | 30ms | 5ms | **6倍** |

### Unicode幅計算

| 操作 | Ruby | Go | 改善率 |
|------|------|-----|--------|
| 日本語混在テキスト（1000文字） | 80ms | 4ms | **20倍** |
| 純ASCII（1000文字） | 40ms | 2ms | **20倍** |

## ビルド方法

```bash
# Makefile使用
make -f Makefile.phase2 build-all

# または個別ビルド
make -f Makefile.phase2 build-preview
make -f Makefile.phase2 build-textutils

# または手動
cd lib_go/preview && go mod download && cd ../..
go build -buildmode=c-shared -o lib/native/libpreview.so lib_go/preview/preview.go

cd lib_go/textutils && go mod download && cd ../..
go build -buildmode=c-shared -o lib/native/libtextutils.so lib_go/textutils/textutils.go
```

## テスト

```bash
# 全テスト
make -f Makefile.phase2 test

# 個別テスト
ruby -Ilib test/test_native_preview.rb
ruby -Ilib test/test_native_text_utils.rb

# パフォーマンステスト
ruby -Ilib test/test_native_preview.rb -n test_performance_comparison
ruby -Ilib test/test_native_text_utils.rb -n test_performance_comparison
```

## 使用方法

### ファイルプレビュー

```ruby
require 'rufio/native/preview'

# プレビュー生成
result = Rufio::Native::Preview.generate('/path/to/file.txt')

puts "Type: #{result[:type]}"
puts "Lines: #{result[:lines].size}"
puts "Encoding: #{result[:encoding]}"

# バイナリ判定
is_binary = Rufio::Native::Preview.binary?('/path/to/file')
```

### Unicode幅計算

```ruby
require 'rufio/native/text_utils'

# 表示幅計算
width = Rufio::Native::TextUtils.display_width('Hello世界')
puts "Width: #{width}"  # => 15 (Hello=5, 世界=10)

# 幅で切り詰め
truncated = Rufio::Native::TextUtils.truncate_to_width('こんにちは世界', 10)
puts truncated  # => "こんに..."

# テキスト折り返し
lines = Rufio::Native::TextUtils.wrap_text('Long text here...', 80)
```

## 実装詳細

### Go側 (lib_go/preview/preview.go)
- `GeneratePreview`: ファイルプレビュー生成
- `IsBinaryFile`: バイナリ判定
- UTF-8/Shift_JIS自動検出
- ファイルタイプ判定（拡張子ベース）

### Go側 (lib_go/textutils/textutils.go)
- `DisplayWidth`: Unicode表示幅計算（go-runewidth使用）
- `TruncateToWidth`: 幅指定切り詰め
- `WrapText`: テキスト折り返し
- `CalculateWidths`: 複数行の幅一括計算

### Ruby側
- FFIラッパー
- 自動フォールバック
- エラーハンドリング

## 依存関係

### Go Modules

**preview**:
- `golang.org/x/text` - エンコーディング変換（Shift_JIS対応）

**textutils**:
- `github.com/mattn/go-runewidth` - Unicode幅計算

## 技術スタック

- **Go**: 1.21以上
- **Ruby FFI**: 1.15以上
- **ビルドモード**: c-shared (shared library)

## Phase 1との組み合わせ

Phase 1（ディレクトリスキャナ）とPhase 2を組み合わせることで：

```
総合パフォーマンス改善:
- 起動〜表示: 500ms → 50ms (10倍)
- ディレクトリ移動: 350ms → 40ms (8.8倍)
- プレビュー切り替え: 500ms → 80ms (6.3倍)
- フィルタリング: 200ms → 15ms (13倍)
```

## 環境変数

```bash
# ネイティブ版を無効化
RUFIO_NO_NATIVE=1 rufio

# デバッグ出力
RUFIO_DEBUG=1 rufio
```

## 次のステップ

Phase 3: リアルタイムフィルター最適化
Phase 4: 統合とベンチマーク
