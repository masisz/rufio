# frozen_string_literal: true

require 'io/console'

module Rufio
  # ダイアログの表示方式選択と入力待ち・後片付けを共有する。
  # 利用側は @dialog_renderer と @terminal_ui を設定する。
  module DialogSupport
    CONFIRMATION_CANCEL_KEYS = ["n", "\e", "\x03"].freeze

    private

    # 表示とキー判定を共有し、終了確認だけは従来どおり q を無視する。
    def confirm_dialog(title, content_lines, options = {}, cancel_on_quit: true)
      confirmed = false
      show_overlay_dialog(title, content_lines, options) do
        confirmed = read_confirmation(cancel_on_quit: cancel_on_quit)
        nil
      end
      confirmed
    end

    def read_confirmation(cancel_on_quit: true)
      loop do
        input = STDIN.getch.downcase
        return true if input == 'y'
        return false if CONFIRMATION_CANCEL_KEYS.include?(input) || (cancel_on_quit && input == 'q')
      end
    end

    def show_overlay_dialog(title, content_lines, options = {}, &block)
      use_overlay = @terminal_ui &&
                    @terminal_ui.respond_to?(:screen) &&
                    @terminal_ui.respond_to?(:renderer) &&
                    @terminal_ui.screen &&
                    @terminal_ui.renderer

      if use_overlay
        @terminal_ui.show_overlay_dialog(title, content_lines, options, &block)
      else
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
  end
end
