# Rufio ハイブリッド移行戦略（Ruby + Go）

## 🎯 戦略概要

**完全書き換えではなく、パフォーマンスクリティカルな部分のみGoで置き換え**

### メリット
- ✅ **低リスク**: 段階的な移行が可能
- ✅ **早期効果**: 数週間で体感できる改善
- ✅ **プラグインシステム維持**: Rubyの柔軟性を保持
- ✅ **学習コスト削減**: Go全体を学ぶ前に成果が出る
- ✅ **週末開発に最適**: 小さな単位で完結

---

## 📊 パフォーマンスボトルネック分析

### 現状の問題箇所（プロファイリング予測）

| 処理 | 推定コスト | 頻度 | 改善優先度 |
|------|-----------|------|-----------|
| **ディレクトリ走査** | 高 | 頻繁 | 🔴 最優先 |
| **ファイルプレビュー生成** | 中 | 頻繁 | 🟠 高 |
| **リアルタイムフィルタリング** | 中 | 頻繁 | 🟠 高 |
| **Unicode幅計算** | 低（累積大） | 超頻繁 | 🟡 中 |
| **ターミナルUI描画** | 低 | 超頻繁 | 🟢 低 |
| **プラグインロード** | 中 | 起動時のみ | 🟢 低 |

---

## 🔧 Ruby-Go 連携方法

### 方法1: FFI（Foreign Function Interface）- 推奨 ⭐⭐⭐⭐⭐

**概要**: Goでshared libraryを作成し、Rubyの`ffi` gemで呼び出し

#### メリット
- 型安全な連携
- パフォーマンスロスがほぼゼロ
- デバッグが容易

#### 実装例

**Go側（shared library）**
```go
// lib/go/scanner/scanner.go
package main

import "C"
import (
    "encoding/json"
    "io/fs"
    "os"
)

type Entry struct {
    Name  string `json:"name"`
    IsDir bool   `json:"is_dir"`
    Size  int64  `json:"size"`
    Mtime int64  `json:"mtime"`
}

//export ScanDirectory
func ScanDirectory(path *C.char) *C.char {
    entries, err := os.ReadDir(C.GoString(path))
    if err != nil {
        return C.CString(`{"error": "` + err.Error() + `"}`)
    }

    var result []Entry
    for _, entry := range entries {
        info, _ := entry.Info()
        result = append(result, Entry{
            Name:  entry.Name(),
            IsDir: entry.IsDir(),
            Size:  info.Size(),
            Mtime: info.ModTime().Unix(),
        })
    }

    jsonBytes, _ := json.Marshal(result)
    return C.CString(string(jsonBytes))
}

func main() {}
```

**ビルド**
```bash
# macOS/Linux
go build -buildmode=c-shared -o lib/native/libscanner.so lib/go/scanner/scanner.go

# Windows
go build -buildmode=c-shared -o lib/native/scanner.dll lib/go/scanner/scanner.go
```

**Ruby側（FFI呼び出し）**
```ruby
# lib/rufio/native/scanner.rb
require 'ffi'
require 'json'

module Rufio
  module Native
    module Scanner
      extend FFI::Library

      # プラットフォームごとにライブラリパスを切り替え
      lib_path = case RbConfig::CONFIG['host_os']
      when /darwin/
        File.expand_path('../../native/libscanner.dylib', __dir__)
      when /linux/
        File.expand_path('../../native/libscanner.so', __dir__)
      when /mswin|mingw/
        File.expand_path('../../native/scanner.dll', __dir__)
      end

      ffi_lib lib_path

      # Go関数をアタッチ
      attach_function :ScanDirectory, [:string], :string

      def self.scan(path)
        result_json = ScanDirectory(path)
        JSON.parse(result_json, symbolize_names: true)
      rescue => e
        { error: e.message }
      end
    end
  end
end
```

**使用例**
```ruby
# lib/rufio/directory_listing.rb
def load_entries
  if Rufio::Native::Scanner.available?
    # Go実装を使用（10倍高速）
    entries = Rufio::Native::Scanner.scan(@current_path)
    @entries = entries.map { |e|
      Entry.new(e[:name], e[:is_dir], e[:size], Time.at(e[:mtime]))
    }
  else
    # フォールバック: Ruby実装
    load_entries_ruby
  end
end
```

