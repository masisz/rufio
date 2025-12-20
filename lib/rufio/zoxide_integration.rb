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
      x, y = @dialog_renderer.calculate_center(dialog_width, dialog_height)

      @dialog_renderer.draw_floating_window(x, y, dialog_width, dialog_height, title, content_lines, {
                                               border_color: "\e[33m", # Yellow
                                               title_color: "\e[1;33m",   # Bold yellow
                                               content_color: "\e[37m"    # White
                                             })

      STDIN.getch
      @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
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
      x, y = @dialog_renderer.calculate_center(dialog_width, dialog_height)

      @dialog_renderer.draw_floating_window(x, y, dialog_width, dialog_height, title, content_lines, {
                                               border_color: "\e[36m", # Cyan
                                               title_color: "\e[1;36m",   # Bold cyan
                                               content_color: "\e[37m"    # White
                                             })

      # Number input mode
      input_buffer = ''

      loop do
        char = STDIN.getch

        case char
        when "\e", "\x03" # ESC, Ctrl+C
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return nil
        when "\r", "\n" # Enter
          unless input_buffer.empty?
            number = input_buffer.to_i
            if number > 0 && number <= display_history.length
              selected_entry = display_history[number - 1]
              @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
              return selected_entry[:path]
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
            selected_entry = display_history[number - 1]
            @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
            return selected_entry[:path]
          end
        end
      end
    end
  end
end
