# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'
require_relative 'support/xlsx_fixture'

# 表プレビューの `/`: 行の絞り込み（SQLite は SQL を内部で実行、CSV / Excel は Ruby 側で判定）
class TestTableSearch < Minitest::Test
  include XlsxFixture

  CSV_CONTENT = <<~CSV
    name,price,stock
    apple,120,30
    みかん,150,8
    banana,80,12
    melon,300,2
  CSV

  def setup
    @dir = Dir.mktmpdir('rufio_table_search')
    @csv = File.join(@dir, 'sales.csv')
    File.write(@csv, CSV_CONTENT)
  end

  def teardown
    Rufio::PreviewRegistry.reset!
    Rufio::SqliteTableSource.reset!
    FileUtils.rm_rf(@dir) if @dir
  end

  def view_for(path = @csv)
    view = Rufio::PreviewView.build(path)
    assert view.table?, "#{path} が表として読めること"
    view
  end

  def filter(view, text)
    assert view.handle_key('/')
    text.each_char { |char| view.handle_key(char) }
    view.handle_key("\r")
    view
  end

  def names(view)
    view.sheet.fetch_rows(0, view.sheet.row_count).map(&:first)
  end

  # === 入力 ===

  def test_slash_opens_the_filter_prompt
    view = view_for

    assert view.handle_key('/')
    assert view.search_prompt_open?
    assert_includes view.status_line, '/'
  end

  def test_typing_builds_the_query_and_does_not_move_the_cursor
    view = view_for
    view.handle_key('/')
    'price > 100'.each_char { |char| view.handle_key(char) }

    assert_equal 'price > 100', view.search_query
    assert_includes view.status_line, '/price > 100'
    assert_equal 0, view.cursor.row
    assert_equal 4, view.sheet.row_count, '確定するまで絞り込まないこと'
  end

  def test_the_filter_key_follows_the_keybind_setting
    rebound = Rufio::ConfigLoader.default_keybinds.merge(search: 'S')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = view_for
      assert view.handle_key('S')
      assert view.search_prompt_open?
    end
  end

  # === CSV の絞り込み（Ruby 側で判定） ===

  def test_enter_applies_the_filter
    view = filter(view_for, 'price > 130')

    assert_equal %w[みかん melon], names(view)
    assert_equal 2, view.sheet.row_count
    refute view.search_prompt_open?
  end

  def test_several_conditions_are_joined_with_and
    view = filter(view_for, 'price > 100, name m%')

    assert_equal %w[melon], names(view)
  end

  def test_a_keyword_searches_every_column
    view = filter(view_for, 'みかん')

    assert_equal %w[みかん], names(view)
  end

  def test_the_cursor_starts_at_the_first_matching_row
    view = filter(view_for, 'price > 130')

    assert_equal 0, view.cursor.row
    assert_equal 'みかん', view.copy_target
  end

  def test_no_matching_rows_leaves_an_empty_grid
    view = filter(view_for, 'name zzz')

    assert_equal 0, view.sheet.row_count
    assert_includes view.status_line, '0 rows'
  end

  def test_the_status_line_shows_the_filter
    view = filter(view_for, 'price > 130')

    assert_includes view.status_line, 'filter: price > 130'
    assert_includes view.status_line, '2 rows'
  end

  def test_a_broken_query_keeps_the_prompt_open_and_reports_why
    view = view_for
    view.handle_key('/')
    'price >'.each_char { |char| view.handle_key(char) }
    view.handle_key("\r")

    assert view.search_prompt_open?, '直せるように入力欄は開いたままにすること'
    assert_includes view.status_line.downcase, 'value'
    assert_equal 4, view.sheet.row_count
  end

  def test_escape_while_typing_cancels_the_filter
    view = view_for
    view.handle_key('/')
    'price > 130'.each_char { |char| view.handle_key(char) }

    assert view.handle_key("\e")
    refute view.search_prompt_open?
    assert_nil view.search_query
    assert_equal 4, view.sheet.row_count
  end

  def test_escape_clears_the_filter_before_leaving_preview
    view = filter(view_for, 'price > 130')

    assert view.handle_key("\e"), 'まず絞り込みを解除すること'
    assert_equal 4, view.sheet.row_count
    assert_nil view.search_query
    refute view.handle_key("\e"), '絞り込みがなければ ESC はビューで扱わない'
  end

  def test_the_filter_survives_cursor_movement
    view = filter(view_for, 'price > 130')
    view.handle_key('j')

    assert_equal 2, view.sheet.row_count
    assert_equal 1, view.cursor.row
    assert_equal 'melon', view.copy_target
  end

  def test_copying_uses_the_filtered_rows
    view = filter(view_for, 'price > 130')
    copied = []
    Rufio::Clipboard.stub(:copy, ->(text) { copied << text; :pbcopy }) { view.handle_key('Y') }

    assert_equal ['みかん,150,8'], copied
  end

  def test_reset_clears_the_filter
    view = filter(view_for, 'price > 130')
    assert view.reset

    assert_nil view.search_query
    assert_equal 4, view.sheet.row_count
  end

  # === Excel（シート切替で解除） ===

  def workbook_view
    path = File.join(@dir, 'book.xlsx')
    write_xlsx(path, [['Sales', [%w[name price], ['apple', 120], ['melon', 300]]],
                      ['Stock', [%w[item count], ['apple', 30]]]])
    view_for(path)
  end

  def test_a_workbook_sheet_is_filtered_too
    view = filter(workbook_view, 'price > 200')

    assert_equal %w[melon], names(view)
  end

  def test_switching_sheets_clears_the_filter
    view = filter(workbook_view, 'price > 200')
    view.handle_key(']')

    assert_nil view.search_query, 'シートを切り替えたら絞り込みは解除すること'
    assert_equal 1, view.sheet.row_count
  end

  # === 描画（UIRenderer） ===

  def renderer_for(name, width: 100, height: 14)
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    ui = Rufio::UIRenderer.new(screen_width: width, screen_height: height,
                               keybind_handler: handler, directory_listing: listing,
                               file_preview: Rufio::FilePreview.new)
    handler.select_index(listing.list_entries.index { |entry| entry[:name] == name })
    assert handler.focus_preview_pane
    [screen, ui, handler]
  end

  def screen_text(screen, height)
    (0...height).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
  end

  def test_the_grid_shows_only_the_matching_rows
    screen, ui, handler = renderer_for('sales.csv')
    handler.handle_key('/')
    'price > 130'.each_char { |char| handler.handle_key(char) }
    handler.handle_key("\r")
    ui.draw_screen(screen)
    text = screen_text(screen, 14)

    assert_includes text, 'みかん'
    assert_includes text, 'melon'
    refute_includes text, 'banana', '条件に合わない行は描かないこと'
    refute_includes text, 'apple'
    assert_includes text, 'filter: price > 130'
    assert_includes text, '2 rows', '最下行の件数も絞り込み後にすること'
  end

  def test_the_query_is_shown_while_typing_in_the_grid
    screen, ui, handler = renderer_for('sales.csv')
    handler.handle_key('/')
    'pri'.each_char { |char| handler.handle_key(char) }
    ui.draw_screen(screen)

    assert_includes screen_text(screen, 14), '/pri'
  end

  def test_clearing_the_filter_redraws_every_row
    screen, ui, handler = renderer_for('sales.csv')
    handler.handle_key('/')
    'price > 130'.each_char { |char| handler.handle_key(char) }
    handler.handle_key("\r")
    ui.draw_screen(screen)
    handler.handle_key("\e")
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 14)

    assert_includes text, 'apple'
    assert_includes text, 'banana'
    refute_includes text, 'filter:'
    assert handler.preview_focused?
  end

  # === SQLite（SQL を内部で実行） ===

  def sqlite3_or_skip
    skip 'sqlite3 コマンドがない' unless Rufio::CommandLocator.available?('sqlite3')
  end

  def database
    return @database if @database

    path = File.join(@dir, 'shop.db')
    IO.popen(['sqlite3', path], 'w') do |io|
      io.write(<<~SQL)
        CREATE TABLE products (id INTEGER, name TEXT, price REAL, note TEXT);
        INSERT INTO products VALUES (1, 'apple', 120.0, 'red, sweet');
        INSERT INTO products VALUES (2, 'みかん', 150.5, '冬の定番');
        INSERT INTO products VALUES (3, 'banana', 80.0, NULL);
        INSERT INTO products VALUES (4, 'melon', 300.0, 'green');
      SQL
    end
    @database = path
  end

  def test_a_database_table_is_filtered_with_sql
    sqlite3_or_skip
    view = filter(view_for(database), 'price > 130')

    assert_equal %w[みかん melon], view.sheet.fetch_rows(0, 10).map { |row| row[1] }
    assert_equal 2, view.sheet.row_count
    assert_includes view.status_line, 'filter: price > 130'
  end

  def test_a_database_filter_runs_a_select_with_a_where_clause
    sqlite3_or_skip
    queries = []
    original = Rufio::SqliteTableSource.runner
    Rufio::SqliteTableSource.runner = lambda do |argv|
      queries << argv.last
      original.call(argv)
    end

    view = filter(view_for(database), 'price > 100, name m%')
    view.sheet.row_count # 絞り込みの SELECT は行を読むときに走る
    filtered = queries.select { |sql| sql.include?('WHERE') && sql.include?('FROM "products"') }

    refute_empty filtered, 'WHERE 付きの SELECT を発行すること'
    sql = filtered.last
    assert_includes sql, 'SELECT'
    assert_includes sql, '"price" > 100'
    assert_includes sql, %(\"name\" LIKE 'm%')
    assert_includes sql, ' AND '
    refute_match(/DELETE|UPDATE|DROP|;\s*\w/, sql, 'SELECT 以外は組み立てないこと')
  ensure
    Rufio::SqliteTableSource.reset!
  end

  def test_a_quote_in_the_query_is_escaped
    sqlite3_or_skip
    view = filter(view_for(database), %(note "red, sweet"))

    assert_equal %w[apple], view.sheet.fetch_rows(0, 10).map { |row| row[1] }

    # ' を含む入力でも SQL として壊れない（結果が 0 件になるだけ）
    other = filter(view_for(database), "name o'brien")
    assert_equal 0, other.sheet.row_count
    assert_nil other.sheet.load_error
  end

  def test_a_database_filter_with_no_matches_keeps_the_columns
    sqlite3_or_skip
    view = filter(view_for(database), 'name zzz')

    assert_equal 0, view.sheet.row_count
    assert_equal %w[id name price note], view.sheet.header, '1 件も残らなくても列は残すこと'
    assert_includes view.status_line, '0 rows'
  end

  def test_the_prompt_starts_empty_even_with_a_filter_applied
    view = filter(view_for, 'price > 130')
    view.handle_key('/')

    assert_equal '', view.search_query, '前の条件に続けて打ち足さないこと'
  end

  def test_a_database_filter_reaches_rows_past_the_row_limit
    sqlite3_or_skip
    path = File.join(@dir, 'many.db')
    IO.popen(['sqlite3', path], 'w') do |io|
      io.write("CREATE TABLE numbers (n INTEGER);\n" \
               "INSERT INTO numbers SELECT value FROM generate_series(1, 300);\n")
    end

    settings = Rufio::ConfigLoader.table_preview.merge(max_rows: 10)
    Rufio::ConfigLoader.stub(:table_preview, settings) do
      view = view_for(path)
      assert_equal 10, view.sheet.row_count, '読み込みは上限で打ち切られていること'

      filtered = filter(view, 'n = 250')
      assert_equal [['250']], filtered.sheet.fetch_rows(0, 10),
                   '読み込み上限より後ろの行も SQL で見つけること'
    end
  end
end
