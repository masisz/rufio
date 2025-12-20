# frozen_string_literal: true

require_relative 'text_utils'

module Rufio
  # Renders floating dialog windows in the terminal
  class DialogRenderer
    include TextUtils

    # Draw a floating window with title, content, and customizable colors
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
    def draw_floating_window(x, y, width, height, title, content_lines, options = {})
      # Default options
      border_color = options[:border_color] || "\e[37m"  # White
      title_color = options[:title_color] || "\e[1;33m"  # Bold yellow
      content_color = options[:content_color] || "\e[37m" # White
      reset_color = "\e[0m"

      # Draw top border
      print "\e[#{y};#{x}H#{border_color}┌#{'─' * (width - 2)}┐#{reset_color}"

      # Draw title line if title exists
      if title
        title_width = TextUtils.display_width(title)
        title_padding = (width - 2 - title_width) / 2
        padded_title = ' ' * title_padding + title
        title_line = TextUtils.pad_string_to_width(padded_title, width - 2)
        print "\e[#{y + 1};#{x}H#{border_color}│#{title_color}#{title_line}#{border_color}│#{reset_color}"

        # Draw title separator
        print "\e[#{y + 2};#{x}H#{border_color}├#{'─' * (width - 2)}┤#{reset_color}"
        content_start_y = y + 3
      else
        content_start_y = y + 1
      end

      # Draw content lines
      content_height = title ? height - 4 : height - 2
      content_lines.each_with_index do |line, index|
        break if index >= content_height

        line_y = content_start_y + index
        line_content = TextUtils.pad_string_to_width(line, width - 2)
        print "\e[#{line_y};#{x}H#{border_color}│#{content_color}#{line_content}#{border_color}│#{reset_color}"
      end

      # Fill remaining lines with empty space
      remaining_lines = content_height - content_lines.length
      remaining_lines.times do |i|
        line_y = content_start_y + content_lines.length + i
        empty_line = ' ' * (width - 2)
        print "\e[#{line_y};#{x}H#{border_color}│#{empty_line}│#{reset_color}"
      end

      # Draw bottom border
      bottom_y = y + height - 1
      print "\e[#{bottom_y};#{x}H#{border_color}└#{'─' * (width - 2)}┘#{reset_color}"
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
  end
end
