# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

# SqliteTableSource: sqlite3 コマンドの呼び出し方、識別子のクォート、出力の解釈。
# sqlite3 が入っていない環境でも動くよう、コマンド実行は差し替えて検証する。
class TestSqliteTableSource < Minitest::Test
  TABLE_LIST = "items\nsales\n"
  ROWS = "id,name\n1,apple\n2,\"red, sweet\"\n"

  def setup
    @dir = Dir.mktmpdir('rufio_sqlite_test')
    @path = File.join(@dir, 'shop.db')
    File.binwrite(@path, "SQLite format 3\x00#{'x' * 64}")
    @calls = []
  end

  def teardown
    Rufio::SqliteTableSource.reset!
    FileUtils.rm_rf(@dir) if @dir && Dir.exist?(@dir)
  end

  # argv ごとに返す出力を決める偽のコマンド
  def with_runner(outputs = {}, ok: true)
    Rufio::SqliteTableSource.runner = lambda do |argv|
      @calls << argv
      sql = argv.last
      key = outputs.keys.find { |pattern| sql.include?(pattern) }
      [key ? outputs[key] : '', ok]
    end
    Rufio::SqliteTableSource.stub(:command_available?, true) { yield }
  ensure
    Rufio::SqliteTableSource.reset!
  end

  def open_db(**kwargs)
    Rufio::SqliteTableSource.open(@path, **kwargs)
  end

  # === supports? ===

  def test_not_supported_without_the_sqlite3_command
    Rufio::SqliteTableSource.stub(:command_available?, false) do
      refute Rufio::SqliteTableSource.supports?(@path), 'コマンドが無ければ表として扱わない'
    end
  end

  def test_supported_extensions_when_the_command_exists
    Rufio::SqliteTableSource.stub(:command_available?, true) do
      assert Rufio::SqliteTableSource.supports?(@path), 'shop.db'
      %w[shop.sqlite shop.sqlite3 other.DB].each do |name|
        path = File.join(@dir, name)
        FileUtils.cp(@path, path)
        assert Rufio::SqliteTableSource.supports?(path), name
      end
    end
  end

  def test_signature_is_recognised_without_a_known_extension
    path = File.join(@dir, 'store.data')
    FileUtils.cp(@path, path)

    Rufio::SqliteTableSource.stub(:command_available?, true) do
      assert Rufio::SqliteTableSource.supports?(path), '先頭のシグネチャで判定すること'
    end
  end

  def test_other_files_are_not_supported
    path = File.join(@dir, 'notes.txt')
    File.write(path, 'plain text')

    Rufio::SqliteTableSource.stub(:command_available?, true) do
      refute Rufio::SqliteTableSource.supports?(path)
      refute Rufio::SqliteTableSource.supports?(File.join(@dir, 'missing.db'))
    end
  end

  def test_registry_skips_sqlite_without_the_command
    Rufio::SqliteTableSource.stub(:command_available?, false) do
      assert_nil Rufio::PreviewRegistry.table_source_for(@path)
    end
  end

  # === 呼び出し方 ===

  def test_opens_the_database_read_only_and_as_csv
    with_runner({ 'sqlite_master' => TABLE_LIST }) { open_db }

    argv = @calls.first
    assert_equal 'sqlite3', argv[0]
    assert_includes argv, '-readonly'
    assert_includes argv, '-csv'
    assert_equal @path, argv[-2]
    assert_includes argv.last, 'FROM sqlite_master'
  end

  def test_table_query_is_a_select_with_a_limit
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM "items"' => ROWS }) do
      limits = Rufio::TableSource::Limits.new(max_bytes: 0, max_rows: 500, max_columns: 256)
      open_db(limits: limits).sheet(0).row_count
    end

    sql = @calls.last.last
    assert_match(/\ASELECT \* FROM "items" LIMIT 501;\z/, sql, '上限 + 1 行だけ読む')
    assert_includes @calls.last, '-header'
  end

  def test_table_names_are_quoted
    with_runner({ 'sqlite_master' => %("odd""name"\n), 'FROM' => ROWS }) do
      open_db.sheet(0).row_count
    end

    assert_includes @calls.last.last, '"odd""name"', '識別子クォートを二重にすること'
  end

  # === 出力の解釈 ===

  def test_lists_tables_as_sheets
    document = with_runner({ 'sqlite_master' => TABLE_LIST }) { open_db }

    assert_equal 2, document.sheet_count
    assert_equal %w[items sales], document.sheets.map(&:name)
  end

  def test_reads_rows_with_a_header
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM "items"' => ROWS }) do
      sheet = open_db.sheet(0)

      assert_equal %w[id name], sheet.header
      assert_equal 2, sheet.row_count
      assert_equal [%w[1 apple], ['2', 'red, sweet']], sheet.fetch_rows(0, 10)
    end
  end

  def test_tables_are_queried_only_when_used
    document = with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => ROWS }) do
      doc = open_db
      assert_equal 1, @calls.length, 'テーブル一覧だけを引くこと'
      doc.sheet(0).row_count
      assert_equal 2, @calls.length
      doc
    end

    assert_equal [true, false], document.sheets.map(&:loaded?)
  end

  def test_row_limit_marks_truncation
    rows = "id\n#{(1..10).map(&:to_s).join("\n")}\n"
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => rows }) do
      limits = Rufio::TableSource::Limits.new(max_bytes: 0, max_rows: 5, max_columns: 256)
      sheet = open_db(limits: limits).sheet(0)

      assert sheet.row_truncated
      assert_equal 5, sheet.row_count
    end
  end

  def test_column_limit_marks_truncation
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => "a,b,c\n1,2,3\n" }) do
      limits = Rufio::TableSource::Limits.new(max_bytes: 0, max_rows: 100, max_columns: 2)
      sheet = open_db(limits: limits).sheet(0)

      assert sheet.column_truncated
      assert_equal 2, sheet.column_count
    end
  end

  def test_null_values_become_empty_cells
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => "a,b\n1,\n" }) do
      assert_equal [['1', '']], open_db.sheet(0).fetch_rows(0, 10)
    end
  end

  # === 失敗の扱い ===

  def test_a_database_without_tables_raises_parse_error
    with_runner({ 'sqlite_master' => '' }) do
      error = assert_raises(Rufio::TableSource::ParseError) { open_db }
      assert_includes error.message, 'no tables'
    end
  end

  def test_a_failing_command_raises_parse_error
    with_runner({ 'sqlite_master' => '' }, ok: false) do
      error = assert_raises(Rufio::TableSource::ParseError) { open_db }
      assert_includes error.message, 'sqlite3 failed'
    end
  end

  def test_a_table_that_fails_to_read_is_empty_instead_of_raising
    calls = 0
    Rufio::SqliteTableSource.runner = lambda do |_argv|
      calls += 1
      calls == 1 ? [TABLE_LIST, true] : ['', false]
    end

    Rufio::SqliteTableSource.stub(:command_available?, true) do
      sheet = open_db.sheet(0)
      assert_equal 0, sheet.row_count, '読めないテーブルは空として扱う'
      assert_includes sheet.load_error, 'sqlite3 failed'
    end
  ensure
    Rufio::SqliteTableSource.reset!
  end
end
