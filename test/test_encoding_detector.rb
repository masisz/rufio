# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

# EncodingDetector: BOM / UTF-8 / CP932 / EUC-JP の判定と、改行境界での切り詰め
class TestEncodingDetector < Minitest::Test
  JAPANESE = "商品,単価\nみかん,150\n"

  def setup
    @test_dir = Dir.mktmpdir('rufio_encoding_test')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def write_bytes(name, bytes)
    path = File.join(@test_dir, name)
    File.binwrite(path, bytes)
    path
  end

  # === decode ===

  def test_ascii_is_utf8
    result = Rufio::EncodingDetector.decode("name,price\n".b)
    assert_equal 'UTF-8', result.encoding
    assert_equal "name,price\n", result.text
    refute result.replaced
  end

  def test_utf8_japanese
    result = Rufio::EncodingDetector.decode(JAPANESE.dup.b)
    assert_equal 'UTF-8', result.encoding
    assert_equal JAPANESE, result.text
  end

  def test_cp932_is_detected_and_converted
    result = Rufio::EncodingDetector.decode(JAPANESE.encode('CP932').b)
    assert_equal 'CP932', result.encoding
    assert_equal JAPANESE, result.text
    assert_equal Encoding::UTF_8, result.text.encoding
  end

  def test_euc_jp_is_detected_and_converted
    result = Rufio::EncodingDetector.decode(JAPANESE.encode('EUC-JP').b)
    assert_equal 'EUC-JP', result.encoding, 'CP932 として読めても半角カタカナばかりなら EUC-JP を選ぶ'
    assert_equal JAPANESE, result.text
  end

  def test_utf8_bom_is_stripped
    result = Rufio::EncodingDetector.decode("\xEF\xBB\xBF".b + "a,b\n".b)
    assert_equal 'UTF-8', result.encoding
    assert_equal "a,b\n", result.text
    refute result.text.start_with?("﻿")
  end

  def test_utf16le_with_bom
    result = Rufio::EncodingDetector.decode("\xFF\xFE".b + "a,b\n".encode('UTF-16LE').b)
    assert_equal 'UTF-16LE', result.encoding
    assert_equal "a,b\n", result.text
  end

  def test_utf16be_with_bom
    result = Rufio::EncodingDetector.decode("\xFE\xFF".b + "a,b\n".encode('UTF-16BE').b)
    assert_equal 'UTF-16BE', result.encoding
    assert_equal "a,b\n", result.text
  end

  def test_undecodable_bytes_fall_back_to_replacement
    result = Rufio::EncodingDetector.decode("\x80\x81\x01\xFFz".b)
    assert_equal 'UTF-8', result.encoding
    assert result.replaced, '置換が発生したことを示すこと'
    assert_equal Encoding::UTF_8, result.text.encoding
    assert result.text.valid_encoding?
  end

  def test_explicit_encoding_is_respected
    result = Rufio::EncodingDetector.decode(JAPANESE.encode('CP932').b, encoding: 'CP932')
    assert_equal 'CP932', result.encoding
    assert_equal JAPANESE, result.text
  end

  def test_unknown_encoding_name_falls_back_to_auto
    result = Rufio::EncodingDetector.decode(JAPANESE.encode('CP932').b, encoding: 'NO-SUCH-ENCODING')
    assert_equal 'CP932', result.encoding
    assert_equal JAPANESE, result.text
  end

  def test_empty_input
    result = Rufio::EncodingDetector.decode(''.b)
    assert_equal '', result.text
    assert_equal 'UTF-8', result.encoding
  end

  # === read_text ===

  def test_read_text_reads_whole_file
    path = write_bytes('plain.csv', JAPANESE.dup.b)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 1024)
    assert_equal JAPANESE, result.text
    refute result.truncated
  end

  def test_read_text_cuts_at_line_boundary
    path = write_bytes('rows.csv', "aaa\nbbb\nccc\nddd\n".b)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 9)
    assert result.truncated
    assert_equal "aaa\nbbb\n", result.text, '上限内の最後の改行までで切ること'
  end

  def test_read_text_does_not_split_multibyte_characters
    # CP932 の 2 バイト文字の途中で上限に当たる長さを選ぶ
    bytes = "あいうえお\nかきくけこ\n".encode('CP932').b
    path = write_bytes('cp932.csv', bytes)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 13)

    assert result.truncated
    assert_equal 'CP932', result.encoding
    assert_equal "あいうえお\n", result.text
    assert result.text.valid_encoding?
  end

  def test_read_text_keeps_a_line_longer_than_the_limit
    # 1 行が上限より長い場合、改行まで戻すと行が丸ごと消えてしまう
    path = write_bytes('long_line.csv', "id,blob\n1,#{'x' * 200}\n".b)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 100)

    assert result.truncated
    assert_includes result.text, '1,xxx', '長い行を捨てずに途中まで読むこと'
    assert_equal 100, result.text.bytesize
  end

  def test_read_text_without_newline_falls_back_to_byte_limit
    path = write_bytes('oneline.csv', ('a' * 100).b)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 10)
    assert result.truncated
    assert_equal 'a' * 10, result.text
  end

  def test_read_text_on_empty_file
    path = write_bytes('empty.csv', ''.b)
    result = Rufio::EncodingDetector.read_text(path, max_bytes: 1024)
    assert_equal '', result.text
    refute result.truncated
  end
end
