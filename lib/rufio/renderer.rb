# frozen_string_literal: true

module Rufio
  # Renderer class - Front buffer for double buffering
  #
  # Manages the front buffer (what's currently displayed on screen)
  # and performs differential rendering by comparing with the back buffer (Screen).
  #
  # Features:
  # - Diff rendering: Only updates changed lines
  # - Cursor positioning: Uses ANSI escape codes
  # - Flush control: Ensures all output is displayed
  #
  class Renderer
    def initialize(width, height, output: STDOUT)
      @width = width
      @height = height
      @front = Array.new(height) { " " * width }
      @output = output
    end

    # Render the screen with differential updates
    #
    # @param screen [Screen] The back buffer to render
    def render(screen)
      # Phase1: Only process dirty rows (rows that have changed)
      screen.dirty_rows.each do |y|
        line = screen.row(y)
        next if line == @front[y]  # Skip if content is actually the same

        # Move cursor to line y (1-indexed) and output the line
        @output.print "\e[#{y + 1};1H#{line}"
        @front[y] = line
      end

      # Phase1: Clear dirty tracking after rendering
      screen.clear_dirty
      @output.flush
    end

    # Resize the front buffer
    #
    # @param width [Integer] New width
    # @param height [Integer] New height
    def resize(width, height)
      @width = width
      @height = height
      @front = Array.new(height) { " " * width }

      # Clear entire screen
      @output.print "\e[2J\e[H"
      @output.flush
    end

    # Clear the front buffer and screen
    def clear
      @front = Array.new(@height) { " " * @width }

      # Clear screen and move cursor to home
      @output.print "\e[2J\e[H"
      @output.flush
    end
  end
end
