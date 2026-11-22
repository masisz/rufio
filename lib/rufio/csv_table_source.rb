# frozen_string_literal: true

require 'csv'
require_relative 'table_source'
require_relative 'table_document'
require_relative 'encoding_detector'

module Rufio
  # CSV / TSV を表として読む TableSource。
  class CsvTableSource < TableSource
    # 拡張子ごとの既定の区切り文字
    DELIMITERS = {
      '.csv' => ',',
      '.tsv' => "\t",
      '.tab' => "\t"
    }.freeze

    # 区切り文字の自動判定で数える候補
    SNIFF_CANDIDATES = [',', ';', "\t"].freeze

    class << self
      def supports?(path)
        DELIMITERS.key?(File.extname(path.to_s).downcase)
      end

      # @return [TableDocument]
      def open(path, limits: TableSource::Limits.default, options: {})
        decoded = EncodingDetector.read_text(
          path, max_bytes: limits.max_bytes, encoding: options.fetch(:encoding, 'auto')
        )
        delimiter = resolve_delimiter(path, decoded.text, options[:delimiter])
        rows, row_truncated, column_truncated = parse(decoded.text, delimiter, limits)

        header = options.fetch(:header, true) && !rows.empty? ? rows.shift : nil
        sheet = MemoryTableSheet.new(
          name: File.basename(path.to_s), header: header, rows: rows,
          row_truncated: row_truncated, column_truncated: column_truncated
        )

        TableDocument.new(
          sheets: [sheet], encoding: decoded.encoding,
          byte_truncated: decoded.truncated, label: File.basename(path.to_s)
        )
      end

      private

      # 設定 > 拡張子 > 1 行目の文字数による推定
      def resolve_delimiter(path, text, configured)
        return configured if configured.is_a?(String) && !configured.empty? && configured != 'auto'

        default = DELIMITERS[File.extname(path.to_s).downcase] || ','
        return default unless default == ','

        sniff(text) || default
      end

      # 欧州式 CSV（';' 区切り）を拾う。',' より明らかに多い候補だけ採用する。
      def sniff(text)
        line = text.each_line.find { |candidate| !candidate.strip.empty? }
        return nil unless line

        counts = SNIFF_CANDIDATES.map { |char| [char, line.count(char)] }.to_h
        best = counts.max_by { |_, count| count }
        return nil if best.nil? || best[1].zero? || best[0] == ','
        return nil unless best[1] > counts[',']

        best[0]
      end

      def parse(text, delimiter, limits)
        raw_rows = parse_rows(text, delimiter, limits.max_rows)
        row_truncated = raw_rows.length > limits.max_rows
        raw_rows = raw_rows[0, limits.max_rows] if row_truncated

        column_truncated = false
        rows = raw_rows.map do |row|
          cells = Array(row).map { |value| value.nil? ? '' : value.to_s }
          if cells.length > limits.max_columns
            cells = cells[0, limits.max_columns]
            column_truncated = true
          end
          cells
        end

        [rows, row_truncated, column_truncated]
      end

      # 壊れた CSV を 3 段階で読む。
      #   1. 通常のパース
      #   2. liberal_parsing（引用符の中途半端な使い方を許容する）
      #   3. 閉じ引用符を補う（バイト上限が引用符つきセルの途中に当たった場合）
      # すべて失敗したら ParseError にして、呼び出し側でテキストプレビューへ戻す。
      #
      # 表示する行数が決まっているので、読み込んだバイト全体をパースせず
      # row_limit + 1 行で打ち切る。こうするとバイト上限を広げても解析時間は増えない。
      def parse_rows(text, delimiter, row_limit)
        attempts = [
          [text, false],
          [text, true],
          ["#{text}\"", true]
        ]

        last_error = nil
        attempts.each do |source, liberal|
          return read_rows(source, delimiter, liberal, row_limit)
        rescue CSV::MalformedCSVError, ArgumentError => e
          last_error = e
        end

        raise TableSource::ParseError, last_error.message
      end

      # 切り詰めの有無を判定できるよう、上限より 1 行だけ多く読む
      def read_rows(source, delimiter, liberal, row_limit)
        rows = []
        CSV.new(source, col_sep: delimiter, liberal_parsing: liberal).each do |row|
          rows << row
          break if rows.length > row_limit
        end
        rows
      end
    end
  end
end