---

### 方法2: サブプロセス（シンプル） ⭐⭐⭐

**概要**: Goで小さなCLIツールを作り、Rubyから呼び出し

#### メリット
- 実装が超簡単
- デバッグしやすい
- クラッシュしても本体に影響なし

#### デメリット
- プロセス起動コストあり（10-20ms）
- 頻繁な呼び出しには不向き

#### 実装例

**Go CLI**
```go
// cmd/rufio-scanner/main.go
package main

import (
    "encoding/json"
    "fmt"
    "os"
)

func main() {
    if len(os.Args) < 2 {
        fmt.Fprintln(os.Stderr, "Usage: rufio-scanner <directory>")
        os.Exit(1)
    }

    entries, _ := os.ReadDir(os.Args[1])
    var result []map[string]interface{}

    for _, entry := range entries {
        info, _ := entry.Info()
        result = append(result, map[string]interface{}{
            "name":  entry.Name(),
            "is_dir": entry.IsDir(),
            "size":  info.Size(),
        })
    }

    json.NewEncoder(os.Stdout).Encode(result)
}
```

**Ruby側**
```ruby
def load_entries_fast
  scanner = File.expand_path('../../bin/rufio-scanner', __dir__)
  if File.exist?(scanner)
    json = `#{scanner} #{Shellwords.escape(@current_path)}`
    JSON.parse(json, symbolize_names: true)
  else
    load_entries_ruby # フォールバック
  end
end
```

---

## 🎯 段階的移行プラン

### Phase 1: ディレクトリスキャナ（週1-2）⭐⭐⭐⭐⭐

**対象**: `directory_listing.rb` の `load_entries`

**期待効果**
- 大量ファイル表示が **5-10倍高速**
- メモリ使用量削減

**実装難易度**: ⭐⭐（簡単）

**Go実装サイズ**: 約50-100行

**成果**:
```
10,000ファイルのディレクトリ
Ruby: 2秒 → Go: 0.2秒（10倍）
```

---

### Phase 2: ファイルプレビューエンジン（週3-5）⭐⭐⭐⭐

**対象**: `file_preview.rb` の `generate_preview`

**期待効果**
- 大きなファイルのプレビューが **3-5倍高速**
- エンコーディング処理の高速化

**実装難易度**: ⭐⭐⭐（中）

**Go実装サイズ**: 約150-200行

**Go側実装例**
```go
//export GeneratePreview
func GeneratePreview(path *C.char, maxLines C.int) *C.char {
    content, err := os.ReadFile(C.GoString(path))
    if err != nil {
        return C.CString("")
    }

    // バイナリ検出
    if isBinary(content) {
        return C.CString("[Binary file]")
    }

    lines := strings.Split(string(content), "\n")
    if len(lines) > int(maxLines) {
        lines = lines[:maxLines]
    }

    result := strings.Join(lines, "\n")
    return C.CString(result)
}

func isBinary(data []byte) bool {
    if len(data) == 0 {
        return false
    }
    sample := data
    if len(data) > 8000 {
        sample = data[:8000]
    }

    nonText := 0
    for _, b := range sample {
        if b < 32 && b != '\n' && b != '\r' && b != '\t' {
            nonText++
        }
    }
    return float64(nonText)/float64(len(sample)) > 0.3
}
```

---

### Phase 3: リアルタイムフィルター（週6-8）⭐⭐⭐⭐

**対象**: `filter_manager.rb` の `apply_filter`

**期待効果**
- キー入力の反応が **超高速**（遅延1ms以下）
- 1,000+ファイルでもスムーズ

**実装難易度**: ⭐⭐⭐（中）

**Go実装サイズ**: 約100-150行

**Go側実装例**
```go
//export FilterEntries
func FilterEntries(entriesJSON *C.char, pattern *C.char) *C.char {
    var entries []string
    json.Unmarshal([]byte(C.GoString(entriesJSON)), &entries)

    patternLower := strings.ToLower(C.GoString(pattern))
    var filtered []string

    for _, entry := range entries {
        if strings.Contains(strings.ToLower(entry), patternLower) {
            filtered = append(filtered, entry)
        }
    }

    result, _ := json.Marshal(filtered)
    return C.CString(string(result))
}
```

---

### Phase 4: Unicode幅計算（週9-10）⭐⭐⭐

**対象**: `text_utils.rb` の `display_width`、`truncate_with_width`

**期待効果**
- 日本語混じりテキストの処理が **10-20倍高速**
- 描画のちらつき削減

**実装難易度**: ⭐⭐（簡単）

**Go実装サイズ**: 約50行

**Go側実装例**
```go
import "github.com/mattn/go-runewidth"

