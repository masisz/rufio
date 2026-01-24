# frozen_string_literal: true

module Rufio
  # Noice風の通知を管理するクラス
  # 画面右上に最大3個までの通知を表示
  class NotificationManager
    MAX_NOTIFICATIONS = 3
    DEFAULT_DISPLAY_DURATION = 3  # 秒

    attr_reader :notifications

    def initialize
      @notifications = []
    end

    # 通知を追加
    # @param name [String] タスク名
    # @param type [Symbol] :success または :error
    # @param duration [Float] タスクの実行時間
    # @param exit_code [Integer, nil] 終了コード（エラー時のみ）
    # @param display_duration [Integer] 通知の表示時間（秒）
    def add(name, type, duration:, exit_code: nil, display_duration: DEFAULT_DISPLAY_DURATION)
      notification = {
        name: name,
        type: type,
        duration: duration,
        exit_code: exit_code,
        created_at: Time.now,
        display_duration: display_duration,
        border_color: type == :success ? :green : :red,
        status_text: build_status_text(type, duration)
      }

      @notifications << notification

      # 最大3個を超えた場合、最も古い通知を削除
      @notifications.shift if @notifications.size > MAX_NOTIFICATIONS
    end

    # 期限切れの通知を削除
    def expire_old_notifications
      now = Time.now
      @notifications.reject! do |notification|
        now - notification[:created_at] > notification[:display_duration]
      end
    end

    # 通知の数
    # @return [Integer]
    def count
      @notifications.size
    end

    # 全ての通知をクリア
    def clear
      @notifications.clear
    end

    private

    # ステータステキストを生成
    # @param type [Symbol] :success または :error
    # @param duration [Float] 実行時間
    # @return [String]
    def build_status_text(type, duration)
      formatted_duration = format('%.1fs', duration)
      case type
      when :success
        "Done (#{formatted_duration})"
      when :error
        "Failed (#{formatted_duration})"
      else
        formatted_duration
      end
    end
  end
end
