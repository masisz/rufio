# frozen_string_literal: true

require_relative 'table_document'

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
    Limits = Struct.new(:max_bytes, :max_rows, :max_columns, keyword_init: true) do
      def self.default
        new(max_bytes: 64 * 1024, max_rows: 1000, max_columns: 256)
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
