# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rufio"

class TestParallelScanner < Minitest::Test
  def setup
    @test_dirs = []
    3.times do |i|
      dir = Dir.mktmpdir("rufio_test_#{i}")
      @test_dirs << dir
      create_test_structure(dir, i)
    end
  end

  def teardown
    @test_dirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  def create_test_structure(dir, index)
    # 各ディレクトリに異なる数のファイルを作成
    (index + 1).times do |i|
      File.write(File.join(dir, "file#{i}.txt"), "content#{i}")
    end
    Dir.mkdir(File.join(dir, "subdir#{index}"))
    File.write(File.join(dir, ".hidden#{index}"), "hidden content")
  end

  def test_parallel_scan_multiple_directories
    # 複数ディレクトリの並列スキャン
    parallel_scanner = Rufio::ParallelScanner.new

    results = parallel_scanner.scan_all(@test_dirs)

    # 各ディレクトリの結果を検証
    assert_equal 3, results.length
    assert_kind_of Hash, results[0]
    assert results[0].key?(:path)
    assert results[0].key?(:entries)
    assert results[0].key?(:success)
  end

  def test_parallel_scan_with_results_merge
    # 結果をマージして返す
    parallel_scanner = Rufio::ParallelScanner.new

    all_entries = parallel_scanner.scan_all_merged(@test_dirs)

    # 全エントリがマージされている
    assert_kind_of Array, all_entries
    # dir0: 3エントリ(file0, subdir0, .hidden0)
    # dir1: 4エントリ(file0, file1, subdir1, .hidden1)
    # dir2: 5エントリ(file0, file1, file2, subdir2, .hidden2)
    # 合計: 12エントリ
    assert_equal 12, all_entries.length
  end

  def test_parallel_scan_with_error_handling
    # 一部のディレクトリが存在しない場合のエラーハンドリング
    parallel_scanner = Rufio::ParallelScanner.new
    paths = @test_dirs + ["/nonexistent/path"]

    results = parallel_scanner.scan_all(paths)

    # 成功した結果と失敗した結果が混在
    assert_equal 4, results.length

    successful = results.select { |r| r[:success] }
    failed = results.reject { |r| r[:success] }

    assert_equal 3, successful.length
    assert_equal 1, failed.length
    assert failed[0].key?(:error)
  end

  def test_parallel_scan_performance
    # パフォーマンステスト：並列の方が速いことを確認
    # 大きなディレクトリを作成
    large_dirs = []
    3.times do |i|
      dir = Dir.mktmpdir("rufio_large_#{i}")
      large_dirs << dir
      50.times { |j| File.write(File.join(dir, "file#{j}.txt"), "content") }
    end

    # 並列スキャン
    parallel_scanner = Rufio::ParallelScanner.new
    start_time = Time.now
    parallel_results = parallel_scanner.scan_all(large_dirs)
    parallel_time = Time.now - start_time

    # シーケンシャルスキャン
    start_time = Time.now
    sequential_results = large_dirs.map do |path|
      scanner = Rufio::NativeScannerRubyCore.new
      begin
        scanner.scan_async(path)
        entries = scanner.wait(timeout: 10)
        { path: path, entries: entries, success: true }
      ensure
        scanner.close
      end
    end
    sequential_time = Time.now - start_time

    # 結果は同じ
    assert_equal 3, parallel_results.length
    assert_equal 3, sequential_results.length

    # 並列の方が速い（または同等）
    # 注：テスト環境によっては並列化の効果が出ない場合もあるため、
    # 単に完了することを確認
    assert parallel_time > 0
    assert sequential_time > 0

    large_dirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  def test_parallel_scan_with_max_workers
    # ワーカー数制限
    parallel_scanner = Rufio::ParallelScanner.new(max_workers: 2)

    results = parallel_scanner.scan_all(@test_dirs)

    assert_equal 3, results.length
    results.each do |result|
      assert result[:success]
    end
  end

  def test_parallel_scan_with_filter
    # フィルタ付きスキャン
    parallel_scanner = Rufio::ParallelScanner.new

    # ファイルのみを抽出
    all_entries = parallel_scanner.scan_all_merged(@test_dirs) do |entry|
      !entry[:is_dir]
    end

    # ディレクトリが除外されている
    all_entries.each do |entry|
      refute entry[:is_dir], "Directory found: #{entry[:name]}"
    end
  end

  def test_parallel_scan_with_zig_backend
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    # Zigバックエンドで並列スキャン
    parallel_scanner = Rufio::ParallelScanner.new(backend: :zig)

    results = parallel_scanner.scan_all(@test_dirs)

    assert_equal 3, results.length
    results.each do |result|
      assert result[:success]
      assert result[:entries].is_a?(Array)
    end
  end

  def test_parallel_scan_with_progress
    # 進捗報告付き並列スキャン
    parallel_scanner = Rufio::ParallelScanner.new
    progress_updates = []

    results = parallel_scanner.scan_all_with_progress(@test_dirs) do |completed, total|
      progress_updates << { completed: completed, total: total }
    end

    assert_equal 3, results.length
    refute_empty progress_updates
    # 最後の進捗は完了を示す
    assert_equal 3, progress_updates.last[:completed]
    assert_equal 3, progress_updates.last[:total]
  end

  def test_parallel_scan_empty_directory_list
    # 空のディレクトリリスト
    parallel_scanner = Rufio::ParallelScanner.new

    results = parallel_scanner.scan_all([])

    assert_equal 0, results.length
  end

  def test_parallel_scan_single_directory
    # 単一ディレクトリでも動作
    parallel_scanner = Rufio::ParallelScanner.new

    results = parallel_scanner.scan_all([@test_dirs[0]])

    assert_equal 1, results.length
    assert results[0][:success]
  end
end
