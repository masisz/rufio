# frozen_string_literal: true

require 'csv'
require_relative 'table_cursor'
require_relative 'sheet_picker'
require_relative 'table_query'
require_relative 'text_utils'
require_relative 'config_loader'

module Rufio
  # 行列（グリッド）プレビュー。セルカーソルを持ち、hjkl で移動する。
  # 形式（CSV / 将来の Excel・SQLite）には依存せず、TableDocument だけを見る。
  class TablePreviewView < PreviewView
    MOVE_HINT = 'hjkl: move  Space: col  /: filter  y: copy  ESC: back'
    SHEET_HINT = '[ ]: sheet  t: list'
    PICKER_HINT = 'j/k: move  Enter: open  ESC: cancel'
    # シート一覧を開くキー（`/` はプレビュー内検索に使うため `t`（table））
    LIST_KEY = 't'
    # 一覧で現在表示中のシートに付ける印（Windows の端末でも崩れない ASCII）
    CURRENT_MARK = '>'
    # ステータス行に並べる選択カラム名の上限（残りは +n と出す）
    SELECTED_LABEL_LIMIT = 4

    attr_reader :document, :cursor, :sheet_index, :picker

    def initialize(document, sheet_index: 0, path: nil)
      super(path: path)
      @document = document
      @sheet_index = sheet_index
      @cursor = TableCursor.new(sheet)
      @picker = nil
      @selected_columns = []
      clear_filter
    end

    # 表示しているシート（`/` で絞り込んでいればその結果）
    def sheet
      @filtered_sheet || @document.sheet(@sheet_index)
    end

    # `/` の入力中はその文字列、確定後は適用中の条件（どちらでもなければ nil）
    def search_query
      @prompt ? @prompt.query : @filter_text
    end

    def search_prompt_open?
      !@prompt.nil?
    end

    # Space で選んだカラム（列の順に並べる）
    def selected_columns
      @selected_columns.sort
    end

    def column_selected?(index)
      @selected_columns.include?(index)
    end

    def table?
      true
    end

    def row_offset
      @cursor.row_offset
    end

    def reset
      close_sheet_list
      clear_filter
      clear_columns
      @cursor = TableCursor.new(sheet)
      clear_notice
      true
    end

    # シート（SQLite のテーブル / Excel のシート）一覧を開いているか
    def picker_open?
      !@picker.nil?
    end

    # 一覧の見出し（"Tables (3)" / "Sheets (2)"）
    def picker_title
      return nil unless @picker

      "#{@document.sheet_label} (#{@picker.count})"
    end

    # 一覧に描く行。反転色をどう出すかは描画側（UIRenderer）が決める
    # @return [Array<Hash>] { text: String, selected: Boolean }
    def picker_rows
      return [] unless @picker

      @picker.visible.map do |index, name|
        mark = index == @sheet_index ? CURRENT_MARK : ' '
        # シート名・テーブル名はファイルやデータベース由来なので無害化する
        { text: "#{mark} #{TextUtils.sanitize_for_display(name.to_s)}",
          selected: index == @picker.index }
      end
    end

    # 一覧を開く。選ぶものがない（シートが 1 枚だけの）表では何もしない
    def open_sheet_list
      return false unless @document.sheet_count > 1

      clear_notice
      @picker = SheetPicker.new(@document.sheet_names, index: @sheet_index)
      true
    end

    def close_sheet_list
      return false unless @picker

      @picker = nil
      true
    end

    def handle_key(key)
      # 一覧・入力欄を開いている間は、すべてのキーをそちらで扱う
      return handle_picker_key(key) if picker_open?
      return handle_prompt_key(key) if search_prompt_open?
      return open_filter_prompt if key == ConfigLoader.keybinds[:search]
      return clear_filter if key == "\e" && filtering?

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
      when :sheet_list     then open_sheet_list
      when :toggle_column  then toggle_column
      when :copy_row       then copy_row
      end
    end

    # 複数シート（Excel のシート / SQLite のテーブル）を切り替える
    def select_sheet(index)
      return false if index.negative? || index >= @document.sheet_count
      return false if index == @sheet_index

      @sheet_index = index
      # 列の並びも中身もシートごとに違うので、選択と絞り込みは持ち越さない
      clear_filter
      clear_columns
      @cursor = TableCursor.new(sheet)
      true
    end

    # マウスホイールなど、キー以外からの縦移動もセルカーソルを動かす
    # （シート一覧を開いている間は一覧の選択を動かす）
    def scroll(delta)
      return @picker.move(delta) if picker_open?

      clear_notice
      @cursor.move(rows: delta)
    end

    def page(delta)
      return @picker.page(delta) if picker_open?

      @cursor.page(delta)
    end

    # 例: "R3C2 price  |  hjkl: move  y: copy  ESC: back"
    # コピー直後は操作ヒントの代わりに結果を出す。
    # 一覧を開いている間は、選んでいるシートと一覧の操作ヒントを出す
    def status_line
      return picker_status_line if picker_open?
      return prompt_status_line if search_prompt_open?

      hint = @document.sheet_count > 1 ? "#{MOVE_HINT}  #{SHEET_HINT}" : MOVE_HINT
      [cell_address, selected_columns_label, filter_label, notice_text || hint].compact.join('  |  ')
    end

    # y でコピーする値（表示用に畳む前の生のセル値）。
    # カラムを選んでいればカーソル行の選択カラムをカンマ区切りで連結した 1 行、
    # 選んでいなければカーソル位置のセル。
    # データ行がなければファイルパスを返す（テキストプレビューと同じ扱い）
    def copy_target
      return super if @cursor.empty?
      return selected_columns_line if @selected_columns.any?

      @cursor.value
    end

    private

    # `/`: 絞り込み条件の入力を始める（毎回空から。ESC で元の表示に戻る）
    def open_filter_prompt
      clear_notice
      @filter_error = nil
      @prompt = SearchPrompt.new
      true
    end

    # 入力中のキーはすべて入力欄で扱う（裏のセルカーソルを動かさない）
    def handle_prompt_key(key)
      case @prompt.handle_key(key)
      when :changed then @filter_error = nil
      when :submitted then apply_filter
      when :cancelled then @prompt = nil
      end
      true
    end

    # 入力を条件として読み、シートを絞り込む。読めなければ入力欄を開いたままにする
    def apply_filter
      text = @prompt.query.to_s.strip
      return clear_filter if text.empty?

      source = @document.sheet(@sheet_index)
      query = TableQuery.parse(text, source.filter_columns)
      filtered = query ? source.filter(query) : nil
      @prompt = nil
      @filter_error = nil
      @filter_text = text
      @filtered_sheet = filtered
      @cursor = TableCursor.new(sheet)
      true
    rescue TableQuery::Error, TableSource::ParseError => e
      @filter_error = e.message
      true
    end

    def filtering?
      !@filter_text.nil?
    end

    def clear_filter
      @prompt = nil
      @filter_text = nil
      @filter_error = nil
      had_filter = !@filtered_sheet.nil?
      @filtered_sheet = nil
      @cursor = TableCursor.new(sheet) if had_filter
      true
    end

    # 例: "/price > 100_" / 読めなかったときは理由を添える
    def prompt_status_line
      [+"/#{@prompt.query}_", @filter_error].compact.join('  |  ')
    end

    # 例: "filter: price > 100 (2 rows)"
    def filter_label
      return nil unless filtering?

      "filter: #{TextUtils.sanitize_for_display(@filter_text)} (#{sheet.row_count} rows)"
    end

    # 一覧のキー。扱わないキーも含めて必ず true を返し、裏の表に通さない
    def handle_picker_key(key)
      keys = ConfigLoader.keybinds

      case key
      when "\r", "\n"                  then choose_sheet
      when "\e", LIST_KEY               then close_sheet_list
      when keys[:move_down], "\e[B"     then @picker.move(1)
      when keys[:move_up], "\e[A"       then @picker.move(-1)
      when "\x04"                       then @picker.page(1)
      when "\x15"                       then @picker.page(-1)
      when keys[:top]                   then @picker.first
      when keys[:bottom]                then @picker.last
      end
      true
    end

    # 一覧で選んだシートを開く（同じシートなら切り替えずに閉じるだけ）
    def choose_sheet
      index = @picker.index
      close_sheet_list
      select_sheet(index)
    end

    # 例: "2/3 sales  |  j/k: move  Enter: open  ESC: cancel"
    def picker_status_line
      name = TextUtils.sanitize_for_display(@picker.selected_name.to_s)
      ["#{@picker.index + 1}/#{@picker.count} #{name}", PICKER_HINT].join('  |  ')
    end

    # y: 選択カラムがあれば、何列コピーしたかを通知に出す
    def perform_copy
      return super unless @selected_columns.any? && !@cursor.empty?

      copy_text(copy_target, label: "#{@selected_columns.length} cols")
    end

    # Space: カーソル位置のカラムを選択・解除する
    def toggle_column
      index = @cursor.column
      return false unless index < sheet.column_count

      clear_notice
      @selected_columns.include?(index) ? @selected_columns.delete(index) : @selected_columns << index
      true
    end

    def clear_columns
      @selected_columns = []
    end

    # 選択カラムのセルを CSV の 1 行として連結する（カンマ区切り。
    # カンマや改行を含むセルは読み戻せるようクォートする）
    def selected_columns_line
      row = sheet.fetch_rows(@cursor.row, 1).first
      CSV.generate_line(selected_columns.map { |index| row && row[index] }).chomp
    end

    # 例: "cols A,B" / "cols A,B,C,D +4"
    def selected_columns_label
      return nil if @selected_columns.empty?

      labels = selected_columns.map { |index| sheet.column_label(index) }
      shown = labels.first(SELECTED_LABEL_LIMIT).join(',')
      rest = labels.length - SELECTED_LABEL_LIMIT
      rest.positive? ? "cols #{shown} +#{rest}" : "cols #{shown}"
    end

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
      when LIST_KEY                       then :sheet_list
      when keys[:select]                  then :toggle_column
      when 'Y'                            then :copy_row
      end
    end
  end
end
