# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/text_utils'
require_relative '../lib/rufio/file_preview'
require 'tmpdir'
require 'fileutils'

class TestEncodingErrorHandling < Minitest::Test
  include Rufio::TextUtils

  def setup
    @temp_dir = Dir.mktmpdir
    @file_preview = Rufio::FilePreview.new
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_wrap_preview_lines_with_invalid_utf8
    # 不正なUTF-8バイトシーケンスを含む行
    invalid_line = "Valid text \x80\x81 more text"
    lines = [invalid_line]

    # wrap_preview_linesがクラッシュせずに動作する
    result = Rufio::TextUtils.wrap_preview_lines(lines, 50)

    assert_kind_of Array, result
    refute_empty result
    # 不正な文字は?に置換される
    assert_includes result.first, '?'
  end

  def test_wrap_preview_lines_with_mixed_encoding
    # 複数のエンコーディング問題を含む行
    lines = [
      "Normal line",
      "Line with \x80 invalid bytes",
      "",
      "Another normal line"
    ]

    result = Rufio::TextUtils.wrap_preview_lines(lines, 50)

    assert_equal 4, result.length
    assert_equal "Normal line", result[0]
    assert_equal "", result[2]
    assert_equal "Another normal line", result[3]
  end

  def test_file_preview_with_invalid_utf8_file
    # 不正なUTF-8を含むファイルを作成
    test_file = File.join(@temp_dir, 'invalid_utf8.txt')
    File.open(test_file, 'wb') do |f|
      f.write("Line 1: Normal text\n")
      f.write("Line 2: Invalid \x80\x81\x82 bytes\n")
      f.write("Line 3: More text\n")
    end

    # プレビューがクラッシュせずに動作する
    result = @file_preview.preview_file(test_file)

    assert_equal 'text', result[:type]
    assert_kind_of Array, result[:lines]
    assert_equal 3, result[:lines].length

    # 各行が文字列である
    result[:lines].each do |line|
      assert_kind_of String, line
    end
  end

  def test_file_preview_with_binary_like_content
    # バイナリっぽいが一部テキストを含むファイル
    test_file = File.join(@temp_dir, 'mixed_content.txt')
    File.open(test_file, 'wb') do |f|
      # 主にテキスト（バイナリ閾値未満）
      f.write("Normal text line 1\n")
      f.write("Normal text line 2\n")
      f.write("Some weird \x01\x02 characters\n")
      f.write("Normal text line 3\n")
    end

    result = @file_preview.preview_file(test_file)

    assert_includes ['text', 'binary'], result[:type]
    assert_kind_of Array, result[:lines]
  end

  def test_wrap_preview_lines_with_very_long_line
    # 非常に長い行（エンコーディングエラーと組み合わせ）
    long_line = "a" * 100 + "\x80" + "b" * 100
    lines = [long_line]

    result = Rufio::TextUtils.wrap_preview_lines(lines, 50)

    assert_kind_of Array, result
    # 複数行に分割される
    assert result.length > 1
  end

  def test_wrap_preview_lines_with_empty_and_nil_cases
    # エッジケース
    assert_equal [], Rufio::TextUtils.wrap_preview_lines([], 50)
    assert_equal [''], Rufio::TextUtils.wrap_preview_lines([''], 50)

    # nil が含まれる場合
    lines = ['text', nil, 'more text'].compact
    result = Rufio::TextUtils.wrap_preview_lines(lines, 50)
    assert_equal 2, result.length
  end

  def test_file_preview_with_shift_jis_file
    # Shift_JISファイルを作成
    test_file = File.join(@temp_dir, 'shift_jis.txt')
    content = "これはShift_JISのテストです"

    begin
      File.open(test_file, 'w:Shift_JIS') do |f|
        f.write(content)
      end

      result = @file_preview.preview_file(test_file)

      # UTF-8またはShift_JISとして読み込まれる
      assert_includes ['text', 'code'], result[:type]
      assert_kind_of Array, result[:lines]
      refute_empty result[:lines]
    rescue Encoding::ConverterNotFoundError
      # Shift_JISが利用できない環境ではスキップ
      skip "Shift_JIS encoding not available"
    end
  end
end
