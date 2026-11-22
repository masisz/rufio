# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio'

# TableCursor: セル移動のクランプ、ページ送り、縦スクロールの追従
class TestTableCursor < Minitest::Test
  def cursor_for(rows:, columns:, visible_rows: nil)
    data = Array.new(rows) { |r| Array.new(columns) { |c| "r#{r}c#{c}" } }
    sheet = Rufio::MemoryTableSheet.new(rows: data, name: 'test.csv')
    cursor = Rufio::TableCursor.new(sheet)
    cursor.visible_rows = visible_rows if visible_rows
    cursor
  end

  # === 初期状態 ===

  def test_starts_at_the_first_cell
    cursor = cursor_for(rows: 5, columns: 3)
    assert_equal 0, cursor.row
    assert_equal 0, cursor.column
    assert_equal 0, cursor.row_offset
    assert_equal 0, cursor.column_offset
    refute cursor.empty?
  end

  def test_empty_sheet_has_no_cell
    cursor = cursor_for(rows: 0, columns: 0)
    assert cursor.empty?
    assert_nil cursor.value
  end

  # === 移動 ===

  def test_moves_down_and_up
    cursor = cursor_for(rows: 5, columns: 3)
    assert cursor.move(rows: 1)
    assert_equal 1, cursor.row
    assert cursor.move(rows: -1)
    assert_equal 0, cursor.row
  end

  def test_moves_right_and_left
    cursor = cursor_for(rows: 5, columns: 3)
    assert cursor.move(columns: 2)
    assert_equal 2, cursor.column
    assert cursor.move(columns: -1)
    assert_equal 1, cursor.column
  end

  def test_does_not_move_past_the_edges
    cursor = cursor_for(rows: 3, columns: 2)
    refute cursor.move(rows: -1), '先頭行より上には動かない'
    assert_equal 0, cursor.row

    cursor.move(rows: 10)
    assert_equal 2, cursor.row
    refute cursor.move(rows: 1), '最終行より下には動かない'

    cursor.move(columns: 10)
    assert_equal 1, cursor.column
    refute cursor.move(columns: 1), '最終列より右には動かない'
  end

  def test_jumps_to_the_edges
    cursor = cursor_for(rows: 10, columns: 4)
    assert cursor.last_row
    assert_equal 9, cursor.row
    assert cursor.last_column
    assert_equal 3, cursor.column
    assert cursor.first_row
    assert_equal 0, cursor.row
    assert cursor.first_column
    assert_equal 0, cursor.column
  end

  def test_value_is_the_raw_cell
    data = [['plain', "two\nlines"]]
    sheet = Rufio::MemoryTableSheet.new(rows: data, name: 'test.csv')
    cursor = Rufio::TableCursor.new(sheet)

    assert_equal 'plain', cursor.value
    cursor.move(columns: 1)
    assert_equal "two\nlines", cursor.value, '改行を畳まない生の値を返すこと'
  end

  # === ページ送り ===

  def test_page_moves_by_the_visible_rows
    cursor = cursor_for(rows: 100, columns: 2, visible_rows: 10)
    cursor.page(1)
    assert_equal 10, cursor.row
    cursor.page(1)
    assert_equal 20, cursor.row
    cursor.page(-1)
    assert_equal 10, cursor.row
  end

  def test_page_stops_at_the_last_row
    cursor = cursor_for(rows: 15, columns: 2, visible_rows: 10)
    cursor.page(5)
    assert_equal 14, cursor.row
  end

  def test_page_size_defaults_without_a_reported_viewport
    cursor = cursor_for(rows: 100, columns: 2)
    cursor.page(1)
    assert_equal Rufio::TableCursor::DEFAULT_VISIBLE_ROWS, cursor.row
  end

  # === 縦スクロールの追従 ===

  def test_scroll_offset_follows_the_cursor_downwards
    cursor = cursor_for(rows: 100, columns: 2, visible_rows: 5)
    4.times { cursor.move(rows: 1) }
    assert_equal 0, cursor.row_offset, '表示範囲内なら動かない'

    cursor.move(rows: 1)
    assert_equal 1, cursor.row_offset, '1 行だけずらすこと'
    assert_equal 5, cursor.row
  end

  def test_scroll_offset_follows_the_cursor_upwards
    cursor = cursor_for(rows: 100, columns: 2, visible_rows: 5)
    cursor.move_to_row(50)
    assert_equal 46, cursor.row_offset

    cursor.move_to_row(10)
    assert_equal 10, cursor.row_offset, '上に飛ぶとその行が先頭になること'
  end

  def test_first_row_resets_the_scroll
    cursor = cursor_for(rows: 100, columns: 2, visible_rows: 5)
    cursor.last_row
    assert_operator cursor.row_offset, :>, 0

    cursor.first_row
    assert_equal 0, cursor.row_offset
  end

  def test_a_smaller_viewport_rescrolls_to_the_cursor
    cursor = cursor_for(rows: 100, columns: 2, visible_rows: 20)
    cursor.move_to_row(15)
    assert_equal 0, cursor.row_offset

    cursor.visible_rows = 5
    assert_equal 11, cursor.row_offset, '表示行数が減ったらカーソルが見える位置まで送ること'
  end

  def test_column_offset_is_set_by_the_caller
    cursor = cursor_for(rows: 5, columns: 10)
    cursor.column_offset = 3
    assert_equal 3, cursor.column_offset
  end
end
