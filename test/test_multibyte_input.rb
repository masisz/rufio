# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'rufio/multibyte_input_reader'

class TestMultibyteInputReader < Minitest::Test
  def make_reader(bytes)
    io = StringIO.new(bytes.b)
    Rufio::MultibyteInputReader.new(io)
  end

  # ASCII文字（"A" = 0x41）
  def test_ascii_char
    reader = make_reader("\x41")
    result = reader.read_char
    assert_equal 'A', result
    assert result.valid_encoding?
    assert_equal Encoding::UTF_8, result.encoding
  end

  # 日本語ひらがな「あ」= 0xE3 0x81 0x82
  def test_japanese_hiragana
    reader = make_reader("\xE3\x81\x82")
    result = reader.read_char
    assert_equal 'あ', result
    assert result.valid_encoding?
    assert_equal Encoding::UTF_8, result.encoding
  end

  # ESCキー（0x1B）は追加読み込みしない
  def test_escape_key
    reader = make_reader("\x1B[A")  # ESC + "[A" (up arrow sequence)
    result = reader.read_char
    assert_equal "\e", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  # 2バイト文字（é = 0xC3 0xA9）
  def test_two_byte_char
    reader = make_reader("\xC3\xA9")
    result = reader.read_char
    assert_equal 'é', result
    assert result.valid_encoding?
    assert_equal Encoding::UTF_8, result.encoding
  end

  # 絵文字（4バイト文字: 😀 = 0xF0 0x9F 0x98 0x80）
  def test_four_byte_emoji
    reader = make_reader("\xF0\x9F\x98\x80")
    result = reader.read_char
    assert_equal '😀', result
    assert result.valid_encoding?
    assert_equal Encoding::UTF_8, result.encoding
  end

  # 不完全なシーケンス（続きがない）→ nil を返す
  def test_incomplete_sequence_returns_nil
    reader = make_reader("\xE3\x81")  # 「あ」の最初の2バイトのみ
    result = reader.read_char
    assert_nil result
  end

  # 空の入力 → nil を返す
  def test_empty_input_returns_nil
    reader = make_reader('')
    result = reader.read_char
    assert_nil result
  end

  # 連続した文字の読み込み
  def test_sequential_reads
    reader = make_reader("A\xE3\x81\x82B")
    assert_equal 'A', reader.read_char
    assert_equal 'あ', reader.read_char
    assert_equal 'B', reader.read_char
    assert_nil reader.read_char
  end
end
