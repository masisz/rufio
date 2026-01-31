# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require_relative 'config'

module Rufio
  # ブックマークストレージの基底クラス
  class BookmarkStorage
    def initialize(file_path)
      @file_path = file_path
    end

    def load
      raise NotImplementedError, 'Subclasses must implement #load'
    end

    def save(_bookmarks)
      raise NotImplementedError, 'Subclasses must implement #save'
    end

    protected

    def ensure_directory
      dir = File.dirname(@file_path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    end

    def valid_bookmark?(bookmark)
      bookmark.is_a?(Hash) &&
        (bookmark.key?(:path) || bookmark.key?('path')) &&
        (bookmark.key?(:name) || bookmark.key?('name'))
    end

    def normalize_bookmark(bookmark)
      {
        path: bookmark[:path] || bookmark['path'],
        name: bookmark[:name] || bookmark['name']
      }
    end

    def filter_valid_bookmarks(bookmarks)
      return [] unless bookmarks.is_a?(Array)

      bookmarks.select { |b| valid_bookmark?(b) }.map { |b| normalize_bookmark(b) }
    end
  end

  # JSON形式のブックマークストレージ
  class JsonBookmarkStorage < BookmarkStorage
    def load
      return [] unless File.exist?(@file_path)

      content = File.read(@file_path)
      bookmarks = JSON.parse(content, symbolize_names: true)
      filter_valid_bookmarks(bookmarks)
    rescue JSON::ParserError, StandardError
      []
    end

    def save(bookmarks)
      ensure_directory
      File.write(@file_path, JSON.pretty_generate(bookmarks))
      true
    rescue StandardError => e
      warn "Failed to save bookmarks to JSON: #{e.message}"
      false
    end
  end

  # YAML形式のブックマークストレージ（新旧形式対応）
  # 新形式: bookmarks.yml（配列形式）
  # 旧形式: config.yml（bookmarksセクション）
  class YamlBookmarkStorage < BookmarkStorage
    def load
      return [] unless File.exist?(@file_path)

      # 新形式: bookmarks.yml（配列形式）
      if @file_path.end_with?('bookmarks.yml')
        return Config.load_bookmarks_from_yml(@file_path)
      end

      # 旧形式: config.yml（bookmarksセクション）
      yaml = YAML.safe_load(File.read(@file_path), symbolize_names: true)
      return [] unless yaml.is_a?(Hash)

      bookmarks = yaml[:bookmarks] || []
      filter_valid_bookmarks(bookmarks)
    rescue StandardError
      []
    end

    def save(bookmarks)
      ensure_directory

      # 新形式: bookmarks.yml（配列形式）
      if @file_path.end_with?('bookmarks.yml')
        Config.save_bookmarks_to_yml(@file_path, bookmarks)
        return true
      end

      # 旧形式: config.yml（bookmarksセクション - 既存の設定を保持）
      existing = if File.exist?(@file_path)
                   YAML.safe_load(File.read(@file_path), symbolize_names: false) || {}
                 else
                   {}
                 end

      existing['bookmarks'] = bookmarks.map do |b|
        { 'path' => b[:path], 'name' => b[:name] }
      end

      File.write(@file_path, YAML.dump(existing))
      true
    rescue StandardError => e
      warn "Failed to save bookmarks to YAML: #{e.message}"
      false
    end
  end

  # JSONからYAMLへのマイグレーター
  class BookmarkMigrator
    # @param json_path [String] JSONファイルのパス
    # @param yaml_path [String] YAMLファイルのパス
    # @return [Boolean] マイグレーションが実行されたかどうか
    def self.migrate(json_path, yaml_path)
      return false unless File.exist?(json_path)

      # JSONからブックマークを読み込む
      json_storage = JsonBookmarkStorage.new(json_path)
      bookmarks = json_storage.load

      return false if bookmarks.empty?

      # YAMLに保存
      yaml_storage = YamlBookmarkStorage.new(yaml_path)
      yaml_storage.save(bookmarks)

      # JSONファイルをバックアップ
      FileUtils.mv(json_path, "#{json_path}.bak")

      true
    rescue StandardError => e
      warn "Migration failed: #{e.message}"
      false
    end
  end
end