//export DisplayWidth
func DisplayWidth(text *C.char) C.int {
    return C.int(runewidth.StringWidth(C.GoString(text)))
}

//export TruncateWithWidth
func TruncateWithWidth(text *C.char, maxWidth C.int) *C.char {
    return C.CString(runewidth.Truncate(C.GoString(text), int(maxWidth), "..."))
}
```

---

## 📊 ハイブリッド構成の最終形

### アーキテクチャ

```
rufio/
├── lib/
│   ├── rufio/              # Ruby コア（UI、プラグイン等）
│   │   ├── terminal_ui.rb
│   │   ├── keybind_handler.rb
│   │   ├── plugin_manager.rb  # Rubyのまま維持
│   │   └── native/
│   │       ├── scanner.rb      # FFI wrapper
│   │       ├── preview.rb      # FFI wrapper
│   │       └── text_utils.rb   # FFI wrapper
│   └── native/             # Go shared libraries
│       ├── libscanner.so
│       ├── libpreview.so
│       └── libtextutils.so
└── lib_go/                 # Go ソースコード
    ├── scanner/
    │   └── scanner.go
    ├── preview/
    │   └── preview.go
    └── textutils/
        └── textutils.go
```

### コンポーネント分担

| コンポーネント | 言語 | 理由 |
|--------------|------|------|
| ターミナルUI | Ruby | 柔軟性が重要、性能は十分 |
| キーバインド処理 | Ruby | ロジックが複雑、変更頻度高 |
| **ディレクトリスキャン** | **Go** | **I/O集約、高速化必須** |
| **ファイルプレビュー** | **Go** | **大ファイル処理、高速化必須** |
| **フィルタリング** | **Go** | **リアルタイム性能重要** |
| **Unicode幅計算** | **Go** | **頻繁に呼ばれる、累積コスト大** |
| プラグインシステム | Ruby | 動的ロード、Rubyの強み |
| 設定システム | Ruby | DSL、柔軟性重要 |
| ブックマーク | Ruby | 単純、性能問題なし |
| 外部ツール統合 | Ruby | シェル操作、Rubyが得意 |

---

## 🚀 パフォーマンス改善見込み

### Phase 1完了時点（ディレクトリスキャナのみ）

| 操作 | Before | After | 改善率 |
|------|--------|-------|--------|
| 起動時間 | 500ms | 450ms | 1.1倍 |
| 1,000ファイル表示 | 200ms | 30ms | **6.7倍** |
| 10,000ファイル表示 | 2秒 | 0.2秒 | **10倍** |
| ディレクトリ移動 | 150ms | 20ms | **7.5倍** |

**体感**: 大きなディレクトリで劇的に改善 🚀

---

### Phase 2完了時点（+プレビュー）

| 操作 | Before | After | 改善率 |
|------|--------|-------|--------|
| 100KBファイルプレビュー | 50ms | 10ms | **5倍** |
| 1MBファイルプレビュー | 500ms | 80ms | **6.3倍** |
| バイナリ判定 | 30ms | 5ms | **6倍** |

**体感**: ファイル切り替えがヌルヌル 🎨

---

### Phase 3完了時点（+フィルター）

| 操作 | Before | After | 改善率 |
|------|--------|-------|--------|
| フィルター入力反応（1,000ファイル） | 20ms | 1ms | **20倍** |
| フィルター入力反応（10,000ファイル） | 200ms | 10ms | **20倍** |

**体感**: キー入力が即座に反映、遅延ゼロ ⚡

---

### Phase 4完了時点（+Unicode幅計算）

| 操作 | Before | After | 改善率 |
|------|--------|-------|--------|
| 日本語ファイル名1,000個表示 | 150ms | 80ms | **1.9倍** |
| 全体的な描画 | 100ms | 70ms | **1.4倍** |

**体感**: 日本語環境で全体的に軽快 🇯🇵

---

### 最終的な総合パフォーマンス

| 指標 | 完全Ruby | ハイブリッド | 完全Go | ハイブリッドの達成率 |
|------|---------|------------|--------|-------------------|
| 起動時間 | 500ms | 400ms | 10ms | **20%達成** |
| メモリ | 50MB | 35MB | 15MB | **43%達成** |
| 大量ファイル表示 | 2秒 | 0.2秒 | 0.15秒 | **90%達成** |
| プレビュー生成 | 500ms | 80ms | 50ms | **93%達成** |
| フィルター反応 | 200ms | 10ms | 5ms | **95%達成** |

**結論**: ハイブリッドで完全Go書き換えの**80-95%のパフォーマンス**を達成可能！

---

## ⏱️ 開発スケジュール比較

### ハイブリッド移行（推奨）

| Phase | 期間 | 累積 | 体感改善 |
|-------|------|------|---------|
| Phase 1: スキャナ | 2週 | 2週 | ⭐⭐⭐⭐⭐ すぐ効果 |
| Phase 2: プレビュー | 3週 | 5週 | ⭐⭐⭐⭐ さらに快適 |
| Phase 3: フィルター | 3週 | 8週 | ⭐⭐⭐⭐⭐ 完璧に近い |
| Phase 4: Unicode | 2週 | 10週 | ⭐⭐⭐ 仕上げ |
| **合計** | **10週** | **2.5ヶ月** | **十分満足** |

### 完全Go書き換え

| Phase | 期間 | 累積 | 体感改善 |
|-------|------|------|---------|
| 学習 | 2週 | 2週 | なし |
| プロトタイプ | 3週 | 5週 | なし |
| コア実装 | 6週 | 11週 | なし |
| 統合 | 4週 | 15週 | なし |
| プラグイン | 4週 | 19週 | なし |
| 完成 | 2週 | 21週 | ⭐⭐⭐⭐⭐ 完成時のみ |
| **合計** | **21週** | **5ヶ月** | **最後まで効果なし** |

**ハイブリッドの優位性**:
- **2週間で効果が出る**（vs 5ヶ月後）
- **期間半分**（10週 vs 21週）
- **リスク低い**（段階的、いつでも中断可）

---

## 💰 コスト・リスク分析

### ハイブリッド移行

| 項目 | 評価 | 詳細 |
|------|------|------|
| 初期学習コスト | 🟢 低 | Go基礎 + FFIのみ |
| 実装コスト | 🟢 低 | Phase 1は50-100行 |
| メンテナンスコスト | 🟡 中 | 2言語管理 |
| 失敗リスク | 🟢 低 | いつでも中断可 |
| ビルド複雑さ | 🟡 中 | Go shared library追加 |
| 配布複雑さ | 🟡 中 | バイナリ同梱必要 |
| **総合リスク** | **🟢 低** | **段階的で安全** |

### 完全Go書き換え

| 項目 | 評価 | 詳細 |
|------|------|------|
| 初期学習コスト | 🟡 中 | Go全般 + TUIフレームワーク |
| 実装コスト | 🔴 高 | 10,000行書き換え |
| メンテナンスコスト | 🟢 低 | 単一言語 |
| 失敗リスク | 🔴 高 | オールオアナッシング |
| ビルド複雑さ | 🟢 低 | `go build`のみ |
| 配布複雑さ | 🟢 低 | シングルバイナリ |
| **総合リスク** | **🟡 中** | **成功時は最高、失敗リスクあり** |

---

## 🛠️ 実装ガイド（Phase 1: ディレクトリスキャナ）

### ステップ1: プロジェクト構造準備（30分）

```bash
mkdir -p lib_go/scanner
mkdir -p lib/native
mkdir -p lib/rufio/native
```

**Gemfile に追加**
```ruby
gem 'ffi', '~> 1.15'
```

---

### ステップ2: Go実装（1-2時間）

**lib_go/scanner/scanner.go**
```go
package main

