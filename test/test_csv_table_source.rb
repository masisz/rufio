# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

# CsvTableSource: 区切り判定・上限・壊れた CSV・文字コード
class TestCsvTableSource < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir('rufio_csv_source_test')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def write(name, content)
    path = File.join(@test_dir, name)
    # セル内改行を含むフィクスチャがあるので、どの OS でも書いたバイト列のままにする
    File.binwrite(path, content)
    path
  end

  def open_source(path, **kwargs)
    Rufio::CsvTableSource.open(path, **kwargs)
  end

  # === supports? ===

  def test_supports_csv_tsv_tab
    assert Rufio::CsvTableSource.supports?('a.csv')
    assert Rufio::CsvTableSource.supports?('a.CSV')
    assert Rufio::CsvTableSource.supports?('a.tsv')
    assert Rufio::CsvTableSource.supports?('a.tab')
  end

  def test_does_not_support_other_extensions
    refute Rufio::CsvTableSource.supports?('a.txt')
    refute Rufio::CsvTableSource.supports?('a.rb')
    refute Rufio::CsvTableSource.supports?('a')
  end

  # === 基本のパース ===

  def test_parses_header_and_rows
    path = write('sales.csv', "name,price\napple,120\nbanana,80\n")
    sheet = open_source(path).sheet

    assert_equal %w[name price], sheet.header
    assert_equal 2, sheet.row_count
    assert_equal 2, sheet.column_count
    assert_equal [%w[apple 120], %w[banana 80]], sheet.fetch_rows(0, 10)
  end

  def test_header_can_be_disabled
    path = write('sales.csv', "apple,120\nbanana,80\n")
    sheet = open_source(path, options: { header: false }).sheet

    assert_nil sheet.header
    assert_equal 2, sheet.row_count
  end

  def test_empty_cells_become_empty_strings
    path = write('gaps.csv', "a,b,c\n1,,3\n")
    row = open_source(path).sheet.fetch_rows(0, 1).first

    assert_equal ['1', '', '3'], row
  end

  def test_quoted_cell_keeps_comma_and_newline
    path = write('quoted.csv', %(name,note\napple,"red, sweet"\nmikan,"two\nlines"\n))
    rows = open_source(path).sheet.fetch_rows(0, 2)

    assert_equal 'red, sweet', rows[0][1]
    assert_equal "two\nlines", rows[1][1], 'セル内改行は生の値として保持する'
  end

  def test_tsv_uses_tab
    path = write('data.tsv', "name\tprice\napple\t120\n")
    sheet = open_source(path).sheet

    assert_equal %w[name price], sheet.header
    assert_equal [%w[apple 120]], sheet.fetch_rows(0, 10)
  end

  def test_semicolon_is_detected_for_csv
    path = write('euro.csv', "name;price;stock\napple;120;30\n")
    sheet = open_source(path).sheet

    assert_equal %w[name price stock], sheet.header
    assert_equal [%w[apple 120 30]], sheet.fetch_rows(0, 10)
  end

  def test_configured_delimiter_wins
    path = write('pipe.csv', "name|price\napple|120\n")
    sheet = open_source(path, options: { delimiter: '|' }).sheet

    assert_equal %w[name price], sheet.header
  end

  # === 上限 ===

  def test_row_limit_marks_truncation
    rows = (1..50).map { |i| "r#{i},#{i}" }.join("\n")
    path = write('many.csv', "a,b\n#{rows}\n")
    limits = Rufio::TableSource::Limits.new(max_bytes: 64 * 1024, max_rows: 10, max_columns: 256)
    sheet = open_source(path, limits: limits).sheet

    assert sheet.row_truncated
    assert_equal 9, sheet.row_count, 'ヘッダ 1 行を含めて max_rows で切ること'
  end

  def test_column_limit_marks_truncation
    path = write('wide.csv', "a,b,c,d\n1,2,3,4\n")
    limits = Rufio::TableSource::Limits.new(max_bytes: 64 * 1024, max_rows: 1000, max_columns: 2)
    sheet = open_source(path, limits: limits).sheet

    assert sheet.column_truncated
    assert_equal 2, sheet.column_count
    assert_equal [%w[1 2]], sheet.fetch_rows(0, 10)
  end

  def test_byte_limit_marks_document
    path = write('big.csv', "a,b\n#{(1..200).map { |i| "#{i},#{i}" }.join("\n")}\n")
    limits = Rufio::TableSource::Limits.new(max_bytes: 64, max_rows: 1000, max_columns: 256)
    document = open_source(path, limits: limits)

    assert document.byte_truncated
    assert document.truncated?
  end

  # === 壊れた CSV ===

  def test_unbalanced_quote_is_read_with_liberal_parsing
    path = write('broken.csv', %(name,note\napple,"unclosed\nbanana,ok\n))
    document = open_source(path)

    assert_equal %w[name note], document.sheet.header
    assert_operator document.sheet.row_count, :>=, 1
  end

  def test_stray_quote_inside_unquoted_field_is_tolerated
    path = write('stray.csv', %(a,b\n"x" y,z\n))
    rows = open_source(path).sheet.fetch_rows(0, 1)

    assert_equal 1, rows.length
    assert_equal 'z', rows[0][1]
  end

  def test_cell_cut_in_the_middle_of_a_quoted_field_still_parses
    # バイト上限が引用符つきセルの途中に当たったときと同じ入力
    path = write('cut.csv', %(name,note\napple,"long note that was cut\n))
    document = open_source(path)

    assert_equal %w[name note], document.sheet.header
    assert_equal 1, document.sheet.row_count
    assert_includes document.sheet.fetch_rows(0, 1).first[1], 'long note'
  end

  # === 文字コード ===

  def test_cp932_file_is_decoded
    path = write('cp932.csv', "商品,単価\nみかん,150\n".encode('CP932').b)
    document = open_source(path)

    assert_equal 'CP932', document.encoding
    assert_equal %w[商品 単価], document.sheet.header
    assert_equal [%w[みかん 150]], document.sheet.fetch_rows(0, 10)
  end

  def test_utf16le_tsv_is_decoded
    bytes = "\xFF\xFE".b + "name\tprice\r\napple\t120\r\n".encode('UTF-16LE').b
    path = write('excel.tsv', bytes)
    document = open_source(path)

    assert_equal 'UTF-16LE', document.encoding
    assert_equal %w[name price], document.sheet.header
  end

  # === シート ===

  def test_single_sheet_with_file_name
    path = write('sales.csv', "a,b\n1,2\n")
    document = open_source(path)

    assert_equal 1, document.sheet_count
    assert_equal 'sales.csv', document.sheet.name
  end

  def test_column_labels_are_spreadsheet_style
    path = write('wide.csv', "#{(1..30).map { |i| "c#{i}" }.join(',')}\n")
    sheet = open_source(path).sheet

    assert_equal 'A', sheet.column_label(0)
    assert_equal 'Z', sheet.column_label(25)
    assert_equal 'AA', sheet.column_label(26)
    assert_equal 'AD', sheet.column_label(29)
  end

  def test_column_title_includes_header_text
    path = write('sales.csv', "name,price\napple,120\n")
    sheet = open_source(path).sheet

    assert_equal 'A name', sheet.column_title(0)
    assert_equal 'B price', sheet.column_title(1)
  end

  def test_fetch_rows_out_of_range
    path = write('sales.csv', "a,b\n1,2\n")
    sheet = open_source(path).sheet

    assert_empty sheet.fetch_rows(10, 5)
    assert_empty sheet.fetch_rows(-1, 5)
    assert_empty sheet.fetch_rows(0, 0)
  end
end
