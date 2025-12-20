# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/text_utils'

class TestTextUtils < Minitest::Test
  include Rufio::TextUtils

  def test_display_width_ascii
    assert_equal 5, Rufio::TextUtils.display_width('hello')
    assert_equal 11, Rufio::TextUtils.display_width('hello world')  # 'hello world' は11文字
    assert_equal 0, Rufio::TextUtils.display_width('')
  end

  def test_display_width_japanese
    # 日本語の全角文字は幅2
    assert_equal 10, Rufio::TextUtils.display_width('こんにちは')  # 5文字 × 2
    assert_equal 4, Rufio::TextUtils.display_width('世界')        # 2文字 × 2
    assert_equal 6, Rufio::TextUtils.display_width('日本語')      # 3文字 × 2
  end

  def test_display_width_mixed
    # 混在: hello(5) + 世界(4) = 9
    assert_equal 9, Rufio::TextUtils.display_width('hello世界')
    # 混在: test(4) + こんにちは(10) = 14
    assert_equal 14, Rufio::TextUtils.display_width('testこんにちは')
  end

  def test_display_width_full_width_symbols
    # 全角スペース、全角記号も幅2
    assert_equal 2, Rufio::TextUtils.display_width('　')  # 全角スペース
    assert_equal 2, Rufio::TextUtils.display_width('！')  # 全角感嘆符
  end

  def test_truncate_to_width_no_truncation_needed
    # 切り詰め不要な場合はそのまま返す
    result = Rufio::TextUtils.truncate_to_width('hello', 10)
    assert_equal 'hello', result
  end

  def test_truncate_to_width_ascii
    # ASCII文字列の切り詰め
    result = Rufio::TextUtils.truncate_to_width('hello world', 5)
    # max_width=5の場合、'he'(2) + '...'(3) = 5
    assert_equal 'he...', result

    result = Rufio::TextUtils.truncate_to_width('hello world', 8)
    # max_width=8の場合、'hello'(5) + '...'(3) = 8
    assert_equal 'hello...', result

    # max_width以下の場合はそのまま返す
    result = Rufio::TextUtils.truncate_to_width('hello', 10)
    assert_equal 'hello', result
  end

  def test_truncate_to_width_japanese
    # 日本語文字列の切り詰め
    result = Rufio::TextUtils.truncate_to_width('こんにちは', 5)
    # 幅5で切り詰める: 'こ'(2) + '...'(3) = 5
    assert_equal 'こ...', result

    result = Rufio::TextUtils.truncate_to_width('こんにちは', 8)
    # 幅8で切り詰める: 'こん'(4) + '...'(3) + 余り1 = 8
    # 実際には'こん'(4) + '...'(3) = 7
    assert_equal 'こん...', result
  end

  def test_truncate_to_width_mixed
    # 混在文字列の切り詰め
    result = Rufio::TextUtils.truncate_to_width('hello世界', 8)
    # hello(5) + '...'(3) = 8
    assert_equal 'hello...', result
  end

  def test_truncate_to_width_very_small
    # 非常に小さい幅
    result = Rufio::TextUtils.truncate_to_width('hello', 2)
    assert_equal 'he', result
  end

  def test_pad_string_to_width_padding_needed
    # パディングが必要な場合
    result = Rufio::TextUtils.pad_string_to_width('foo', 10)
    # 表示幅が10になることを確認（文字数ではない）
    assert_equal 10, Rufio::TextUtils.display_width(result)
    assert_equal 'foo       ', result
  end

  def test_pad_string_to_width_no_padding_needed
    # パディング不要（ちょうど）
    result = Rufio::TextUtils.pad_string_to_width('hello', 5)
    assert_equal 'hello', result
  end

  def test_pad_string_to_width_truncation_needed
    # 切り詰めが必要な場合
    result = Rufio::TextUtils.pad_string_to_width('hello world', 5)
    assert_equal 5, Rufio::TextUtils.display_width(result)
  end

  def test_pad_string_to_width_japanese
    # 日本語文字列のパディング
    result = Rufio::TextUtils.pad_string_to_width('世界', 10)
    # 世界(4) + スペース6 = 表示幅10
    assert_equal 10, Rufio::TextUtils.display_width(result)
    assert result.start_with?('世界')
    assert result.end_with?('      ')
  end

  def test_pad_string_to_width_mixed
    # 混在文字列のパディング
    result = Rufio::TextUtils.pad_string_to_width('hello世界', 15)
    # hello(5) + 世界(4) = 9, + スペース6 = 表示幅15
    assert_equal 15, Rufio::TextUtils.display_width(result)
  end

  def test_find_break_point_no_break_needed
    # 改行不要な場合
    result = Rufio::TextUtils.find_break_point('hello', 10)
    assert_equal 5, result
  end

  def test_find_break_point_ascii
    # ASCII文字列の改行位置
    result = Rufio::TextUtils.find_break_point('hello world test', 10)
    # "hello world"で11文字なので、10以内で区切る
    assert result <= 10
    assert result > 0
  end

  def test_find_break_point_with_space
    # スペースでの改行
    line = 'hello world test'
    result = Rufio::TextUtils.find_break_point(line, 12)
    # スペースで区切れる位置を優先
    assert result > 5  # "hello"より後
  end

  def test_find_break_point_japanese_punctuation
    # 日本語の句読点での改行
    line = 'これは、テストです。'
    result = Rufio::TextUtils.find_break_point(line, 10)
    assert result > 0
  end

  def test_find_break_point_no_good_break
    # 良い改行位置がない場合
    line = 'verylongword'
    result = Rufio::TextUtils.find_break_point(line, 5)
    assert_equal 5, result
  end

  def test_empty_string_handling
    # 空文字列の処理
    assert_equal 0, Rufio::TextUtils.display_width('')
    assert_equal '', Rufio::TextUtils.truncate_to_width('', 10)
    assert_equal '          ', Rufio::TextUtils.pad_string_to_width('', 10)
  end

  def test_single_character
    # 単一文字の処理
    assert_equal 1, Rufio::TextUtils.display_width('a')
    assert_equal 2, Rufio::TextUtils.display_width('あ')
    assert_equal 'a', Rufio::TextUtils.truncate_to_width('a', 5)
    assert_equal 'あ', Rufio::TextUtils.truncate_to_width('あ', 5)
  end
end
