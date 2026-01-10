# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

class TestNativeScannerRubyAsync < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('rufio_ruby_async_test')
    # テスト用のファイルとディレクトリを作成
    FileUtils.touch(File.join(@test_dir, 'file1.txt'))
    FileUtils.touch(File.join(@test_dir, 'file2.rb'))
    FileUtils.mkdir(File.join(@test_dir, 'subdir'))
    FileUtils.touch(File.join(@test_dir, 'subdir', 'file3.md'))

    # 大量のファイルを含むディレクトリ（進捗テスト用）
    @large_dir = Dir.mktmpdir('rufio_ruby_async_large_test')
    50.times { |i| FileUtils.touch(File.join(@large_dir, "file_#{i}.txt")) }
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    FileUtils.rm_rf(@large_dir) if @large_dir && Dir.exist?(@large_dir)
  end

  def test_async_scan_basic
    # 非同期スキャンの基本動作
    scanner = Rufio::NativeScannerRubyCore.new

    scanner.scan_async(@test_dir)
    entries = scanner.wait(timeout: 5)

    assert_kind_of Array, entries
    assert entries.length >= 3, "Expected at least 3 entries, got #{entries.length}"

    # エントリの構造を確認
    entry = entries.find { |e| e[:name] == 'file1.txt' }
    assert entry, "file1.txt not found in entries"
    assert_equal 'file', entry[:type]
    assert entry.key?(:size)
    assert entry.key?(:mtime)
  ensure
    scanner&.close
  end

  def test_async_scan_fast
    # 高速スキャン（エントリ数制限付き）
    scanner = Rufio::NativeScannerRubyCore.new

    scanner.scan_fast_async(@large_dir, 10)
    entries = scanner.wait(timeout: 5)

    assert_kind_of Array, entries
    assert entries.length <= 10, "Expected at most 10 entries, got #{entries.length}"
  ensure
    scanner&.close
  end

  def test_get_state_transitions
    # 状態遷移のテスト
    scanner = Rufio::NativeScannerRubyCore.new

    # 初期状態
    assert_equal :idle, scanner.get_state

    # スキャン開始
    scanner.scan_async(@test_dir)

    # スキャン中または完了状態になるまで待機
    state = nil
    10.times do
      state = scanner.get_state
      break if [:done, :scanning].include?(state)
      sleep 0.01
    end

    assert_includes [:scanning, :done], state

    # 完了を待つ
    scanner.wait(timeout: 5)
    assert_equal :done, scanner.get_state
  ensure
    scanner&.close
  end

  def test_wait_with_progress
    # 進捗報告付きで完了待ち
    scanner = Rufio::NativeScannerRubyCore.new
    progress_updates = []

    scanner.scan_async(@large_dir)
    entries = scanner.wait_with_progress do |current, total|
      progress_updates << { current: current, total: total }
    end

    assert_kind_of Array, entries
    # 進捗が報告されることを確認（少なくとも1回）
    refute_empty progress_updates, "Progress should be reported at least once"
  ensure
    scanner&.close
  end

  def test_get_progress
    # 進捗取得のテスト
    scanner = Rufio::NativeScannerRubyCore.new

    scanner.scan_async(@large_dir)

    # 進捗を取得
    progress = scanner.get_progress
    assert_kind_of Hash, progress
    assert progress.key?(:current)
    assert progress.key?(:total)
    assert progress[:current].is_a?(Integer)
    assert progress[:total].is_a?(Integer)

    scanner.wait(timeout: 5)
  ensure
    scanner&.close
  end

  def test_cancel
    # キャンセル機能のテスト
    scanner = Rufio::NativeScannerRubyCore.new

    scanner.scan_async(@large_dir)

    # キャンセル
    scanner.cancel

    # キャンセル後の状態確認
    sleep 0.1 # キャンセル処理が反映されるまで少し待つ
    state = scanner.get_state
    assert_equal :cancelled, state
  ensure
    scanner&.close
  end

  def test_wait_timeout
    # タイムアウトのテスト
    scanner = Rufio::NativeScannerRubyCore.new

    # 非常に短いタイムアウトを設定（失敗することを期待）
    scanner.scan_async(@large_dir)

    # タイムアウトエラーが発生する可能性がある
    # （ただし、スキャンが非常に速い場合は成功する可能性もある）
    begin
      scanner.wait(timeout: 0.001)
      # 成功した場合はテストをパス
    rescue StandardError => e
      assert_match(/Timeout/, e.message)
    end
  ensure
    scanner&.close
  end

  def test_nonexistent_directory
    # 存在しないディレクトリのエラーハンドリング
    scanner = Rufio::NativeScannerRubyCore.new

    assert_raises(StandardError) do
      scanner.scan_async('/nonexistent/path/12345')
    end
  ensure
    scanner&.close
  end

  def test_close_idempotent
    # closeが冪等であることを確認
    scanner = Rufio::NativeScannerRubyCore.new

    scanner.scan_async(@test_dir)
    scanner.wait(timeout: 5)

    # 複数回closeしてもエラーにならない
    scanner.close
    scanner.close
  end

  def test_multiple_scanners
    # 複数のスキャナーを同時に使用できることを確認
    scanner1 = Rufio::NativeScannerRubyCore.new
    scanner2 = Rufio::NativeScannerRubyCore.new

    scanner1.scan_async(@test_dir)
    scanner2.scan_async(@large_dir)

    entries1 = scanner1.wait(timeout: 5)
    entries2 = scanner2.wait(timeout: 5)

    assert_kind_of Array, entries1
    assert_kind_of Array, entries2
    refute_equal entries1.length, entries2.length
  ensure
    scanner1&.close
    scanner2&.close
  end
end
