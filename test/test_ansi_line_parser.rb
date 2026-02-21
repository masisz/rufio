# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestAnsiLineParser < Minitest::Test
  # =========================================================
  # parse メソッドのテスト
  # =========================================================

  def test_parse_plain_text
    tokens = Rufio::AnsiLineParser.parse("hello world")
    assert_equal 1, tokens.length
    assert_equal "hello world", tokens[0][:text]
    assert_nil tokens[0][:fg]
  end

  def test_parse_empty_string
    tokens = Rufio::AnsiLineParser.parse("")
    assert_equal [], tokens
  end

  def test_parse_single_color
    tokens = Rufio::AnsiLineParser.parse("\e[32mhello\e[0m")
    assert_equal 1, tokens.length
    assert_equal "hello", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
  end

  def test_parse_color_then_plain
    tokens = Rufio::AnsiLineParser.parse("\e[32mhello\e[0m world")
    assert_equal 2, tokens.length
    assert_equal "hello", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
    assert_equal " world", tokens[1][:text]
    assert_nil tokens[1][:fg]
  end

  def test_parse_multiple_colors
    tokens = Rufio::AnsiLineParser.parse("\e[32mfoo\e[0m\e[31mbar\e[0m")
    assert_equal 2, tokens.length
    assert_equal "foo", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
    assert_equal "bar", tokens[1][:text]
    assert_equal "\e[31m", tokens[1][:fg]
  end

  def test_parse_reset_without_code
    # \e[m は \e[0m と同じリセット
    tokens = Rufio::AnsiLineParser.parse("\e[32mfoo\e[mbar")
    assert_equal 2, tokens.length
    assert_equal "foo", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
    assert_equal "bar", tokens[1][:text]
    assert_nil tokens[1][:fg]
  end

  def test_parse_truecolor_sequence
    # bat が出力する TrueColor ANSI コード
    tokens = Rufio::AnsiLineParser.parse("\e[38;2;100;200;50mtext\e[0m")
    assert_equal 1, tokens.length
    assert_equal "text", tokens[0][:text]
    assert_equal "\e[38;2;100;200;50m", tokens[0][:fg]
  end

  def test_parse_reset_plus_color
    # \e[0;32m はリセット + 緑色
    tokens = Rufio::AnsiLineParser.parse("\e[0;32mtext\e[0m")
    assert_equal 1, tokens.length
    assert_equal "text", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
  end

  def test_parse_japanese_text
    tokens = Rufio::AnsiLineParser.parse("\e[32m日本語\e[0m")
    assert_equal 1, tokens.length
    assert_equal "日本語", tokens[0][:text]
    assert_equal "\e[32m", tokens[0][:fg]
  end

  def test_parse_mixed_ascii_and_japanese
    tokens = Rufio::AnsiLineParser.parse("abc\e[32m日本\e[0mdef")
    assert_equal 3, tokens.length
    assert_equal "abc", tokens[0][:text]
    assert_nil tokens[0][:fg]
    assert_equal "日本", tokens[1][:text]
    assert_equal "\e[32m", tokens[1][:fg]
    assert_equal "def", tokens[2][:text]
    assert_nil tokens[2][:fg]
  end

  def test_parse_no_text_only_ansi
    tokens = Rufio::AnsiLineParser.parse("\e[32m\e[0m")
    assert_equal [], tokens
  end

  # =========================================================
  # display_width メソッドのテスト
  # =========================================================

  def test_display_width_plain_tokens
    tokens = [{ text: "hello", fg: nil }]
    assert_equal 5, Rufio::AnsiLineParser.display_width(tokens)
  end

  def test_display_width_colored_tokens
    tokens = [{ text: "hello", fg: "\e[32m" }, { text: " world", fg: nil }]
    assert_equal 11, Rufio::AnsiLineParser.display_width(tokens)
  end

  def test_display_width_japanese_tokens
    tokens = [{ text: "日本語", fg: nil }]
    assert_equal 6, Rufio::AnsiLineParser.display_width(tokens)
  end

  def test_display_width_empty_tokens
    assert_equal 0, Rufio::AnsiLineParser.display_width([])
  end

  def test_display_width_excludes_ansi_codes
    # parse後のトークンを使用: ANSI コードが幅に影響しないことを確認
    tokens = Rufio::AnsiLineParser.parse("\e[32mhello\e[0m world")
    assert_equal 11, Rufio::AnsiLineParser.display_width(tokens)
  end

  # =========================================================
  # wrap メソッドのテスト
  # =========================================================

  def test_wrap_short_text_no_wrap_needed
    tokens = [{ text: "hello", fg: nil }]
    lines = Rufio::AnsiLineParser.wrap(tokens, 10)
    assert_equal 1, lines.length
    assert_equal "hello", lines[0].map { |t| t[:text] }.join
  end

  def test_wrap_long_text_wraps_to_two_lines
    tokens = [{ text: "hello world", fg: nil }]
    lines = Rufio::AnsiLineParser.wrap(tokens, 7)
    assert_equal 2, lines.length
    assert_equal "hello w", lines[0].map { |t| t[:text] }.join
    assert_equal "orld", lines[1].map { |t| t[:text] }.join
  end

  def test_wrap_preserves_fg_color
    tokens = [{ text: "hello", fg: "\e[32m" }]
    lines = Rufio::AnsiLineParser.wrap(tokens, 3)
    assert_equal 2, lines.length
    # 各行のトークンが元の fg を保持していることを確認
    lines[0].each { |t| assert_equal "\e[32m", t[:fg] }
    lines[1].each { |t| assert_equal "\e[32m", t[:fg] }
  end

  def test_wrap_multiple_colored_tokens
    tokens = [
      { text: "foo", fg: "\e[32m" },
      { text: "bar", fg: "\e[31m" }
    ]
    lines = Rufio::AnsiLineParser.wrap(tokens, 4)
    # "foobar" を幅4で折り返し: "foob" と "ar"
    assert_equal 2, lines.length
    assert_equal "foob", lines[0].map { |t| t[:text] }.join
    assert_equal "ar", lines[1].map { |t| t[:text] }.join
  end

  def test_wrap_fullwidth_characters
    # 日本語（幅2）: "日本語" = 表示幅6
    tokens = [{ text: "日本語", fg: nil }]
    # 幅5で折り返し: "日本" (4) + "語" (2) → "語" は5に入らないのでラップ
    lines = Rufio::AnsiLineParser.wrap(tokens, 5)
    assert_equal 2, lines.length
    assert_equal "日本", lines[0].map { |t| t[:text] }.join
    assert_equal "語", lines[1].map { |t| t[:text] }.join
  end

  def test_wrap_empty_tokens
    lines = Rufio::AnsiLineParser.wrap([], 10)
    # 空トークンは空の行リストを返す
    assert_equal 0, lines.length
  end

  def test_wrap_exact_width
    # 幅と同じ長さのテキストは折り返しなし
    tokens = [{ text: "hello", fg: nil }]
    lines = Rufio::AnsiLineParser.wrap(tokens, 5)
    assert_equal 1, lines.length
    assert_equal "hello", lines[0].map { |t| t[:text] }.join
  end

  def test_wrap_all_display_text_preserved
    # 折り返し後も全文字が保持されていること
    tokens = [{ text: "abcdefghij", fg: nil }]
    lines = Rufio::AnsiLineParser.wrap(tokens, 3)
    combined = lines.map { |line| line.map { |t| t[:text] }.join }.join
    assert_equal "abcdefghij", combined
  end

  # =========================================================
  # parse + wrap 統合テスト
  # =========================================================

  def test_parse_and_wrap_colored_line
    ansi_line = "\e[32mhello world\e[0m"
    tokens = Rufio::AnsiLineParser.parse(ansi_line)
    lines = Rufio::AnsiLineParser.wrap(tokens, 7)
    assert_equal 2, lines.length
    # 最初の行: "hello w" が緑色
    assert lines[0].all? { |t| t[:fg] == "\e[32m" }
    # 2番目の行: "orld" が緑色
    assert lines[1].all? { |t| t[:fg] == "\e[32m" }
  end
end
