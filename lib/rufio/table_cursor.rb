# frozen_string_literal: true

module Rufio
  # 表プレビューのセルカーソル。行・列の位置と、縦横のスクロール位置を持つ。
  #
  # 縦スクロールは「カーソルが見えるように最小限ずらす」方式で、表示できる行数は
  # 描画側（UIRenderer）が毎フレーム visible_rows= で教える。
  # 横スクロールは列幅に依存するため、ずらす量の計算は TableLayout#offset_for が担う。
  class TableCursor
    # 表示行数が分からないうちのページ送り量（既存のプレビュースクロールと同じ）
    DEFAULT_VISIBLE_ROWS = 20

    attr_reader :row, :column, :row_offset, :visible_rows
    attr_accessor :column_offset

    def initialize(sheet)
      @sheet = sheet
      @row = 0
      @column = 0
      @row_offset = 0
      @column_offset = 0
      @visible_rows = DEFAULT_VISIBLE_ROWS
    end

    def row_count
      @sheet.row_count
    end

    def column_count
      @sheet.column_count
    end

    # カーソルの指すセルの生の値（表示用に畳んでいない値）
    def value
      @sheet.cell(@row, @column)
    end

    def empty?
      row_count.zero? || column_count.zero?
    end

    # 先頭のセルに戻す（表示できる行数の記憶は保つ）
    def reset
      @row = 0
      @column = 0
      @row_offset = 0
      @column_offset = 0
      true
    end

    # @return [Boolean] 位置が動いたか
    def move(rows: 0, columns: 0)
      move_to(@row + rows, @column + columns)
    end

    def move_to(row, column)
      before = [@row, @column, @row_offset]
      @row = clamp(row, row_count)
      @column = clamp(column, column_count)
      ensure_row_visible
      before != [@row, @column, @row_offset]
    end

    def move_to_row(row)
      move_to(row, @column)
    end

    def move_to_column(column)
      move_to(@row, column)
    end

    def first_row
      move_to_row(0)
    end

    def last_row
      move_to_row(row_count - 1)
    end

    def first_column
      move_to_column(0)
    end

    def last_column
      move_to_column(column_count - 1)
    end

    # @param pages [Integer] 正で下、負で上
    def page(pages)
      move(rows: pages * [@visible_rows, 1].max)
    end

    # 描画側が表示できるデータ行数を伝える
    def visible_rows=(count)
      @visible_rows = [count.to_i, 1].max
      ensure_row_visible
    end

    # カーソル行が表示範囲に入るよう、スクロール位置を最小限ずらす
    def ensure_row_visible
      @row_offset = @row if @row < @row_offset
      last_visible = @row_offset + @visible_rows - 1
      @row_offset = @row - @visible_rows + 1 if @row > last_visible
      @row_offset = 0 if @row_offset.negative?
      @row_offset = [@row_offset, [row_count - 1, 0].max].min
      @row_offset
    end

    private

    def clamp(value, count)
      return 0 if count <= 0

      value.clamp(0, count - 1)
    end
  end
end
