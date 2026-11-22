# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'
require_relative 'support/xlsx_fixture'

# PreviewView プロトコル: テキストと表のビューが同じ約束を満たし、
# プレビューモード中のキーがビューに委譲されること
class TestPreviewView < Minitest::Test
  include XlsxFixture

  PROTOCOL = %i[row_offset reset handle_key scroll page status_line copy_target cursor table?].freeze

  def setup
    @test_dir = Dir.mktmpdir('rufio_preview_view_test')
    @csv_path = File.join(@test_dir, 'sales.csv')
    File.write(@csv_path, "name,price\napple,120\nみかん,150\nbanana,80\n")
    @txt_path = File.join(@test_dir, 'notes.txt')
    File.write(@txt_path, (1..100).map { |i| "line #{i}" }.join("\n"))
  end

  def teardown
    Rufio::PreviewRegistry.reset!
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === プロトコル ===

  def test_both_views_satisfy_the_protocol
    [Rufio::PreviewView.build(@txt_path), Rufio::PreviewView.build(@csv_path)].each do |view|
      PROTOCOL.each do |method|
        assert_respond_to view, method, "#{view.class} が #{method} を持つこと"
      end
    end
  end

  def test_factory_picks_the_view_by_format
    assert_instance_of Rufio::TextPreviewView, Rufio::PreviewView.build(@txt_path)
    assert_instance_of Rufio::TablePreviewView, Rufio::PreviewView.build(@csv_path)
  end

  def test_factory_falls_back_to_text_for_a_missing_file
    assert_instance_of Rufio::TextPreviewView, Rufio::PreviewView.build(File.join(@test_dir, 'gone.csv'))
  end

  # === テキストビュー（従来の挙動を保つ） ===

  def test_text_view_scrolls_by_line
    view = Rufio::PreviewView.build(@txt_path)
    assert view.handle_key('j')
    assert_equal 1, view.row_offset
    assert view.handle_key('k')
    assert_equal 0, view.row_offset
    refute_equal(-1, view.row_offset)
  end

  def test_text_view_does_not_scroll_above_the_top
    view = Rufio::PreviewView.build(@txt_path)
    view.handle_key('k')
    assert_equal 0, view.row_offset
  end

  def test_text_view_pages_with_ctrl_d_and_u
    view = Rufio::PreviewView.build(@txt_path)
    view.handle_key("\x04")
    assert_equal Rufio::TextPreviewView::PAGE_ROWS, view.row_offset
    view.handle_key("\x15")
    assert_equal 0, view.row_offset
  end

  def test_text_view_copies_the_file_path
    view = Rufio::PreviewView.build(@txt_path)
    assert_nil view.cursor
    refute view.table?
    assert_equal File.expand_path(@txt_path), view.copy_target,
                 'テキストプレビューの y はファイルパスをコピーする'
    assert_equal Rufio::TextPreviewView::SCROLL_HINT, view.status_line
  end

  def test_text_view_ignores_unknown_keys
    view = Rufio::PreviewView.build(@txt_path)
    refute view.handle_key('x')
    refute view.handle_key('h')
  end

  # === 表ビュー ===

  def test_table_view_moves_the_cell_cursor_with_hjkl
    view = Rufio::PreviewView.build(@csv_path)
    assert view.table?

    assert view.handle_key('j')
    assert_equal 1, view.cursor.row
    assert view.handle_key('l')
    assert_equal 1, view.cursor.column
    assert view.handle_key('k')
    assert_equal 0, view.cursor.row
    assert view.handle_key('h')
    assert_equal 0, view.cursor.column
  end

  def test_table_view_moves_with_arrow_keys
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key("\e[B")
    view.handle_key("\e[C")
    assert_equal [1, 1], [view.cursor.row, view.cursor.column]
    view.handle_key("\e[A")
    view.handle_key("\e[D")
    assert_equal [0, 0], [view.cursor.row, view.cursor.column]
  end

  def test_table_view_jumps_to_edges
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('}')
    assert_equal 2, view.cursor.row, '} で最終行へ'
    view.handle_key('$')
    assert_equal 1, view.cursor.column, '$ で最終列へ'
    view.handle_key('g')
    assert_equal 0, view.cursor.row, 'g で先頭行へ'
    view.handle_key('0')
    assert_equal 0, view.cursor.column, '0 で先頭列へ'
  end

  def test_table_view_follows_rebound_keys
    rebound = Rufio::ConfigLoader.default_keybinds.merge(move_down: 'n', navigate_enter: 'f')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = Rufio::PreviewView.build(@csv_path)
      assert view.handle_key('n'), '設定した移動キーで動くこと'
      assert_equal 1, view.cursor.row
      assert view.handle_key('f')
      assert_equal 1, view.cursor.column
      refute view.handle_key('j'), '既定キーは設定で置き換わること'
    end
  end

  def test_table_view_ignores_unknown_keys
    view = Rufio::PreviewView.build(@csv_path)
    refute view.handle_key('Z')
  end

  def test_table_view_row_offset_follows_the_cursor
    path = File.join(@test_dir, 'long.csv')
    File.write(path, "id\n#{(1..100).map(&:to_s).join("\n")}\n")
    view = Rufio::PreviewView.build(path)
    view.cursor.visible_rows = 10

    9.times { view.handle_key('j') }
    assert_equal 0, view.row_offset
    view.handle_key('j')
    assert_equal 1, view.row_offset
  end

  def test_table_view_status_shows_the_cell_address_and_column_name
    view = Rufio::PreviewView.build(@csv_path)
    assert_includes view.status_line, 'R1C1 name'

    view.handle_key('j')
    view.handle_key('l')
    assert_includes view.status_line, 'R2C2 price'
    assert_includes view.status_line, 'hjkl'
  end

  def test_table_view_copy_target_is_the_raw_cell
    view = Rufio::PreviewView.build(@csv_path)
    assert_equal 'apple', view.copy_target

    view.handle_key('j')
    assert_equal 'みかん', view.copy_target

    view.handle_key('l')
    assert_equal '150', view.copy_target
  end

  def test_table_view_scroll_and_page_move_the_cursor
    path = File.join(@test_dir, 'long.csv')
    File.write(path, "id\n#{(1..100).map(&:to_s).join("\n")}\n")
    view = Rufio::PreviewView.build(path)
    view.cursor.visible_rows = 10

    view.scroll(1)
    assert_equal 1, view.cursor.row
    view.page(1)
    assert_equal 11, view.cursor.row
  end

  # === シート切替（[ / ]） ===

  def multi_sheet_view
    document = Rufio::TableDocument.new(
      sheets: [
        Rufio::MemoryTableSheet.new(name: 'Sales', header: %w[name price], rows: [%w[apple 120]]),
        Rufio::MemoryTableSheet.new(name: 'Stock', header: %w[item count], rows: [%w[apple 30], %w[mikan 8]])
      ]
    )
    Rufio::TablePreviewView.new(document, path: @csv_path)
  end

  def test_brackets_switch_sheets
    view = multi_sheet_view
    assert_equal 0, view.sheet_index

    assert view.handle_key(']')
    assert_equal 1, view.sheet_index
    assert_equal 'Stock', view.sheet.name

    assert view.handle_key('[')
    assert_equal 0, view.sheet_index
  end

  def test_sheet_switching_stops_at_the_ends
    view = multi_sheet_view
    refute view.handle_key('['), '先頭シートより前には動かない'
    view.handle_key(']')
    refute view.handle_key(']'), '最終シートより後ろには動かない'
  end

  def test_switching_sheets_resets_the_cursor
    view = multi_sheet_view
    view.handle_key(']')
    view.handle_key('j')
    assert_equal 1, view.cursor.row

    view.handle_key('[')
    assert_equal 0, view.cursor.row, '切り替えたらカーソルは先頭セルに戻る'
    assert_equal 1, view.cursor.row_count, 'カーソルは切り替え先のシートを見ること'
  end

  def test_sheet_hint_only_appears_with_several_sheets
    assert_includes multi_sheet_view.status_line, '[ ]: sheet'
    refute_includes Rufio::PreviewView.build(@csv_path).status_line, '[ ]: sheet'
  end

  def test_copy_uses_the_selected_sheet
    view = multi_sheet_view
    view.handle_key(']')
    view.handle_key('l')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['30'], copied
  end

  # === y: クリップボードへのコピー ===

  def capture_copy(result = :pbcopy)
    copied = []
    Rufio::Clipboard.stub(:copy, ->(text) { copied << text; result }) { yield }
    copied
  end

  def test_y_copies_the_cell_under_the_cursor
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('j')
    view.handle_key('l')

    copied = capture_copy { assert view.handle_key('y') }
    assert_equal ['150'], copied
    assert_includes view.status_line, 'copied (pbcopy)'
  end

  def test_y_copies_the_raw_cell_value
    path = File.join(@test_dir, 'quoted.csv')
    File.write(path, %(name,note\napple,"two\nlines"\n))
    view = Rufio::PreviewView.build(path)
    view.handle_key('l')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ["two\nlines"], copied, '表示用に畳む前の値をコピーすること'
  end

  def test_y_in_a_text_preview_copies_the_path
    view = Rufio::PreviewView.build(@txt_path)
    copied = capture_copy { assert view.handle_key('y') }

    assert_equal [File.expand_path(@txt_path)], copied
    assert_includes view.status_line, 'copied (pbcopy)'
  end

  def test_the_notice_reports_the_line_count_for_a_multiline_cell
    # グリッドは改行を空白に畳んで表示するので、コピー内容が複数行だと分かるようにする
    path = File.join(@test_dir, 'multi.csv')
    File.write(path, %(item,note\n"echo hi\nrm -rf ~/x",ok\n))
    view = Rufio::PreviewView.build(path)

    capture_copy { view.handle_key('y') }
    assert_includes view.status_line, 'copied, 2 lines (pbcopy)'

    view.handle_key('l')
    capture_copy { view.handle_key('y') }
    assert_includes view.status_line, 'copied (pbcopy)'
    refute_includes view.status_line, 'lines'
  end

  def test_y_reports_a_failed_copy
    view = Rufio::PreviewView.build(@csv_path)
    capture_copy(false) { view.handle_key('y') }

    assert_includes view.status_line, 'clipboard unavailable'
  end

  def test_the_copy_notice_disappears_on_the_next_move
    view = Rufio::PreviewView.build(@csv_path)
    capture_copy { view.handle_key('y') }
    assert_includes view.status_line, 'copied'

    view.handle_key('j')
    refute_includes view.status_line, 'copied'
    assert_includes view.status_line, 'hjkl'
  end

  def test_y_on_a_table_without_data_copies_the_path
    path = File.join(@test_dir, 'header_only.csv')
    File.write(path, "a,b\n")
    view = Rufio::PreviewView.build(path)

    copied = capture_copy { view.handle_key('y') }
    assert_equal [File.expand_path(path)], copied
  end

  def test_y_follows_a_rebound_copy_key
    rebound = Rufio::ConfigLoader.default_keybinds.merge(copy_to_clipboard: 'Y')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = Rufio::PreviewView.build(@csv_path)
      copied = capture_copy { assert view.handle_key('Y') }
      assert_equal ['apple'], copied, '設定したキーは行コピー（Y）より優先されること'
      refute view.handle_key('y')
    end
  end

  def test_capital_y_copies_the_whole_row_as_csv
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('j')

    copied = capture_copy { assert view.handle_key('Y') }
    assert_equal ['みかん,150'], copied
    assert_includes view.status_line, 'copied row (pbcopy)'
  end

  def test_capital_y_quotes_cells_that_need_it
    path = File.join(@test_dir, 'quoted.csv')
    File.write(path, %(name,note\napple,"red, sweet"\n))
    view = Rufio::PreviewView.build(path)

    copied = capture_copy { view.handle_key('Y') }
    assert_equal ['apple,"red, sweet"'], copied, 'CSV として読み戻せる形でコピーすること'
  end

  # === NavigationController / KeybindHandler への委譲 ===

  def handler_for(name)
    listing = Rufio::DirectoryListing.new(@test_dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    index = listing.list_entries.index { |entry| entry[:name] == name }
    refute_nil index
    handler.select_index(index)
    handler
  end

  def test_focusing_a_csv_builds_a_table_view
    handler = handler_for('sales.csv')
    assert handler.focus_preview_pane
    assert_instance_of Rufio::TablePreviewView, handler.preview_view
    refute_nil handler.preview_cursor
  end

  def test_focusing_a_text_file_builds_a_text_view
    handler = handler_for('notes.txt')
    assert handler.focus_preview_pane
    assert_instance_of Rufio::TextPreviewView, handler.preview_view
    assert_nil handler.preview_cursor
  end

  def test_preview_keys_reach_the_table_view
    handler = handler_for('sales.csv')
    handler.focus_preview_pane

    assert handler.handle_key('l')
    assert_equal 1, handler.preview_cursor.column
    assert handler.handle_key('j')
    assert_equal 1, handler.preview_cursor.row
  end

  def test_escape_leaves_preview_mode_and_drops_the_view
    handler = handler_for('sales.csv')
    handler.focus_preview_pane
    assert handler.handle_key("\e")

    refute handler.preview_focused?
    assert_nil handler.preview_view
  end

  def test_scroll_offset_is_reported_from_the_view
    handler = handler_for('notes.txt')
    handler.focus_preview_pane
    handler.handle_key('j')
    handler.handle_key('j')

    assert_equal 2, handler.preview_scroll_offset
  end

  def test_reset_returns_both_views_to_the_top
    text = Rufio::PreviewView.build(@txt_path)
    3.times { text.handle_key('j') }
    assert text.reset
    assert_equal 0, text.row_offset

    table = Rufio::PreviewView.build(@csv_path)
    table.handle_key('j')
    table.handle_key('l')
    table.cursor.column_offset = 1
    assert table.reset
    assert_equal [0, 0, 0, 0],
                 [table.cursor.row, table.cursor.column, table.row_offset, table.cursor.column_offset]
  end

  def test_preview_mode_y_reaches_the_view
    handler = handler_for('sales.csv')
    handler.focus_preview_pane
    handler.handle_key('l')

    copied = capture_copy { assert handler.handle_key('y') }
    assert_equal ['120'], copied
  end

  def test_files_mode_y_copies_the_current_path
    handler = handler_for('sales.csv')
    copied = capture_copy { assert handler.handle_key('y') }

    assert_equal [File.expand_path(@csv_path)], copied
  end

  def test_files_mode_y_copies_every_selected_path
    handler = handler_for('sales.csv')
    handler.handle_key(' ') # 選択
    index = handler.get_active_entries.index { |entry| entry[:name] == 'notes.txt' }
    handler.select_index(index)
    handler.handle_key(' ')

    copied = capture_copy { handler.handle_key('y') }
    assert_equal 1, copied.length
    lines = copied.first.split("\n")
    assert_equal [File.expand_path(@csv_path), File.expand_path(@txt_path)].sort, lines.sort
  end

  def test_mouse_wheel_moves_the_cell_cursor
    handler = handler_for('sales.csv')
    handler.focus_preview_pane

    handler.scroll_preview_down
    assert_equal 1, handler.preview_cursor.row
    handler.scroll_preview_up
    assert_equal 0, handler.preview_cursor.row
  end

  # === テーブル／シート一覧（/） ===

  def many_sheet_view(count = 10)
    sheets = (1..count).map do |i|
      Rufio::MemoryTableSheet.new(name: "t#{i}", header: %w[a], rows: [["v#{i}"]])
    end
    Rufio::TablePreviewView.new(Rufio::TableDocument.new(sheets: sheets, sheet_label: 'Tables'),
                                path: @csv_path)
  end

  def test_t_opens_the_sheet_list
    view = multi_sheet_view
    refute view.picker_open?, '最初は一覧を開いていないこと'

    assert view.handle_key('t')
    assert view.picker_open?
    assert_equal %w[Sales Stock], view.picker.names, 'シート名を並べること'
    assert_equal 0, view.picker.index, '現在のシートを選んだ状態で開くこと'
  end

  def test_the_list_opens_on_the_current_sheet
    view = multi_sheet_view
    view.handle_key(']')
    view.handle_key('t')

    assert_equal 1, view.picker.index
  end

  def test_the_list_moves_without_switching_sheets
    view = multi_sheet_view
    view.handle_key('t')

    assert view.handle_key('j')
    assert_equal 1, view.picker.index
    assert_equal 0, view.sheet_index, '選ぶまではシートを切り替えないこと'
    assert_equal 'Sales', view.sheet.name

    assert view.handle_key('k')
    assert_equal 0, view.picker.index
  end

  def test_the_list_moves_with_arrow_keys
    view = multi_sheet_view
    view.handle_key('t')

    view.handle_key("\e[B")
    assert_equal 1, view.picker.index
    view.handle_key("\e[A")
    assert_equal 0, view.picker.index
  end

  def test_the_list_stops_at_the_ends
    view = multi_sheet_view
    view.handle_key('t')

    view.handle_key('k')
    assert_equal 0, view.picker.index
    view.handle_key('j')
    view.handle_key('j')
    assert_equal 1, view.picker.index
  end

  def test_the_list_jumps_to_the_first_and_last_entry
    view = many_sheet_view
    view.handle_key('t')

    view.handle_key('}')
    assert_equal 9, view.picker.index
    view.handle_key('g')
    assert_equal 0, view.picker.index
  end

  def test_enter_opens_the_selected_sheet_and_closes_the_list
    view = multi_sheet_view
    view.handle_key('t')
    view.handle_key('j')

    assert view.handle_key("\r")
    refute view.picker_open?, '選んだら一覧は閉じること'
    assert_equal 1, view.sheet_index
    assert_equal 'Stock', view.sheet.name
    assert_equal 0, view.cursor.row, 'カーソルは切り替え先の先頭セルに戻ること'
  end

  def test_the_list_also_accepts_a_newline
    view = multi_sheet_view
    view.handle_key('t')
    view.handle_key('j')
    view.handle_key("\n")

    assert_equal 1, view.sheet_index
  end

  def test_escape_closes_the_list_and_keeps_the_sheet
    view = multi_sheet_view
    view.handle_key('t')
    view.handle_key('j')

    assert view.handle_key("\e")
    refute view.picker_open?
    assert_equal 0, view.sheet_index, 'ESC では切り替えないこと'
  end

  def test_t_closes_the_list_again
    view = multi_sheet_view
    view.handle_key('t')
    assert view.handle_key('t')

    refute view.picker_open?
  end

  def test_the_list_swallows_other_keys
    view = multi_sheet_view
    view.handle_key('t')

    assert view.handle_key('l'), '一覧を開いている間はキーを通さないこと'
    assert view.handle_key('Z')
    assert_equal 0, view.cursor.column, '裏のセルカーソルは動かないこと'

    copied = capture_copy { assert view.handle_key('y') }
    assert_empty copied, '一覧を開いている間はコピーもしないこと'
  end

  def test_t_does_nothing_for_a_single_sheet_table
    view = Rufio::PreviewView.build(@csv_path)

    refute view.handle_key('t'), '1 枚しかない表では一覧を開かないこと'
    refute view.picker_open?
  end

  def test_the_list_follows_rebound_move_keys
    rebound = Rufio::ConfigLoader.default_keybinds.merge(move_down: 'n')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = multi_sheet_view
      view.handle_key('t')
      view.handle_key('n')
      assert_equal 1, view.picker.index
    end
  end

  def test_the_status_line_shows_the_list_hint
    assert_includes multi_sheet_view.status_line, 't: list'
    refute_includes Rufio::PreviewView.build(@csv_path).status_line, 't: list'
  end

  def test_the_status_line_shows_the_selected_entry_while_the_list_is_open
    view = multi_sheet_view
    view.handle_key('t')
    view.handle_key('j')

    assert_includes view.status_line, '2/2 Stock'
    assert_includes view.status_line, 'Enter: open'
    assert_includes view.status_line, 'ESC: cancel'
  end

  def test_the_list_title_uses_the_document_label
    assert_equal 'Tables (10)', many_sheet_view.tap { |view| view.handle_key('t') }.picker_title
    assert_equal 'Sheets (2)', multi_sheet_view.tap { |view| view.handle_key('t') }.picker_title
  end

  def test_the_list_rows_mark_the_current_sheet_and_the_selection
    view = multi_sheet_view
    view.handle_key('t')
    view.handle_key('j')
    rows = view.picker_rows

    assert_equal ['> Sales', '  Stock'], rows.map { |row| row[:text] }
    assert_equal [false, true], rows.map { |row| row[:selected] }
  end

  def test_the_list_rows_sanitize_the_sheet_name
    document = Rufio::TableDocument.new(
      sheets: [Rufio::MemoryTableSheet.new(name: "ok", header: %w[a], rows: [%w[1]]),
               Rufio::MemoryTableSheet.new(name: "bad\e[31mname", header: %w[a], rows: [%w[2]])]
    )
    view = Rufio::TablePreviewView.new(document, path: @csv_path)
    view.handle_key('t')

    refute_includes view.picker_rows.last[:text], "\e", 'シート名の制御文字を無害化すること'
  end

  def test_the_list_scrolls_to_keep_the_selection_visible
    view = many_sheet_view
    view.handle_key('t')
    view.picker.visible_rows = 3

    assert_equal %w[t1 t2 t3], view.picker_rows.map { |row| row[:text][2..] }
    view.handle_key('}')
    assert_equal %w[t8 t9 t10], view.picker_rows.map { |row| row[:text][2..] }
    assert_equal 9, view.picker.index
  end

  def test_the_wheel_moves_the_list_while_it_is_open
    view = many_sheet_view(30)
    view.handle_key('t')

    assert view.scroll(1), 'ホイールは一覧の選択を動かすこと'
    assert_equal 1, view.picker.index
    assert_equal 0, view.cursor.row, '裏のセルカーソルは動かないこと'

    view.page(1)
    assert_equal 1 + view.picker.visible_rows, view.picker.index
    assert_equal 0, view.cursor.row
  end

  def test_reset_closes_the_list
    view = multi_sheet_view
    view.handle_key('t')
    assert view.reset

    refute view.picker_open?
  end

  # === 一覧と NavigationController ===

  def xlsx_handler
    path = File.join(@test_dir, 'book.xlsx')
    write_xlsx(path, [['Sales', [%w[name price], ['apple', 120]]],
                      ['Stock', [%w[item count], ['mikan', 30]]]])
    handler = handler_for('book.xlsx')
    assert handler.focus_preview_pane
    handler
  end

  def test_the_list_opens_from_preview_mode
    handler = xlsx_handler
    assert handler.handle_key('t')

    assert handler.preview_view.picker_open?
  end

  def test_escape_closes_the_list_before_leaving_preview_mode
    handler = xlsx_handler
    handler.handle_key('t')

    assert handler.handle_key("\e")
    assert handler.preview_focused?, 'ESC は一覧を閉じるだけでプレビューは抜けないこと'
    refute handler.preview_view.picker_open?

    assert handler.handle_key("\e")
    refute handler.preview_focused?
  end

  def test_choosing_from_the_list_switches_the_sheet
    handler = xlsx_handler
    handler.handle_key('t')
    handler.handle_key('j')
    handler.handle_key("\r")

    assert_equal 1, handler.preview_view.sheet_index
    assert_equal 'Stock', handler.preview_view.sheet.name
  end

  # === カラム選択（Space）と選択カラムのコピー ===

  def test_space_selects_the_column_under_the_cursor
    view = Rufio::PreviewView.build(@csv_path)

    assert_empty view.selected_columns
    assert view.handle_key(' ')
    assert_equal [0], view.selected_columns
    assert view.column_selected?(0)
    refute view.column_selected?(1)
  end

  def test_space_again_unselects_the_column
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    assert view.handle_key(' ')

    assert_empty view.selected_columns
    refute view.column_selected?(0)
  end

  def test_several_columns_can_be_selected
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')

    assert_equal [0, 1], view.selected_columns
  end

  def test_space_follows_a_rebound_select_key
    rebound = Rufio::ConfigLoader.default_keybinds.merge(select: 'v')
    Rufio::ConfigLoader.stub(:keybinds, rebound) do
      view = Rufio::PreviewView.build(@csv_path)
      assert view.handle_key('v')
      assert_equal [0], view.selected_columns
      refute view.handle_key(' '), '既定キーは設定で置き換わること'
    end
  end

  def test_selecting_a_column_keeps_the_cell_cursor
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('j')
    view.handle_key(' ')

    assert_equal 1, view.cursor.row, 'Space ではカーソルを動かさないこと'
    assert_equal [0], view.selected_columns
  end

  def test_moving_the_cursor_keeps_the_selection
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    view.handle_key('j')
    view.handle_key('l')

    assert_equal [0], view.selected_columns
  end

  def test_space_does_nothing_without_columns
    path = File.join(@test_dir, 'empty.csv')
    File.write(path, '')
    view = Rufio::PreviewView.build(path)

    refute view.handle_key(' ') if view.table?
    assert_empty view.selected_columns if view.table?
  end

  def test_y_copies_the_selected_columns_of_the_cursor_row
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')

    copied = capture_copy { assert view.handle_key('y') }
    assert_equal ['apple,120'], copied, '選択カラムをカンマ区切りで連結すること'
    assert_includes view.status_line, 'copied 2 cols (pbcopy)'
  end

  def test_the_copied_row_follows_the_cursor
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')
    view.handle_key('j')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['みかん,150'], copied
  end

  def test_the_selected_columns_are_copied_in_column_order
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('l')
    view.handle_key(' ')
    view.handle_key('h')
    view.handle_key(' ')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['apple,120'], copied, '選んだ順ではなく列の順に並べること'
  end

  def test_one_selected_column_copies_that_column_not_the_cursor_cell
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('l')
    view.handle_key(' ')
    view.handle_key('h')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['120'], copied, '選択があればカーソル位置の列ではなく選択列をコピーすること'
    assert_includes view.status_line, 'copied 1 cols (pbcopy)'
  end

  def test_cells_that_need_quoting_are_quoted
    path = File.join(@test_dir, 'quoted.csv')
    File.write(path, %(name,note\napple,"red, sweet"\n))
    view = Rufio::PreviewView.build(path)
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['apple,"red, sweet"'], copied, 'CSV として読み戻せる形でコピーすること'
  end

  def test_a_missing_cell_becomes_an_empty_field
    path = File.join(@test_dir, 'ragged.csv')
    File.write(path, "a,b,c\n1\n")
    view = Rufio::PreviewView.build(path)
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['1,,'], copied
  end

  def test_y_without_a_selection_still_copies_the_cell
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key('l')

    copied = capture_copy { view.handle_key('y') }
    assert_equal ['120'], copied
  end

  def test_capital_y_still_copies_the_whole_row
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')

    copied = capture_copy { view.handle_key('Y') }
    assert_equal ['apple,120'], copied, 'Y は選択に関係なく行全体をコピーすること'
    assert_includes view.status_line, 'copied row (pbcopy)'
  end

  def test_y_on_a_table_without_rows_copies_the_path
    path = File.join(@test_dir, 'header_only.csv')
    File.write(path, "a,b\n")
    view = Rufio::PreviewView.build(path)
    view.handle_key(' ')

    copied = capture_copy { view.handle_key('y') }
    assert_equal [File.expand_path(path)], copied
  end

  def test_the_status_line_lists_the_selected_columns
    view = Rufio::PreviewView.build(@csv_path)
    refute_includes view.status_line, 'cols'

    view.handle_key(' ')
    view.handle_key('l')
    view.handle_key(' ')
    assert_includes view.status_line, 'cols A,B'
    assert_includes view.status_line, 'Space: col'
  end

  def test_the_status_line_shortens_a_long_selection
    sheet = Rufio::MemoryTableSheet.new(name: 'wide', header: ('a'..'h').to_a,
                                        rows: [('1'..'8').to_a])
    view = Rufio::TablePreviewView.new(Rufio::TableDocument.new(sheets: [sheet]), path: @csv_path)
    8.times do
      view.handle_key(' ')
      view.handle_key('l')
    end

    assert_includes view.status_line, 'cols A,B,C,D +4'
  end

  def test_switching_sheets_clears_the_selection
    view = multi_sheet_view
    view.handle_key(' ')
    view.handle_key(']')

    assert_empty view.selected_columns, 'シートを切り替えたら選択は残さないこと'
  end

  def test_choosing_from_the_list_clears_the_selection
    view = multi_sheet_view
    view.handle_key(' ')
    view.handle_key('t')
    view.handle_key('j')
    view.handle_key("\r")

    assert_empty view.selected_columns
  end

  def test_reset_clears_the_selection
    view = Rufio::PreviewView.build(@csv_path)
    view.handle_key(' ')
    assert view.reset

    assert_empty view.selected_columns
  end

  def test_the_list_swallows_the_select_key
    view = multi_sheet_view
    view.handle_key('t')

    assert view.handle_key(' ')
    assert_empty view.selected_columns, '一覧を開いている間はカラムを選ばないこと'
  end

  def test_selected_columns_reach_the_view_from_preview_mode
    handler = handler_for('sales.csv')
    handler.focus_preview_pane

    assert handler.handle_key(' ')
    assert_equal [0], handler.preview_view.selected_columns

    copied = capture_copy { handler.handle_key('y') }
    assert_equal ['apple'], copied
  end
end