import "C"
import (
    "encoding/json"
    "os"
    "time"
)

type Entry struct {
    Name  string `json:"name"`
    IsDir bool   `json:"is_dir"`
    Size  int64  `json:"size"`
    Mtime int64  `json:"mtime"`
}

//export ScanDirectory
func ScanDirectory(path *C.char) *C.char {
    entries, err := os.ReadDir(C.GoString(path))
    if err != nil {
        errorJSON := `{"error":"` + err.Error() + `"}`
        return C.CString(errorJSON)
    }

    var result []Entry
    for _, entry := range entries {
        info, err := entry.Info()
        if err != nil {
            continue
        }
        result = append(result, Entry{
            Name:  entry.Name(),
            IsDir: entry.IsDir(),
            Size:  info.Size(),
            Mtime: info.ModTime().Unix(),
        })
    }

    jsonBytes, _ := json.Marshal(result)
    return C.CString(string(jsonBytes))
}

//export FreeCString
func FreeCString(ptr *C.char) {
    C.free(unsafe.Pointer(ptr))
}

func main() {}
```

**ビルドスクリプト（Rakefile）**
```ruby
task :build_native do
  case RbConfig::CONFIG['host_os']
  when /darwin/
    ext = 'dylib'
  when /linux/
    ext = 'so'
  when /mswin|mingw/
    ext = 'dll'
  end

  sh "go build -buildmode=c-shared -o lib/native/libscanner.#{ext} lib_go/scanner/scanner.go"
