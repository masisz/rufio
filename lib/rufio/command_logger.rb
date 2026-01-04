# frozen_string_literal: true

require 'fileutils'
require 'time'

module Rufio
  # コマンド実行ログを保存・管理するクラス
  class CommandLogger
    attr_reader :log_dir

    # 初期化
    # @param log_dir [String] ログディレクトリのパス
    def initialize(log_dir)
      @log_dir = log_dir
      FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
    end

    # コマンド実行ログを保存
    # @param command [String] 実行したコマンド
    # @param output [String] コマンドの出力
    # @param success [Boolean] 実行が成功したかどうか
    # @param error [String, nil] エラーメッセージ（失敗時）
    def log(command, output, success:, error: nil)
      timestamp = Time.now
      filename = generate_filename(command, timestamp)
      filepath = File.join(@log_dir, filename)

      content = format_log_content(command, output, timestamp, success, error)

      # ディレクトリが存在しない場合は作成（バックグラウンドスレッドでの実行時の競合を防ぐ）
      FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)

      File.write(filepath, content)
    end

    # ログファイル一覧を取得（新しい順）
    # @return [Array<String>] ログファイルのパス一覧
    def list_logs
      Dir.glob(File.join(@log_dir, "*.log")).sort.reverse
    end

    # 古いログを削除
    # @param max_logs [Integer] 保管する最大ログ数
    def cleanup_old_logs(max_logs:)
      logs = list_logs
      return if logs.size <= max_logs

      logs_to_delete = logs[max_logs..-1]
      logs_to_delete.each do |log_file|
        File.delete(log_file)
      end
    end

    private

    # ログファイル名を生成
    # @param command [String] コマンド
    # @param timestamp [Time] タイムスタンプ
    # @return [String] ファイル名
    def generate_filename(command, timestamp)
      # ミリ秒を含めて一意性を確保
      timestamp_str = timestamp.strftime("%Y%m%d%H%M%S") + sprintf("%03d", (timestamp.usec / 1000).to_i)
      command_part = sanitize_command(command)
      "#{timestamp_str}-#{command_part}.log"
    end

    # コマンド文字列をファイル名用にサニタイズ
    # @param command [String] コマンド
    # @return [String] サニタイズされたコマンド
    def sanitize_command(command)
      # Remove ! prefix if exists
      cmd = command.start_with?('!') ? command[1..-1] : command

      # Take first word (command name)
      cmd = cmd.split.first || 'command'

      # Remove unsafe characters
      cmd = cmd.gsub(/[^\w\-]/, '_')

      # Limit length
      cmd[0...50]
    end

    # ログ内容をフォーマット
    # @param command [String] コマンド
    # @param output [String] 出力
    # @param timestamp [Time] タイムスタンプ
    # @param success [Boolean] 成功フラグ
    # @param error [String, nil] エラーメッセージ
    # @return [String] フォーマットされたログ内容
    def format_log_content(command, output, timestamp, success, error)
      lines = []
      lines << "=" * 80
      lines << "Command Execution Log"
      lines << "=" * 80
      lines << ""
      lines << "Timestamp: #{timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
      lines << "Command:   #{command}"
      lines << "Status:    #{success ? 'Success' : 'Failed'}"
      lines << ""

      if error
        lines << "Error:"
        lines << error
        lines << ""
      end

      if output && !output.empty?
        lines << "Output:"
        lines << "-" * 80
        lines << output
        lines << "-" * 80
      end

      lines << ""
      lines << "=" * 80

      lines.join("\n")
    end
  end
end
