# frozen_string_literal: true

require 'yaml'

module Rufio
  # プラグインの設定を管理するクラス
  class PluginConfig
    class << self
      # 設定ファイルを読み込む
      def load
        config_path = File.expand_path('~/.rufio/config.yml')

        if File.exist?(config_path)
          begin
            @config = YAML.load_file(config_path) || {}
          rescue StandardError => e
            warn "⚠️  Failed to load config file: #{e.message}"
            @config = {}
          end
        else
          # 設定ファイルが存在しない場合はデフォルト設定（空のハッシュ）
          @config = {}
        end
      end

      # プラグインが有効かどうかをチェックする
      def plugin_enabled?(name)
        # 設定が未読み込みの場合は読み込む
        load if @config.nil?

        # pluginsセクションがない場合は全プラグイン有効
        return true unless @config.is_a?(Hash) && @config['plugins']

        plugins_config = @config['plugins']
        return true unless plugins_config.is_a?(Hash)

        # プラグイン名を小文字に統一して検索
        normalized_name = name.to_s.downcase

        # 設定のキーも小文字に変換して検索
        plugin_setting = nil
        plugins_config.each do |key, value|
          if key.downcase == normalized_name
            plugin_setting = value
            break
          end
        end

        # 設定が存在しない場合は有効とみなす
        return true if plugin_setting.nil?

        # enabled設定を確認（デフォルトはtrue）
        return true unless plugin_setting.is_a?(Hash)

        plugin_setting.fetch('enabled', true)
      end
    end
  end
end
