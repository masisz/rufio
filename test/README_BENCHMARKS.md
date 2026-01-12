# Rufio Benchmarks

このディレクトリには、Rufioの各種パフォーマンスベンチマークが含まれています。

## ベンチマークの実行方法

### FilePreview パフォーマンスベンチマーク

```bash
# 基本的なファイルプレビューベンチマーク
ruby test/benchmark_file_preview.rb

# 詳細なエンコーディングベンチマーク
ruby test/benchmark_encoding_details.rb
```

### その他のベンチマーク

```bash
# FPS（フレームレート）ベンチマーク
ruby test/benchmark_fps.rb

# メモリ使用量ベンチマーク
ruby test/benchmark_memory.rb

# 実際の使用状況でのメモリベンチマーク
ruby test/benchmark_real_usage.rb
```

## ベンチマーク結果

最新のベンチマーク結果は以下を参照してください:

- [総合結果サマリー](/Users/miso/devs/public-git/rufio/BENCHMARK_RESULTS.md)
- [FilePreview詳細レポート](/Users/miso/devs/public-git/rufio/test/benchmark_file_preview_report.md)

## FilePreview ベンチマークの内容

### benchmark_file_preview.rb

以下の項目を測定します:

1. **キャッシュミスシナリオ** - 初回ファイル読み込みのパフォーマンス
2. **キャッシュヒットシナリオ** - 繰り返しファイル読み込みのパフォーマンス
3. **ファイルサイズの影響** - 各種サイズのファイルでの処理時間
4. **行の切り詰めパフォーマンス** - 長い行の処理オーバーヘッド
5. **invalid: :replace の比較** - オプション有無での比較
6. **メモリ影響分析** - オブジェクト生成とGCの動作

テスト対象のファイルタイプ:
- UTF-8 valid（通常のUTF-8ファイル）
- UTF-8 invalid（無効なバイト列を含むファイル）
- Shift_JIS（日本語エンコーディング）
- Large（1000行の大きなファイル）
- Wide chars（絵文字やマルチバイト文字）
- Mixed lines（様々な長さの行）

### benchmark_encoding_details.rb

以下の詳細な測定を行います:

1. **Pure Ruby エンコーディングパフォーマンス**
   - `invalid: :replace` オプションの直接的な影響測定
   
2. **FilePreview エンコーディングパフォーマンス**
   - UTF-8, Shift_JIS, invalid UTF-8 の比較

3. **無効なバイト列のハンドリング**
   - 0%, 1%, 5%, 10% の無効なバイト含有率でのテスト

4. **エンコーディング検出パフォーマンス**
   - UTF-8 直接読み込みと Shift_JIS フォールバック検出の比較

## 主要な発見

### invalid: :replace オプションは実質コストゼロ

```
Pure Ruby レベルでの測定（1000回のイテレーション）:
- オプションなし: 11.436 ms
- オプション付き: 10.879 ms
- オーバーヘッド: -0.557 μs/回（マイナス！）
```

### 優れた処理速度

すべてのファイルタイプで **0.1ms 未満**の処理時間を達成:
- UTF-8 valid: 0.070 ms
- UTF-8 invalid: 0.066 ms
- Shift_JIS: 0.081 ms

### スケーラビリティ

ファイルサイズの影響は最小限:
- 100行（1.8KB）: 0.066 ms
- 10000行（175.8KB）: 0.070 ms

## ベンチマークの追加

新しいベンチマークを追加する場合は、以下のテンプレートを参考にしてください:

```ruby
# frozen_string_literal: true

require "benchmark"
require_relative "../lib/rufio"

class MyBenchmark
  ITERATIONS = 100

  def self.run
    puts "=" * 70
    puts "My Benchmark Title"
    puts "=" * 70
    
    # ベンチマークコード
    time = Benchmark.measure do
      ITERATIONS.times do
        # 測定対象の処理
      end
    end
    
    avg_time = (time.real / ITERATIONS) * 1000
    puts format("Average: %.3f ms/iteration", avg_time)
  end
end

if __FILE__ == $0
  MyBenchmark.run
end
```

## 注意事項

- ベンチマークは複数回実行して平均を取ることを推奨
- システムの負荷状況により結果が変動する可能性あり
- 大量のイテレーションを行うため、実行には時間がかかる場合あり
- 一時ファイルは自動的にクリーンアップされます

## 関連ファイル

- [FilePreview実装](/Users/miso/devs/public-git/rufio/lib/rufio/file_preview.rb)
- [FilePreviewテスト](/Users/miso/devs/public-git/rufio/test/test_file_preview.rb)
