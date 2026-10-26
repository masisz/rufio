# frozen_string_literal: true

require_relative 'text_utils'

module Rufio
  # Renders floating dialog windows in the terminal
  class DialogRenderer
    include TextUtils

    # Phase 4: Screenバッファにフローティングウィンドウを描画
    # @param screen [Screen] Screen buffer to draw to
    # @param x [Integer] X position (column)
    # @param y [Integer] Y position (row)
    # @param width [Integer] Window width
    # @param height [Integer] Window height
    # @param title [String, nil] Window title (optional)
    # @param content_lines [Array<String>] Content lines to display
    # @param options [Hash] Customization options
    # @option options [String] :border_color Border color ANSI code
    # @option options [String] :title_color Title color ANSI code
    # @option options [String] :content_color Content color ANSI code
    def draw_floating_window_to_buffer(screen, x, y, width, height, title, content_lines, options = {})
      draw_window_cells(x, y, width, height, title, content_lines, options,
                        put_cell: ->(cx, cy, ch, fg: nil) { screen.put(cx, cy, ch, fg: fg) },
                        put_str: ->(cx, cy, str, fg: nil) { screen.put_string(cx, cy, str, fg: fg) })
    end

    # オーバーレイレイヤーにフローティングウィンドウを描画
    def draw_floating_window_to_overlay(screen, x, y, width, height, title, content_lines, options = {})
      screen.enable_overlay unless screen.overlay_enabled?

      draw_window_cells(x, y, width, height, title, content_lines, options,
                        put_cell: ->(cx, cy, ch, fg: nil) { screen.put_overlay(cx, cy, ch, fg: fg) },
                        put_str: ->(cx, cy, str, fg: nil) { screen.put_overlay_string(cx, cy, str, fg: fg) })
    end

    # Draw a floating window with title, content, and customizable colors
    def draw_floating_window(x, y, width, height, title, content_lines, options = {})
      border_color = options[:border_color] || "\e[37m"  # White
      title_color = options[:title_color] || "\e[1;33m"  # Bold yellow
      content_color = options[:content_color] || "\e[37m" # White
      reset_color = "\e[0m"
      inner_width = width - 2

      print "\e[#{y};#{x}H#{border_color}┌#{'─' * inner_width}┐#{reset_color}"

      if title
        title_line = format_centered_title(title, inner_width)
        print "\e[#{y + 1};#{x}H#{border_color}│#{title_color}#{title_line}#{border_color}│#{reset_color}"
        print "\e[#{y + 2};#{x}H#{border_color}├#{'─' * inner_width}┤#{reset_color}"
        content_start_y = y + 3
      else
        content_start_y = y + 1
      end

      content_height = title ? height - 4 : height - 2
      content_height.times do |index|
        line_y = content_start_y + index
        if index < content_lines.length
          line_content = TextUtils.pad_string_to_width(content_lines[index], inner_width)
          print "\e[#{line_y};#{x}H#{border_color}│#{content_color}#{line_content}#{border_color}│#{reset_color}"
        else
          print "\e[#{line_y};#{x}H#{border_color}│#{' ' * inner_width}│#{reset_color}"
        end
      end

      bottom_y = y + height - 1
      print "\e[#{bottom_y};#{x}H#{border_color}└#{'─' * inner_width}┘#{reset_color}"
    end

    # Calculate center position for a window
    # @param content_width [Integer] Window width
    # @param content_height [Integer] Window height
    # @return [Array<Integer>] [x, y] position
    def calculate_center(content_width, content_height)
      # Get terminal size
      console = IO.console
      if console
        screen_width, screen_height = console.winsize.reverse
      else
        screen_width = 80
        screen_height = 24
      end

      # Calculate center position
      x = [(screen_width - content_width) / 2, 1].max
      y = [(screen_height - content_height) / 2, 1].max

      [x, y]
    end

    # Clear a rectangular area on the screen
    # @param x [Integer] X position
    # @param y [Integer] Y position
    # @param width [Integer] Area width
    # @param height [Integer] Area height
    def clear_area(x, y, width, height)
      height.times do |row|
        print "\e[#{y + row};#{x}H#{' ' * width}"
      end
    end

    # Calculate appropriate dimensions for content
    # @param content_lines [Array<String>] Content lines
    # @param options [Hash] Options
    # @option options [String, nil] :title Window title
    # @option options [Integer] :min_width Minimum width (default: 30)
    # @option options [Integer] :max_width Maximum width (default: 80)
    # @return [Array<Integer>] [width, height]
    def calculate_dimensions(content_lines, options = {})
      title = options[:title]
      min_width = options[:min_width] || 30
      max_width = options[:max_width] || 80

      # Calculate required width based on content
      max_content_width = content_lines.map { |line| TextUtils.display_width(line) }.max || 0
      title_width = title ? TextUtils.display_width(title) : 0
      required_width = [max_content_width, title_width].max + 4 # +4 for borders and padding

      width = [[required_width, min_width].max, max_width].min

      # Calculate height: borders + title (if exists) + separator + content
      height = content_lines.length + 2 # +2 for top and bottom borders
      height += 2 if title # +2 for title line and separator

      [width, height]
    end

    # Show a floating input dialog and get user input
    # @param title [String] Dialog title
    # @param prompt [String] Prompt message
    # @param options [Hash] Customization options
    # @option options [String] :border_color Border color ANSI code
    # @option options [String] :title_color Title color ANSI code
    # @option options [String] :content_color Content color ANSI code
    # @option options [Integer] :width Dialog width (default: 50)
    # @return [String, nil] User input (nil if cancelled)
    def show_input_dialog(title, prompt, options = {})
      require 'io/console'

      width = options[:width] || 50
      height = 8 # title + separator + prompt + input line + blank + ESC message + borders

      x, y = calculate_center(width, height)

      content_lines = [
        '',
        prompt,
        '',
        '> ', # Input line with prompt indicator
        '',
        '',
        'Press ESC to cancel'
      ]

      # Draw initial dialog
      draw_floating_window(x, y, width, height, title, content_lines, options)

      # Position cursor at input line
      # y + 1 (top border) + 1 (title) + 1 (separator) + 1 (blank) + 1 (prompt) + 1 (blank) + 1 (input line) = y + 6
      input_y = y + 6
      input_x = x + 4 # Inside border with prompt '> ' (border 1 + space 1 + '> ' 2)
      print "\e[#{input_y};#{input_x}H"
      STDOUT.flush

      # Read input with escape support
      input = read_input_in_dialog(x, y, width, height, input_x, input_y, options)

      # Clear dialog
      clear_area(x, y, width, height)

      input
    end

    private

    def format_centered_title(title, inner_width)
      title_width = TextUtils.display_width(title)
      title_padding = [(inner_width - title_width) / 2, 0].max
      padded_title = ' ' * title_padding + title
      TextUtils.pad_string_to_width(padded_title, inner_width)
    end

    def draw_window_cells(x, y, width, height, title, content_lines, options, put_cell:, put_str:)
      border_color = options[:border_color] || "\e[37m"
      title_color = options[:title_color] || "\e[1;33m"
      content_color = options[:content_color] || "\e[37m"
      inner_width = width - 2

      put_str.call(x, y, "┌#{'─' * inner_width}┐", fg: border_color)

      if title
        title_line = format_centered_title(title, inner_width)
        put_cell.call(x, y + 1, '│', fg: border_color)
        put_str.call(x + 1, y + 1, title_line, fg: title_color)
        put_cell.call(x + width - 1, y + 1, '│', fg: border_color)

        put_str.call(x, y + 2, "├#{'─' * inner_width}┤", fg: border_color)
        content_start_y = y + 3
      else
        content_start_y = y + 1
      end

      content_height = title ? height - 4 : height - 2
      empty_line = ' ' * inner_width
      content_height.times do |index|
        line_y = content_start_y + index
        put_cell.call(x, line_y, '│', fg: border_color)
        if index < content_lines.length
          line_content = TextUtils.pad_string_to_width(content_lines[index], inner_width)
          put_str.call(x + 1, line_y, line_content, fg: content_color)
        else
          put_str.call(x + 1, line_y, empty_line)
        end
        put_cell.call(x + width - 1, line_y, '│', fg: border_color)
      end

      bottom_y = y + height - 1
      put_str.call(x, bottom_y, "└#{'─' * inner_width}┘", fg: border_color)
    end

    # ASCII character range constants
    ASCII_PRINTABLE_START = 32
    ASCII_PRINTABLE_END = 127
    MULTIBYTE_THRESHOLD = 1

    # Read user input within a dialog
    # @param dialog_x [Integer] Dialog X position
    # @param dialog_y [Integer] Dialog Y position
    # @param dialog_width [Integer] Dialog width
    # @param dialog_height [Integer] Dialog height
    # @param input_x [Integer] Input field X position
    # @param input_y [Integer] Input field Y position
    # @param options [Hash] Display options
    # @return [String, nil] User input (nil if cancelled)
    def read_input_in_dialog(dialog_x, dialog_y, dialog_width, dialog_height, input_x, input_y, options)
      content_color = options[:content_color] || "\e[37m"
      reset_color = "\e[0m"

      input_chars = []
      max_input_width = dialog_width - 8 # Leave space for borders and padding (border 2 + padding 4 + border 2)

      loop do
        char = KeyInput.getch

        case char
        when "\e" # Escape - cancel
          return nil
        when "\r", "\n" # Enter - submit
          return input_chars.join.strip
        when "\u007F", "\b" # Backspace/Delete
          unless input_chars.empty?
            input_chars.pop
            # Redraw input line - clear the entire input area
            print "\e[#{input_y};#{input_x}H"
            print "#{content_color}#{' ' * max_input_width}#{reset_color}"
            print "\e[#{input_y};#{input_x}H"
            print "#{content_color}#{input_chars.join}#{reset_color}"
            STDOUT.flush
          end
        when "\u0003" # Ctrl+C
          raise Interrupt
        else
          # Accept printable characters
          if (char.ord >= ASCII_PRINTABLE_START && char.ord < ASCII_PRINTABLE_END) ||
             char.bytesize > MULTIBYTE_THRESHOLD # Multibyte characters (Japanese, etc.)
            current_width = TextUtils.display_width(input_chars.join)
            char_width = TextUtils.display_width(char)

            if current_width + char_width <= max_input_width
              input_chars << char
              print "#{content_color}#{char}#{reset_color}"
              STDOUT.flush
            end
          end
        end
      end
    end
  end
end
