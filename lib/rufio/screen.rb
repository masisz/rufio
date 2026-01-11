# frozen_string_literal: true

require 'set'

module Rufio
  # Screen class - Back buffer for double buffering
  #
  # Manages a virtual screen buffer where each cell contains:
  # - Character
  # - Foreground color (ANSI code)
  # - Background color (ANSI code)
  # - Display width (for multibyte characters)
  #
  # Supports:
  # - ASCII characters (width = 1)
  # - Full-width characters (width = 2, e.g., Japanese, Chinese)
  # - Emoji (width = 2+)
  #
  # Phase1 Optimizations:
  # - Width pre-calculation (computed once in put method)
  # - Dirty row tracking (only render changed rows)
  # - Optimized format_cell (String.new with capacity)
  # - Optimized row generation (width accumulation, no ANSI strip)
  # - Minimal ANSI stripping (only once in put_string)
  #
  class Screen
    attr_reader :width, :height

    def initialize(width, height)
      @width = width
      @height = height
      @cells = Array.new(height) { Array.new(width) { default_cell } }
      @dirty_rows = Set.new  # Phase1: Dirty row tracking
    end

    # Put a single character at (x, y) with optional color
    #
    # @param x [Integer] X position (0-indexed)
    # @param y [Integer] Y position (0-indexed)
    # @param char [String] Character to put
    # @param fg [String, nil] Foreground ANSI color code
    # @param bg [String, nil] Background ANSI color code
    # @param width [Integer, nil] Display width (auto-detected if not provided)
    def put(x, y, char, fg: nil, bg: nil, width: nil)
      return if out_of_bounds?(x, y)

      # Phase1: Width is calculated once here (not in rendering loop)
      char_width = width || TextUtils.display_width(char)
      @cells[y][x] = {
        char: char,
        fg: fg,
        bg: bg,
        width: char_width
      }

      # Phase1: Mark row as dirty
      @dirty_rows.add(y)

      # For full-width characters, mark the next cell as occupied
      if char_width >= 2 && x + 1 < @width
        (char_width - 1).times do |offset|
          next_x = x + 1 + offset
          break if next_x >= @width
          @cells[y][next_x] = {
            char: '',
            fg: nil,
            bg: nil,
            width: 0
          }
        end
      end
    end

    # Put a string starting at (x, y)
    #
    # @param x [Integer] Starting X position
    # @param y [Integer] Y position
    # @param str [String] String to put (ANSI codes will be stripped)
    # @param fg [String, nil] Foreground ANSI color code
    # @param bg [String, nil] Background ANSI color code
    def put_string(x, y, str, fg: nil, bg: nil)
      return if out_of_bounds?(x, y)

      # Phase1: ANSI stripping only once (minimal processing)
      # Only strip if the string contains ANSI codes
      clean_str = str.include?("\e") ? ColorHelper.strip_ansi(str) : str

      current_x = x
      clean_str.each_char do |char|
        break if current_x >= @width

        char_width = TextUtils.display_width(char)
        put(current_x, y, char, fg: fg, bg: bg, width: char_width)
        current_x += char_width
      end
    end

    # Get the cell at (x, y)
    #
    # @param x [Integer] X position
    # @param y [Integer] Y position
    # @return [Hash] Cell data {char:, fg:, bg:, width:}
    def get_cell(x, y)
      return default_cell if out_of_bounds?(x, y)
      @cells[y][x]
    end

    # Get a row as a formatted string
    #
    # @param y [Integer] Row number
    # @return [String] Formatted row with ANSI codes
    def row(y)
      return " " * @width if y < 0 || y >= @height

      # Phase1: Pre-allocate string capacity for better performance
      result = String.new(capacity: @width * 20)
      current_width = 0  # Phase1: Accumulate width from cells (no recalculation)

      @cells[y].each do |cell|
        # Skip marker cells for full-width characters
        next if cell[:width] == 0

        result << format_cell(cell)
        current_width += cell[:width]  # Phase1: Use pre-calculated width
      end

      # Pad the row to full width
      # Phase1: No ANSI stripping or width recalculation needed
      if current_width < @width
        result << (" " * (@width - current_width))
      end

      result
    end

    # Clear the entire screen
    def clear
      @cells.each do |row|
        row.fill { default_cell }
      end
      # Phase1: Clear dirty rows after full clear
      @dirty_rows.clear
    end

    # Phase1: Get dirty rows (rows that have been modified since last clear)
    #
    # @return [Array<Integer>] Array of dirty row indices
    def dirty_rows
      @dirty_rows.to_a
    end

    # Phase1: Clear dirty row tracking
    def clear_dirty
      @dirty_rows.clear
    end

    private

    def default_cell
      { char: ' ', fg: nil, bg: nil, width: 1 }
    end

    def out_of_bounds?(x, y)
      x < 0 || y < 0 || x >= @width || y >= @height
    end

    def format_cell(cell)
      char = cell[:char]
      fg = cell[:fg]
      bg = cell[:bg]

      # Phase1: Fast path for cells without color
      return char if fg.nil? && bg.nil?

      # Phase1: String builder with pre-allocated capacity (no array generation)
      result = String.new(capacity: 30)
      result << fg if fg
      result << bg if bg
      result << char
      result << "\e[0m"
      result
    end
  end
end
