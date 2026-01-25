# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'

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
        bookmark.key?(:path) &&
        bookmark.key?(:name) &&
        bookmark[:path].is_a?(String) &&
        bookmark[:name].is_a?(String)
    end

    def filter_valid_bookmarks(bookmarks)
      return [] unless bookmarks.is_a?(Array)

      bookmarks.select { |b| valid_bookmark?(b) }
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

  # YAML形式のブックマークストレージ（config.ymlに統合）
  class YamlBookmarkStorage < BookmarkStorage
    def load
      return [] unless File.exist?(@file_path)

      content = YAML.safe_load(File.read(@file_path), symbolize_names: true)
      return [] unless content.is_a?(Hash) && content[:bookmarks]

      filter_valid_bookmarks(content[:bookmarks])
    rescue StandardError
      []
    end

    def save(bookmarks)
      ensure_directory

      # 既存の設定を読み込み
      existing_config = if File.exist?(@file_path)
                          YAML.safe_load(File.read(@file_path), symbolize_names: true) || {}
                        else
                          {}
                        end

      # ブックマークを文字列キーのハッシュに変換（YAMLの可読性のため）
      bookmarks_for_yaml = bookmarks.map do |b|
        { 'path' => b[:path], 'name' => b[:name] }
      end

      # ブックマークセクションを更新
      existing_config_string_keys = deep_stringify_keys(existing_config)
      existing_config_string_keys['bookmarks'] = bookmarks_for_yaml

      File.write(@file_path, YAML.dump(existing_config_string_keys))
      true
    rescue StandardError => e
      warn "Failed to save bookmarks to YAML: #{e.message}"
      false
    end

    private

    def deep_stringify_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.transform_keys(&:to_s).transform_values do |v|
        case v
        when Hash
          deep_stringify_keys(v)
        when Array
          v.map { |item| item.is_a?(Hash) ? deep_stringify_keys(item) : item }
        else
          v
        end
      end
    end
  end

  # ブックマークのJSON→YAMLマイグレーター
  class BookmarkMigrator
    class << self
      def migrate(json_path, yaml_path)
        return false unless File.exist?(json_path)

        # JSONからブックマークを読み込み
        json_storage = JsonBookmarkStorage.new(json_path)
        bookmarks = json_storage.load

        # YAMLに保存
        yaml_storage = YamlBookmarkStorage.new(yaml_path)
        yaml_storage.save(bookmarks)

        # JSONファイルをバックアップして削除
        backup_path = "#{json_path}.bak"
        FileUtils.mv(json_path, backup_path)

        true
      rescue StandardError => e
        warn "Failed to migrate bookmarks: #{e.message}"
        false
      end
    end
  end
end
