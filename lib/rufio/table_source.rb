# frozen_string_literal: true

require_relative 'table_document'
require_relative 'config_loader'

module Rufio
  # 表として読める形式の共通インターフェース。
  #
  # 形式を追加するときに実装するのは supports? と open の 2 つだけで、
  # 描画（TableLayout / UIRenderer）とキー処理には手を入れない。
  #
  #   class SqliteTableSource < TableSource
  #     def self.supports?(path) = ...
  #     def self.open(path, limits:, options: {}) = TableDocument.new(sheets: [...])
  #   end
  class TableSource
    # 表として解釈できなかったとき（テキストプレビューへフォールバックする）
    class ParseError < StandardError; end

    # 読み込みの上限。形式に依存しない共通の歯止め。
    # 既定値は設定（TABLE_PREVIEW）から取り、上限の定義を 1 箇所にする。
    Limits = Struct.new(:max_bytes, :max_rows, :max_columns, keyword_init: true) do
      def self.default
        settings = ConfigLoader.table_preview
        new(max_bytes: settings[:max_bytes], max_rows: settings[:max_rows],
            max_columns: settings[:max_columns])
      end
    end

    class << self
      # @param _path [String]
      # @return [Boolean] この形式として扱えるか
      def supports?(_path)
        false
      end

      # @param _path [String]
      # @param limits [Limits]
      # @param options [Hash] 形式ごとの設定（header / delimiter / encoding など）
      # @return [TableDocument]
      def open(_path, limits: Limits.default, options: {})
        raise NotImplementedError, "#{self} must implement open"
      end
    end
  end
end
