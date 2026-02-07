# frozen_string_literal: true

require 'shellwords'

module Rufio
  # Integrates with zoxide for directory history navigation
  class ZoxideIntegration
    # Dialog size constants
    DIALOG_WIDTH = 45
    DIALOG_BORDER_HEIGHT = 4

    def initialize(dialog_renderer = nil)
      @dialog_renderer = dialog_renderer
      @terminal_ui = nil
    end

    # terminal_ui を設定
    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    # Check if zoxide is available
    # @return [Boolean]
    def available?
      system('which zoxide > /dev/null 2>&1')
    end

    # Get zoxide history
    # @return [Array<Hash>] Array of { path: String, score: Float }
    def get_history
      return [] unless available?

      begin
        # Get zoxide history with scores
        output = `zoxide query --list --score 2>/dev/null`.strip
        return [] if output.empty?

        # Parse each line into path and score
        lines = output.split("\n")
        history = lines.map do |line|
          # zoxide output format: "score path"
          if line.match(/^\s*(\d+(?:\.\d+)?)\s+(.+)$/)
            score = ::Regexp.last_match(1).to_f
            path = ::Regexp.last_match(2).strip
            { path: path, score: score }
          else
            # No score (backward compatibility)
            { path: line.strip, score: 0.0 }
          end
        end

        # Filter to only existing directories
        history.select { |entry| Dir.exist?(entry[:path]) }
      rescue StandardError
        []
      end
    end

    # Show zoxide history menu and let user select
    # @return [String, nil] Selected path or nil if cancelled
    def show_menu
      return nil unless @dialog_renderer

      history = get_history

      if history.empty?
        show_no_history_message
        return nil
      end

      select_from_history(history)
    end

    # Add directory to zoxide history
    # @param path [String] Directory path
    # @return [Boolean] Success status
    def add_to_history(path)
      return false unless available?
      return false unless Dir.exist?(path)

      begin
        system("zoxide add #{Shellwords.escape(path)} > /dev/null 2>&1")
        true
      rescue StandardError
        false
      end
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

    # Show message when no history is available
    def show_no_history_message
      return unless @dialog_renderer

      title = 'Zoxide'
      content_lines = [
        '',
        'No zoxide history found.',
        '',
        'Zoxide learns from your directory navigation.',
        'Use zoxide more to build up history.',
        '',
        'Press any key to continue...'
      ]

      dialog_width = DIALOG_WIDTH
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # オーバーレイダイアログを表示
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[33m", # Yellow
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })
    end

    # Select from zoxide history
    # @param history [Array<Hash>] History entries
    # @return [String, nil] Selected path or nil
    def select_from_history(history)
      return nil unless @dialog_renderer

      title = 'Zoxide History'

      # Format history for display (max 20 items)
      display_history = history.first(20)
      content_lines = ['']

      display_history.each_with_index do |entry, index|
        # Shorten path display (replace home directory with ~)
        display_path = entry[:path].gsub(ENV['HOME'], '~')
        line = "  #{index + 1}. #{display_path}"
        # Truncate if too long
        line = line[0...60] + '...' if line.length > 63
        content_lines << line
      end

      content_lines << ''
      content_lines << 'Enter number (1-' + display_history.length.to_s + ') or ESC to cancel'

      dialog_width = 70
      dialog_height = [4 + content_lines.length, 25].min

      # Number input mode
      selected_path = nil
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[36m", # Cyan
        title_color: "\e[1;36m",   # Bold cyan
        content_color: "\e[37m"    # White
      }) do
        input_buffer = ''

        loop do
          char = STDIN.getch

          case char
          when "\e", "\x03" # ESC, Ctrl+C
            break
          when "\r", "\n" # Enter
            unless input_buffer.empty?
              number = input_buffer.to_i
              if number > 0 && number <= display_history.length
                selected_path = display_history[number - 1][:path]
                break
              end
            end
            # Invalid input, ask again
            input_buffer = ''
          when "\u007f", "\b" # Backspace
            input_buffer = input_buffer[0...-1] unless input_buffer.empty?
          when /[0-9]/
            input_buffer += char
            # Max 2 digits
            input_buffer = input_buffer[-2..-1] if input_buffer.length > 2

            # If number is within range, select immediately
            number = input_buffer.to_i
            if number > 0 && number <= display_history.length &&
               (number >= 10 || input_buffer.length == 1)
              selected_path = display_history[number - 1][:path]
              break
            end
          end
        end
        nil
      end

      selected_path
    end
  end
end
