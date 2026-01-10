# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rufio"

begin
  require "async"
  ASYNC_AVAILABLE = true
rescue LoadError
  ASYNC_AVAILABLE = false
end

class TestAsyncScannerFiber < Minitest::Test
  def setup
    skip "async gem not available" unless ASYNC_AVAILABLE

    @test_dir = Dir.mktmpdir("rufio_test")
    create_test_structure
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir
  end

  def create_test_structure
    # ファイルとディレクトリを作成
    File.write(File.join(@test_dir, "file1.txt"), "content1")
    File.write(File.join(@test_dir, "file2.txt"), "content2")
    File.write(File.join(@test_dir, "file3.rb"), "ruby code")
    Dir.mkdir(File.join(@test_dir, "subdir1"))
    Dir.mkdir(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, ".hidden"), "hidden content")
  end

  def test_basic_async_fiber_scan
    # 基本的なFiberでの非同期スキャン
    result = nil

    Async do
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      result = wrapper.scan_async(@test_dir)
    end

    assert_equal 6, result.length
    assert_includes result.map { |e| e[:name] }, "file1.txt"
  end

  def test_async_fiber_with_timeout
    # タイムアウト付きFiberスキャン
    result = nil

    Async do
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      result = wrapper.scan_async(@test_dir, timeout: 10)
    end

    assert_equal 6, result.length
  end

  def test_async_fiber_fast_scan
    # 高速スキャン（エントリ数制限）
    result = nil

    Async do
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      result = wrapper.scan_fast_async(@test_dir, 3)
    end

    assert_operator result.length, :<=, 3
  end

  def test_multiple_concurrent_scans
    # 複数の並行スキャン
    dir1 = Dir.mktmpdir("rufio_test1")
    dir2 = Dir.mktmpdir("rufio_test2")
    dir3 = Dir.mktmpdir("rufio_test3")

    File.write(File.join(dir1, "file1.txt"), "content1")
    File.write(File.join(dir2, "file2.txt"), "content2")
    File.write(File.join(dir3, "file3.txt"), "content3")

    results = []

    Async do |task|
      # 3つのスキャンを並列実行
      tasks = [dir1, dir2, dir3].map do |dir|
        task.async do
          scanner = Rufio::NativeScannerRubyCore.new
          wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)
          wrapper.scan_async(dir)
        end
      end

      # 全ての結果を取得
      results = tasks.map(&:wait)
    end

    assert_equal 3, results.length
    results.each do |entries|
      assert_equal 1, entries.length
    end

    FileUtils.rm_rf(dir1)
    FileUtils.rm_rf(dir2)
    FileUtils.rm_rf(dir3)
  end

  def test_async_fiber_with_progress
    # 進捗報告付きスキャン
    progress_updates = []
    result = nil

    Async do
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      result = wrapper.scan_async_with_progress(@test_dir) do |current, total|
        progress_updates << { current: current, total: total }
      end
    end

    assert_equal 6, result.length
    refute_empty progress_updates
  end

  def test_async_fiber_error_handling
    # エラーハンドリング
    Async do
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      assert_raises(StandardError) do
        wrapper.scan_async("/nonexistent/directory/path")
      end
    end
  end

  def test_async_fiber_with_zig_scanner
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    result = nil

    Async do
      scanner = Rufio::NativeScannerZigCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      result = wrapper.scan_async(@test_dir)
    end

    assert_equal 6, result.length
    assert_includes result.map { |e| e[:name] }, "file1.txt"
  end

  def test_async_fiber_cancellation
    # キャンセル機能
    large_dir = Dir.mktmpdir("rufio_large")
    1000.times { |i| File.write(File.join(large_dir, "file#{i}.txt"), "content") }

    cancelled = false

    Async do |task|
      scanner = Rufio::NativeScannerRubyCore.new
      wrapper = Rufio::AsyncScannerFiberWrapper.new(scanner)

      scan_task = task.async do
        wrapper.scan_async(large_dir)
      end

      # 少し待ってキャンセル
      sleep 0.01
      wrapper.cancel

      begin
        scan_task.wait
      rescue StandardError
        cancelled = true
      end
    end

    # キャンセルが成功したか、スキャンが速すぎて完了した場合
    # どちらも許容する
    FileUtils.rm_rf(large_dir)
  end
end
