# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# 表プレビューの上限・表示設定は既定値で動き、config.rb の TABLE_PREVIEW で変更できる。
class TestTablePreviewConfig < Minitest::Test
  DEFAULTS = {
    max_bytes: 65_536, max_rows: 1000, max_columns: 256, max_column_width: 32,
    header: true, delimiter: 'auto', encoding: 'auto'
  }.freeze

  def table_config(value)
    Rufio::ConfigLoader.stub(:load_config, { table_preview: value }) { Rufio::ConfigLoader.table_preview }
  end

  def test_defaults_without_setting
    assert_equal DEFAULTS, Rufio::ConfigLoader.stub(:load_config, {}) { Rufio::ConfigLoader.table_preview }
    assert_equal DEFAULTS, table_config(nil)
    assert_equal DEFAULTS, table_config([1, 2])
  end

  def test_byte_limit_matches_the_text_preview_default
    assert_equal Rufio::FilePreview::MAX_PREVIEW_BYTES, DEFAULTS[:max_bytes]
  end

  def test_partial_setting_is_merged_with_defaults
    assert_equal DEFAULTS.merge(max_rows: 50, max_column_width: 12),
                 table_config({ max_rows: 50, max_column_width: 12 })
  end

  def test_values_are_clamped_to_the_limits
    high = table_config({ max_bytes: 10**9, max_rows: 10**9, max_columns: 10**9, max_column_width: 10**9 })
    assert_equal Rufio::ConfigLoader::MAX_TABLE_PREVIEW[:max_bytes], high[:max_bytes]
    assert_equal Rufio::ConfigLoader::MAX_TABLE_PREVIEW[:max_rows], high[:max_rows]
    assert_equal Rufio::ConfigLoader::MAX_TABLE_PREVIEW[:max_columns], high[:max_columns]
    assert_equal Rufio::ConfigLoader::MAX_TABLE_PREVIEW[:max_column_width], high[:max_column_width]

    low = table_config({ max_bytes: 0, max_rows: 0, max_columns: 0, max_column_width: 0 })
    assert_equal Rufio::ConfigLoader::MIN_TABLE_PREVIEW, low.slice(*Rufio::ConfigLoader::MIN_TABLE_PREVIEW.keys)
  end

  def test_invalid_numbers_fall_back_to_defaults
    assert_equal DEFAULTS, table_config({ max_bytes: '64', max_rows: 1.5, max_columns: nil, max_column_width: true })
  end

  def test_header_can_be_disabled
    refute table_config({ header: false })[:header]
    assert table_config({ header: true })[:header]
    assert table_config({ header: 'yes' })[:header], '明示的な false 以外はヘッダありとして扱う'
  end

  def test_delimiter_and_encoding_accept_strings_only
    config = table_config({ delimiter: ';', encoding: 'CP932' })
    assert_equal ';', config[:delimiter]
    assert_equal 'CP932', config[:encoding]

    fallback = table_config({ delimiter: 1, encoding: :cp932 })
    assert_equal 'auto', fallback[:delimiter]
    assert_equal 'auto', fallback[:encoding]
  end
end
