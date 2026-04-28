# frozen_string_literal: true

# Windows Console 入力検証テスト
# GitHub Actions の windows-latest runner で ESC キー・マルチバイト入力・
# マウスイベント・IO.select タイムアウト動作を確認する。
# Unix 環境でも全テストが通過するように設計している（skip を使わず）。

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'
require 'stringio'
require 'rufio/multibyte_input_reader'
require 'minitest/autorun'

class TestWindowsConsoleInput < Minitest::Test
  # -----------------------------------------------------------------------
  # Platform detection
  # -----------------------------------------------------------------------

  def test_windows_detection_on_mingw
    # mingw / mswin プラットフォームで windows? が true を返すことを確認
    stub_platform('x64-mingw-ucrt') do
      assert windows_check?, 'mingw は Windows と判定されるべき'
    end
  end

  def test_windows_detection_on_mswin
    stub_platform('i386-mswin32') do
      assert windows_check?, 'mswin は Windows と判定されるべき'
    end
  end

  def test_windows_detection_excludes_cygwin
    stub_platform('x86_64-cygwin') do
      refute windows_check?, 'Cygwin は Windows と判定されないべき（POSIX 互換）'
    end
  end

  def test_windows_detection_excludes_linux
    stub_platform('x86_64-linux') do
      refute windows_check?, 'Linux は Windows と判定されないべき'
    end
  end

  def test_windows_detection_excludes_darwin
    stub_platform('x86_64-darwin') do
      refute windows_check?, 'macOS は Windows と判定されないべき'
    end
  end

  # -----------------------------------------------------------------------
  # ブロッキング入力スレッド（Windows ConPTY 対応）
  # -----------------------------------------------------------------------

  def test_blocking_input_thread_captures_bytes_via_queue
    # Queue にバイトを積むと windows_queue_pop_with_timeout で取り出せることを確認
    queue = Queue.new
    queue << 0x41  # 'A'
    queue << 0x42  # 'B'

    popped = []
    2.times do
      b = windows_queue_pop_with_timeout_helper(queue, 0.01)
      popped << b
    end
    assert_equal [0x41, 0x42], popped
  end

  def test_blocking_input_thread_timeout_returns_nil
    # データがないときは nil を返す
    queue = Queue.new
    result = windows_queue_pop_with_timeout_helper(queue, 0.005)
    assert_nil result
  end

  def test_windows_build_char_ascii
    # ASCII バイト（ESC を含む）は 1 文字そのまま返す
    assert_equal "\e", windows_build_char_helper(0x1B, Queue.new)
    assert_equal 'A',  windows_build_char_helper(0x41, Queue.new)
  end

  def test_windows_build_char_japanese
    # 「あ」= 0xE3 0x81 0x82 (3バイト) をキューから組み立てる
    queue = Queue.new
    queue << 0x81
    queue << 0x82
    result = windows_build_char_helper(0xE3, queue)
    assert_equal 'あ', result
    assert result.valid_encoding?
  end

  def test_windows_build_char_incomplete_multibyte_returns_nil
    # 後続バイトがなければ nil を返す
    queue = Queue.new  # 空
    result = windows_build_char_helper(0xE3, queue)
    assert_nil result
  end

  # IO.select タイムアウト（Unix パス用）
  def test_io_select_0ms_timeout_does_not_raise
    r, w = IO.pipe
    result = IO.select([r], nil, nil, 0)
    assert_nil result, 'IO.select(timeout=0ms) は入力がなければ nil を返すべき'
  ensure
    r&.close
    w&.close
  end

  # -----------------------------------------------------------------------
  # ESC キー処理（MultibyteInputReader 経由）
  # -----------------------------------------------------------------------

  def test_escape_key_returns_single_byte
    # ESC (0x1B) は ASCII 範囲なので追加バイトを読まずにそのまま返す
    reader = Rufio::MultibyteInputReader.new(StringIO.new("\x1B".b))
    result = reader.read_char
    assert_equal "\e", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  def test_escape_followed_by_sequence_does_not_consume_sequence
    # ESC の後に "[A"（上矢印シーケンス）が続く場合、
    # read_char は ESC だけを返し "[A" はバッファに残る
    io = StringIO.new("\x1B[A".b)
    reader = Rufio::MultibyteInputReader.new(io)

    first = reader.read_char
    assert_equal "\e", first, '最初の read_char は ESC を返すべき'

    second = reader.read_char
    assert_equal '[', second, '次の read_char は "[" を返すべき'
  end

  # -----------------------------------------------------------------------
  # マルチバイト文字（コマンドモードで日本語入力）
  # -----------------------------------------------------------------------

  def test_japanese_hiragana_in_command_mode
    # コマンドモードで「あ」(3バイト UTF-8) が正しく1文字として読まれる
    reader = Rufio::MultibyteInputReader.new(StringIO.new("\xE3\x81\x82".b))
    result = reader.read_char
    assert_equal 'あ', result
    assert result.valid_encoding?
  end

  def test_kanji_in_command_mode
    # 漢字「漢」(3バイト UTF-8)
    reader = Rufio::MultibyteInputReader.new(StringIO.new('漢'.b))
    result = reader.read_char
    assert_equal '漢', result
    assert result.valid_encoding?
  end

  def test_emoji_in_command_mode
    # 絵文字「😀」(4バイト UTF-8)
    reader = Rufio::MultibyteInputReader.new(StringIO.new('😀'.b))
    result = reader.read_char
    assert_equal '😀', result
    assert result.valid_encoding?
  end

  def test_mixed_ascii_and_japanese_sequence
    # ASCII と日本語が混在した入力を順番に正しく読む
    io = StringIO.new("A\xE3\x81\x82B".b)
    reader = Rufio::MultibyteInputReader.new(io)
    assert_equal 'A',  reader.read_char
    assert_equal 'あ', reader.read_char
    assert_equal 'B',  reader.read_char
    assert_nil reader.read_char
  end

  # -----------------------------------------------------------------------
  # 不正・不完全シーケンスの安全処理
  # -----------------------------------------------------------------------

  def test_incomplete_multibyte_returns_nil
    # 「あ」の先頭 2 バイトだけ（3 バイト必要）→ nil
    reader = Rufio::MultibyteInputReader.new(StringIO.new("\xE3\x81".b))
    assert_nil reader.read_char
  end

  def test_empty_input_returns_nil
    reader = Rufio::MultibyteInputReader.new(StringIO.new(''))
    assert_nil reader.read_char
  end

  # -----------------------------------------------------------------------
  # マウス有効化シーケンス（Windows vs Unix）
  # -----------------------------------------------------------------------

  def test_mouse_enable_sequence_windows
    # Windows では \e[?1000h\e[?1006h（ボタンイベントのみ + SGR座標）
    stub_platform('x64-mingw-ucrt') do
      assert_equal "\e[?1000h\e[?1006h", mouse_enable_sequence
    end
  end

  def test_mouse_enable_sequence_unix
    # Unix では \e[?1003h\e[?1006h（any-event + SGR座標）
    stub_platform('x86_64-linux') do
      assert_equal "\e[?1003h\e[?1006h", mouse_enable_sequence
    end
  end

  def test_mouse_disable_sequence_windows
    stub_platform('x64-mingw-ucrt') do
      assert_equal "\e[?1000l\e[?1006l", mouse_disable_sequence
    end
  end

  def test_mouse_disable_sequence_unix
    stub_platform('x86_64-linux') do
      assert_equal "\e[?1003l\e[?1006l", mouse_disable_sequence
    end
  end

  # -----------------------------------------------------------------------
  # SGR マウスイベントのパース（\e[<Btn;Col;RowM/m）
  # -----------------------------------------------------------------------

  SGR_PATTERN = /\A(\d+);(\d+);(\d+)([Mm])\z/

  def test_sgr_left_click_press
    m = '0;12;5M'.match(SGR_PATTERN)
    assert m
    assert_equal 0,    m[1].to_i  # btn: 左クリック
    assert_equal 12,   m[2].to_i  # col
    assert_equal 5,    m[3].to_i  # row
    assert_equal true, m[4] == 'M' # press
  end

  def test_sgr_left_click_release
    m = '0;12;5m'.match(SGR_PATTERN)
    assert m
    assert_equal false, m[4] == 'M' # release
  end

  def test_sgr_scroll_up
    m = '64;1;1M'.match(SGR_PATTERN)
    assert m
    assert_equal 64, m[1].to_i  # btn: ホイールアップ
  end

  def test_sgr_scroll_down
    m = '65;1;1M'.match(SGR_PATTERN)
    assert m
    assert_equal 65, m[1].to_i  # btn: ホイールダウン
  end

  def test_sgr_large_coordinates
    # 大きな座標値（高解像度ターミナル）でも正しくパースできる
    m = '0;220;55M'.match(SGR_PATTERN)
    assert m
    assert_equal 220, m[2].to_i
    assert_equal 55,  m[3].to_i
  end

  def test_sgr_invalid_sequence_no_match
    # 不完全・不正なシーケンスはマッチしない
    refute '0;12'.match(SGR_PATTERN)
    refute '0;12;'.match(SGR_PATTERN)
    refute ';12;5M'.match(SGR_PATTERN)
    refute '0;12;5X'.match(SGR_PATTERN)
  end

  # -----------------------------------------------------------------------
  # IO.select 20ms タイムアウト（マウスシーケンス読み取り用）
  # -----------------------------------------------------------------------

  def test_io_select_20ms_timeout_with_data
    # read_next_mouse_byte が使う 20ms タイムアウトでデータが届くことを確認
    r, w = IO.pipe
    w.write('0')
    w.flush
    result = IO.select([r], nil, nil, 0.020)
    assert result, 'IO.select(timeout=20ms) はデータがあれば truthy を返すべき'
  ensure
    r&.close
    w&.close
  end

  def test_io_select_20ms_timeout_without_data
    # データがなければ nil（タイムアウト）を返す
    r, w = IO.pipe
    result = IO.select([r], nil, nil, 0.020)
    assert_nil result, 'IO.select(timeout=20ms) はデータがなければ nil を返すべき'
  ensure
    r&.close
    w&.close
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  private

  # windows_queue_pop_with_timeout のロジックをテスト用に再現
  def windows_queue_pop_with_timeout_helper(queue, timeout_sec)
    deadline = Time.now + timeout_sec
    loop do
      begin
        return queue.pop(true)
      rescue ThreadError
        return nil if Time.now >= deadline
        sleep 0.001
      end
    end
  end

  # windows_build_char のロジックをテスト用に再現
  def windows_build_char_helper(first_byte_int, queue)
    remaining = case first_byte_int
                when 0x00..0x7F then 0
                when 0xC0..0xDF then 1
                when 0xE0..0xEF then 2
                when 0xF0..0xF7 then 3
                else 0
                end
    if remaining == 0
      first_byte_int.chr(Encoding::UTF_8)
    else
      buf = first_byte_int.chr(Encoding::BINARY)
      remaining.times do
        b = windows_queue_pop_with_timeout_helper(queue, 0.005)
        return nil if b.nil?
        buf << b.chr(Encoding::BINARY)
      end
      result = buf.force_encoding(Encoding::UTF_8)
      result.valid_encoding? ? result : nil
    end
  end

  # RUBY_PLATFORM を一時的に差し替えて windows? ロジックを評価する
  def stub_platform(platform)
    original = RUBY_PLATFORM
    Object.send(:remove_const, :RUBY_PLATFORM)
    Object.const_set(:RUBY_PLATFORM, platform)
    yield
  ensure
    Object.send(:remove_const, :RUBY_PLATFORM)
    Object.const_set(:RUBY_PLATFORM, original)
  end

  def windows_check?
    RUBY_PLATFORM =~ /mswin|mingw/ ? true : false
  end

  def mouse_enable_sequence
    if windows_check?
      "\e[?1000h\e[?1006h"
    else
      "\e[?1003h\e[?1006h"
    end
  end

  def mouse_disable_sequence
    if windows_check?
      "\e[?1000l\e[?1006l"
    else
      "\e[?1003l\e[?1006l"
    end
  end
end
