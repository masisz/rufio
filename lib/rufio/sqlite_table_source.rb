# frozen_string_literal: true

require 'csv'
require_relative 'table_source'
require_relative 'table_document'
require_relative 'command_locator'

module Rufio
  # SQLite のデータベースをテーブルごとの表として読む TableSource。
  #
  # rga / bat / zoxide と同じ「インストールされていれば使う」方式で、sqlite3 コマンドが
  # 無ければ表として扱わない（プレビューは従来のバイナリ表示になる）。gem を増やさない。
  #
  # 判定は拡張子ではなくファイル先頭のシグネチャで行う。拡張子は .db / .sqlite に限らず
  # 何でもよく、逆に .db という名前の別形式を誤って開くこともない。
  #
  # 実行は argv（シェル非経由）で、必ず読み取り専用で開き、発行するのは SELECT だけ。
  class SqliteTableSource < TableSource
    COMMAND = 'sqlite3'
    SIGNATURE = "SQLite format 3\x00".b
    # 表示するテーブル（sqlite_ で始まる内部テーブルは除く）
    TABLE_LIST_SQL = "SELECT name FROM sqlite_master WHERE type IN ('table','view') " \
                     "AND name NOT LIKE 'sqlite_%' ORDER BY name;"

    class << self
      def supports?(path)
        return false unless command_available?

        file = path.to_s
        return false unless File.file?(file)

        sqlite_file?(file)
      end

      def open(path, limits: TableSource::Limits.default, options: {})
        tables = list_tables(path)
        raise TableSource::ParseError, 'no tables' if tables.empty?

        sheets = tables.map do |table|
          LazyTableSheet.new(name: table) { load_table(path, table, limits, options) }
        end

        TableDocument.new(sheets: sheets, encoding: 'UTF-8', label: File.basename(path.to_s))
      end

      # sqlite3 コマンドが使えるか（テストから差し替えられるよう public）
      def command_available?
        return @command_available unless @command_available.nil?

        @command_available = CommandLocator.available?(COMMAND)
      end

      # argv を受け取り [出力, 成功したか] を返す Proc（テストから差し替える）
      def runner
        @runner ||= method(:run_command)
      end

      # -safe を付けられるか（古い sqlite3 は知らないオプションで失敗する）。
      # プロセス内で 1 度だけ確認する
      def safe_mode_supported?
        return @safe_mode_supported unless @safe_mode_supported.nil?

        _output, ok = runner.call([COMMAND, '-safe', '-csv', ':memory:', 'SELECT 1;'])
        @safe_mode_supported = ok
      end

      attr_writer :runner

      def reset!
        @runner = nil
        @command_available = nil
        @safe_mode_supported = nil
        CommandLocator.reset!
      end

      private

      def sqlite_file?(file)
        File.binread(file, SIGNATURE.bytesize) == SIGNATURE
      rescue SystemCallError
        false
      end

      def list_tables(path)
        output = query(path, TABLE_LIST_SQL, header: false)
        CSV.parse(output).flatten.compact.map(&:strip).reject(&:empty?)
      rescue CSV::MalformedCSVError => e
        raise TableSource::ParseError, e.message
      end

      def load_table(path, table, limits, options)
        # 上限 + 1 行だけ取り、全体の件数を数える COUNT(*) は発行しない
        sql = "SELECT * FROM #{quote_identifier(table)} LIMIT #{limits.max_rows + 1};"
        parsed = CSV.parse(query(path, sql, header: true))

        # 列の切り詰めは見出し行にも掛ける（掛け忘れると列数が行とずれる）
        column_truncated = false
        rows = parsed.map do |row|
          cells = Array(row).map { |value| value.nil? ? '' : value.to_s }
          if cells.length > limits.max_columns
            cells = cells[0, limits.max_columns]
            column_truncated = true
          end
          cells
        end

        header = options.fetch(:header, true) && !rows.empty? ? rows.shift : nil
        row_truncated = rows.length > limits.max_rows
        rows = rows[0, limits.max_rows] if row_truncated

        { rows: rows, header: header, row_truncated: row_truncated, column_truncated: column_truncated }
      end

      def query(path, sql, header:)
        argv = [COMMAND, '-readonly', '-csv']
        # -safe は writefile() / load_extension() / ATTACH などを拒否する（sqlite3 3.34+）。
        # 読み取り専用の SELECT しか発行しないため、この機能に失うものはない
        argv << '-safe' if safe_mode_supported?
        argv << '-header' if header
        # SECURITY.md の方針どおり、'-' で始まるパスがオプションと解釈されないようにする
        argv += [File.expand_path(path.to_s), sql]

        output, ok = runner.call(argv)
        raise TableSource::ParseError, "#{COMMAND} failed" unless ok

        force_utf8(output)
      end

      def run_command(argv)
        output = IO.popen(argv, 'r', err: File::NULL, &:read)
        status = Process.last_status
        [force_utf8(output), status.nil? || status.success?]
      rescue SystemCallError, IOError => e
        raise TableSource::ParseError, e.message
      end

      # コマンドの出力は Encoding.default_external になる（LANG が無い環境では US-ASCII）。
      # sqlite3 は UTF-8 で出力するため、読み替えないと日本語を含むテーブルで
      # CSV が「Invalid byte sequence」になる。
      def force_utf8(output)
        text = output.to_s.dup.force_encoding(Encoding::UTF_8)
        text.valid_encoding? ? text : text.scrub('?')
      end

      # テーブル名は識別子クォートする（SQL を文字列連結で組まない）
      def quote_identifier(name)
        %("#{name.to_s.gsub('"', '""')}")
      end
    end
  end
end
