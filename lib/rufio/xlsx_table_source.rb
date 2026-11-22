# frozen_string_literal: true

require_relative 'table_source'
require_relative 'table_document'

module Rufio
  # Excel（.xlsx / .xlsm）と OpenDocument（.ods）を表として読む TableSource。
  # 既に依存している roo を使い、シートは表示するものだけを読む。
  class XlsxTableSource < TableSource
    EXTENSIONS = %w[.xlsx .xlsm .ods].freeze

    # roo はワークブックを展開するためメモリを食う。大きすぎるファイルは表にしない
    # （プレビューは ZIP のエントリ一覧にフォールバックする）
    MAX_FILE_SIZE = 10 * 1024 * 1024

    class << self
      def supports?(path)
        EXTENSIONS.include?(File.extname(path.to_s).downcase)
      end

      def open(path, limits: TableSource::Limits.default, options: {})
        size = File.size(path)
        if size > MAX_FILE_SIZE
          raise TableSource::ParseError, "file is larger than #{MAX_FILE_SIZE / (1024 * 1024)} MiB"
        end

        book = open_workbook(path)
        header_enabled = options.fetch(:header, true)

        sheets = book.sheets.map do |name|
          LazyTableSheet.new(name: name) { load_sheet(book, name, limits, header_enabled) }
        end
        raise TableSource::ParseError, 'no sheets' if sheets.empty?

        TableDocument.new(sheets: sheets, encoding: 'UTF-8', label: File.basename(path.to_s))
      rescue TableSource::ParseError
        raise
      rescue StandardError => e
        raise TableSource::ParseError, "#{e.class}: #{e.message}"
      end

      private

      # roo は読み込みが重いので、使うときだけ require する
      def open_workbook(path)
        require 'roo'

        case File.extname(path.to_s).downcase
        when '.ods' then Roo::OpenOffice.new(path.to_s)
        else Roo::Excelx.new(path.to_s)
        end
      end

      def load_sheet(book, name, limits, header_enabled)
        rows = []
        row_truncated = false
        column_truncated = false

        each_sheet_row(book, name) do |row|
          if rows.length >= limits.max_rows
            row_truncated = true
            next false
          end

          cells = row.map { |cell| cell_text(cell) }
          if cells.length > limits.max_columns
            cells = cells[0, limits.max_columns]
            column_truncated = true
          end
          rows << cells
          true
        end

        header = header_enabled && !rows.empty? ? rows.shift : nil
        { rows: rows, header: header, row_truncated: row_truncated, column_truncated: column_truncated }
      end

      # 行を 1 行ずつ渡す。ブロックが false を返したら読み取りを止める。
      # .xlsx はストリーミング API があるが、.ods（Roo::OpenOffice）には無いので行番号で読む。
      def each_sheet_row(book, name)
        sheet = book.sheet(name)

        if sheet.respond_to?(:each_row_streaming)
          # pad_cells: 空セルを nil で埋める（埋めないと桁がずれる）
          sheet.each_row_streaming(pad_cells: true) { |row| break unless yield(Array(row)) }
        else
          first = sheet.first_row
          last = sheet.last_row
          return if first.nil? || last.nil?

          (first..last).each { |number| break unless yield(Array(sheet.row(number))) }
        end
      end

      # 書式は再現せず、値をそのまま文字列にする（整数は .0 を付けない）
      def cell_text(cell)
        value = cell.respond_to?(:value) ? cell.value : cell
        case value
        when nil then ''
        when Float then value == value.to_i ? value.to_i.to_s : value.to_s
        when Time then value.strftime('%H:%M:%S')
        else
          if defined?(Date) && value.is_a?(Date)
            value.strftime('%Y-%m-%d')
          else
            value.to_s
          end
        end
      end
    end
  end
end
