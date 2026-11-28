# frozen_string_literal: true

require_relative 'preview_registry'
require_relative 'table_layout'
require_relative 'table_source'

module Rufio
  class FilePreview
    BINARY_THRESHOLD = 0.3  # treat as binary if 30% or more binary characters
    DEFAULT_MAX_LINES = 50
    # プレビューモード（P）はスクロールとファイル内検索（/）で先の行まで見るため、
    # 行数の上限を広げる。読み込む量そのものは MAX_PREVIEW_BYTES が決める
    PREVIEW_MODE_MAX_LINES = 20_000
    MAX_LINE_LENGTH = 500
    MAX_PREVIEW_BYTES = 64 * 1024

    # Binary detection constants
    BINARY_SAMPLE_SIZE = 512
    PRINTABLE_CHAR_THRESHOLD = 32
    CONTROL_CHAR_TAB = 9
    CONTROL_CHAR_NEWLINE = 10
    CONTROL_CHAR_CARRIAGE_RETURN = 13

    # ZIPプレビューで一覧表示するエントリ数の上限
    ARCHIVE_PREVIEW_ENTRIES = 200

    def initialize
      # future: hold syntax highlight settings etc.
    end

    def preview_file(file_path, max_lines: DEFAULT_MAX_LINES)
      return error_response(ConfigLoader.message('file.not_found')) unless File.exist?(file_path)
      return error_response(ConfigLoader.message('file.not_readable')) unless File.readable?(file_path)

      file_size = File.size(file_path)
      return empty_response if file_size == 0

      begin
        # PDF bodies are not displayed; never scan their binary streams as text.
        return binary_response(file_path) if File.extname(file_path).casecmp?('.pdf')

        # 表として読める形式（CSV / TSV / Excel / SQLite）はグリッド表示に回す。
        # UTF-16 の CSV は NUL バイトが多くバイナリ判定に引っかかるため、判定より前に置く。
        table, table_error = table_response(file_path, max_lines)
        return table if table

        # 表として読めなかった場合は従来の流れに戻す（.xlsx なら ZIP のエントリ一覧になる）
        with_table_error(fallback_response(file_path, file_size, max_lines), table_error)
      rescue => e
        error_response("#{ConfigLoader.message('file.read_error')}: #{e.message}")
      end
    end

    private

    # 表として読めなかったときの従来の流れ（ZIP → バイナリ → テキスト）
    def fallback_response(file_path, file_size, max_lines)
      return archive_response(file_path, max_lines) if zip_archive?(file_path)

      sample = File.binread(file_path, [file_size, BINARY_SAMPLE_SIZE].min)
      return binary_response(file_path) if binary_file?(sample)

      text_response(file_path, max_lines)
    end

    # 表として読めなかった理由は、テキスト表示になったときだけ先頭行に出す
    def with_table_error(response, table_error)
      return response if table_error.nil? || !%w[text code].include?(response[:type])

      response[:table_error] = table_error
      response[:lines] = ["(#{ConfigLoader.message('file.not_parsed_as_table')}: #{table_error})"] +
                         Array(response[:lines])
      response
    end

    # 通常のテキスト／コードプレビュー
    def text_response(file_path, max_lines)
      lines = read_text_file(file_path, max_lines)
      file_type = determine_file_type(file_path)

      {
        type: file_type[:type],
        language: file_type[:language],
        lines: lines[:content],
        truncated: lines[:truncated],
        size: File.size(file_path),
        modified: File.mtime(file_path),
        encoding: lines[:encoding]
      }
    end

    # 行列（グリッド）プレビュー。
    # lines には整形済みのグリッド文字列も入れておき、表描画を知らない利用側
    # （検索画面のプレビューなど）でもそのまま読めるようにする。
    # @return [Array(Hash, nil), Array(nil, String)] 表として読めなければ [nil, 理由]
    def table_response(file_path, max_lines)
      return [nil, nil] unless PreviewRegistry.table?(file_path)

      settings = ConfigLoader.table_preview
      limits = TableSource::Limits.new(
        max_bytes: settings[:max_bytes],
        max_rows: settings[:max_rows],
        max_columns: settings[:max_columns]
      )
      document = PreviewRegistry.load_table(
        file_path,
        limits: limits,
        options: {
          header: settings[:header],
          delimiter: settings[:delimiter],
          encoding: settings[:encoding]
        }
      )
      raise TableSource::ParseError, 'no table source' unless document

      [{
        type: 'table',
        language: nil,
        document: document,
        # グリッドの文字列は表示を知らない利用側向けの控えなので、行数は既定の上限で足りる
        lines: TableLayout.plain_lines(
          document, max_lines: [max_lines, DEFAULT_MAX_LINES].min,
          max_column_width: settings[:max_column_width]
        ),
        truncated: document.truncated?,
        size: File.size(file_path),
        modified: File.mtime(file_path),
        encoding: document.encoding
      }, nil]
    rescue TableSource::ParseError => e
      [nil, e.message]
    end

    def zip_archive?(file_path)
      File.extname(file_path).casecmp?('.zip') || ZipArchive.zip_signature?(file_path)
    end

    # unzip -l 相当のエントリ一覧をプレビュー行として返す
    def archive_response(file_path, max_lines)
      limit = [max_lines, ARCHIVE_PREVIEW_ENTRIES].max
      listing = ZipArchive.list(file_path, limit: limit)
      total_size = listing.entries.sum(&:size)

      lines = ["ZIP archive: #{listing.total_entries} entries#{' (ZIP64)' if listing.zip64?}", '']
      lines << format('%12s  %-8s  %-16s  %s', 'Length', 'Method', 'Modified', 'Name')
      lines << format('%12s  %-8s  %-16s  %s', '-' * 10, '-' * 8, '-' * 16, '-' * 4)
      listing.entries.each do |entry|
        modified = entry.mtime ? entry.mtime.strftime('%Y-%m-%d %H:%M') : '-'
        method = entry.encrypted? ? "#{ZipArchive.method_name(entry.method)}*" : ZipArchive.method_name(entry.method)
        lines << format('%12d  %-8s  %-16s  %s', entry.size, method, modified, entry.name)
      end
      lines << format('%12s', '-' * 10)
      if listing.truncated?
        lines << "... #{listing.total_entries - listing.entries.length} more entries"
      else
        lines << format('%12d  %d files', total_size, listing.entries.length)
      end
      lines << "Comment: #{listing.comment}" unless listing.comment.empty?

      {
        type: "archive",
        language: nil,
        lines: lines,
        truncated: listing.truncated?,
        size: File.size(file_path),
        modified: File.mtime(file_path),
        encoding: "UTF-8"
      }
    rescue ZipArchive::FormatError => e
      error_response("#{ConfigLoader.message('file.invalid_archive')}: #{e.message}")
    end

    def binary_file?(sample)
      return false if sample.empty?

      allowed_control_chars = [CONTROL_CHAR_TAB, CONTROL_CHAR_NEWLINE, CONTROL_CHAR_CARRIAGE_RETURN]
      binary_chars = sample.bytes.count { |byte| byte < PRINTABLE_CHAR_THRESHOLD && !allowed_control_chars.include?(byte) }
      (binary_chars.to_f / sample.bytes.length) > BINARY_THRESHOLD
    end

    def read_text_file(file_path, max_lines)
      # Bound the read before decoding or splitting: a binary stream or minified
      # file can contain a single line spanning the entire file.
      content = File.binread(file_path, MAX_PREVIEW_BYTES + 1)
      truncated = content.bytesize > MAX_PREVIEW_BYTES
      content = content.byteslice(0, MAX_PREVIEW_BYTES) if truncated
      content = content.force_encoding('UTF-8').encode(
        'UTF-8', invalid: :replace, undef: :replace, replace: '?'
      )
      lines = []
      content.each_line.with_index do |line, index|
        if index >= max_lines
          truncated = true
          break
        end

        line = line[0...MAX_LINE_LENGTH] + '...' if line.length > MAX_LINE_LENGTH
        lines << line.chomp
      end

      {
        content: lines,
        truncated: truncated,
        encoding: 'UTF-8'
      }
    end

    def determine_file_type(file_path)
      extension = File.extname(file_path).downcase
      basename = File.basename(file_path)

      # 拡張子なしファイル名での判定（Dockerfile 等）
      case basename
      when "Dockerfile", /\ADockerfile\./
        return { type: "code", language: "dockerfile" }
      when "Makefile", "GNUmakefile"
        return { type: "code", language: "makefile" }
      end

      case extension
      when ".rb"
        { type: "code", language: "ruby" }
      when ".py"
        { type: "code", language: "python" }
      when ".js", ".mjs"
        { type: "code", language: "javascript" }
      when ".ts"
        { type: "code", language: "typescript" }
      when ".html", ".htm"
        { type: "code", language: "html" }
      when ".css"
        { type: "code", language: "css" }
      when ".json"
        { type: "code", language: "json" }
      when ".yml", ".yaml"
        { type: "code", language: "yaml" }
      when ".md", ".markdown"
        { type: "code", language: "markdown" }
      when ".go"
        { type: "code", language: "go" }
      when ".rs"
        { type: "code", language: "rust" }
      when ".sh", ".bash", ".zsh"
        { type: "code", language: "shell" }
      when ".toml"
        { type: "code", language: "toml" }
      when ".sql"
        { type: "code", language: "sql" }
      when ".c", ".h"
        { type: "code", language: "c" }
      when ".cpp", ".cc", ".cxx", ".hpp"
        { type: "code", language: "cpp" }
      when ".java"
        { type: "code", language: "java" }
      when ".txt", ".log"
        { type: "text", language: nil }
      when ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z"
        { type: "archive", language: nil }
      when ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg"
        { type: "image", language: nil }
      when ".pdf"
        { type: "document", language: nil }
      when ".exe", ".dmg", ".deb", ".rpm"
        { type: "executable", language: nil }
      else
        { type: "text", language: nil }
      end
    end

    def empty_response
      {
        type: "empty",
        lines: [],
        size: 0,
        modified: File.mtime(""),
        encoding: "UTF-8"
      }
    rescue
      {
        type: "empty",
        lines: [],
        size: 0,
        modified: Time.now,
        encoding: "UTF-8"
      }
    end

    def binary_response(file_path = nil)
      file_size = file_path ? File.size(file_path) : 0
      modified_time = file_path ? File.mtime(file_path) : Time.now
      
      {
        type: "binary",
        message: "#{ConfigLoader.message('file.binary_file')} - #{ConfigLoader.message('file.cannot_preview')}",
        lines: ["(#{ConfigLoader.message('file.binary_file')})"],
        size: file_size,
        modified: modified_time,
        encoding: "binary"
      }
    rescue => _e
      {
        type: "binary",
        message: "#{ConfigLoader.message('file.binary_file')} - #{ConfigLoader.message('file.cannot_preview')}",
        lines: ["(#{ConfigLoader.message('file.binary_file')})"],
        size: 0,
        modified: Time.now,
        encoding: "binary"
      }
    end

    def error_response(message)
      {
        type: "error",
        message: message,
        lines: ["#{ConfigLoader.message('file.error_prefix')}: #{message}"],
        size: 0,
        modified: Time.now,
        encoding: "UTF-8"
      }
    end
  end
end