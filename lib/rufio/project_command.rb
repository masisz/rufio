# frozen_string_literal: true

require 'open3'

module Rufio
  # プロジェクトコマンド - 登録されたコマンドを実行する
  class ProjectCommand
    def initialize(log_dir)
      @log_dir = log_dir
      @registered_commands = {}
    end

    # コマンドを実行する
    # @param command [String] 実行するコマンド
    # @param working_dir [String] 作業ディレクトリ
    # @return [Hash] 実行結果 { success: Boolean, output: String, error: String }
    def execute(command, working_dir)
      begin
        stdout, stderr, status = Open3.capture3(command, chdir: working_dir)

        {
          success: status.success?,
          output: stdout,
          error: stderr
        }
      rescue StandardError => e
        {
          success: false,
          output: '',
          error: "Command not found or failed to execute: #{e.message}"
        }
      end
    end

    # 登録されたコマンドを実行する
    # @param command_name [String] コマンド名
    # @param working_dir [String] 作業ディレクトリ
    # @return [Hash] 実行結果
    def execute_registered(command_name, working_dir)
      unless @registered_commands.key?(command_name)
        return {
          success: false,
          output: '',
          error: "Command '#{command_name}' not found in registered commands"
        }
      end

      command = @registered_commands[command_name]
      execute(command, working_dir)
    end

    # コマンドを登録する
    # @param name [String] コマンド名
    # @param command [String] コマンド文字列
    def register(name, command)
      @registered_commands[name] = command
    end

    # 登録されているコマンドの一覧を取得
    # @return [Array<String>] コマンド名の配列
    def list_registered_commands
      @registered_commands.keys
    end

    # 左画面用の表示データを取得
    # @return [Array<String>] コマンド名の配列
    def get_left_pane_data
      @registered_commands.keys.map.with_index(1) do |name, index|
        "#{index}. #{name}"
      end
    end
  end
end
