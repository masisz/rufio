# frozen_string_literal: true

require 'open3'

module Rufio
  # バックグラウンドでシェルコマンドを実行するクラス
  class BackgroundCommandExecutor
    attr_reader :command_logger

    # 初期化
    # @param command_logger [CommandLogger] コマンドロガー
    def initialize(command_logger)
      @command_logger = command_logger
      @thread = nil
      @command = nil
      @completed = false
      @completion_message = nil
    end

    # コマンドを非同期で実行
    # @param command [String] 実行するコマンド
    # @return [Boolean] 実行を開始した場合はtrue、既に実行中の場合はfalse
    def execute_async(command)
      # 既に実行中の場合は新しいコマンドを開始しない
      return false if running?

      @command = command
      @completed = false
      @completion_message = nil

      @thread = Thread.new do
        begin
          # コマンドを実行
          stdout, stderr, status = Open3.capture3(command)

          # 結果をログに保存
          output = stdout + stderr
          success = status.success?

          error_message = success ? nil : stderr

          @command_logger.log(
            command,
            output,
            success: success,
            error: error_message
          )

          # 完了メッセージを生成
          command_name = extract_command_name(command)
          if success
            @completion_message = "✓ #{command_name} 完了"
          else
            @completion_message = "✗ #{command_name} 失敗"
          end

          @completed = true
        rescue StandardError => e
          # エラーが発生した場合もログに記録
          @command_logger.log(
            command,
            "",
            success: false,
            error: e.message
          )

          command_name = extract_command_name(command)
          @completion_message = "✗ #{command_name} エラー"
          @completed = true
        end
      end

      true
    end

    # コマンドが実行中かどうか
    # @return [Boolean] 実行中の場合はtrue
    def running?
      @thread&.alive? || false
    end

    # 完了メッセージを取得
    # @return [String, nil] 完了メッセージ（完了していない場合はnil）
    def get_completion_message
      @completion_message
    end

    private

    # コマンド文字列からコマンド名を抽出
    # @param command [String] コマンド
    # @return [String] コマンド名
    def extract_command_name(command)
      # 最初の単語を取得
      command.strip.split.first || 'command'
    end
  end
end