end
```

---

### ステップ3: Ruby FFI ラッパー（1時間）

**lib/rufio/native/scanner.rb**
```ruby
require 'ffi'
require 'json'

module Rufio
  module Native
    module Scanner
      extend FFI::Library

      def self.library_path
        ext = case RbConfig::CONFIG['host_os']
        when /darwin/ then 'dylib'
        when /linux/  then 'so'
        when /mswin|mingw/ then 'dll'
        end
        File.expand_path("../../native/libscanner.#{ext}", __dir__)
      end

      def self.available?
        @available ||= File.exist?(library_path)
      end

      if available?
        ffi_lib library_path
        attach_function :ScanDirectory, [:string], :string
        attach_function :FreeCString, [:pointer], :void
      end

      def self.scan(path)
        return nil unless available?

        result_json = ScanDirectory(path)
        data = JSON.parse(result_json, symbolize_names: true)

        # メモリ解放（オプション、GCに任せても可）
        # FreeCString(result_json)

        data
      rescue JSON::ParserError, FFI::NotFoundError => e
        { error: e.message }
      end
    end
  end
end
```

---

### ステップ4: 既存コード統合（30分）

**lib/rufio/directory_listing.rb**
```ruby
def load_entries
  # Go実装を試みる
  if Rufio::Native::Scanner.available?
    entries_data = Rufio::Native::Scanner.scan(@current_path)

    if entries_data.is_a?(Hash) && entries_data[:error]
      # エラー時はRuby実装にフォールバック
      load_entries_ruby
    else
      @entries = entries_data.map do |e|
        {
          name: e[:name],
          directory: e[:is_dir],
          size: e[:size],
          mtime: Time.at(e[:mtime])
        }
      end
    end
  else
    # Go実装が利用できない場合
    load_entries_ruby
  end
end

private

def load_entries_ruby
  # 既存のRuby実装（バックアップ）
  @entries = Dir.entries(@current_path).map do |name|
    next if name == '.' || name == '..'
    path = File.join(@current_path, name)
    stat = File.stat(path)
    {
      name: name,
      directory: stat.directory?,
      size: stat.size,
      mtime: stat.mtime
    }
  end.compact
end
```

---

### ステップ5: ビルド・テスト（30分）

```bash
# Go shared library ビルド
rake build_native

# テスト
ruby -Ilib -e "
  require 'rufio/native/scanner'

  if Rufio::Native::Scanner.available?
    puts '✓ Native scanner available'
    result = Rufio::Native::Scanner.scan('.')
    puts \"Found #{result.size} entries\"
    puts result.first.inspect
  else
    puts '✗ Native scanner not available'
  end
