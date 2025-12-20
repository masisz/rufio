# frozen_string_literal: true

module Rufio
  # コマンドモード - プラグインコマンドを実行するためのインターフェース
  class CommandMode
    def initialize
      @commands = {}
      load_plugin_commands
    end

    # コマンドを実行する
    def execute(command_string)
      # 空のコマンドは無視
      return nil if command_string.nil? || command_string.strip.empty?

      # コマンド名を取得 (前後の空白を削除)
      command_name = command_string.strip.to_sym

      # コマンドが存在するかチェック
      unless @commands.key?(command_name)
        return "⚠️  コマンドが見つかりません: #{command_name}"
      end

      # コマンドを実行
      begin
        command_method = @commands[command_name][:method]
        command_method.call
      rescue StandardError => e
        "⚠️  コマンド実行エラー: #{e.message}"
      end
    end

    # 利用可能なコマンドのリストを取得
    def available_commands
      @commands.keys
    end

    # コマンドの情報を取得
    def command_info(command_name)
      return nil unless @commands.key?(command_name)

      {
        name: command_name,
        plugin: @commands[command_name][:plugin],
        description: @commands[command_name][:description]
      }
    end

    private

    # プラグインからコマンドを読み込む
    def load_plugin_commands
      # 有効なプラグインを取得
      enabled_plugins = PluginManager.enabled_plugins

      # 各プラグインからコマンドを取得
      enabled_plugins.each do |plugin|
        plugin_name = plugin.name
        plugin_commands = plugin.commands

        # 各コマンドを登録
        plugin_commands.each do |command_name, command_method|
          @commands[command_name] = {
            method: command_method,
            plugin: plugin_name,
            description: plugin.description
          }
        end
      end
    end
  end
end
