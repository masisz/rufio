# frozen_string_literal: true

require 'open3'

module Rufio
  # コマンドモード - DSLコマンドを実行するための統一インターフェース
  # すべてのコマンドはDslCommandとして扱われる
  class CommandMode
    attr_accessor :background_executor

    def initialize(background_executor = nil)
      @commands = {}
      @background_executor = background_executor
      load_builtin_commands
      load_dsl_commands
    end

    # コマンドを実行する
    def execute(command_string)
      # 空のコマンドは無視
      return nil if command_string.nil? || command_string.strip.empty?

      # シェルコマンドの実行 (! で始まる場合)
      if command_string.strip.start_with?('!')
        shell_command = command_string.strip[1..-1]

        # バックグラウンドエグゼキュータが利用可能な場合は非同期実行
        if @background_executor
          if @background_executor.execute_async(shell_command)
            return "🔄 バックグラウンドで実行中: #{shell_command.split.first}"
          else
            return "⚠️  既にコマンドが実行中です"
          end
        else
          # バックグラウンドエグゼキュータがない場合は同期実行
          return execute_shell_command(shell_command)
        end
      end

      # コマンド名を取得 (前後の空白を削除)
      command_name = command_string.strip.to_sym

      # 統一されたコマンドストアから検索
      command = @commands[command_name]
      unless command
        return "⚠️  コマンドが見つかりません: #{command_name}"
      end

      # 統一された実行パス
      execute_unified_command(command_name, command)
    end

    # 利用可能なコマンドのリストを取得
    def available_commands
      @commands.keys
    end

    # コマンドの情報を取得
    def command_info(command_name)
      command = @commands[command_name]
      return nil unless command

      {
        name: command_name,
        plugin: command[:source] || "dsl",
        description: command[:command].description
      }
    end

    # DSLコマンドをロードする
    # @param paths [Array<String>, nil] 設定ファイルのパス配列（nilの場合はデフォルトパス）
    def load_dsl_commands(paths = nil)
      loader = DslCommandLoader.new

      commands = if paths
                   loader.load_from_paths(paths)
                 else
                   loader.load
                 end

      # ユーザーDSLコマンドは既存のコマンドを上書きする（優先度が高い）
      commands.each do |cmd|
        @commands[cmd.name.to_sym] = {
          command: cmd,
          source: "dsl"
        }
      end
    end

    private

    # 組み込みコマンドをロードする
    def load_builtin_commands
      builtin = BuiltinCommands.load
      builtin.each do |name, cmd|
        @commands[name] = {
          command: cmd,
          source: "builtin"
        }
      end
    end

    # 統一されたコマンド実行
    # @param command_name [Symbol] コマンド名
    # @param command [Hash] コマンド情報 { command: DslCommand, source: String }
    # @return [Hash] 実行結果
    def execute_unified_command(command_name, command)
      dsl_cmd = command[:command]

      # バックグラウンドエグゼキュータが利用可能な場合は非同期実行
      if @background_executor
        command_display_name = command_name.to_s
        if @background_executor.execute_ruby_async(command_display_name) do
             ScriptExecutor.execute_command(dsl_cmd)
           end
          return "🔄 バックグラウンドで実行中: #{command_display_name}"
        else
          return "⚠️  既にコマンドが実行中です"
        end
      end

      # 同期実行
      ScriptExecutor.execute_command(dsl_cmd)
    end

    # シェルコマンドを実行する
    def execute_shell_command(shell_command)
      # コマンドが空の場合
      return { success: false, error: "コマンドが指定されていません" } if shell_command.strip.empty?

      begin
        # Open3を使って標準出力と標準エラーを分離して取得
        stdout, stderr, status = Open3.capture3(shell_command)

        result = {
          success: status.success?,
          output: stdout.strip,
          stderr: stderr.strip
        }

        # コマンドが失敗した場合、エラーメッセージを追加
        unless status.success?
          result[:error] = "コマンドが失敗しました (終了コード: #{status.exitstatus})"
        end

        result
      rescue Errno::ENOENT => e
        { success: false, error: "コマンドが見つかりません: #{e.message}" }
      rescue StandardError => e
        { success: false, error: "コマンド実行エラー: #{e.message}" }
      end
    end
  end
end
