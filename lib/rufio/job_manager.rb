# frozen_string_literal: true

require_relative 'task_status'

module Rufio
  # 複数のジョブを管理するクラス
  # ジョブの追加、状態追跡、通知連携を行う
  class JobManager
    attr_reader :jobs

    def initialize(notification_manager: nil)
      @jobs = []
      @notification_manager = notification_manager
      @next_id = 1
    end

    # ジョブを追加
    # @param name [String] ジョブ名
    # @param path [String] 実行ディレクトリ
    # @param command [String] 実行コマンド
    # @return [TaskStatus] 作成されたジョブ
    def add_job(name:, path:, command:)
      job = TaskStatus.new(
        id: @next_id,
        name: name,
        path: path
      )
      # commandを保存（TaskStatusに追加）
      job.instance_variable_set(:@command, command)
      job.define_singleton_method(:command) { @command }

      @jobs << job
      @next_id += 1
      job
    end

    # IDでジョブを検索
    # @param id [Integer] ジョブID
    # @return [TaskStatus, nil]
    def find_job(id)
      @jobs.find { |job| job.id == id }
    end

    # ジョブ数を取得
    # @return [Integer]
    def job_count
      @jobs.size
    end

    # 実行中のジョブ数
    # @return [Integer]
    def running_count
      @jobs.count(&:running?)
    end

    # 完了したジョブ数
    # @return [Integer]
    def completed_count
      @jobs.count(&:completed?)
    end

    # 失敗したジョブ数
    # @return [Integer]
    def failed_count
      @jobs.count(&:failed?)
    end

    # ステータスサマリーを取得
    # @return [Hash] { total:, running:, done:, failed: }
    def status_summary
      {
        total: @jobs.size,
        running: running_count,
        done: completed_count,
        failed: failed_count
      }
    end

    # ジョブをキャンセル
    # @param id [Integer] ジョブID
    # @return [Boolean] キャンセル成功かどうか
    def cancel_job(id)
      job = find_job(id)
      return false unless job

      job.cancel
      true
    end

    # 完了したジョブをクリア
    def clear_completed
      @jobs.reject! { |job| job.completed? || job.cancelled? }
    end

    # ステータスバー用のテキストを生成
    # @return [String] "3 jobs: 2 running, 1 done" のような形式
    def status_bar_text
      summary = status_summary
      "#{summary[:total]} jobs: #{summary[:running]} running, #{summary[:done]} done"
    end

    # ジョブがあるかどうか
    # @return [Boolean]
    def has_jobs?
      !@jobs.empty?
    end

    # 実行中のジョブがあるかどうか
    # @return [Boolean]
    def any_running?
      @jobs.any?(&:running?)
    end

    # ジョブ完了時の通知を送信（NotificationManagerと連携）
    # @param job [TaskStatus] 完了したジョブ
    def notify_completion(job)
      return unless @notification_manager

      type = job.completed? ? :success : :error
      @notification_manager.add(
        job.name,
        type,
        duration: job.duration || 0,
        exit_code: job.exit_code
      )
    end
  end
end
