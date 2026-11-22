# frozen_string_literal: true

require_relative 'csv_table_source'

module Rufio
  # プレビュー種別の登録表。
  #
  # 表として読める形式を追加するときは register_table_source を 1 行足すだけで、
  # FilePreview / UIRenderer / キー処理には手を入れない。
  #
  #   PreviewRegistry.register_table_source(XlsxTableSource)
  #   PreviewRegistry.register_table_source(SqliteTableSource)
  module PreviewRegistry
    DEFAULT_TABLE_SOURCES = [CsvTableSource].freeze

    class << self
      def table_sources
        @table_sources ||= DEFAULT_TABLE_SOURCES.dup
      end

      # 後に登録したものを先に試す（既定の挙動を後から上書きできる）
      def register_table_source(source)
        table_sources.unshift(source) unless table_sources.include?(source)
        source
      end

      # @return [Class, nil] path を表として扱える TableSource
      def table_source_for(path)
        return nil if path.nil? || path.to_s.empty?

        table_sources.find { |source| source.supports?(path) }
      end

      def table?(path)
        !table_source_for(path).nil?
      end

      # テスト用: 登録を初期状態へ戻す
      def reset!
        @table_sources = DEFAULT_TABLE_SOURCES.dup
      end
    end
  end
end
