# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rufio"

# Screen バッファ事前確保（プリアロケーション）のテスト
#
# put / clear が毎回 Hash を生成するのではなく、
# 事前に確保した Cell オブジェクトをミューテートすることを確認する。
class TestScreenPrealloc < Minitest::Test
  # セルが Cell Struct であること
  def test_cell_is_struct_not_hash
    screen = Rufio::Screen.new(10, 5)
    cell = screen.get_cell(0, 0)
    assert_kind_of Rufio::Screen::Cell, cell
  end

  # put が既存 Cell オブジェクトをミューテートすること（新規生成しない）
  def test_put_reuses_cell_object
    screen = Rufio::Screen.new(10, 5)
    cell_before = screen.get_cell(0, 0)
    screen.put(0, 0, 'A')
    cell_after = screen.get_cell(0, 0)
    assert_same cell_before, cell_after, "put should mutate the existing Cell, not create a new one"
  end

  # clear が既存 Cell オブジェクトをリセットすること（再確保しない）
  def test_clear_reuses_cell_objects
    screen = Rufio::Screen.new(10, 5)
    cell_before = screen.get_cell(0, 0)
    screen.put(0, 0, 'A', fg: "\e[31m")
    screen.clear
    cell_after = screen.get_cell(0, 0)
    assert_same cell_before, cell_after, "clear should reset the existing Cell, not allocate a new one"
  end

  # put 後に Cell の内容が正しく更新されていること
  def test_put_updates_cell_attributes
    screen = Rufio::Screen.new(10, 5)
    screen.put(0, 0, 'Z', fg: "\e[33m", bg: "\e[44m")
    cell = screen.get_cell(0, 0)
    assert_equal 'Z', cell[:char]
    assert_equal "\e[33m", cell[:fg]
    assert_equal "\e[44m", cell[:bg]
    assert_equal 1, cell[:width]
  end

  # clear 後に Cell がデフォルト値にリセットされていること
  def test_clear_resets_cell_to_default
    screen = Rufio::Screen.new(10, 5)
    screen.put(0, 0, 'X', fg: "\e[31m")
    screen.clear
    cell = screen.get_cell(0, 0)
    assert_equal ' ', cell[:char]
    assert_nil cell[:fg]
    assert_nil cell[:bg]
    assert_equal 1, cell[:width]
  end

  # 全角文字のマーカーセルも既存オブジェクトをミューテートすること
  def test_wide_char_marker_reuses_cell
    screen = Rufio::Screen.new(10, 5)
    marker_before = screen.get_cell(1, 0)
    screen.put(0, 0, '全', width: 2)
    marker_after = screen.get_cell(1, 0)
    assert_same marker_before, marker_after, "Wide char marker cell should be the same object"
    assert_equal 0, marker_after[:width]
  end
end
