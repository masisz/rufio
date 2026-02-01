# frozen_string_literal: true

module Rufio
  # タブモード管理クラス
  # 上部メニューの2段目に表示するモードタブを管理する
  class TabModeManager
    MODES = %i[files logs jobs help].freeze

    MODE_LABELS = {
      files: 'Files',
      logs: 'Logs',
      jobs: 'Jobs',
      help: 'Help'
    }.freeze

    attr_reader :current_mode

    def initialize
      @current_mode = :files
      @mode_change_callback = nil
    end

    # 利用可能なモード一覧
    def available_modes
      MODES
    end

    # モードのラベル一覧
    def mode_labels
      MODE_LABELS
    end

    # 次のモードに切り替え
    def next_mode
      current_index = MODES.index(@current_mode)
      new_index = (current_index + 1) % MODES.length
      switch_to(MODES[new_index])
    end

    # 前のモードに切り替え
    def previous_mode
      current_index = MODES.index(@current_mode)
      new_index = (current_index - 1) % MODES.length
      switch_to(MODES[new_index])
    end

    # 特定のモードに切り替え
    def switch_to(mode)
      return unless MODES.include?(mode)
      return if @current_mode == mode

      @current_mode = mode
      @mode_change_callback&.call(mode)
    end

    # 現在のモード情報を取得
    def current_mode_info
      {
        mode: @current_mode,
        label: MODE_LABELS[@current_mode],
        index: MODES.index(@current_mode)
      }
    end

    # モード変更時のコールバックを設定
    def on_mode_change(&block)
      @mode_change_callback = block
    end

    # タブ行をレンダリング
    # @param width [Integer] 画面幅
    # @return [String] ANSIエスケープシーケンスを含むタブ行
    def render_tab_line(width)
      tabs = MODES.map do |mode|
        label = MODE_LABELS[mode]
        if mode == @current_mode
          # 現在のモード: シアン背景 + 黒文字 + 太字で目立たせる
          "\e[46m\e[30m\e[1m #{label} \e[0m"
        else
          # 非選択モード: 暗めの色
          "\e[90m #{label} \e[0m"
        end
      end

      tab_content = tabs.join("\e[90m│\e[0m")

      # 幅に合わせてパディング
      # ANSIエスケープシーケンスを除いた実際の表示幅を計算
      display_width = strip_ansi(tab_content).length
      padding = width - display_width

      if padding > 0
        tab_content + ' ' * padding
      else
        tab_content[0...width]
      end
    end

    private

    # ANSIエスケープシーケンスを除去して実際の表示幅を取得
    def strip_ansi(str)
      str.gsub(/\e\[[0-9;]*m/, '')
    end
  end
end
