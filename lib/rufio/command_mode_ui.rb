# frozen_string_literal: true

require 'io/console'

module Rufio
  # コマンドモードのUI - Tab補完とフローティングウィンドウでの結果表示
  class CommandModeUI
    def initialize(command_mode, dialog_renderer)
      @command_mode = command_mode
      @dialog_renderer = dialog_renderer
      @terminal_ui = nil
      # 最後に表示したウィンドウの位置とサイズを保存
      @last_window = nil
    end

    # terminal_ui を設定
    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    # 入力文字列に対する補完候補を取得
    # @param input [String] 現在の入力文字列
    # @return [Array<String>] 補完候補の配列
    def autocomplete(input)
      # 利用可能なコマンド一覧を取得
      available = @command_mode.available_commands.map(&:to_s)

      # 入力が空の場合は全てのコマンドを返す
      return available if input.empty?

      # 入力に一致するコマンドをフィルタリング
      available.select { |cmd| cmd.start_with?(input) }
    end

    # コマンドを補完する
    # @param input [String] 現在の入力文字列
    # @return [String] 補完後の文字列
    def complete_command(input)
      suggestions = autocomplete(input)

      # マッチするものがない場合は元の入力を返す
      return input if suggestions.empty?

      # 一つだけマッチする場合はそれを返す
      return suggestions.first if suggestions.length == 1

      # 複数マッチする場合は共通プレフィックスを返す
      find_common_prefix(suggestions)
    end

    # コマンド入力プロンプトをフローティングウィンドウで表示
    # @param input [String] 現在の入力文字列
    # @param suggestions [Array<String>] 補完候補（オプション）
    def show_input_prompt(input, suggestions = [])
      # タイトル
      title = "Command Mode"

      # Build content lines
      content_lines = [""]
      content_lines << "#{input}_"  # Show cursor as _
      content_lines << ""
      content_lines << "Tab: Complete | Enter: Execute | ESC: Cancel"

      # ウィンドウの色設定（青）
      border_color = "\e[34m"      # Blue
      title_color = "\e[1;34m"     # Bold blue
      content_color = "\e[37m"     # White

      # ウィンドウサイズを計算
      width, height = @dialog_renderer.calculate_dimensions(content_lines, {
                                                               title: title,
                                                               min_width: 50,
                                                               max_width: 80
                                                             })

      # 中央位置を計算
      x, y = @dialog_renderer.calculate_center(width, height)

      # ウィンドウの位置とサイズを保存
      @last_window = { x: x, y: y, width: width, height: height }

      # フローティングウィンドウを描画
      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
                                               border_color: border_color,
                                               title_color: title_color,
                                               content_color: content_color
                                             })
    end

    # コマンド実行結果をフローティングウィンドウで表示
    # @param result [String, Hash, nil] コマンド実行結果
    def show_result(result)
      # nil または空文字列の場合は何も表示しない
      return if result.nil? || result.empty?

      # Hash形式の結果を処理
      if result.is_a?(Hash)
        result_text = format_hash_result(result)
        is_error = !result[:success]
      else
        # 文字列形式の結果（従来の動作）
        result_text = result
        is_error = result.include?("⚠️") || result.include?("Error")
      end

      # 結果を行に分割
      result_lines = result_text.split("\n")

      # ウィンドウの色設定
      if is_error
        border_color = "\e[31m"      # Red
        title_color = "\e[1;31m"     # Bold red
        content_color = "\e[37m"     # White
      else
        border_color = "\e[32m"      # Green
        title_color = "\e[1;32m"     # Bold green
        content_color = "\e[37m"     # White
      end

      # ウィンドウタイトル
      title = "Command Result"

      # コンテンツ行を構築
      content_lines = [""] + result_lines + ["", "Press any key to close"]

      # ウィンドウサイズを計算
      width, height = @dialog_renderer.calculate_dimensions(content_lines, {
                                                               title: title,
                                                               min_width: 40,
                                                               max_width: 100
                                                             })

      # オーバーレイダイアログを表示
      show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: border_color,
        title_color: title_color,
        content_color: content_color
      })
    end

    # コマンド入力プロンプトをクリア
    def clear_prompt
      return unless @last_window

      @dialog_renderer.clear_area(
        @last_window[:x],
        @last_window[:y],
        @last_window[:width],
        @last_window[:height]
      )
      @last_window = nil
    end

    private

    # オーバーレイダイアログを表示してキー入力を待つヘルパーメソッド
    def show_overlay_dialog(title, content_lines, options = {}, &block)
      # terminal_ui が利用可能で、screen と renderer が存在する場合のみオーバーレイを使用
      use_overlay = @terminal_ui &&
                    @terminal_ui.respond_to?(:screen) &&
                    @terminal_ui.respond_to?(:renderer) &&
                    @terminal_ui.screen &&
                    @terminal_ui.renderer

      if use_overlay
        # オーバーレイを使用
        @terminal_ui.show_overlay_dialog(title, content_lines, options, &block)
      else
        # フォールバック: 従来の方法
        width = options[:width]
        height = options[:height]

        unless width && height
          width, height = @dialog_renderer.calculate_dimensions(content_lines, {
            title: title,
            min_width: options[:min_width] || 40,
            max_width: options[:max_width] || 80
          })
        end

        x, y = @dialog_renderer.calculate_center(width, height)

        @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
          border_color: options[:border_color] || "\e[37m",
          title_color: options[:title_color] || "\e[1;33m",
          content_color: options[:content_color] || "\e[37m"
        })

        key = block_given? ? yield : STDIN.getch

        @dialog_renderer.clear_area(x, y, width, height)
        @terminal_ui&.refresh_display

        key
      end
    end

    # 文字列配列の共通プレフィックスを見つける
    # @param strings [Array<String>] 文字列配列
    # @return [String] 共通プレフィックス
    def find_common_prefix(strings)
      return "" if strings.empty?
      return strings.first if strings.length == 1

      # 最短の文字列の長さを取得
      min_length = strings.map(&:length).min

      # 各文字位置で全ての文字列が同じ文字を持っているかチェック
      common_length = 0
      min_length.times do |i|
        char = strings.first[i]
        if strings.all? { |s| s[i] == char }
          common_length = i + 1
        else
          break
        end
      end

      strings.first[0...common_length]
    end

    # Hash形式の結果を文字列に変換
    # @param result [Hash] コマンド実行結果
    # @return [String] フォーマットされた結果
    def format_hash_result(result)
      lines = []

      # エラーメッセージがある場合
      if result[:error]
        lines << result[:error]
        lines << ""
      end

      # 標準出力
      if result[:output] && !result[:output].empty?
        lines << result[:output]
      end

      # 標準エラー出力（空でない場合のみ）
      if result[:stderr] && !result[:stderr].empty?
        lines << "" if lines.any?
        lines << "--- stderr ---"
        lines << result[:stderr]
      end

      # 何も出力がない場合
      if lines.empty?
        if result[:success]
          lines << "Command executed successfully"
        else
          lines << "Command failed"
        end
      end

      lines.join("\n")
    end
  end
end
