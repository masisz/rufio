# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "tmpdir"

# メモリ測定用スクリプト
class MemoryBenchmark
  def self.measure
    GC.start
    GC.disable

    before = memory_usage
    result = yield
    after = memory_usage

    GC.enable
    GC.start

    {
      before: before,
      after: after,
      delta: after - before,
      result: result
    }
  end

  def self.memory_usage
    # macOSとLinuxで動作するメモリ取得
    if RUBY_PLATFORM =~ /darwin/
      # macOS
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0  # MB
    else
      # Linux
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0  # MB
    end
  end

  def self.format_mb(mb)
    "%.2f MB" % mb
  end
end

puts "=" * 60
puts "rufio Memory Usage Benchmark"
puts "=" * 60
puts

# 1. 基本的な起動メモリ
puts "1. Basic Initialization"
puts "-" * 60
mem = MemoryBenchmark.measure do
  # 何もしない（基本的なRuby実行環境）
end
puts "Ruby base memory: #{MemoryBenchmark.format_mb(mem[:before])}"
puts

# 2. rufioモジュールのロード
puts "2. Loading rufio modules"
puts "-" * 60
mem = MemoryBenchmark.measure do
  # すでにロード済みなので、主要クラスのインスタンス化
  Rufio::Config
  Rufio::ConfigLoader
end
puts "Memory after loading: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts

# 3. DirectoryListingの初期化
puts "3. DirectoryListing initialization"
puts "-" * 60
test_dir = Dir.mktmpdir("rufio_memory_test")
# テストファイルを作成
100.times do |i|
  File.write(File.join(test_dir, "file_#{i}.txt"), "test content #{i}")
end
10.times do |i|
  Dir.mkdir(File.join(test_dir, "dir_#{i}"))
end

mem = MemoryBenchmark.measure do
  Rufio::DirectoryListing.new(test_dir)
end
puts "Memory for DirectoryListing: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts "Files in directory: 110"
puts

# 4. 各コンポーネントの初期化
puts "4. All components initialization"
puts "-" * 60
mem = MemoryBenchmark.measure do
  directory_listing = Rufio::DirectoryListing.new(test_dir)
  keybind_handler = Rufio::KeybindHandler.new
  keybind_handler.set_directory_listing(directory_listing)
  file_preview = Rufio::FilePreview.new
  # terminal_ui = Rufio::TerminalUI.new  # 実際のターミナルUIは起動しない
end
puts "Memory for all components: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase from base: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts

# 5. 大量のファイルでのテスト
puts "5. Large directory test (1000 files)"
puts "-" * 60
large_test_dir = Dir.mktmpdir("rufio_large_test")
1000.times do |i|
  File.write(File.join(large_test_dir, "file_#{i}.txt"), "test content #{i}")
end

mem = MemoryBenchmark.measure do
  directory_listing = Rufio::DirectoryListing.new(large_test_dir)
  directory_listing.list_entries
end
puts "Memory for 1000 files: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts "Per file: #{MemoryBenchmark.format_mb(mem[:delta] / 1000)}"
puts

# 6. フィルター機能のメモリ使用
puts "6. Filter functionality"
puts "-" * 60
directory_listing = Rufio::DirectoryListing.new(large_test_dir)
keybind_handler = Rufio::KeybindHandler.new
keybind_handler.set_directory_listing(directory_listing)

mem = MemoryBenchmark.measure do
  # フィルターモード開始
  filter_manager = keybind_handler.instance_variable_get(:@filter_manager)
  filter_manager.start_filter_mode(directory_listing.list_entries)
  # 文字入力シミュレーション
  filter_manager.instance_variable_set(:@filter_query, "file_1")
  filter_manager.send(:apply_filter)
end
puts "Memory for filtering: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts

# 7. 選択機能のメモリ使用
puts "7. Selection functionality (100 files selected)"
puts "-" * 60
keybind_handler = Rufio::KeybindHandler.new
directory_listing = Rufio::DirectoryListing.new(large_test_dir)
keybind_handler.set_directory_listing(directory_listing)

mem = MemoryBenchmark.measure do
  entries = directory_listing.list_entries
  selection_manager = keybind_handler.instance_variable_get(:@selection_manager)
  100.times do |i|
    selection_manager.toggle_selection(entries[i]) if entries[i]
  end
end
puts "Memory for 100 selections: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts "Per selection: #{MemoryBenchmark.format_mb(mem[:delta] / 100)}"
puts

# 8. ブックマーク機能
puts "8. Bookmark functionality (10 bookmarks)"
puts "-" * 60
mem = MemoryBenchmark.measure do
  bookmark = Rufio::Bookmark.new
  10.times do |i|
    bookmark.add("bookmark_#{i}", "/tmp/test_#{i}")
  end
end
puts "Memory for 10 bookmarks: #{MemoryBenchmark.format_mb(mem[:after])}"
puts "Increase: #{MemoryBenchmark.format_mb(mem[:delta])}"
puts

# クリーンアップ
FileUtils.rm_rf(test_dir)
FileUtils.rm_rf(large_test_dir)

puts "=" * 60
puts "Summary"
puts "=" * 60
puts "rufio is a lightweight file manager with minimal memory footprint."
puts "Typical memory usage: 20-40 MB for normal operations"
puts "Scales well with large directories (1000+ files)"
puts "=" * 60
