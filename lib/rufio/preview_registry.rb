# frozen_string_literal: true

require_relative 'csv_table_source'

require 'monitor'

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

    # 同じファイルを二度パースしないための小さなキャッシュ（ファイル数）
    CACHE_LIMIT = 4

    # FilePreview（描画ループ）と FuzzyPreviewLoader（別スレッド）から呼ばれるため
    # キャッシュはロックで守る
    LOCK = Monitor.new

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

      # 表として読み込む。パス・更新時刻・サイズ・設定が同じなら前回の結果を返す。
      # @return [TableDocument, nil] 表として扱えない場合は nil
      def load_table(path, limits:, options: {})
        source = table_source_for(path)
        return nil unless source

        key = [File.expand_path(path), File.mtime(path).to_f, File.size(path), limits, options]
        LOCK.synchronize do
          cached = cache[key]
          return cached if cached
        end

        document = source.open(path, limits: limits, options: options)
        LOCK.synchronize do
          cache.shift while cache.size >= CACHE_LIMIT
          cache[key] = document
        end
        document
      end

      def clear_cache!
        LOCK.synchronize { @cache = {} }
      end

      # テスト用: 登録とキャッシュを初期状態へ戻す
      def reset!
        @table_sources = DEFAULT_TABLE_SOURCES.dup
        clear_cache!
      end

      private

      def cache
        @cache ||= {}
      end
    end
  end
end
