# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

module Rufio
  # UIテスト用のハーネス
  # Screen/Rendererをラップし、テスト用のヘルパーメソッドを提供
  class UITestHarness
    attr_reader :screen, :renderer, :output, :terminal_ui
    attr_reader :directory_listing, :keybind_handler, :file_preview

    # テスト用の画面サイズ
    DEFAULT_WIDTH = 80
    DEFAULT_HEIGHT = 24

    def initialize(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT)
      @width = width
      @height = height
      @output = StringIO.new
      @screen = Screen.new(width, height)
      @renderer = Renderer.new(width, height, output: @output)

      # テスト用の一時ディレクトリを作成
      @test_dir = Dir.mktmpdir("rufio_ui_test")
      setup_test_files
    end

    # テスト用のTerminalUIを作成（モック版）
    def setup_terminal_ui
      @directory_listing = DirectoryListing.new(@test_dir)
      @keybind_handler = KeybindHandler.new
      @file_preview = FilePreview.new

      @keybind_handler.set_directory_listing(@directory_listing)

      # TerminalUIの内部メソッドをテスト用に呼び出すためのプロキシ
      @terminal_ui = TerminalUITestProxy.new(
        screen: @screen,
        renderer: @renderer,
        directory_listing: @directory_listing,
        keybind_handler: @keybind_handler,
        file_preview: @file_preview,
        width: @width,
        height: @height
      )
    end

    # キー入力をシミュレート
    def send_keys(*keys)
      keys.each do |key|
        @keybind_handler.handle_key(key)
        render_frame
      end
    end

    # 1フレーム描画
    def render_frame
      @output.string.clear
      @renderer.clear
      @screen.clear
      @terminal_ui.draw_screen_to_buffer(@screen, nil, nil)
      @renderer.render(@screen)
    end

    # 画面出力を取得（ANSIコード付き）
    def raw_output
      @output.string.dup
    end

    # 画面出力を取得（ANSIコード除去）
    def plain_output
      strip_ansi(@output.string)
    end

    # 特定の行を取得（ANSIコード除去）
    def line(y)
      strip_ansi(@screen.row(y))
    end

    # 画面全体をテキストとして取得
    def screen_text
      (0...@height).map { |y| line(y) }.join("\n")
    end

    # ANSIコードを除去
    def strip_ansi(str)
      str.gsub(/\e\[[0-9;]*m/, "")
    end

    # クリーンアップ
    def cleanup
      FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    end

    private

    # テスト用のファイル構造を作成
    def setup_test_files
      FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
      FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
      File.write(File.join(@test_dir, "file1.txt"), "Hello World\nLine 2\nLine 3")
      File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'\nputs 'world'")
      File.write(File.join(@test_dir, "README.md"), "# README\n\nThis is a test file.")
    end
  end

  # TerminalUIのテスト用プロキシ
  # 実際のターミナル操作なしでバッファ描画をテスト可能にする
  class TerminalUITestProxy
    HEADER_HEIGHT = 2
    FOOTER_HEIGHT = 1
    HEADER_FOOTER_MARGIN = 3
    LEFT_PANEL_RATIO = 0.5
    CONTENT_START_LINE = 1

    def initialize(screen:, renderer:, directory_listing:, keybind_handler:, file_preview:, width:, height:)
      @screen = screen
      @renderer = renderer
      @directory_listing = directory_listing
      @keybind_handler = keybind_handler
      @file_preview = file_preview
      @screen_width = width
      @screen_height = height
      @tab_mode_manager = TabModeManager.new
      @dialog_renderer = DialogRenderer.new
      @preview_cache = {}
      @last_preview_path = nil
      @in_job_mode = false
    end

    # バッファへの描画（TerminalUIのメソッドを模倣）
    def draw_screen_to_buffer(screen, notification_message = nil, fps = nil)
      # フッタ y=0（上部）、コンテンツ y=1〜h-3、モードタブ y=h-2、ヘッダ y=h-1（下部）
      draw_footer_to_buffer(screen, 0, fps)

      content_height = @screen_height - HEADER_FOOTER_MARGIN
      entries = get_display_entries
      selected_entry = entries[@keybind_handler.current_index]

      left_width = (@screen_width * LEFT_PANEL_RATIO).to_i
      right_width = @screen_width - left_width

      draw_directory_list_to_buffer(screen, entries, left_width, content_height)
      draw_file_preview_to_buffer(screen, selected_entry, right_width, content_height, left_width)

      draw_mode_tabs_to_buffer(screen, @screen_height - 2)
      draw_header_to_buffer(screen, @screen_height - 1)

      if notification_message
        notification_line = @screen_height - 1
        message_display = " #{notification_message} "
        message_display = message_display[0...(@screen_width - 3)] + "..." if message_display.length > @screen_width
        screen.put_string(0, notification_line, message_display.ljust(@screen_width), fg: "\e[7m")
      end
    end

    private

    def draw_header_to_buffer(screen, y)
      current_path = @directory_listing.current_path
      header = "rufio - #{current_path}"

      if @keybind_handler.help_mode?
        header += " [Help Mode - Press ESC to exit]"
      end

      if @keybind_handler.filter_active?
        filter_text = " [Filter: #{@keybind_handler.filter_query}]"
        header += filter_text
      end

      if header.length > @screen_width - 2
        header = "rufio - ...#{current_path[-(@screen_width - 15)..-1]}"
      end

      screen.put_string(0, y, header.ljust(@screen_width), fg: "\e[7m")
    end

    def draw_mode_tabs_to_buffer(screen, y)
      modes = @tab_mode_manager.available_modes
      labels = @tab_mode_manager.mode_labels
      current_mode = @tab_mode_manager.current_mode

      current_x = 0
      modes.each_with_index do |mode, index|
        label = " #{labels[mode]} "

        if mode == current_mode
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[30m\e[1m", bg: "\e[46m")
            current_x += 1
          end
        else
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[90m")
            current_x += 1
          end
        end

        if index < modes.length - 1
          screen.put(current_x, y, "|", fg: "\e[90m")
          current_x += 1
        end
      end

      while current_x < @screen_width
        screen.put(current_x, y, " ")
        current_x += 1
      end
    end

    def draw_directory_list_to_buffer(screen, entries, width, height)
      start_index = [@keybind_handler.current_index - height / 2, 0].max

      (0...height).each do |i|
        entry_index = start_index + i
        line_num = i + CONTENT_START_LINE

        if entry_index < entries.length
          entry = entries[entry_index]
          is_selected = entry_index == @keybind_handler.current_index
          draw_entry_line_to_buffer(screen, entry, width, is_selected, 0, line_num)
        else
          safe_width = [width - 1, (@screen_width * LEFT_PANEL_RATIO).to_i - 1].min
          screen.put_string(0, line_num, " " * safe_width)
        end
      end
    end

    def draw_entry_line_to_buffer(screen, entry, width, is_selected, x, y)
      icon, color = get_entry_display_info(entry)
      safe_width = [width - 1, (@screen_width * LEFT_PANEL_RATIO).to_i - 1].min

      selection_mark = @keybind_handler.is_selected?(entry[:name]) ? "* " : "  "
      name = entry[:name]
      max_name_length = safe_width - 12
      name = name[0...max_name_length - 3] + "..." if max_name_length > 0 && name.length > max_name_length

      size_info = format_size(entry[:size])
      content_without_size = "#{selection_mark}#{icon} #{name}"
      available_for_content = safe_width - size_info.length

      line_content = if available_for_content > 0
                       content_without_size.ljust(available_for_content) + size_info
                     else
                       content_without_size
                     end

      line_content = line_content[0...safe_width]

      if is_selected
        screen.put_string(x, y, line_content, fg: "\e[1;33m")
      elsif @keybind_handler.is_selected?(entry[:name])
        screen.put_string(x, y, line_content, fg: "\e[42m\e[30m")
      else
        screen.put_string(x, y, line_content, fg: color)
      end
    end

    def draw_file_preview_to_buffer(screen, selected_entry, width, height, left_offset)
      cursor_position = left_offset + 1
      max_chars_from_cursor = @screen_width - cursor_position
      safe_width = [max_chars_from_cursor - 2, width - 2, 0].max

      preview_content = nil
      if selected_entry && selected_entry[:type] == "file"
        preview_content = get_preview_content(selected_entry)
      end

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE
        screen.put(cursor_position, line_num, "|")

        content_to_print = ""

        if selected_entry && i == 0
          content_to_print = " #{selected_entry[:name]} "
        elsif preview_content && i >= 2 && (i - 2) < preview_content.length
          line = preview_content[i - 2] || ""
          content_to_print = " #{line}"
        else
          content_to_print = " "
        end

        next if safe_width <= 0

        if TextUtils.display_width(content_to_print) > safe_width
          content_to_print = TextUtils.truncate_to_width(content_to_print, safe_width)
        end

        remaining_space = safe_width - TextUtils.display_width(content_to_print)
        content_to_print += " " * remaining_space if remaining_space > 0

        screen.put_string(cursor_position + 1, line_num, content_to_print)
      end
    end

    def draw_footer_to_buffer(screen, y, fps = nil)
      right_info = fps ? "#{fps.round(1)} FPS" : ""

      if right_info.empty?
        footer_content = "".ljust(@screen_width)
      else
        footer_content = "".ljust(@screen_width - right_info.length) + right_info
      end
      footer_content = footer_content[0...@screen_width]
      screen.put_string(0, y, footer_content, fg: "\e[7m")
    end

    def get_display_entries
      @directory_listing.list_entries
    end

    def get_entry_display_info(entry)
      case entry[:type]
      when "directory"
        ["D", "\e[34m"]
      when "executable"
        ["*", "\e[32m"]
      else
        case File.extname(entry[:name]).downcase
        when ".rb"
          ["R", "\e[31m"]
        when ".js", ".ts"
          ["J", "\e[33m"]
        when ".txt", ".md"
          ["T", "\e[37m"]
        else
          ["F", "\e[37m"]
        end
      end
    end

    def format_size(size)
      return "      " if size == 0

      if size < 1024
        "#{size}B".rjust(6)
      elsif size < 1024 * 1024
        "#{(size / 1024.0).round(1)}K".rjust(6)
      else
        "#{(size / (1024 * 1024.0)).round(1)}M".rjust(6)
      end
    end

    def get_preview_content(entry)
      return [] unless entry && entry[:type] == "file"

      begin
        preview = @file_preview.preview_file(entry[:path])
        case preview[:type]
        when "text", "code"
          preview[:lines]
        when "binary"
          ["(Binary file)", "Cannot preview"]
        else
          ["(Cannot preview)"]
        end
      rescue StandardError
        ["(Preview error)"]
      end
    end
  end
end
