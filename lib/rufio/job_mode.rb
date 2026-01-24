# frozen_string_literal: true

module Rufio
  # ジョブモードのUI管理クラス
  # ジョブ一覧の表示、選択、操作を行う
  class JobMode
    attr_reader :selected_index

    def initialize(job_manager:)
      @job_manager = job_manager
      @active = false
      @selected_index = 0
      @log_mode = false
    end

    # ジョブモードを有効化
    def activate
      @active = true
      @selected_index = 0
      @log_mode = false
    end

    # ジョブモードを無効化
    def deactivate
      @active = false
      @log_mode = false
    end

    # ジョブモードが有効かどうか
    # @return [Boolean]
    def active?
      @active
    end

    # ログモードが有効かどうか
    # @return [Boolean]
    def log_mode?
      @log_mode
    end

    # ログモードに入る
    def enter_log_mode
      @log_mode = true
    end

    # ログモードを終了
    def exit_log_mode
      @log_mode = false
    end

    # 下に移動
    def move_down
      max_index = [@job_manager.job_count - 1, 0].max
      @selected_index = [@selected_index + 1, max_index].min
    end

    # 上に移動
    def move_up
      @selected_index = [@selected_index - 1, 0].max
    end

    # 先頭に移動
    def move_to_top
      @selected_index = 0
    end

    # 末尾に移動
    def move_to_bottom
      @selected_index = [@job_manager.job_count - 1, 0].max
    end

    # 選択中のジョブを取得
    # @return [TaskStatus, nil]
    def selected_job
      return nil if @job_manager.jobs.empty?

      @job_manager.jobs[@selected_index]
    end

    # 選択中のジョブをキャンセル
    # @return [Boolean]
    def cancel_selected_job
      job = selected_job
      return false unless job

      @job_manager.cancel_job(job.id)
    end

    # キー入力を処理
    # @param key [String] 入力されたキー
    # @return [Boolean, Symbol] 処理結果
    def handle_key(key)
      # ログモード中の処理
      if @log_mode
        return handle_log_mode_key(key)
      end

      case key
      when 'j'
        move_down
        true
      when 'k'
        move_up
        true
      when 'g'
        move_to_top
        true
      when 'G'
        move_to_bottom
        true
      when 'x'
        cancel_selected_job
        true
      when ' '  # Space
        enter_log_mode if selected_job
        :show_log
      when "\e"  # Escape
        deactivate
        :exit
      else
        false
      end
    end

    private

    # ログモード中のキー処理
    # @param key [String] 入力されたキー
    # @return [Boolean, Symbol]
    def handle_log_mode_key(key)
      case key
      when "\e"  # Escape
        exit_log_mode
        true
      when 'j'
        # ログのスクロール（将来実装）
        true
      when 'k'
        # ログのスクロール（将来実装）
        true
      else
        false
      end
    end
  end
end
