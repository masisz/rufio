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
    # @return [Array<Integer>] 実際に書き換えた行番号（何も書かなければ空）。
    #   画像（GraphicsLayer）は、自分の矩形と交差する行が書き換えられたかを見て
    #   送り直すかを決める
    def render(screen)
      # CPU最適化: Dirty rowsが空の場合は完全にスキップ
      dirty = screen.dirty_rows
      return [] if dirty.empty?

      # Phase1: Only process dirty rows (rows that have changed)
      # 全dirty rowsの出力を1つのバッファに積んでから単一の write() で書き出す。
      # STDOUT sync=true 環境で print を行ごとに呼ぶと各行で即座にフラッシュされ
      # 中間状態が表示されてちらつきが発生するため、アトミックな更新を保証する。
      buf = String.new("")
      rewritten = []
      dirty.each do |y|
        line = screen.row(y)
        next if line == @front[y]  # Skip if content is actually the same

        # Move cursor to line y (1-indexed) and buffer the line
        buf << "\e[#{y + 1};1H#{line}"
        @front[y] = line
        rewritten << y
      end

      # Phase1: Clear dirty tracking after rendering
      screen.clear_dirty

      # 単一の write() でアトミックに出力し、その後 flush する
      unless rewritten.empty?
        @output.write(buf)
        @output.flush
      end

      rewritten
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