"

# rufio起動
./exe/rufio
```

---

## 📦 配布戦略

### Gem パッケージング

**rufio.gemspec に追加**
```ruby
spec.files += Dir['lib/native/*.{so,dylib,dll}']

# プラットフォーム別gemを作成（オプション）
spec.platform = Gem::Platform::CURRENT
```

### プリビルドバイナリ戦略

**GitHub Actionsでビルド**
```yaml
# .github/workflows/build-native.yml
name: Build Native Libraries
on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}

    steps:
    - uses: actions/checkout@v3
    - uses: actions/setup-go@v4
      with:
        go-version: '1.21'

    - name: Build native library
      run: |
        cd lib_go/scanner
        go build -buildmode=c-shared -o ../../lib/native/libscanner.${{ matrix.ext }} scanner.go

    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: native-${{ matrix.os }}
        path: lib/native/*
```

### インストール時の自動ビルド

**Rakefile に post-install hook**
```ruby
task :install do
  Rake::Task[:build_native].invoke
rescue => e
  warn "⚠️  Native library build failed, falling back to Ruby implementation"
  warn e.message
end
```

---

## 🎯 最終推奨

### ✅ ハイブリッド移行を推奨する理由

1. **早期効果** 🚀
   - 2週間で大幅改善を体感
   - モチベーション維持しやすい

2. **低リスク** 🛡️
   - 段階的、いつでも中断可能
   - Ruby実装がバックアップとして残る

3. **週末開発に最適** 📅
   - 10週（2.5ヶ月）で完成
   - 各Phaseが独立、細切れ時間で進められる

4. **十分なパフォーマンス** ⚡
   - 完全Go書き換えの80-95%の性能
   - 体感では「ほぼ完璧」

5. **プラグインシステム維持** 🔌
   - Rubyの柔軟性を保持
   - 既存エコシステムを壊さない

---

## 📊 比較まとめ

| 項目 | ハイブリッド | 完全Go | 完全Ruby |
|------|------------|--------|---------|
| **完成期間** | **10週** | 21週 | - |
| **初期効果** | **2週で実感** | 5ヶ月後 | - |
| **パフォーマンス** | **完全Goの80-95%** | 100% | 基準 |
| **起動時間** | 400ms | 10ms | 500ms |
| **大量ファイル** | 0.2秒 | 0.15秒 | 2秒 |
| **リスク** | **低** | 中 | - |
| **学習コスト** | **低** | 中 | - |
| **プラグイン** | **維持可能** | 再設計必要 | そのまま |
| **週末開発適合** | **⭐⭐⭐⭐⭐** | ⭐⭐⭐ | - |

---

## 🚀 推奨アクション

### 今すぐ開始する場合

1. **Week 1-2**: Phase 1（ディレクトリスキャナ）実装
   - Go基礎学習（3日）
   - FFI実装（2日）
   - 統合・テスト（2日）

2. **効果測定**
   - 10,000ファイルのディレクトリで速度比較
   - 体感で満足なら継続、不十分なら完全移行検討

3. **Phase 2以降**
   - 効果が高い順に実装
   - 各Phaseで立ち止まって評価

### 判断基準

**ハイブリッドで十分な場合**
- ✅ 日常使用で遅延を感じなくなった
- ✅ 1,000ファイル程度のディレクトリがメイン
- ✅ プラグインシステムが重要

**完全Go移行すべき場合**
- ✅ 10,000+ファイルが日常的
- ✅ 起動時間が致命的（1秒でも許せない）
- ✅ 配布の簡単さが最優先

---

## 結論

**週2日×数時間の開発なら、ハイブリッド移行が最適解です！**

- 📅 **10週で完成**（完全Goの半分）
- 🚀 **2週で効果実感**（モチベーション維持）
- ⚡ **80-95%の性能達成**（体感では十分）
- 🛡️ **低リスク**（段階的、中断可能）
- 🔌 **プラグイン維持**（Rubyの強みを活かす）

**まずはPhase 1（ディレクトリスキャナ）から始めましょう！**
