# frozen_string_literal: true

require_relative 'table_cursor'
require_relative 'config_loader'

module Rufio
  # 行列（グリッド）プレビュー。セルカーソルを持ち、hjkl で移動する。
  # 形式（CSV / 将来の Excel・SQLite）には依存せず、TableDocument だけを見る。
  class TablePreviewView < PreviewView
    MOVE_HINT = 'hjkl: move  ESC: back'

    attr_reader :document, :cursor, :sheet_index

    def initialize(document, sheet_index: 0)
      super()
      @document = document
      @sheet_index = sheet_index
      @cursor = TableCursor.new(sheet)
    end

    def table?
      true
    end

    def sheet
      @document.sheet(@sheet_index)
    end

    def row_offset
      @cursor.row_offset
    end

    def reset
      @cursor.reset
      true
    end

    def handle_key(key)
      case action_for(key)
      when :down         then @cursor.move(rows: 1)
      when :up           then @cursor.move(rows: -1)
      when :left         then @cursor.move(columns: -1)
      when :right        then @cursor.move(columns: 1)
      when :page_down    then @cursor.page(1)
      when :page_up      then @cursor.page(-1)
      when :first_row    then @cursor.first_row
      when :last_row     then @cursor.last_row
      when :first_column then @cursor.first_column
      when :last_column  then @cursor.last_column
      else false
      end
    end

    # マウスホイールなど、キー以外からの縦移動もセルカーソルを動かす
    def scroll(delta)
      @cursor.move(rows: delta)
    end

    def page(delta)
      @cursor.page(delta)
    end

    # 例: "R3C2 price  |  hjkl: move  ESC: back"
    def status_line
      [cell_address, MOVE_HINT].compact.join('  |  ')
    end

    # y でコピーする値（表示用に畳む前の生のセル値）
    def copy_target
      return nil if @cursor.empty?

      @cursor.value
    end

    private

    def cell_address
      return nil if @cursor.empty?

      title = sheet.header && sheet.header[@cursor.column]
      address = "R#{@cursor.row + 1}C#{@cursor.column + 1}"
      title.nil? || title.empty? ? address : "#{address} #{title}"
    end

    # キーバインド設定（hjkl の変更に追従する）と固定キーから操作を決める
    def action_for(key)
      keys = ConfigLoader.keybinds

      case key
      when keys[:move_down], "\e[B"       then :down
      when keys[:move_up], "\e[A"         then :up
      when keys[:navigate_parent], "\e[D" then :left
      when keys[:navigate_enter], "\e[C"  then :right
      when "\x04"                         then :page_down
      when "\x15"                         then :page_up
      when keys[:top]                     then :first_row
      when keys[:bottom]                  then :last_row
      when '0'                            then :first_column
      when '$'                            then :last_column
      end
    end
  end
end
