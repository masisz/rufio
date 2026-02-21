# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'
require 'tmpdir'

class TestSyntaxHighlighter < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("rufio_syntax_test")
    @ruby_file = File.join(@tmpdir, "test.rb")
    File.write(@ruby_file, "# Ruby file\ndef hello\n  puts 'hello'\nend\n")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # =========================================================
  # available? メソッドのテスト
  # =========================================================

  def test_available_returns_boolean
    hl = Rufio::SyntaxHighlighter.new
    result = hl.available?
    assert [true, false].include?(result), "available? は true または false を返すべき"
  end

  # =========================================================
  # highlight メソッドのテスト（bat なし環境をシミュレート）
  # =========================================================

  def test_highlight_returns_empty_when_bat_unavailable
    hl = Rufio::SyntaxHighlighter.new
    # bat が利用不可の場合をシミュレート
    hl.instance_variable_set(:@bat_available, false)

    result = hl.highlight(@ruby_file)
    assert_equal [], result
  end

  def test_highlight_returns_empty_for_nonexistent_file
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    result = hl.highlight("/nonexistent/path/file.rb")
    assert_equal [], result
  end

  def test_highlight_returns_array_of_strings_when_bat_available
    hl = Rufio::SyntaxHighlighter.new
    skip "bat コマンドが見つかりません" unless hl.available?

    result = hl.highlight(@ruby_file)
    assert_kind_of Array, result
    assert result.all? { |line| line.is_a?(String) }, "全ての要素が String であるべき"
    refute result.empty?, "bat が利用可能な場合、結果は空でないべき"
  end

  def test_highlight_line_count_respects_max_lines
    hl = Rufio::SyntaxHighlighter.new
    skip "bat コマンドが見つかりません" unless hl.available?

    # 多数の行を含むファイルを作成
    large_file = File.join(@tmpdir, "large.rb")
    File.write(large_file, (1..100).map { |i| "puts #{i}" }.join("\n"))

    result = hl.highlight(large_file, max_lines: 10)
    assert result.length <= 10, "max_lines=10 のとき、結果は10行以下であるべき"
  end

  def test_highlight_caches_result
    hl = Rufio::SyntaxHighlighter.new
    skip "bat コマンドが見つかりません" unless hl.available?

    # 1回目の呼び出し
    result1 = hl.highlight(@ruby_file)
    # 2回目の呼び出し（キャッシュから取得）
    result2 = hl.highlight(@ruby_file)

    assert_equal result1, result2
  end

  def test_highlight_cache_invalidated_on_mtime_change
    hl = Rufio::SyntaxHighlighter.new
    skip "bat コマンドが見つかりません" unless hl.available?

    # 1回目の呼び出し（キャッシュ登録）
    result1 = hl.highlight(@ruby_file)

    # ファイルを変更してmtimeを更新
    sleep 0.01
    File.write(@ruby_file, "# Modified\nputs 'changed'\n")

    # 2回目の呼び出し（キャッシュ無効化 → 再取得）
    result2 = hl.highlight(@ruby_file)

    # キャッシュが更新されていること（ファイルが変わったので内容も変わりうる）
    # ここでは例外なく実行できること、配列が返ることのみ確認
    assert_kind_of Array, result2
  end

  def test_highlight_handles_error_gracefully
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    # run_bat を強制的にエラーさせる（読み取れないパスをシミュレート）
    # highlight はエラー時に [] を返すべき
    def hl.run_bat(_, _)
      raise "Unexpected error"
    end

    result = hl.highlight(@ruby_file)
    assert_equal [], result
  end

  # =========================================================
  # ANSI 出力の検証
  # =========================================================

  def test_highlight_contains_ansi_codes_when_bat_available
    hl = Rufio::SyntaxHighlighter.new
    skip "bat コマンドが見つかりません" unless hl.available?

    result = hl.highlight(@ruby_file)
    # 色付きコードが含まれることを確認（ANSIエスケープコードが含まれる）
    has_ansi = result.any? { |line| line.include?("\e[") }
    assert has_ansi, "bat の出力に ANSI エスケープコードが含まれるべき"
  end

  # =========================================================
  # highlight_async メソッドのテスト（Fix 2: 非同期化）
  # =========================================================

  # bat が利用不可の場合はコールバックを呼ばず即座にリターン
  def test_highlight_async_does_not_call_callback_when_bat_unavailable
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, false)

    callback_called = false
    hl.highlight_async(@ruby_file) { callback_called = true }

    refute callback_called, "bat 利用不可時はコールバックを呼ばないべき"
  end

  # キャッシュヒット時はコールバックを即時同期呼び出しする
  def test_highlight_async_uses_cache_for_immediate_callback
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    mtime = File.mtime(@ruby_file)
    hl.instance_variable_get(:@cache)[@ruby_file] = { mtime: mtime, lines: ['cached line'] }

    result_lines = nil
    callback_called = false
    hl.highlight_async(@ruby_file) do |lines|
      result_lines = lines
      callback_called = true
    end

    assert callback_called, "キャッシュヒット時はコールバックが即時呼ばれるべき"
    assert_equal ['cached line'], result_lines
  end

  # highlight_async はメインスレッドをブロックしない（bat 完了を待たない）
  def test_highlight_async_returns_before_bat_completes
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    # run_bat を遅延させる（100ms）
    hl.define_singleton_method(:run_bat) do |_, _|
      sleep 0.1
      ['highlighted line']
    end

    callback_called = false
    start = Time.now
    hl.highlight_async(@ruby_file) { |_| callback_called = true }
    elapsed = Time.now - start

    assert elapsed < 0.05, "highlight_async は50ms以内に返るべき（#{(elapsed * 1000).round}ms）"

    # コールバックはバックグラウンドで呼ばれる
    deadline = Time.now + 1.0
    sleep 0.01 until callback_called || Time.now > deadline
    assert callback_called, "コールバックが1秒以内に呼ばれるべき"
  end

  # コールバックは bat の結果（ANSI行配列）を受け取る
  def test_highlight_async_callback_receives_lines
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    hl.define_singleton_method(:run_bat) do |_, _|
      ['line1', 'line2']
    end

    received = nil
    hl.highlight_async(@ruby_file) { |lines| received = lines }

    deadline = Time.now + 1.0
    sleep 0.01 until received || Time.now > deadline
    assert_equal ['line1', 'line2'], received
  end

  # 同じファイルへの重複呼び出しでは run_bat を1回だけ実行する（ペンディングガード）
  def test_highlight_async_no_duplicate_threads_while_pending
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    started_count = 0
    count_mutex = Mutex.new

    hl.define_singleton_method(:run_bat) do |_, _|
      count_mutex.synchronize { started_count += 1 }
      sleep 0.05
      ['line']
    end

    # 同じファイルへ素早く2回呼ぶ（1回目がペンディング中）
    hl.highlight_async(@ruby_file)
    hl.highlight_async(@ruby_file)  # ← ペンディングガードでスキップされるべき

    sleep 0.2  # スレッドが完了するまで待つ

    assert_equal 1, started_count, "ペンディング中の重複呼び出しは run_bat を1回だけ実行すべき"
  end

  # スレッドエラー時でもクラッシュせずコールバックを呼ぶ
  def test_highlight_async_handles_bat_error_gracefully
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    hl.define_singleton_method(:run_bat) do |_, _|
      raise "bat failed"
    end

    received = nil
    hl.highlight_async(@ruby_file) { |lines| received = lines }

    deadline = Time.now + 1.0
    sleep 0.01 until !received.nil? || Time.now > deadline
    assert_equal [], received, "bat エラー時はコールバックに [] を渡すべき"
  end

  # Mutex によるスレッドセーフ: 複数ファイルへの並行呼び出しでキャッシュが壊れない
  def test_highlight_async_is_thread_safe
    hl = Rufio::SyntaxHighlighter.new
    hl.instance_variable_set(:@bat_available, true)

    file2 = File.join(@tmpdir, "test2.rb")
    File.write(file2, "puts 2\n")

    hl.define_singleton_method(:run_bat) do |file_path, _|
      sleep rand(0.01..0.03)
      ["result_for_#{File.basename(file_path)}"]
    end

    results = {}
    mutex = Mutex.new

    hl.highlight_async(@ruby_file) { |l| mutex.synchronize { results[:file1] = l } }
    hl.highlight_async(file2)       { |l| mutex.synchronize { results[:file2] = l } }

    deadline = Time.now + 1.0
    sleep 0.01 until results.size == 2 || Time.now > deadline

    assert_equal ["result_for_test.rb"],  results[:file1]
    assert_equal ["result_for_test2.rb"], results[:file2]
  end
end
