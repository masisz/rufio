# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rufio"

class TestNativeScannerZigAsync < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_test")
    create_test_structure
    Rufio::NativeScanner.mode = "zig"
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def create_test_structure
    # ファイルとディレクトリを作成
    File.write(File.join(@test_dir, "file1.txt"), "content1")
    File.write(File.join(@test_dir, "file2.txt"), "content2")
    Dir.mkdir(File.join(@test_dir, "subdir1"))
    Dir.mkdir(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, ".hidden"), "hidden content")
  end

  def test_zig_scanner_available
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?
    assert Rufio::NativeScannerZigFFI.available?
  end

  def test_zig_async_scan_basic
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(@test_dir)

    # 状態を確認
    state = scanner.get_state
    assert_includes [:scanning, :done], state

    # 完了を待つ
    entries = scanner.wait(timeout: 10)

    # 結果を検証
    assert_equal 5, entries.length
    names = entries.map { |e| e[:name] }
    assert_includes names, "file1.txt"
    assert_includes names, "file2.txt"
    assert_includes names, "subdir1"
    assert_includes names, "subdir2"
    assert_includes names, ".hidden"

    scanner.close
  end

  def test_zig_async_scan_fast
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_fast_async(@test_dir, 3)

    entries = scanner.wait(timeout: 10)

    # エントリ数制限が機能していることを確認
    assert_operator entries.length, :<=, 3

    scanner.close
  end

  def test_zig_get_state_transitions
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new

    # 初期状態
    assert_equal :idle, scanner.get_state

    # スキャン開始
    scanner.scan_async(@test_dir)

    # スキャン中または完了
    state = scanner.get_state
    assert_includes [:scanning, :done], state

    # 完了を待つ
    scanner.wait(timeout: 10)

    # 完了状態
    assert_equal :done, scanner.get_state

    scanner.close
  end

  def test_zig_wait_with_progress
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(@test_dir)

    progress_updates = []
    entries = scanner.wait_with_progress do |current, total|
      progress_updates << { current: current, total: total }
    end

    # 進捗が更新されたことを確認
    refute_empty progress_updates
    assert_equal 5, entries.length

    scanner.close
  end

  def test_zig_get_progress
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(@test_dir)

    # 進捗を取得
    progress = scanner.get_progress
    assert progress.key?(:current)
    assert progress.key?(:total)

    scanner.wait(timeout: 10)
    scanner.close
  end

  def test_zig_cancel
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    # 大きなディレクトリを作成
    large_dir = Dir.mktmpdir("rufio_large")
    1000.times { |i| File.write(File.join(large_dir, "file#{i}.txt"), "content") }

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(large_dir)

    # スキャンが開始されるまで少し待つ
    sleep 0.001
    scanner.cancel

    # キャンセルされたか、既に完了している場合もある
    # （スキャンが非常に速い場合）
    begin
      scanner.wait(timeout: 5)
      # 完了した場合はスキップ
      skip "Scan completed too fast to cancel"
    rescue StandardError => e
      # キャンセルエラーが発生したことを確認
      assert_match(/cancel/i, e.message)
    end

    scanner.close
    FileUtils.rm_rf(large_dir)
  end

  def test_zig_wait_timeout
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(@test_dir)

    # タイムアウトは発生しないはず（十分な時間）
    assert scanner.wait(timeout: 10)

    scanner.close
  end

  def test_zig_close_idempotent
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    scanner.scan_async(@test_dir)
    scanner.wait(timeout: 10)

    # 複数回closeしても問題ないことを確認
    scanner.close
    scanner.close
  end

  def test_zig_multiple_scanners
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    # 複数のディレクトリを作成
    dir1 = Dir.mktmpdir("rufio_test1")
    dir2 = Dir.mktmpdir("rufio_test2")

    File.write(File.join(dir1, "file1.txt"), "content1")
    File.write(File.join(dir2, "file2.txt"), "content2")

    scanner1 = Rufio::NativeScannerZigCore.new
    scanner2 = Rufio::NativeScannerZigCore.new

    scanner1.scan_async(dir1)
    scanner2.scan_async(dir2)

    entries1 = scanner1.wait(timeout: 10)
    entries2 = scanner2.wait(timeout: 10)

    assert_equal 1, entries1.length
    assert_equal 1, entries2.length

    scanner1.close
    scanner2.close

    FileUtils.rm_rf(dir1)
    FileUtils.rm_rf(dir2)
  end

  def test_zig_version
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    version = Rufio::NativeScannerZigFFI.version
    assert_equal "4.0.0-async", version
  end
end
