# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'
require_relative 'support/xlsx_fixture'

# 表プレビューの統合テスト
# FilePreview が 'table' を返すこと、UIRenderer がグリッドを描画すること、
# 表として読めない場合にテキストプレビューへ戻ること
class TestTablePreview < Minitest::Test
  include XlsxFixture

  CSV_CONTENT = <<~CSV
    name,price,stock
    apple,120,30
    みかん,150,8
    banana,80,12
  CSV

  # 表として読めない形式の代役
  class FailingTableSource < Rufio::TableSource
    class << self
      def supports?(path)
        File.extname(path.to_s) == '.boom'
      end

      def open(_path, limits: nil, options: {})
        raise Rufio::TableSource::ParseError, 'test failure'
      end
    end
  end

  def setup
    @test_dir = Dir.mktmpdir('rufio_table_preview_test')
    @csv_path = File.join(@test_dir, 'sales.csv')
    File.write(@csv_path, CSV_CONTENT)
    File.write(File.join(@test_dir, 'notes.txt'), "plain text\nsecond line\n")

    @file_preview = Rufio::FilePreview.new
  end

  def teardown
    Rufio::PreviewRegistry.reset!
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  # === FilePreview ===

  def test_csv_is_previewed_as_table
    preview = @file_preview.preview_file(@csv_path)

    assert_equal 'table', preview[:type]
    assert_instance_of Rufio::TableDocument, preview[:document]
    assert_equal %w[name price stock], preview[:document].sheet.header
    assert_equal 3, preview[:document].sheet.row_count
  end

  def test_table_preview_provides_plain_lines_for_other_consumers
    preview = @file_preview.preview_file(@csv_path)

    assert(preview[:lines].any? { |line| line.include?('A name') })
    assert(preview[:lines].any? { |line| line.include?('apple') })
  end

  def test_text_file_is_not_a_table
    preview = @file_preview.preview_file(File.join(@test_dir, 'notes.txt'))

    assert_equal 'text', preview[:type]
    assert_nil preview[:document]
  end

  def test_cp932_csv_is_decoded_instead_of_mojibake
    path = File.join(@test_dir, 'cp932.csv')
    File.binwrite(path, "商品,単価\nみかん,150\n".encode('CP932').b)
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type]
    assert_equal 'CP932', preview[:encoding]
    assert_equal %w[商品 単価], preview[:document].sheet.header
  end

  def test_utf16_csv_is_not_treated_as_binary
    path = File.join(@test_dir, 'utf16.csv')
    File.binwrite(path, "\xFF\xFE".b + "name,price\r\napple,120\r\n".encode('UTF-16LE').b)
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type], 'NUL バイトの多い UTF-16 でも表として扱うこと'
    assert_equal %w[name price], preview[:document].sheet.header
  end

  def test_empty_csv_is_still_handled
    path = File.join(@test_dir, 'empty.csv')
    File.write(path, '')
    preview = @file_preview.preview_file(path)

    assert_equal 'empty', preview[:type], '0 バイトは従来どおり empty'
  end

  def test_header_only_csv
    path = File.join(@test_dir, 'header_only.csv')
    File.write(path, "a,b\n")
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type]
    assert_equal %w[a b], preview[:document].sheet.header
    assert_equal 0, preview[:document].sheet.row_count
    assert preview[:document].sheet.empty?
  end

  def test_unparsable_table_falls_back_to_text_preview
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    path = File.join(@test_dir, 'broken.boom')
    File.write(path, "line one\nline two\n")

    preview = @file_preview.preview_file(path)

    refute_equal 'table', preview[:type]
    assert_equal 'test failure', preview[:table_error]
    assert_includes preview[:lines].first, 'not parsed as table'
    assert_includes preview[:lines], 'line one'
  end

  # === PreviewRegistry ===

  def test_registry_finds_the_csv_source
    assert_equal Rufio::CsvTableSource, Rufio::PreviewRegistry.table_source_for('a.csv')
    assert_nil Rufio::PreviewRegistry.table_source_for('a.txt')
    assert_nil Rufio::PreviewRegistry.table_source_for(nil)
  end

  def test_registered_source_takes_precedence
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    assert_equal FailingTableSource, Rufio::PreviewRegistry.table_source_for('a.boom')
    assert Rufio::PreviewRegistry.table?('a.boom')
  end

  def test_reset_restores_the_defaults
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    Rufio::PreviewRegistry.reset!
    assert_nil Rufio::PreviewRegistry.table_source_for('a.boom')
  end

  # === UIRenderer ===

  def renderer_for(width: 100, height: 24, name: 'sales.csv')
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@test_dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)

    ui = Rufio::UIRenderer.new(
      screen_width: width, screen_height: height,
      keybind_handler: handler, directory_listing: listing,
      file_preview: Rufio::FilePreview.new
    )

    entries = listing.list_entries
    index = entries.index { |entry| entry[:name] == name }
    refute_nil index, "#{name} がエントリに含まれること"

    handler.select_index(index)

    [screen, ui, handler]
  end

  def screen_text(screen, height)
    (0...height).map { |y| strip_ansi(screen.row(y)) }.join("\n")
  end

  def test_split_pane_draws_the_grid
    screen, ui, = renderer_for
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'A name'
    assert_includes text, 'apple'
    assert_includes text, 'みかん'
    assert_includes text, '3 rows  3 cols'
  end

  def test_fullscreen_preview_draws_the_grid
    screen, ui, handler = renderer_for
    assert handler.focus_preview_pane
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, '[PREVIEW MODE]'
    assert_includes text, 'A name'
    assert_includes text, 'banana'
  end

  def test_grid_rows_are_numbered
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)
    rows = (0...24).map { |y| strip_ansi(screen.row(y)) }

    apple_row = rows.find { |row| row.include?('apple') }
    assert_match(/\A\s*1 \|/, apple_row)
  end

  def test_short_table_does_not_scroll_when_the_cursor_moves
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)

    handler.scroll_preview_down
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'apple', '全行が収まっているうちはスクロールしないこと'
    assert_includes text, 'A name'
    assert_equal 1, handler.preview_cursor.row
  end

  def test_cursor_past_the_bottom_scrolls_and_keeps_the_header
    path = File.join(@test_dir, 'long.csv')
    File.write(path, "id,label\n#{(1..40).map { |i| "#{i},row#{i}" }.join("\n")}\n")

    screen, ui, handler = renderer_for(name: 'long.csv', height: 12)
    handler.focus_preview_pane
    30.times { handler.scroll_preview_down }
    ui.draw_screen(screen)
    text = screen_text(screen, 12)

    assert_includes text, 'A id', 'ヘッダ行は固定されたままであること'
    refute_includes text, 'row1,', '先頭行はスクロールアウトしていること'
    assert_includes text, 'row31'
    assert_equal 30, handler.preview_cursor.row
  end

  # 反転色（選択色）で描かれた文字だけを集める。
  # 全画面プレビュー中はファイル一覧を描かないので、カーソルセルだけが該当する。
  def highlighted_text(screen, width, height)
    selected = Rufio::ColorHelper.color_to_selected_ansi(Rufio::ConfigLoader.colors[:selected])
    (0...height).flat_map do |y|
      (0...width).map do |x|
        cell = screen.get_cell(x, y)
        cell && cell[:fg] == selected ? cell[:char] : nil
      end
    end.compact.join
  end

  def test_cursor_cell_is_highlighted
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)

    assert_includes highlighted_text(screen, 100, 24), 'apple', '最初のセルが反転表示されること'
  end

  def test_cursor_highlight_follows_the_keys
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    handler.handle_key('j')
    handler.handle_key('l')
    ui.draw_screen(screen)

    highlighted = highlighted_text(screen, 100, 24)
    assert_includes highlighted, '150', 'R2C2 のセルが反転表示されること'
    refute_includes highlighted, 'apple'
  end

  def test_status_line_shows_the_cell_address
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)
    assert_includes screen_text(screen, 24), 'R1C1 name'

    handler.handle_key('l')
    screen.clear
    ui.draw_screen(screen)
    assert_includes screen_text(screen, 24), 'R1C2 price'
  end

  def test_text_preview_keeps_the_scroll_hint
    screen, ui, handler = renderer_for(name: 'notes.txt')
    handler.focus_preview_pane
    ui.draw_screen(screen)

    assert_includes screen_text(screen, 24), Rufio::TextPreviewView::SCROLL_HINT
  end

  def test_moving_right_scrolls_the_columns_into_view
    path = File.join(@test_dir, 'wide.csv')
    File.write(path, "c1,c2,c3,c4,c5,c6
#{(1..6).map { |i| "value#{i}" }.join(',')}
")

    screen, ui, handler = renderer_for(name: 'wide.csv', width: 46)
    handler.focus_preview_pane
    ui.draw_screen(screen)
    refute_includes screen_text(screen, 24), 'value6', '最初は右端の列は見えていない'

    5.times { handler.handle_key('l') }
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'value6', 'カーソルに合わせて横スクロールすること'
    assert_includes highlighted_text(screen, 46, 24), 'value6'
    assert_operator handler.preview_cursor.column_offset, :>, 0
  end

  def test_empty_table_has_no_cursor_cell
    path = File.join(@test_dir, 'header_only2.csv')
    File.write(path, "a,b
")

    screen, ui, handler = renderer_for(name: 'header_only2.csv')
    handler.focus_preview_pane
    ui.draw_screen(screen)

    assert_empty highlighted_text(screen, 100, 24), 'データ行がなければカーソルを描かないこと'
    assert_includes screen_text(screen, 24), 'A a'
  end

  def test_status_line_reports_a_copy
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    Rufio::Clipboard.stub(:copy, :pbcopy) { handler.handle_key('y') }
    ui.draw_screen(screen)

    assert_includes screen_text(screen, 24), 'copied (pbcopy)'
  end

  # === Excel（複数シート） ===

  def test_xlsx_is_previewed_as_a_grid
    path = File.join(@test_dir, 'book.xlsx')
    write_xlsx(path, [['Sales', [%w[name price], ['apple', 120]]],
                      ['Stock', [%w[item count], ['apple', 30]]]])

    screen, ui, handler = renderer_for(name: 'book.xlsx')
    handler.focus_preview_pane
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'A name'
    assert_includes text, 'apple'
    assert_includes text, '1/2 Sales'
  end

  def test_switching_sheets_redraws_the_grid
    path = File.join(@test_dir, 'book.xlsx')
    write_xlsx(path, [['Sales', [%w[name price], ['apple', 120]]],
                      ['Stock', [%w[item count], ['mikan', 30]]]])

    screen, ui, handler = renderer_for(name: 'book.xlsx')
    handler.focus_preview_pane
    ui.draw_screen(screen)
    refute_includes screen_text(screen, 24), 'A item'

    handler.handle_key(']')
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'A item', '切り替えたシートの見出しを描くこと'
    assert_includes text, 'mikan'
    assert_includes text, '2/2 Stock'
  end

  def test_an_unparsable_xlsx_falls_back_to_the_zip_listing
    path = File.join(@test_dir, 'broken.xlsx')
    # 中身は ZIP だが Excel として読めないファイル
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('hello.txt')
      zip.write('not a spreadsheet')
    end

    preview = @file_preview.preview_file(path)

    assert_equal 'archive', preview[:type], '表として読めなければ ZIP のエントリ一覧に戻すこと'
    assert(preview[:lines].any? { |line| line.include?('hello.txt') })
  end

  def test_narrow_pane_reports_hidden_columns
    screen, ui, = renderer_for(width: 60)
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, '+1 hidden', '収まらない列数を最下行に出すこと'
  end

  # === テーブル／シート一覧（/） ===

  def workbook_renderer
    path = File.join(@test_dir, 'book.xlsx')
    write_xlsx(path, [['Sales', [%w[name price], ['apple', 120]]],
                      ['Stock', [%w[item count], ['mikan', 30]]]])
    screen, ui, handler = renderer_for(name: 'book.xlsx')
    handler.focus_preview_pane
    [screen, ui, handler]
  end

  def test_t_draws_the_sheet_list
    screen, ui, handler = workbook_renderer
    handler.handle_key('t')
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'Sheets (2)', '一覧の見出しを出すこと'
    assert_includes text, 'Sales'
    assert_includes text, 'Stock'
    refute_includes text, 'A name', '一覧を開いている間はグリッドを描かないこと'
    assert_includes text, 'Enter: open'
  end

  def test_the_selected_entry_is_highlighted_in_the_list
    screen, ui, handler = workbook_renderer
    handler.handle_key('t')
    handler.handle_key('j')
    ui.draw_screen(screen)

    highlighted = highlighted_text(screen, 100, 24)
    assert_includes highlighted, 'Stock', '選択中の行を反転表示すること'
    refute_includes highlighted, 'Sales'
  end

  def test_choosing_from_the_list_draws_the_selected_grid
    screen, ui, handler = workbook_renderer
    handler.handle_key('t')
    handler.handle_key('j')
    handler.handle_key("\r")
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'A item', '選んだシートのグリッドを描くこと'
    assert_includes text, 'mikan'
    assert_includes text, '2/2 Stock'
    refute_includes text, 'Sheets (2)'
  end

  # SQLite は「テーブル一覧」として同じ一覧に出る（sqlite3 コマンドがある環境のみ）
  def test_the_list_shows_the_tables_of_a_database
    skip 'sqlite3 コマンドがない' unless Rufio::CommandLocator.available?('sqlite3')

    path = File.join(@test_dir, 'shop.db')
    IO.popen(['sqlite3', path], 'w') do |io|
      io.write("CREATE TABLE items (id INTEGER, name TEXT);\n" \
               "INSERT INTO items VALUES (1, 'apple');\n" \
               "CREATE TABLE sales (id INTEGER, total REAL);\n" \
               "INSERT INTO sales VALUES (1, 120.0);\n")
    end

    screen, ui, handler = renderer_for(name: 'shop.db')
    assert handler.focus_preview_pane
    handler.handle_key('t')
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'Tables (2)', 'SQLite ではテーブル一覧として出すこと'
    assert_includes text, 'items'
    assert_includes text, 'sales'
  end

  # === カラム選択（Space）の描画 ===

  # 選択マーク色（ファイル一覧の選択済みアイテムと同じ緑背景・黒文字）で
  # 描かれた文字だけを集める
  def marked_text(screen, width, height)
    (0...height).flat_map do |y|
      (0...width).map do |x|
        cell = screen.get_cell(x, y)
        cell && cell[:fg] == Rufio::UIRenderer::MARKED_COLUMN_COLOR ? cell[:char] : nil
      end
    end.compact.join
  end

  def test_a_selected_column_is_marked
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    handler.handle_key(' ')
    ui.draw_screen(screen)

    marked = marked_text(screen, 100, 24)
    assert_includes marked, 'name', '選択したカラムの見出しに印を付けること'
    assert_includes marked, 'みかん', 'そのカラムのセルにも印を付けること'
    refute_includes marked, 'price', '選んでいないカラムには印を付けないこと'
    refute_includes marked, '150'
  end

  def test_the_cursor_cell_stays_visible_in_a_selected_column
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    handler.handle_key(' ')
    ui.draw_screen(screen)

    assert_includes highlighted_text(screen, 100, 24), 'apple',
                    '選択カラムの中でもカーソルセルは反転表示のままであること'
  end

  def test_unselecting_removes_the_mark
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    handler.handle_key(' ')
    handler.handle_key(' ')
    screen.clear
    ui.draw_screen(screen)

    assert_empty marked_text(screen, 100, 24)
  end

  def test_the_status_line_lists_the_selected_columns
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    handler.handle_key(' ')
    ui.draw_screen(screen)

    assert_includes screen_text(screen, 24), 'cols A'
  end
end
