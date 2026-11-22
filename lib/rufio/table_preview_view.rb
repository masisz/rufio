# frozen_string_literal: true

require 'csv'
require_relative 'table_cursor'
require_relative 'text_utils'
require_relative 'config_loader'

module Rufio
  # 行列（グリッド）プレビュー。セルカーソルを持ち、hjkl で移動する。
  # 形式（CSV / 将来の Excel・SQLite）には依存せず、TableDocument だけを見る。
  class TablePreviewView < PreviewView
    MOVE_HINT = 'hjkl: move  y: copy  ESC: back'
    SHEET_HINT = '[/]: sheet'

    attr_reader :document, :cursor, :sheet_index

    def initialize(document, sheet_index: 0, path: nil)
      super(path: path)
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
      clear_notice
      true
    end

    def handle_key(key)
      # 設定されたコピーキー（既定 y）は共通処理に渡す。Y に再割り当てされていても
      # 行コピーより設定が優先される
      return super if copy_key?(key)

      action = action_for(key)
      return super if action.nil?

      clear_notice
      case action
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
      when :previous_sheet then select_sheet(@sheet_index - 1)
      when :next_sheet     then select_sheet(@sheet_index + 1)
      when :copy_row       then copy_row
      end
    end

    # 複数シート（Excel のシート / SQLite のテーブル）を切り替える
    def select_sheet(index)
      return false if index.negative? || index >= @document.sheet_count
      return false if index == @sheet_index

      @sheet_index = index
      @cursor = TableCursor.new(sheet)
      true
    end

    # マウスホイールなど、キー以外からの縦移動もセルカーソルを動かす
    def scroll(delta)
      clear_notice
      @cursor.move(rows: delta)
    end

    def page(delta)
      @cursor.page(delta)
    end

    # 例: "R3C2 price  |  hjkl: move  y: copy  ESC: back"
    # コピー直後は操作ヒントの代わりに結果を出す
    def status_line
      hint = @document.sheet_count > 1 ? "#{MOVE_HINT}  #{SHEET_HINT}" : MOVE_HINT
      [cell_address, notice_text || hint].compact.join('  |  ')
    end

    # y でコピーする値（表示用に畳む前の生のセル値）。
    # データ行がなければファイルパスを返す（テキストプレビューと同じ扱い）
    def copy_target
      return super if @cursor.empty?

      @cursor.value
    end

    private

    # Y: カーソル行を CSV の 1 行としてコピーする
    def copy_row
      return copy_text(nil) if @cursor.empty?

      row = sheet.fetch_rows(@cursor.row, 1).first
      copy_text(CSV.generate_line(Array(row)).chomp, label: 'row')
    end

    def cell_address
      return nil if @cursor.empty?

      title = sheet.header && sheet.header[@cursor.column]
      address = "R#{@cursor.row + 1}C#{@cursor.column + 1}"
      return address if title.nil? || title.empty?

      # 見出しはファイル由来。ここは幅が広く長い文字列が入るため必ず無害化する
      "#{address} #{TextUtils.sanitize_for_display(title)}"
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
      when '['                            then :previous_sheet
      when ']'                            then :next_sheet
      when 'Y'                            then :copy_row
      end
    end
  end
end
