# frozen_string_literal: true

require 'fileutils'
require 'time'

module Rufio
  # プロジェクトログ - コマンド実行ログを管理する
  class ProjectLog
    def initialize(log_dir)
      @log_dir = log_dir
      FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
    end

    # ログを保存する
    # @param project_name [String] プロジェクト名
    # @param command [String] 実行したコマンド
    # @param output [String] コマンドの出力
    # @return [String] 保存したログファイルのパス
    def save(project_name, command, output)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      log_filename = "#{project_name}_#{timestamp}.log"
      log_path = File.join(@log_dir, log_filename)

      log_content = <<~LOG
        Project: #{project_name}
        Command: #{command}
        Timestamp: #{Time.now}

        Output:
        #{output}
      LOG

      File.write(log_path, log_content)
      log_path
    end

    # ログディレクトリに移動する
    # @return [Hash] ログディレクトリ情報
    def navigate_to_log_dir
      {
        path: @log_dir
      }
    end

    # ログファイルの一覧を取得（新しい順）
    # @return [Array<String>] ログファイル名の配列
    def list_log_files
      log_files = Dir.glob(File.join(@log_dir, '*.log'))

      # ファイルの更新時刻でソート（新しい順）
      log_files.sort_by { |f| -File.mtime(f).to_i }
                .map { |f| File.basename(f) }
    end

    # ログファイルのプレビューを取得
    # @param filename [String] ログファイル名
    # @return [String] ログファイルの内容
    def preview(filename)
      log_path = File.join(@log_dir, filename)

      return '' unless File.exist?(log_path)

      File.read(log_path)
    rescue StandardError
      ''
    end
  end
end
