# frozen_string_literal: true

module Rufio
  # プラグインを管理するクラス
  class PluginManager
    class << self
      # 登録済みプラグインクラスのリスト
      def plugins
        @plugins ||= []
      end

      # プラグインを登録する
      def register(plugin_class)
        @plugins ||= []
        @plugins << plugin_class unless @plugins.include?(plugin_class)
      end

      # 全プラグインを読み込む（本体同梱 + ユーザープラグイン）
      def load_all
        load_builtin_plugins
        load_user_plugins
      end

      # 有効なプラグインインスタンスのリストを取得
      def enabled_plugins
        return @enabled_plugins if @enabled_plugins

        @enabled_plugins = []

        plugins.each do |plugin_class|
          # プラグイン名を取得（クラス名から推測）
          plugin_name = plugin_class.name.split('::').last

          # PluginConfigで有効かチェック
          next unless PluginConfig.plugin_enabled?(plugin_name)

          # プラグインのインスタンスを作成
          begin
            plugin_instance = plugin_class.new
            @enabled_plugins << plugin_instance
          rescue Plugin::DependencyError => e
            warn "⚠️  #{e.message}"
            # プラグインは無効化されるが、rufioは起動継続
          rescue StandardError => e
            warn "⚠️  Failed to load plugin #{plugin_name}: #{e.message}"
          end
        end

        @enabled_plugins
      end

      private

      # 本体同梱プラグインを読み込む
      def load_builtin_plugins
        # plugin_manager.rbは/lib/rufio/にあるので、pluginsディレクトリは同じディレクトリ内
        builtin_plugins_dir = File.join(__dir__, 'plugins')
        return unless Dir.exist?(builtin_plugins_dir)

        Dir.glob(File.join(builtin_plugins_dir, '*.rb')).sort.each do |file|
          begin
            require file
          rescue StandardError => e
            warn "⚠️  Failed to load builtin plugin #{File.basename(file)}: #{e.message}"
          end
        end
      end

      # ユーザープラグインを読み込む
      def load_user_plugins
        user_plugins_dir = File.expand_path('~/.rufio/plugins')
        return unless Dir.exist?(user_plugins_dir)

        Dir.glob(File.join(user_plugins_dir, '*.rb')).sort.each do |file|
          begin
            require file
          rescue SyntaxError, StandardError => e
            warn "⚠️  Failed to load user plugin #{File.basename(file)}: #{e.message}"
          end
        end
      end
    end
  end
end
