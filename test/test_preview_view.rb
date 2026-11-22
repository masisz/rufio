# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

# PreviewView プロトコル: テキストと表のビューが同じ約束を満たし、
# プレビューモード中のキーがビューに委譲されること
class TestPreviewView < Minitest::Test
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

  def test_text_view_has_no_cursor_and_nothing_to_copy
    view = Rufio::PreviewView.build(@txt_path)
    assert_nil view.cursor
    assert_nil view.copy_target
    refute view.table?
    assert_equal Rufio::PreviewView::BACK_HINT, view.status_line
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

  def test_mouse_wheel_moves_the_cell_cursor
    handler = handler_for('sales.csv')
    handler.focus_preview_pane

    handler.scroll_preview_down
    assert_equal 1, handler.preview_cursor.row
    handler.scroll_preview_up
    assert_equal 0, handler.preview_cursor.row
  end
end
