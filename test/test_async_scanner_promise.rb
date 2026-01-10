# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/rufio"

class TestAsyncScannerPromise < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_test")
    create_test_structure
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
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

  def test_promise_basic_usage
    # Promise風インターフェースの基本的な使い方
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    result = promise
      .scan_async(@test_dir)
      .wait

    assert_equal 6, result.length
    assert_includes result.map { |e| e[:name] }, "file1.txt"
  end

  def test_promise_with_single_then
    # 1つのthenコールバック
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    callback_executed = false
    callback_result = nil

    result = promise
      .scan_async(@test_dir)
      .then do |entries|
        callback_executed = true
        callback_result = entries.length
        entries
      end
      .wait

    assert callback_executed, "コールバックが実行されていません"
    assert_equal 6, callback_result
    assert_equal 6, result.length
  end

  def test_promise_with_multiple_then
    # 複数のthenをチェーン
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    execution_order = []

    result = promise
      .scan_async(@test_dir)
      .then do |entries|
        execution_order << :first
        entries
      end
      .then do |entries|
        execution_order << :second
        entries.select { |e| !e[:is_dir] }
      end
      .then do |files|
        execution_order << :third
        files
      end
      .wait

    assert_equal [:first, :second, :third], execution_order
    # ファイルのみ（ディレクトリを除外）
    assert_operator result.length, :>, 0
    result.each do |entry|
      refute entry[:is_dir], "ディレクトリが含まれています: #{entry[:name]}"
    end
  end

  def test_promise_with_transformation
    # データ変換をチェーン
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    result = promise
      .scan_async(@test_dir)
      .then { |entries| entries.select { |e| e[:type] == 'file' } }
      .then { |files| files.map { |f| f[:name] } }
      .then { |names| names.sort }
      .wait

    assert_kind_of Array, result
    assert result.all? { |name| name.is_a?(String) }
    # ソートされていることを確認
    assert_equal result, result.sort
  end

  def test_promise_auto_close
    # Promise完了後にスキャナーが自動的にクローズされることを確認
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    promise
      .scan_async(@test_dir)
      .wait

    # スキャナーの状態を確認（クローズ後はスレッドがnil）
    assert_nil scanner.instance_variable_get(:@thread)
  end

  def test_promise_error_handling
    # 存在しないディレクトリのエラーハンドリング
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    assert_raises(StandardError) do
      promise
        .scan_async("/nonexistent/directory/path")
        .wait
    end
  end

  def test_promise_with_filter_chain
    # 実用的なフィルタリングチェーン
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    result = promise
      .scan_async(@test_dir)
      .then { |entries| entries.reject { |e| e[:hidden] } }  # 隠しファイルを除外
      .then { |entries| entries.select { |e| e[:type] == 'file' } }  # ファイルのみ
      .then { |files| files.select { |f| f[:name].end_with?('.txt') } }  # .txtのみ
      .wait

    assert_equal 2, result.length
    assert_includes result.map { |e| e[:name] }, "file1.txt"
    assert_includes result.map { |e| e[:name] }, "file2.txt"
  end

  def test_promise_with_fast_scan
    # 高速スキャン（エントリ数制限）との組み合わせ
    scanner = Rufio::NativeScannerRubyCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    result = promise
      .scan_fast_async(@test_dir, 3)
      .then { |entries| entries.map { |e| e[:name] } }
      .wait

    assert_operator result.length, :<=, 3
  end

  # === Zig版スキャナーとのテスト ===

  def test_promise_with_zig_scanner
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    result = promise
      .scan_async(@test_dir)
      .then { |entries| entries.reject { |e| e[:is_dir] } }  # ファイルのみ
      .then { |files| files.map { |f| f[:name] } }
      .wait

    assert_kind_of Array, result
    assert_operator result.length, :>, 0
  end

  def test_promise_with_zig_scanner_chain
    skip "Zig library not available" unless Rufio::NativeScannerZigFFI.available?

    scanner = Rufio::NativeScannerZigCore.new
    promise = Rufio::AsyncScannerPromise.new(scanner)

    execution_order = []

    result = promise
      .scan_async(@test_dir)
      .then do |entries|
        execution_order << :first
        entries.reject { |e| e[:hidden] }
      end
      .then do |entries|
        execution_order << :second
        entries.select { |e| !e[:is_dir] }
      end
      .wait

    assert_equal [:first, :second], execution_order
    assert_kind_of Array, result
  end
end
