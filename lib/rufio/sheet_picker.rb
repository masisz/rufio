# frozen_string_literal: true

module Rufio
  # 表プレビューのシート一覧（Excel のシート / SQLite のテーブル）の選択状態。
  #
  # 名前の並びだけを受け取り、選択位置と縦スクロール位置を持つ。TableCursor と同じく
  # 「選択が見えるように最小限ずらす」方式で、表示できる行数は描画側（UIRenderer）が
  # 毎フレーム visible_rows= で教える。
  class SheetPicker
    # 表示行数が分からないうちの既定値
    DEFAULT_VISIBLE_ROWS = 10

    attr_reader :names, :index, :offset, :visible_rows

    # @param names [Array<String>] シート名（表示順）
    # @param index [Integer] 最初に選んでおく添字（現在表示中のシート）
    def initialize(names, index: 0)
      @names = Array(names)
      @index = empty? ? 0 : index.to_i.clamp(0, count - 1)
      @offset = 0
      @visible_rows = DEFAULT_VISIBLE_ROWS
      ensure_visible
    end

    def count
      @names.length
    end

    def empty?
      @names.empty?
    end

    def selected_name
      @names[@index]
    end

    # @return [Boolean] 選択位置かスクロール位置が動いたか
    def move(delta)
      move_to(@index + delta)
    end

    def first
      move_to(0)
    end

    def last
      move_to(count - 1)
    end

    def move_to(index)
      return false if empty?

      before = [@index, @offset]
      @index = index.to_i.clamp(0, count - 1)
      ensure_visible
      before != [@index, @offset]
    end

    def page(pages)
      move(pages * @visible_rows)
    end

    # 描画側が表示できる行数を伝える
    def visible_rows=(rows)
      @visible_rows = [rows.to_i, 1].max
      ensure_visible
    end

    # @return [Array<Array(Integer, String)>] 表示する [添字, 名前] の並び
    def visible
      return [] if empty?

      last_index = [@offset + @visible_rows, count].min - 1
      (@offset..last_index).map { |i| [i, @names[i]] }
    end

    private

    # 選択行が表示範囲に入るよう、スクロール位置を最小限ずらす
    def ensure_visible
      @offset = @index if @index < @offset
      last_visible = @offset + @visible_rows - 1
      @offset = @index - @visible_rows + 1 if @index > last_visible
      @offset = @offset.clamp(0, [count - @visible_rows, 0].max)
    end
  end
end
