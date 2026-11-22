# frozen_string_literal: true

module Rufio
  # 表プレビューの 1 シート。
  # CSV は 1 枚、Excel はシート、SQLite はテーブルがそれぞれこれに対応する。
  #
  # 行は fetch_rows(offset, limit) 経由でのみ取得する。こうしておくと、
  # 全行をメモリに持つ形式（CSV）と、必要な範囲だけ読む形式（SQLite の LIMIT/OFFSET、
  # Excel のストリーミング）を同じ表示コードで扱える。
  class TableSheet
    attr_reader :name, :header, :row_count, :column_count, :row_truncated, :column_truncated

    def initialize(name:, header: nil, row_count: 0, column_count: 0,
                   row_truncated: false, column_truncated: false)
      @name = name
      @header = header
      @row_count = row_count
      @column_count = column_count
      @row_truncated = row_truncated
      @column_truncated = column_truncated
    end

    # @param offset [Integer] 0 始まりのデータ行番号
    # @param limit [Integer] 取得する行数
    # @return [Array<Array<String>>]
    def fetch_rows(_offset, _limit)
      raise NotImplementedError, "#{self.class} must implement fetch_rows"
    end

    def empty?
      @row_count.zero?
    end

    # @return [Array<String>, nil] 1 行
    def row(index)
      fetch_rows(index, 1).first
    end

    # @return [String, nil] 生のセル値（表示用に畳んでいない値）
    def cell(row_index, column_index)
      values = row(row_index)
      return nil unless values

      values[column_index]
    end

    # 列見出し（A, B, ... Z, AA, AB, ...）。Excel の列名と同じ規則。
    def column_label(index)
      return '' if index.negative?

      label = ''
      number = index
      loop do
        label = ((number % 26) + 65).chr + label
        number = number / 26 - 1
        break if number.negative?
      end
      label
    end

    # ヘッダ行に表示する文字列（"A name" / ヘッダなしなら "A"）
    def column_title(index)
      title = @header && @header[index]
      title.nil? || title.empty? ? column_label(index) : "#{column_label(index)} #{title}"
    end
  end

  # 行をメモリ上に保持するシート（CSV のような一括読み形式向け）
  class MemoryTableSheet < TableSheet
    def initialize(rows:, name:, header: nil, row_truncated: false, column_truncated: false)
      @rows = rows
      widths = rows.map(&:length)
      widths << header.length if header
      super(name: name, header: header, row_count: rows.length,
            column_count: widths.max || 0,
            row_truncated: row_truncated, column_truncated: column_truncated)
    end

    def fetch_rows(offset, limit)
      return [] if offset.negative? || limit <= 0

      @rows.slice(offset, limit) || []
    end
  end

  # 1 ファイル分の表データ。複数シートを持つ形式（Excel / SQLite）にも対応する。
  class TableDocument
    attr_reader :sheets, :encoding, :byte_truncated, :label

    def initialize(sheets:, encoding: 'UTF-8', byte_truncated: false, label: nil)
      @sheets = sheets
      @encoding = encoding
      @byte_truncated = byte_truncated
      @label = label
    end

    def sheet(index = 0)
      @sheets[index]
    end

    def sheet_count
      @sheets.length
    end

    def truncated?
      @byte_truncated || @sheets.any? { |sheet| sheet.row_truncated || sheet.column_truncated }
    end

    # 画面最下行に出す情報（行数・列数・文字コード・切り詰め）
    def status_line(index = 0)
      target = sheet(index)
      return nil unless target

      parts = []
      parts << "#{index + 1}/#{sheet_count} #{target.name}" if sheet_count > 1
      parts << "#{target.row_count}#{'+' if target.row_truncated} rows"
      parts << "#{target.column_count}#{'+' if target.column_truncated} cols"
      parts << @encoding unless @encoding == 'UTF-8'
      parts << 'byte limit reached' if @byte_truncated
      parts.join('  ')
    end
  end
end
