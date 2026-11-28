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

  # -safe を使えるかの確認（:memory: への問い合わせ）を除いた、実データへの問い合わせ
  def queries
    @calls.reject { |argv| argv.include?(':memory:') }
  end

  # === supports? ===

  def test_not_supported_without_the_sqlite3_command
    Rufio::SqliteTableSource.stub(:command_available?, false) do
      refute Rufio::SqliteTableSource.supports?(@path), 'コマンドが無ければ表として扱わない'
    end
  end

  def test_any_extension_is_recognised_by_the_signature
    Rufio::SqliteTableSource.stub(:command_available?, true) do
      assert Rufio::SqliteTableSource.supports?(@path), 'shop.db'
      %w[shop.sqlite store.data archive].each do |name|
        path = File.join(@dir, name)
        FileUtils.cp(@path, path)
        assert Rufio::SqliteTableSource.supports?(path), name
      end
    end
  end

  def test_other_files_are_not_supported
    text = File.join(@dir, 'notes.txt')
    File.write(text, 'plain text')
    impostor = File.join(@dir, 'impostor.db')
    File.write(impostor, 'this is not a database')

    Rufio::SqliteTableSource.stub(:command_available?, true) do
      refute Rufio::SqliteTableSource.supports?(text)
      refute Rufio::SqliteTableSource.supports?(impostor), '拡張子だけで判定しないこと'
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

    argv = queries.first
    assert_equal 'sqlite3', argv[0]
    assert_includes argv, '-readonly'
    assert_includes argv, '-csv'
    assert_equal @path, argv[-2]
    assert_includes argv.last, 'FROM sqlite_master'
  end

  # === 安全側の既定（-safe と絶対パス） ===

  def test_safe_mode_is_checked_once_and_then_used
    with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => ROWS }) do
      open_db.sheet(0).row_count
      open_db.sheet(0).row_count
    end

    probes = @calls.select { |argv| argv.include?(':memory:') }
    assert_equal 1, probes.length, '-safe の確認はプロセスで 1 度だけ'
    assert_equal %w[sqlite3 -safe -csv :memory: SELECT\ 1;], probes.first.map(&:to_s)
    queries.each { |argv| assert_includes argv, '-safe', "#{argv.inspect} に -safe が入ること" }
  end

  def test_safe_mode_is_dropped_when_the_command_does_not_support_it
    # 古い sqlite3 は -safe を知らず、確認が失敗する
    Rufio::SqliteTableSource.runner = lambda do |argv|
      @calls << argv
      argv.include?(':memory:') ? ['', false] : [TABLE_LIST, true]
    end

    Rufio::SqliteTableSource.stub(:command_available?, true) { open_db }

    refute_includes queries.first, '-safe', '使えないときは付けないこと'
    assert_includes queries.first, '-readonly'
  ensure
    Rufio::SqliteTableSource.reset!
  end

  def test_the_database_path_is_absolute_so_a_dash_is_not_an_option
    with_runner({ 'sqlite_master' => TABLE_LIST }) do
      Dir.chdir(@dir) do
        File.binwrite('-weird.db', "SQLite format 3\x00#{'x' * 32}")
        Rufio::SqliteTableSource.open('-weird.db')
      end
    end

    path_argument = queries.first[-2]
    assert File.absolute_path?(path_argument), "#{path_argument.inspect} が絶対パスであること"
    refute path_argument.start_with?('-')
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
      assert_equal 1, queries.length, 'テーブル一覧だけを引くこと'
      doc.sheet(0).row_count
      assert_equal 2, queries.length
      doc
    end

    assert_equal [true, false], document.sheets.map(&:loaded?)
  end

  def test_the_table_list_is_labelled_as_tables
    document = with_runner({ 'sqlite_master' => TABLE_LIST }) { open_db }

    assert_equal 'Tables', document.sheet_label, '一覧の見出しは「シート」ではなく「テーブル」にすること'
  end

  def test_the_table_list_does_not_read_any_table
    document = with_runner({ 'sqlite_master' => TABLE_LIST, 'FROM' => ROWS }) do
      doc = open_db
      view = Rufio::TablePreviewView.new(doc, path: @path)

      assert view.handle_key('t'), 't でテーブル一覧を開くこと'
      assert_equal %w[items sales], view.picker.names
      assert_equal 'Tables (2)', view.picker_title
      assert_equal 1, queries.length, '一覧を出すだけではテーブルの中身を読まないこと'
      doc
    end

    assert_equal [false, false], document.sheets.map(&:loaded?)
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

  # === 出力の文字コード ===

  def test_output_in_the_default_external_encoding_is_read_as_utf8
    # コマンドの出力は Encoding.default_external になる。LANG が無い環境では US-ASCII で、
    # そのまま CSV に渡すと日本語を含むテーブルが「Invalid byte sequence」になる
    ascii_tables = "products\n".dup.force_encoding(Encoding::US_ASCII)
    ascii_rows = "name,note\nみかん,冬の定番\n".dup.force_encoding(Encoding::US_ASCII)

    with_runner({ 'sqlite_master' => ascii_tables, 'FROM' => ascii_rows }) do
      sheet = open_db.sheet(0)

      assert_nil sheet.load_error
      assert_equal %w[name note], sheet.header
      assert_equal [%w[みかん 冬の定番]], sheet.fetch_rows(0, 10)
      assert_equal Encoding::UTF_8, sheet.fetch_rows(0, 1).first.first.encoding
    end
  end

  def test_invalid_bytes_in_the_output_are_replaced
    broken = "a\n\xFF\xFE\n".dup.force_encoding(Encoding::ASCII_8BIT)
    with_runner({ 'sqlite_master' => "t\n", 'FROM' => broken }) do
      sheet = open_db.sheet(0)

      assert_nil sheet.load_error, '不正なバイトでも読み込みを止めないこと'
      assert sheet.fetch_rows(0, 1).first.first.valid_encoding?
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
    Rufio::SqliteTableSource.runner = lambda do |argv|
      sql = argv.last
      ok = argv.include?(':memory:') || sql.include?('sqlite_master')
      [ok ? TABLE_LIST : '', ok]
    end

    Rufio::SqliteTableSource.stub(:command_available?, true) do
      sheet = open_db.sheet(0)
      assert_equal 0, sheet.row_count, '読めないテーブルは空として扱う'
      assert_includes sheet.load_error, 'sqlite3 failed'
    end
  ensure
    Rufio::SqliteTableSource.reset!
  end

  # === 実際の sqlite3 コマンドを使った確認 ===
  # コマンドが無い環境（CI など）では skip する

  def sqlite3_or_skip
    skip 'sqlite3 コマンドがない' unless Rufio::CommandLocator.available?('sqlite3')
  end

  def build_database(path, sql)
    IO.popen(['sqlite3', path], 'w') { |io| io.write(sql) }
    assert File.exist?(path)
    path
  end

  def real_database
    build_database(File.join(@dir, 'real.db'), <<~SQL)
      CREATE TABLE products (id INTEGER, name TEXT, price REAL, note TEXT);
      INSERT INTO products VALUES (1, 'apple', 120.0, 'red, sweet');
      INSERT INTO products VALUES (2, 'みかん', 150.5, '冬の定番');
      INSERT INTO products VALUES (3, 'banana', 80.0, NULL);
      CREATE TABLE "odd name" (a TEXT);
      INSERT INTO "odd name" VALUES ('quoted "value"');
      CREATE VIEW cheap AS SELECT name FROM products WHERE price < 100;
    SQL
  end

  def test_real_database_is_recognised
    sqlite3_or_skip
    path = real_database

    assert Rufio::SqliteTableSource.supports?(path)
    assert_equal Rufio::SqliteTableSource, Rufio::PreviewRegistry.table_source_for(path)
  end

  def test_real_database_lists_tables_and_views
    sqlite3_or_skip
    document = Rufio::SqliteTableSource.open(real_database)

    assert_equal ['cheap', 'odd name', 'products'], document.sheets.map(&:name)
  end

  def test_real_database_reads_rows_with_japanese_and_nulls
    sqlite3_or_skip
    sheet = Rufio::SqliteTableSource.open(real_database).sheets.find { |s| s.name == 'products' }

    assert_nil sheet.load_error
    assert_equal %w[id name price note], sheet.header
    assert_equal 3, sheet.row_count
    assert_equal ['1', 'apple', '120.0', 'red, sweet'], sheet.fetch_rows(0, 1).first
    assert_equal ['2', 'みかん', '150.5', '冬の定番'], sheet.fetch_rows(1, 1).first
    assert_equal '', sheet.fetch_rows(2, 1).first.last, 'NULL は空セルになること'
  end

  def test_real_database_quotes_odd_table_names
    sqlite3_or_skip
    sheet = Rufio::SqliteTableSource.open(real_database).sheets.find { |s| s.name == 'odd name' }

    assert_equal [['quoted "value"']], sheet.fetch_rows(0, 10)
  end

  def test_real_database_respects_the_row_limit
    sqlite3_or_skip
    path = build_database(File.join(@dir, 'many.db'), <<~SQL)
      CREATE TABLE numbers (n INTEGER);
      INSERT INTO numbers SELECT value FROM generate_series(1, 50);
    SQL

    limits = Rufio::TableSource::Limits.new(max_bytes: 0, max_rows: 10, max_columns: 256)
    sheet = Rufio::SqliteTableSource.open(path, limits: limits).sheet

    assert sheet.row_truncated
    assert_equal 10, sheet.row_count
  end

  def test_real_database_is_opened_read_only
    sqlite3_or_skip
    path = real_database
    before = File.read(path, mode: 'rb')

    output = IO.popen(['sqlite3', '-readonly', path, "INSERT INTO products VALUES (9,'x',1,'y');"],
                      err: [:child, :out], &:read)

    assert_includes output, 'readonly'
    assert_equal before, File.read(path, mode: 'rb'), 'データベースが変わらないこと'
  end

  def test_a_file_that_is_not_a_database_is_not_supported
    sqlite3_or_skip
    path = File.join(@dir, 'fake.db')
    File.write(path, 'this is not a database')

    refute Rufio::SqliteTableSource.supports?(path), 'シグネチャが違えば表として扱わない'
  end

  def test_an_empty_database_raises_parse_error
    sqlite3_or_skip
    path = build_database(File.join(@dir, 'empty.db'), "CREATE TABLE t (a TEXT); DROP TABLE t;
")

    assert_raises(Rufio::TableSource::ParseError) { Rufio::SqliteTableSource.open(path) }
  end

  def test_file_preview_shows_a_real_database_as_a_grid
    sqlite3_or_skip
    preview = Rufio::FilePreview.new.preview_file(real_database)

    assert_equal 'table', preview[:type]
    assert(preview[:lines].any? { |line| line.include?('A name') })
  end
end
