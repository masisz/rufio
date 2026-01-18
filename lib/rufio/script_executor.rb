# frozen_string_literal: true

require "open3"
require "timeout"

module Rufio
  # スクリプトを安全に実行するクラス
  class ScriptExecutor
    class << self
      # スクリプトを実行する
      # @param interpreter [String] インタープリタ（ruby, python3, bashなど）
      # @param script_path [String] スクリプトのパス
      # @param args [Array<String>] スクリプトへの引数
      # @param timeout [Numeric, nil] タイムアウト秒数（nilの場合は無制限）
      # @param chdir [String, nil] 作業ディレクトリ
      # @param env [Hash, nil] 環境変数
      # @return [Hash] 実行結果
      def execute(interpreter, script_path, args = [], timeout: nil, chdir: nil, env: nil)
        # 配列ベースのコマンドを構築（シェルインジェクション防止）
        command = [interpreter, script_path, *args]

        # オプションを構築
        options = {}
        options[:chdir] = chdir if chdir
        # 環境変数をマージ（既存の環境変数を保持）
        spawn_env = env || {}

        execute_with_options(command, spawn_env, options, timeout)
      rescue StandardError => e
        build_error_result(e)
      end

      # DslCommandを実行する（タイプ別に分岐）
      # @param dsl_command [DslCommand] 実行するDSLコマンド
      # @param args [Array<String>] 追加の引数
      # @param timeout [Numeric, nil] タイムアウト秒数
      # @param chdir [String, nil] 作業ディレクトリ
      # @param env [Hash, nil] 環境変数
      # @return [Hash] 実行結果
      def execute_command(dsl_command, args = [], timeout: nil, chdir: nil, env: nil)
        case dsl_command.command_type
        when :ruby
          execute_ruby(dsl_command)
        when :shell
          execute_shell(dsl_command, timeout: timeout, chdir: chdir, env: env)
        else
          exec_args = dsl_command.to_execution_args
          execute(exec_args[0], exec_args[1], args, timeout: timeout, chdir: chdir, env: env)
        end
      end

      # inline Rubyコマンドを実行する
      # @param dsl_command [DslCommand] 実行するDSLコマンド
      # @return [Hash] 実行結果
      def execute_ruby(dsl_command)
        result = dsl_command.ruby_block.call
        {
          success: true,
          exit_code: 0,
          stdout: result.to_s,
          stderr: "",
          timeout: false
        }
      rescue StandardError => e
        {
          success: false,
          exit_code: 1,
          stdout: "",
          stderr: "",
          error: e.message,
          timeout: false
        }
      end

      # inline シェルコマンドを実行する
      # @param dsl_command [DslCommand] 実行するDSLコマンド
      # @param timeout [Numeric, nil] タイムアウト秒数
      # @param chdir [String, nil] 作業ディレクトリ
      # @param env [Hash, nil] 環境変数
      # @return [Hash] 実行結果
      def execute_shell(dsl_command, timeout: nil, chdir: nil, env: nil)
        options = {}
        options[:chdir] = chdir if chdir
        spawn_env = env || {}

        if timeout
          execute_shell_with_timeout(dsl_command.shell_command, spawn_env, options, timeout)
        else
          execute_shell_without_timeout(dsl_command.shell_command, spawn_env, options)
        end
      rescue StandardError => e
        build_error_result(e)
      end

      private

      # コマンドを実行し、結果を返す
      # @param command [Array<String>] 実行するコマンド
      # @param env [Hash] 環境変数
      # @param options [Hash] Open3オプション
      # @param timeout_sec [Numeric, nil] タイムアウト秒数
      # @return [Hash] 実行結果
      def execute_with_options(command, env, options, timeout_sec)
        if timeout_sec
          execute_with_timeout(command, env, options, timeout_sec)
        else
          execute_without_timeout(command, env, options)
        end
      end

      # タイムアウト付きで実行
      def execute_with_timeout(command, env, options, timeout_sec)
        stdout = ""
        stderr = ""
        status = nil
        timed_out = false
        pid = nil

        begin
          Timeout.timeout(timeout_sec) do
            stdin, stdout_io, stderr_io, wait_thread = Open3.popen3(env, *command, **options)
            pid = wait_thread.pid
            stdin.close
            stdout = stdout_io.read
            stderr = stderr_io.read
            stdout_io.close
            stderr_io.close
            status = wait_thread.value
          end
        rescue Timeout::Error
          timed_out = true
          # プロセスを終了
          if pid
            begin
              Process.kill("TERM", pid)
              sleep 0.1
              Process.kill("KILL", pid)
            rescue Errno::ESRCH, Errno::EPERM
              # プロセスが既に終了している、または権限がない
            end
          end
        end

        if timed_out
          {
            success: false,
            exit_code: nil,
            stdout: stdout,
            stderr: stderr,
            timeout: true
          }
        else
          {
            success: status&.success? || false,
            exit_code: status&.exitstatus || 1,
            stdout: stdout,
            stderr: stderr,
            timeout: false
          }
        end
      end

      # タイムアウトなしで実行
      def execute_without_timeout(command, env, options)
        stdout, stderr, status = Open3.capture3(env, *command, **options)

        {
          success: status.success?,
          exit_code: status.exitstatus,
          stdout: stdout,
          stderr: stderr,
          timeout: false
        }
      end

      # シェルコマンドをタイムアウト付きで実行
      def execute_shell_with_timeout(shell_command, env, options, timeout_sec)
        stdout = ""
        stderr = ""
        status = nil
        timed_out = false
        pid = nil

        begin
          Timeout.timeout(timeout_sec) do
            stdin, stdout_io, stderr_io, wait_thread = Open3.popen3(env, shell_command, **options)
            pid = wait_thread.pid
            stdin.close
            stdout = stdout_io.read
            stderr = stderr_io.read
            stdout_io.close
            stderr_io.close
            status = wait_thread.value
          end
        rescue Timeout::Error
          timed_out = true
          if pid
            begin
              Process.kill("TERM", pid)
              sleep 0.1
              Process.kill("KILL", pid)
            rescue Errno::ESRCH, Errno::EPERM
              # プロセスが既に終了している、または権限がない
            end
          end
        end

        if timed_out
          {
            success: false,
            exit_code: nil,
            stdout: stdout,
            stderr: stderr,
            timeout: true
          }
        else
          {
            success: status&.success? || false,
            exit_code: status&.exitstatus || 1,
            stdout: stdout,
            stderr: stderr,
            timeout: false
          }
        end
      end

      # シェルコマンドをタイムアウトなしで実行
      def execute_shell_without_timeout(shell_command, env, options)
        stdout, stderr, status = Open3.capture3(env, shell_command, **options)

        {
          success: status.success?,
          exit_code: status.exitstatus,
          stdout: stdout,
          stderr: stderr,
          timeout: false
        }
      end

      # エラー結果を構築
      def build_error_result(error)
        {
          success: false,
          exit_code: 1,
          stdout: "",
          stderr: "",
          error: error.message,
          timeout: false
        }
      end
    end
  end
end
