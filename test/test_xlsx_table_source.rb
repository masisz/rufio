# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'
require_relative 'support/xlsx_fixture'

# XlsxTableSource: シートの一覧、遅延読み込み、空セルの桁合わせ、上限
class TestXlsxTableSource < Minitest::Test
  include XlsxFixture

  def setup
    @dir = Dir.mktmpdir('rufio_xlsx_test')
    @path = File.join(@dir, 'book.xlsx')
    write_xlsx(@path, [
                 ['Sales', [%w[name price], ['apple', 120], ['みかん', 150]]],
                 ['Stock', [%w[item count], ['apple', 30]]]
               ])
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir && Dir.exist?(@dir)
  end

  def open_book(path = @path, **kwargs)
    Rufio::XlsxTableSource.open(path, **kwargs)
  end

  # === supports? ===

  def test_supports_spreadsheet_extensions
    assert Rufio::XlsxTableSource.supports?('a.xlsx')
    assert Rufio::XlsxTableSource.supports?('a.XLSX')
    assert Rufio::XlsxTableSource.supports?('a.xlsm')
    assert Rufio::XlsxTableSource.supports?('a.ods')
    refute Rufio::XlsxTableSource.supports?('a.csv')
    refute Rufio::XlsxTableSource.supports?('a.zip')
  end

  def test_registry_routes_xlsx_here
    assert_equal Rufio::XlsxTableSource, Rufio::PreviewRegistry.table_source_for('a.xlsx')
  end

  # === シート ===

  def test_lists_every_sheet
    document = open_book
    assert_equal 2, document.sheet_count
    assert_equal %w[Sales Stock], document.sheets.map(&:name)
  end

  def test_reads_the_first_sheet
    sheet = open_book.sheet
    assert_equal %w[name price], sheet.header
    assert_equal 2, sheet.row_count
    assert_equal [['apple', '120'], ['みかん', '150']], sheet.fetch_rows(0, 10)
  end

  def test_reads_a_later_sheet
    sheet = open_book.sheet(1)
    assert_equal %w[item count], sheet.header
    assert_equal [%w[apple 30]], sheet.fetch_rows(0, 10)
  end

  def test_sheets_are_read_only_when_used
    document = open_book
    assert_equal [false, false], document.sheets.map(&:loaded?)

    document.sheet(0).row_count
    assert_equal [true, false], document.sheets.map(&:loaded?),
                 '表示していないシートは読まないこと'
  end

  def test_status_line_names_the_sheet
    document = open_book
    assert_includes document.status_line(1), '2/2 Stock'
  end

  # === セルの値 ===

  def test_integers_keep_no_decimal_point
    path = File.join(@dir, 'numbers.xlsx')
    write_xlsx(path, [['S', [%w[a b], [120, 1.5]]]])
    assert_equal [['120', '1.5']], open_book(path).sheet.fetch_rows(0, 10)
  end

  def test_empty_cells_keep_the_columns_aligned
    path = File.join(@dir, 'gaps.xlsx')
    write_xlsx(path, [['S', [%w[a b c], ['x', nil, 'z']]]])
    row = open_book(path).sheet.fetch_rows(0, 1).first

    assert_equal 3, row.length, '空セルを詰めずに桁を保つこと'
    assert_equal 'x', row[0]
    assert_equal '', row[1]
    assert_equal 'z', row[2]
  end

  def test_header_can_be_disabled
    sheet = open_book(@path, options: { header: false }).sheet
    assert_nil sheet.header
    assert_equal 3, sheet.row_count
  end

  # === 上限 ===

  def test_row_limit_marks_truncation
    path = File.join(@dir, 'many.xlsx')
    rows = [%w[id]] + (1..30).map { |i| [i.to_s] }
    write_xlsx(path, [['S', rows]])

    limits = Rufio::TableSource::Limits.new(max_bytes: 64 * 1024, max_rows: 10, max_columns: 256)
    sheet = open_book(path, limits: limits).sheet

    assert sheet.row_truncated
    assert_equal 9, sheet.row_count
  end

  def test_column_limit_marks_truncation
    limits = Rufio::TableSource::Limits.new(max_bytes: 64 * 1024, max_rows: 1000, max_columns: 1)
    sheet = open_book(@path, limits: limits).sheet

    assert sheet.column_truncated
    assert_equal 1, sheet.column_count
  end

  # === OpenDocument（.ods） ===

  def test_reads_an_ods_file
    path = File.join(@dir, 'book.ods')
    write_ods(path, [['Sheet1', [%w[name price], ['みかん', 150]]]])
    sheet = open_book(path).sheet

    assert_equal %w[name price], sheet.header
    assert_equal [['みかん', '150']], sheet.fetch_rows(0, 10),
                 'Roo::OpenOffice にストリーミング API が無くても読めること'
  end

  def test_ods_row_limit
    path = File.join(@dir, 'many.ods')
    write_ods(path, [['S', [%w[id]] + (1..20).map { |i| [i.to_s] }]])
    limits = Rufio::TableSource::Limits.new(max_bytes: 0, max_rows: 5, max_columns: 256)
    sheet = open_book(path, limits: limits).sheet

    assert sheet.row_truncated
    assert_equal 4, sheet.row_count
  end

  # === 失敗の扱い ===

  def test_a_file_that_is_not_a_spreadsheet_raises_parse_error
    path = File.join(@dir, 'broken.xlsx')
    File.write(path, 'not a spreadsheet')

    assert_raises(Rufio::TableSource::ParseError) { open_book(path) }
  end

  def test_an_oversized_file_raises_parse_error
    path = File.join(@dir, 'big.xlsx')
    File.write(path, 'x')
    File.stub(:size, Rufio::XlsxTableSource::MAX_FILE_SIZE + 1) do
      error = assert_raises(Rufio::TableSource::ParseError) { open_book(path) }
      assert_includes error.message, 'larger than'
    end
  end

  def test_an_unreadable_sheet_is_empty_instead_of_raising
    sheet = Rufio::LazyTableSheet.new(name: 'boom') { raise 'sheet is broken' }

    assert_equal 0, sheet.row_count
    assert sheet.empty?
    assert_equal 'sheet is broken', sheet.load_error
  end
end
