# frozen_string_literal: true

require_relative 'text_utils'

module Rufio
  # 表プレビューの幅計算と行文字列の生成。形式（CSV / Excel / SQLite）に依存しない。
  #
  # 1 行の構成:
  #   <行番号ガター><"| " + セル><"| " + セル>...<"|">
  #
  # 列幅は全角を 2 として数え（TextUtils）、min..max の範囲に収める。
  class TableLayout
    MIN_COLUMN_WIDTH = 3
    DEFAULT_MAX_COLUMN_WIDTH = 32
    # 列幅算出に使う先頭行数（全行走査を避けるため）
    SAMPLE_ROWS = 200
    # 列の区切り（罫線 + スペース）とセル右側の余白
    CELL_PREFIX = '| '
    CELL_SUFFIX = ' '
    CLOSING_SEPARATOR = '|'
    # 1 列が消費する幅 = 区切り + 余白 + 列幅
    SEGMENT_OVERHEAD = CELL_PREFIX.length + CELL_SUFFIX.length
    MIN_GUTTER_DIGITS = 2
    # 幅指定なしで生成するとき（lines フォールバック用）の上限
    PLAIN_MAX_WIDTH = 500
    # 幅計算と表示で見るセルの文字数。表示幅は max_column_width 以下なので、
    # 極端に長いセル（数十万文字）を毎回走査しないための歯止め
    CELL_SCAN_LIMIT = 256

    attr_reader :width, :column_widths, :gutter_width, :max_column_width

    # @param sheet [TableSheet]
    # @param width [Integer, nil] 表示幅。nil / 0 以下なら内容に合わせた自然幅
    def self.build(sheet, width, max_column_width: DEFAULT_MAX_COLUMN_WIDTH, sample_rows: SAMPLE_ROWS)
      new(sheet, width, max_column_width: max_column_width, sample_rows: sample_rows)
    end

    # FilePreview の lines フォールバック用。グリッドを文字列の配列として返す。
    def self.plain_lines(document, max_lines: 50, max_column_width: DEFAULT_MAX_COLUMN_WIDTH)
      sheet = document.sheet
      return [] unless sheet

      layout = build(sheet, nil, max_column_width: max_column_width)
      layout = build(sheet, PLAIN_MAX_WIDTH, max_column_width: max_column_width) if layout.width > PLAIN_MAX_WIDTH

      lines = []
      lines << layout.header_line if sheet.header
      remaining = [max_lines - lines.length - 1, 0].max
      sheet.fetch_rows(0, remaining).each_with_index do |row, index|
        lines << layout.row_line(index + 1, row)
      end
      status = document.status_line
      lines << status if status && !status.empty?
      lines
    end

    def initialize(sheet, width, max_column_width: DEFAULT_MAX_COLUMN_WIDTH, sample_rows: SAMPLE_ROWS)
      @sheet = sheet
      @max_column_width = [max_column_width.to_i, MIN_COLUMN_WIDTH].max
      @column_widths = compute_column_widths(sample_rows)
      @gutter_digits = [sheet.row_count.to_s.length, MIN_GUTTER_DIGITS].max

      requested = width.to_i
      if requested <= 0
        @gutter_width = @gutter_digits + 1
        @width = natural_width
      else
        @width = requested
        @gutter_width = fits_gutter? ? @gutter_digits + 1 : 0
      end
    end

    def column_count
      @sheet.column_count
    end

    # col_offset から始まり、表示幅に収まる列インデックス（最低 1 列は返す）
    def visible_columns(col_offset = 0)
      return [] if column_count.zero?

      offset = col_offset.clamp(0, column_count - 1)
      available = @width - @gutter_width
      return [offset] if available <= 0

      columns = []
      consumed = 0
      (offset...column_count).each do |index|
        segment = SEGMENT_OVERHEAD + @column_widths[index]
        if consumed + segment > available
          columns << index if columns.empty?
          break
        end
        columns << index
        consumed += segment
      end
      columns
    end

    # 表示されていない右側の列数
    def hidden_column_count(col_offset = 0)
      visible = visible_columns(col_offset)
      return column_count if visible.empty?

      # 左にスクロールして隠れた列 + 右に収まらなかった列
      visible.first + (column_count - (visible.last + 1))
    end

    # column_index が表示範囲に入る最小の col_offset を返す（横スクロール量の計算）
    def offset_for(column_index, current_offset = 0)
      return 0 if column_count.zero?

      target = column_index.clamp(0, column_count - 1)
      offset = current_offset.clamp(0, column_count - 1)
      return target if target < offset

      offset += 1 while offset < target && !visible_columns(offset).include?(target)
      offset
    end

    # ペイン内のセル描画開始 x（セル本体の先頭。区切りとスペースの右側）
    # @return [Integer, nil] 表示範囲外なら nil
    def column_x(column_index, col_offset = 0)
      visible = visible_columns(col_offset)
      return nil unless visible.include?(column_index)

      x = @gutter_width
      visible.each do |index|
        return x + CELL_PREFIX.length if index == column_index

        x += SEGMENT_OVERHEAD + @column_widths[index]
      end
      nil
    end

    def column_width(column_index)
      @column_widths[column_index] || MIN_COLUMN_WIDTH
    end

    # セル 1 個分の表示文字列（改行・タブを畳み、列幅に揃える）
    def format_cell(value, column_index)
      TextUtils.pad_string_to_width(normalize(value), column_width(column_index))
    end

    def gutter_text(row_number)
      return '' if @gutter_width.zero?

      "#{row_number.to_s.rjust(@gutter_digits)} "
    end

    def header_line(col_offset = 0)
      line = ' ' * @gutter_width
      visible_columns(col_offset).each do |index|
        line += CELL_PREFIX + TextUtils.pad_string_to_width(@sheet.column_title(index), column_width(index)) + CELL_SUFFIX
      end
      fit(close(line))
    end

    # @param row_number [Integer] 1 始まりの表示用行番号
    # @param cells [Array<String>, nil]
    def row_line(row_number, cells, col_offset = 0)
      line = gutter_text(row_number)
      visible_columns(col_offset).each do |index|
        line += CELL_PREFIX + format_cell(cells && cells[index], index) + CELL_SUFFIX
      end
      fit(close(line))
    end

    private

    def natural_width
      @gutter_width + @column_widths.sum { |w| SEGMENT_OVERHEAD + w } + CLOSING_SEPARATOR.length
    end

    def fits_gutter?
      desired = @gutter_digits + 1
      @width - desired >= SEGMENT_OVERHEAD + MIN_COLUMN_WIDTH
    end

    def compute_column_widths(sample_rows)
      rows = @sheet.fetch_rows(0, sample_rows)
      Array.new(column_count) do |index|
        longest = TextUtils.display_width(@sheet.column_title(index))
        rows.each do |row|
          candidate = TextUtils.display_width(normalize(row[index]))
          longest = candidate if candidate > longest
        end
        longest.clamp(MIN_COLUMN_WIDTH, @max_column_width)
      end
    end

    # 表示用の正規化。セル内の改行・タブは幅計算を壊すのでスペースに畳む。
    # y でコピーする値は元のまま（TableSheet 側が保持している）。
    def normalize(value)
      return '' if value.nil?

      text = value.to_s
      text = text[0, CELL_SCAN_LIMIT] if text.length > CELL_SCAN_LIMIT
      text.gsub(/[\r\n\t]+/, ' ')
    end

    def close(line)
      TextUtils.display_width(line) + CLOSING_SEPARATOR.length <= @width ? line + CLOSING_SEPARATOR : line
    end

    # 幅に満たなければ空白で埋め、超えていれば切り詰める（セル側の "..." と区別するため
    # 行末では省略記号を付けない）
    def fit(line)
      current = TextUtils.display_width(line)
      return line + ' ' * (@width - current) if current < @width
      return line if current == @width

      clipped = ''
      consumed = 0
      line.each_char do |char|
        char_width = TextUtils.char_width(char)
        break if consumed + char_width > @width

        clipped += char
        consumed += char_width
      end
      consumed < @width ? clipped + ' ' * (@width - consumed) : clipped
    end
  end
end
