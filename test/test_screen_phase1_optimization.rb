# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rufio"
require 'set'

# Phase1改善のテスト
# 以下の最適化が正しく動作することを確認:
# 1. Dirty Row管理
# 2. Width事前計算
# 3. format_cellの最適化
# 4. Screen.rowの最適化
# 5. ANSI除去の最小化
class TestScreenPhase1Optimization < Minitest::Test
  # ===== Dirty Row管理のテスト =====

  def test_dirty_rows_initialized
    screen = Rufio::Screen.new(10, 5)

    # 初期状態ではdirty_rowsは空
    assert_respond_to screen, :dirty_rows
    assert_equal [], screen.dirty_rows
  end

  def test_dirty_rows_marked_on_put
    screen = Rufio::Screen.new(10, 5)

    # putを呼ぶと対象行がダーティになる
    screen.put(0, 0, 'A')
    assert_includes screen.dirty_rows, 0

    # 別の行にputすると、その行もダーティになる
    screen.put(0, 2, 'B')
    assert_includes screen.dirty_rows, 2

    # 同じ行に複数回putしても、1回だけマークされる
    screen.put(1, 0, 'C')
    assert_equal 2, screen.dirty_rows.size  # 0と2の2行のみ
  end

  def test_dirty_rows_marked_on_put_string
    screen = Rufio::Screen.new(20, 5)

    # put_stringを呼ぶと対象行がダーティになる
    screen.put_string(0, 1, "Hello")
    assert_includes screen.dirty_rows, 1
  end

  def test_dirty_rows_cleared
    screen = Rufio::Screen.new(10, 5)

    screen.put(0, 0, 'A')
    screen.put(0, 2, 'B')
    assert_equal 2, screen.dirty_rows.size

    # clear_dirtyを呼ぶとdirty_rowsがクリアされる
    screen.clear_dirty
    assert_equal [], screen.dirty_rows
  end

  def test_dirty_rows_cleared_on_full_clear
    screen = Rufio::Screen.new(10, 5)

    screen.put(0, 0, 'A')
    screen.put(0, 2, 'B')

    # clearを呼ぶとdirty_rowsもクリアされる
    screen.clear
    assert_equal [], screen.dirty_rows
  end

  # ===== Width事前計算のテスト =====

  def test_width_precalculated_on_put
    screen = Rufio::Screen.new(10, 5)

    # widthを指定してput
    screen.put(0, 0, 'A', width: 1)
    cell = screen.get_cell(0, 0)
    assert_equal 1, cell[:width]

    # widthなしでputすると、自動計算される
    screen.put(2, 0, '全')
    cell = screen.get_cell(2, 0)
    assert_equal 2, cell[:width]
  end

  def test_width_stored_in_cell
    screen = Rufio::Screen.new(10, 5)

    # 全角文字
    screen.put(0, 0, '日')
    cell = screen.get_cell(0, 0)
    assert_equal 2, cell[:width]

    # 半角文字
    screen.put(3, 0, 'A')
    cell = screen.get_cell(3, 0)
    assert_equal 1, cell[:width]
  end

  # ===== format_cellの最適化テスト =====

  def test_format_cell_no_color_fast_path
    screen = Rufio::Screen.new(10, 5)

    # 色なしの場合、文字をそのまま返す
    screen.put(0, 0, 'A')
    row = screen.row(0)

    # ANSIコードなしで文字が含まれる
    assert_match /A/, row

    # 色なしスペースは特別扱い
    screen.put(1, 0, ' ')
    row = screen.row(0)
    # スペースも正しく含まれる
  end

  def test_format_cell_with_color
    screen = Rufio::Screen.new(20, 5)

    # 前景色あり
    screen.put(0, 0, 'R', fg: "\e[31m")
    row = screen.row(0)
    assert_includes row, "\e[31m"
    assert_includes row, "R"
    assert_includes row, "\e[0m"

    # 背景色あり
    screen.put(2, 0, 'B', bg: "\e[44m")
    row = screen.row(0)
    assert_includes row, "\e[44m"
    assert_includes row, "B"
  end

  def test_format_cell_with_both_colors
    screen = Rufio::Screen.new(20, 5)

    # 前景色と背景色の両方
    screen.put(0, 0, 'X', fg: "\e[31m", bg: "\e[44m")
    row = screen.row(0)
    assert_includes row, "\e[31m"
    assert_includes row, "\e[44m"
    assert_includes row, "X"
    assert_includes row, "\e[0m"
  end

  # ===== Screen.rowの最適化テスト =====

  def test_row_uses_cell_width
    screen = Rufio::Screen.new(20, 5)

    # 全角文字を配置
    screen.put(0, 0, '日', width: 2)
    screen.put(2, 0, '本', width: 2)
    screen.put(4, 0, 'A', width: 1)

    row = screen.row(0)

    # 正しくパディングされている
    # row自体の表示幅を検証するより、パディングが正しく計算されるかを確認
    # 'width: 2+2+1 = 5, 残り15文字がスペース' という計算が行われることを期待
    assert_includes row, '日'
    assert_includes row, '本'
    assert_includes row, 'A'
  end

  def test_row_padding_calculation
    screen = Rufio::Screen.new(10, 5)

    # 幅5の文字列を配置
    screen.put_string(0, 0, "Hello")  # width=5

    row = screen.row(0)
    # 行全体が幅10になるようにパディングされる
    # ANSIコードを除去した後の幅を確認
    clean_row = Rufio::ColorHelper.strip_ansi(row)
    assert_equal 10, Rufio::TextUtils.display_width(clean_row)
  end

  # ===== ANSI除去の最小化テスト =====

  def test_put_string_strips_ansi_once
    screen = Rufio::Screen.new(30, 5)

    # ANSIコード付き文字列を渡す
    colored_string = "\e[31mRed\e[0m Text"
    screen.put_string(0, 0, colored_string, fg: "\e[32m")

    # セルにはANSIコードなしの文字が格納される
    cell0 = screen.get_cell(0, 0)
    assert_equal 'R', cell0[:char]

    cell1 = screen.get_cell(1, 0)
    assert_equal 'e', cell1[:char]

    cell2 = screen.get_cell(2, 0)
    assert_equal 'd', cell2[:char]

    # スペースもセルに含まれる
    cell3 = screen.get_cell(3, 0)
    assert_equal ' ', cell3[:char]
  end

  def test_put_string_without_ansi_no_strip
    screen = Rufio::Screen.new(20, 5)

    # ANSIコードなし文字列
    plain_string = "Plain Text"
    screen.put_string(0, 0, plain_string)

    # セルに正しく格納される
    cell0 = screen.get_cell(0, 0)
    assert_equal 'P', cell0[:char]

    cell5 = screen.get_cell(5, 0)
    assert_equal ' ', cell5[:char]

    cell6 = screen.get_cell(6, 0)
    assert_equal 'T', cell6[:char]
  end

  # ===== 統合テスト =====

  def test_phase1_integration
    screen = Rufio::Screen.new(20, 5)

    # 複数行に文字列を配置
    screen.put_string(0, 0, "Line 1")
    screen.put_string(0, 1, "Line 2")
    screen.put_string(0, 2, "日本語")

    # dirty_rowsが正しくマークされる
    assert_equal 3, screen.dirty_rows.size
    assert_includes screen.dirty_rows, 0
    assert_includes screen.dirty_rows, 1
    assert_includes screen.dirty_rows, 2

    # 各行が正しく取得できる
    assert_includes screen.row(0), "Line 1"
    assert_includes screen.row(1), "Line 2"
    assert_includes screen.row(2), "日本語"

    # clear_dirty後は空になる
    screen.clear_dirty
    assert_equal [], screen.dirty_rows

    # 再度putするとダーティになる
    screen.put_string(0, 3, "New Line")
    assert_equal [3], screen.dirty_rows
  end
end
