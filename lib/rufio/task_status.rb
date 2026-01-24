# frozen_string_literal: true

module Rufio
  # ジョブ（タスク）の状態を管理するクラス
  # status: :waiting, :running, :completed, :failed, :cancelled
  class TaskStatus
    attr_accessor :id, :name, :path, :status, :start_time, :end_time, :logs, :exit_code

    # 初期化
    # @param id [Integer] タスクID
    # @param name [String] タスク名（スクリプト名）
    # @param path [String] 実行ディレクトリ
    def initialize(id:, name:, path:)
      @id = id
      @name = name
      @path = path
      @status = :waiting
      @start_time = nil
      @end_time = nil
      @logs = []
      @exit_code = nil
    end

    # タスクを開始する
    def start
      @status = :running
      @start_time = Time.now
    end

    # タスクを完了する
    # @param exit_code [Integer] 終了コード
    def complete(exit_code:)
      @status = :completed
      @end_time = Time.now
      @exit_code = exit_code
    end

    # タスクを失敗させる
    # @param exit_code [Integer] 終了コード
    def fail(exit_code:)
      @status = :failed
      @end_time = Time.now
      @exit_code = exit_code
    end

    # タスクをキャンセルする
    def cancel
      @status = :cancelled
      @end_time = Time.now
    end

    # 実行時間を取得
    # @return [Float, nil] 秒単位の実行時間（未開始の場合はnil）
    def duration
      return nil unless @start_time

      (@end_time || Time.now) - @start_time
    end

    # ログを追加
    # @param line [String] ログ行
    def append_log(line)
      @logs << line
    end

    # 実行中かどうか
    # @return [Boolean]
    def running?
      @status == :running
    end

    # 完了したかどうか
    # @return [Boolean]
    def completed?
      @status == :completed
    end

    # 失敗したかどうか
    # @return [Boolean]
    def failed?
      @status == :failed
    end

    # キャンセルされたかどうか
    # @return [Boolean]
    def cancelled?
      @status == :cancelled
    end

    # ステータスアイコンを取得
    # @return [String] ステータスアイコン
    def status_icon
      case @status
      when :waiting
        '⏸'
      when :running
        '⚙'
      when :completed
        '✓'
      when :failed
        '✗'
      when :cancelled
        '⏹'
      else
        '?'
      end
    end

    # フォーマット済みの実行時間を取得
    # @return [String] "12.4s" 形式の文字列（未開始の場合は空文字列）
    def formatted_duration
      d = duration
      return '' unless d

      format('%.1fs', d)
    end
  end
end
