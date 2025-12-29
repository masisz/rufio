# frozen_string_literal: true

require 'io/console'
require_relative 'text_utils'

module Rufio
  class TerminalUI
    # Layout constants
    HEADER_HEIGHT = 1              # Header占有行数
    FOOTER_HEIGHT = 1              # Footer占有行数
    HEADER_FOOTER_MARGIN = 3       # Header + Footer分のマージン

    # Panel layout ratios
    LEFT_PANEL_RATIO = 0.5         # 左パネルの幅比率
    RIGHT_PANEL_RATIO = 1.0 - LEFT_PANEL_RATIO

    # Display constants
    DEFAULT_SCREEN_WIDTH = 80      # デフォルト画面幅
    DEFAULT_SCREEN_HEIGHT = 24     # デフォルト画面高さ
    HEADER_PADDING = 2             # ヘッダーのパディング
    FILTER_TEXT_RESERVED = 15      # フィルタテキスト表示の予約幅

    # File display constants
    ICON_SIZE_PADDING = 12         # アイコン、選択マーク、サイズ情報分
    CURSOR_OFFSET = 1              # カーソル位置のオフセット

    # Size display constants (bytes)
    KILOBYTE = 1024
    MEGABYTE = KILOBYTE * 1024
    GIGABYTE = MEGABYTE * 1024

    # Line offsets
    CONTENT_START_LINE = 2         # コンテンツ開始行（ヘッダー1行スキップ）

    def initialize
      console = IO.console
      if console
        @screen_width, @screen_height = console.winsize.reverse
      else
        # fallback values (for test environments etc.)
        @screen_width = DEFAULT_SCREEN_WIDTH
        @screen_height = DEFAULT_SCREEN_HEIGHT
      end
      @running = false
      @command_mode_active = false
      @command_input = ""
      @command_mode = CommandMode.new
      @dialog_renderer = DialogRenderer.new
      @command_mode_ui = CommandModeUI.new(@command_mode, @dialog_renderer)

      # Project mode
      @project_mode = nil
      @project_command = nil
      @project_log = nil
      @in_project_mode = false
      @in_log_mode = false
    end

    def start(directory_listing, keybind_handler, file_preview)
      @directory_listing = directory_listing
      @keybind_handler = keybind_handler
      @file_preview = file_preview
      @keybind_handler.set_directory_listing(@directory_listing)
      @keybind_handler.set_terminal_ui(self)

      @running = true
      setup_terminal

      # Show info notices if any
      show_info_notices

      begin
        main_loop
      ensure
        cleanup_terminal
      end
    end

    def refresh_display
      # ウィンドウサイズを更新してから画面をクリアして再描画
      update_screen_size
      print "\e[2J\e[H"  # clear screen, cursor to home
    end

    private

    def setup_terminal
      # terminal setup
      system('tput smcup')  # alternate screen
      system('tput civis')  # cursor invisible
      print "\e[2J\e[H"     # clear screen, cursor to home (first time only)

      # re-acquire terminal size (just in case)
      update_screen_size
    end

    def update_screen_size
      console = IO.console
      return unless console

      @screen_width, @screen_height = console.winsize.reverse
    end

    def cleanup_terminal
      system('tput rmcup')  # normal screen
      system('tput cnorm')  # cursor normal
      puts ConfigLoader.message('app.terminated')
    end

    def main_loop
      while @running
        draw_screen
        handle_input
      end
    end

    def draw_screen
      # move cursor to top of screen (don't clear)
      print "\e[H"

      # プロジェクトモードの場合は専用の画面を描画
      if @in_project_mode
        draw_project_mode_screen
        return
      end

      # header (1 line)
      draw_header

      # main content (left: directory list, right: preview)
      entries = get_display_entries
      selected_entry = entries[@keybind_handler.current_index]

      # calculate height with header and footer margin
      content_height = @screen_height - HEADER_FOOTER_MARGIN
      left_width = (@screen_width * LEFT_PANEL_RATIO).to_i
      right_width = @screen_width - left_width

      # adjust so right panel doesn't overflow into left panel
      right_width = @screen_width - left_width if left_width + right_width > @screen_width

      draw_directory_list(entries, left_width, content_height)
      draw_file_preview(selected_entry, right_width, content_height, left_width)

      # footer
      draw_footer

      # コマンドモードがアクティブな場合はコマンド入力ウィンドウを表示
      if @command_mode_active
        # 補完候補を取得
        suggestions = @command_mode_ui.autocomplete(@command_input)
        # フローティングウィンドウで表示
        @command_mode_ui.show_input_prompt(@command_input, suggestions)
      else
        # move cursor to invisible position
        print "\e[#{@screen_height};#{@screen_width}H"
      end
    end

    def draw_header
      current_path = @directory_listing.current_path
      header = "📁 rufio - #{current_path}"

      # Add filter indicator if in filter mode
      if @keybind_handler.filter_active?
        filter_text = " [Filter: #{@keybind_handler.filter_query}]"
        header += filter_text
      end

      # abbreviate if path is too long
      if header.length > @screen_width - HEADER_PADDING
        if @keybind_handler.filter_active?
          # prioritize showing filter when active
          filter_text = " [Filter: #{@keybind_handler.filter_query}]"
          base_length = @screen_width - filter_text.length - FILTER_TEXT_RESERVED
          header = "📁 rufio - ...#{current_path[-base_length..-1]}#{filter_text}"
        else
          header = "📁 rufio - ...#{current_path[-(@screen_width - FILTER_TEXT_RESERVED)..-1]}"
        end
      end

      puts "\e[7m#{header.ljust(@screen_width)}\e[0m" # reverse display
    end



    def draw_directory_list(entries, width, height)
      start_index = [@keybind_handler.current_index - height / 2, 0].max
      [start_index + height - 1, entries.length - 1].min

      (0...height).each do |i|
        entry_index = start_index + i
        line_num = i + CONTENT_START_LINE

        print "\e[#{line_num};1H" # set cursor position

        if entry_index < entries.length
          entry = entries[entry_index]
          is_selected = entry_index == @keybind_handler.current_index

          draw_entry_line(entry, width, is_selected)
        else
          # 左ペイン専用の安全な幅で空行を出力
          safe_width = [width - CURSOR_OFFSET, (@screen_width * LEFT_PANEL_RATIO).to_i - CURSOR_OFFSET].min
          print ' ' * safe_width
        end
      end
    end

    def draw_entry_line(entry, width, is_selected)
      # アイコンと色の設定
      icon, color = get_entry_display_info(entry)

      # 左ペイン専用の安全な幅を計算（右ペインにはみ出さないよう）
      safe_width = [width - CURSOR_OFFSET, (@screen_width * LEFT_PANEL_RATIO).to_i - CURSOR_OFFSET].min

      # 選択マークの追加
      selection_mark = @keybind_handler.is_selected?(entry[:name]) ? "✓ " : "  "

      # ファイル名（必要に応じて切り詰め）
      name = entry[:name]
      max_name_length = safe_width - ICON_SIZE_PADDING
      name = name[0...max_name_length - 3] + '...' if max_name_length > 0 && name.length > max_name_length

      # サイズ情報
      size_info = format_size(entry[:size])

      # 行の内容を構築（安全な幅内で）
      content_without_size = "#{selection_mark}#{icon} #{name}"
      available_for_content = safe_width - size_info.length

      line_content = if available_for_content > 0
                       content_without_size.ljust(available_for_content) + size_info
                     else
                       content_without_size
                     end

      # 確実に safe_width を超えないよう切り詰め
      line_content = line_content[0...safe_width]

      if is_selected
        selected_color = ColorHelper.color_to_selected_ansi(ConfigLoader.colors[:selected])
        print "#{selected_color}#{line_content}#{ColorHelper.reset}"
      else
        # 選択されたアイテムは異なる色で表示
        if @keybind_handler.is_selected?(entry[:name])
          print "\e[42m\e[30m#{line_content}\e[0m"  # 緑背景、黒文字
        else
          print "#{color}#{line_content}#{ColorHelper.reset}"
        end
      end
    end

    def get_entry_display_info(entry)
      colors = ConfigLoader.colors
      
      case entry[:type]
      when 'directory'
        color_code = ColorHelper.color_to_ansi(colors[:directory])
        ['📁', color_code]
      when 'executable'
        color_code = ColorHelper.color_to_ansi(colors[:executable])
        ['⚡', color_code]
      else
        case File.extname(entry[:name]).downcase
        when '.rb'
          ['💎', "\e[31m"]  # 赤
        when '.js', '.ts'
          ['📜', "\e[33m"]  # 黄
        when '.txt', '.md'
          color_code = ColorHelper.color_to_ansi(colors[:file])
          ['📄', color_code]
        else
          color_code = ColorHelper.color_to_ansi(colors[:file])
          ['📄', color_code]
        end
      end
    end

    def format_size(size)
      return '      ' if size == 0

      if size < KILOBYTE
        "#{size}B".rjust(6)
      elsif size < MEGABYTE
        "#{(size / KILOBYTE.to_f).round(1)}K".rjust(6)
      elsif size < GIGABYTE
        "#{(size / MEGABYTE.to_f).round(1)}M".rjust(6)
      else
        "#{(size / GIGABYTE.to_f).round(1)}G".rjust(6)
      end
    end

    def draw_file_preview(selected_entry, width, height, left_offset)
      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE
        # カーソル位置を左パネルの右端に設定
        cursor_position = left_offset + CURSOR_OFFSET

        # 画面の境界を厳密に計算
        max_chars_from_cursor = @screen_width - cursor_position
        # 区切り線（│）分を除いて、さらに安全マージンを取る
        safe_width = [max_chars_from_cursor - 2, width - 2, 0].max

        print "\e[#{line_num};#{cursor_position}H" # カーソル位置設定
        print '│' # 区切り線

        content_to_print = ''

        if selected_entry && i == 0
          # プレビューヘッダー
          header = " #{selected_entry[:name]} "
          content_to_print = header
        elsif selected_entry && selected_entry[:type] == 'file' && i >= 2
          # ファイルプレビュー（折り返し対応）
          preview_content = get_preview_content(selected_entry)
          wrapped_lines = TextUtils.wrap_preview_lines(preview_content, safe_width - 1) # スペース分を除く
          display_line_index = i - 2

          if display_line_index < wrapped_lines.length
            line = wrapped_lines[display_line_index] || ''
            # スペースを先頭に追加
            content_to_print = " #{line}"
          else
            content_to_print = ' '
          end
        else
          content_to_print = ' '
        end

        # 絶対にsafe_widthを超えないよう強制的に切り詰める
        if safe_width <= 0
          # 表示スペースがない場合は何も出力しない
          next
        elsif TextUtils.display_width(content_to_print) > safe_width
          # 表示幅ベースで切り詰める
          content_to_print = TextUtils.truncate_to_width(content_to_print, safe_width)
        end

        # 出力（パディングなし、はみ出し防止のため）
        print content_to_print

        # 残りのスペースを埋める（ただし安全な範囲内のみ）
        remaining_space = safe_width - TextUtils.display_width(content_to_print)
        print ' ' * remaining_space if remaining_space > 0
      end
    end

    def get_preview_content(entry)
      return [] unless entry && entry[:type] == 'file'

      preview = @file_preview.preview_file(entry[:path])
      case preview[:type]
      when 'text', 'code'
        preview[:lines]
      when 'binary'
        ["(#{ConfigLoader.message('file.binary_file')})", ConfigLoader.message('file.cannot_preview')]
      when 'error'
        ["#{ConfigLoader.message('file.error_prefix')}:", preview[:message]]
      else
        ["(#{ConfigLoader.message('file.cannot_preview')})"]
      end
    rescue StandardError
      ["(#{ConfigLoader.message('file.preview_error')})"]
    end


    def get_display_entries
      if @keybind_handler.filter_active?
        # Get filtered entries from keybind_handler
        all_entries = @directory_listing.list_entries
        query = @keybind_handler.filter_query.downcase
        query.empty? ? all_entries : all_entries.select { |entry| entry[:name].downcase.include?(query) }
      else
        @directory_listing.list_entries
      end
    end

    def draw_footer
      # 最下行から1行上に表示してスクロールを避ける
      footer_line = @screen_height - FOOTER_HEIGHT
      print "\e[#{footer_line};1H"

      if @keybind_handler.filter_active?
        if @keybind_handler.instance_variable_get(:@filter_mode)
          help_text = "Filter mode: Type to filter, ESC to clear, Enter to apply, Backspace to delete"
        else
          help_text = "Filtered view active - Space to edit filter, ESC to clear filter"
        end
      else
        help_text = ConfigLoader.message('help.full')
        help_text = ConfigLoader.message('help.short') if help_text.length > @screen_width
      end

      # 文字列を確実に画面幅に合わせる
      footer_content = help_text.ljust(@screen_width)[0...@screen_width]
      print "\e[7m#{footer_content}\e[0m"
    end

    def handle_input
      begin
        input = STDIN.getch
      rescue Errno::ENOTTY, Errno::ENODEV
        # ターミナルでない環境（IDE等）では標準入力を使用
        print "\nOperation: "
        input = STDIN.gets
        return 'q' if input.nil?
        input = input.chomp.downcase
        return input[0] if input.length > 0

        return 'q'
      end

      # 特殊キーの処理
      if input == "\e"
        # エスケープシーケンスの処理
        next_char = begin
          STDIN.read_nonblock(1)
        rescue StandardError
          nil
        end
        if next_char == '['
          arrow_key = begin
            STDIN.read_nonblock(1)
          rescue StandardError
            nil
          end
          input = case arrow_key
                  when 'A'  # 上矢印
                    'k'
                  when 'B'  # 下矢印
                    'j'
                  when 'C'  # 右矢印
                    'l'
                  when 'D'  # 左矢印
                    'h'
                  else
                    "\e" # ESCキー（そのまま保持）
                  end
        else
          input = "\e" # ESCキー（そのまま保持）
        end
      end

      # コマンドモードがアクティブな場合は、コマンド入力を処理
      if @command_mode_active
        handle_command_input(input)
        return
      end

      # キーバインドハンドラーに処理を委譲
      _result = @keybind_handler.handle_key(input)

      # 終了処理（qキーのみ）
      if input == 'q'
        @running = false
      end
    end

    # コマンドモード関連のメソッドは public にする
    public

    # コマンドモードを起動
    def activate_command_mode
      @command_mode_active = true
      @command_input = ""
    end

    # コマンドモードを終了
    def deactivate_command_mode
      @command_mode_active = false
      @command_input = ""
    end

    # コマンドモードがアクティブかどうか
    def command_mode_active?
      @command_mode_active
    end

    # コマンド入力を処理
    def handle_command_input(input)
      case input
      when "\r", "\n"
        # Enter キーでコマンドを実行
        execute_command(@command_input)
        deactivate_command_mode
      when "\e"
        # Escape キーでコマンドモードをキャンセル
        deactivate_command_mode
      when "\t"
        # Tab キーで補完
        @command_input = @command_mode_ui.complete_command(@command_input)
      when "\u007F", "\b"
        # Backspace
        @command_input.chop! unless @command_input.empty?
      else
        # 通常の文字を追加
        @command_input += input if input.length == 1
      end
    end

    # コマンドを実行
    def execute_command(command_string)
      return if command_string.nil? || command_string.empty?

      result = @command_mode.execute(command_string)

      # コマンド実行結果をフローティングウィンドウで表示
      @command_mode_ui.show_result(result) if result

      # 画面を再描画
      draw_screen
    end

    # Show info notices from the info directory if any are unread
    def show_info_notices
      require_relative 'info_notice'
      info_notice = InfoNotice.new
      notices = info_notice.unread_notices

      notices.each do |notice|
        show_info_notice(notice, info_notice)
      end
    end

    # Show a single info notice
    # @param notice [Hash] Notice hash with :title and :content
    # @param info_notice [InfoNotice] InfoNotice instance to mark as shown
    def show_info_notice(notice, info_notice)
      # Calculate window dimensions
      width = [@screen_width - 10, 70].min
      # Calculate height based on content length
      content_length = notice[:content].length
      height = [content_length + 4, @screen_height - 4].min # +4 for borders and title
      x = (@screen_width - width) / 2
      y = (@screen_height - height) / 2

      # Display the notice window
      @dialog_renderer.draw_floating_window(
        x, y, width, height,
        notice[:title],
        notice[:content],
        {
          border_color: "\e[36m",  # Cyan
          title_color: "\e[1;36m", # Bold cyan
          content_color: "\e[37m"  # White
        }
      )

      # Force flush to ensure display
      $stdout.flush

      # Wait for any key press
      require 'io/console'
      IO.console.getch

      # Mark as shown
      info_notice.mark_as_shown(notice[:file])

      # Clear the notice window
      @dialog_renderer.clear_area(x, y, width, height)

      # Redraw the screen
      draw_screen
    end

    # プロジェクトモードを設定
    def set_project_mode(project_mode, project_command, project_log)
      @project_mode = project_mode
      @project_command = project_command
      @project_log = project_log
      @in_project_mode = true
      @in_log_mode = false
      refresh_display
      draw_screen
    end

    # プロジェクトモードを終了
    def exit_project_mode
      @in_project_mode = false
      @in_log_mode = false
      @project_mode = nil
      @project_command = nil
      @project_log = nil
      refresh_display
      draw_screen
    end

    # ログモードに入る
    def enter_log_mode(project_log)
      @in_log_mode = true
      @project_log = project_log
      refresh_display
      draw_screen
    end

    # プロジェクトモード画面を描画
    def draw_project_mode_screen
      # header
      print "\e[1;1H"  # Move to top-left
      header = @in_log_mode ? "📋 Project Mode - Logs" : "📁 Project Mode - Bookmarks"
      print "\e[44m\e[97m#{header.ljust(@screen_width)}\e[0m\n"
      print "\e[0m#{' ' * @screen_width}\n"

      # calculate dimensions
      content_height = @screen_height - HEADER_FOOTER_MARGIN
      left_width = (@screen_width * LEFT_PANEL_RATIO).to_i
      right_width = @screen_width - left_width

      if @in_log_mode
        # ログモード: ログファイル一覧と内容
        draw_log_list(left_width, content_height)
        draw_log_preview(right_width, content_height, left_width)
      else
        # ブックマークモード: プロジェクト一覧と詳細
        draw_bookmark_list(left_width, content_height)
        draw_bookmark_detail(right_width, content_height, left_width)
      end

      # footer（通常モードと同じスタイル）
      footer_line = @screen_height
      print "\e[#{footer_line};1H"
      footer_text = if @in_log_mode
        "ESC:exit log j/k:move"
      else
        "SPACE:select l:logs ::cmd r:rename d:delete ESC:exit j/k:move"
      end
      # 文字列を確実に画面幅に合わせる
      footer_content = footer_text.ljust(@screen_width)[0...@screen_width]
      print "\e[7m#{footer_content}\e[0m"

      # move cursor to invisible position
      print "\e[#{@screen_height};#{@screen_width}H"
    end

    # ブックマーク一覧を描画
    def draw_bookmark_list(width, height)
      bookmarks = @project_mode.list_bookmarks
      current_index = @keybind_handler.current_index

      print "\e[#{CONTENT_START_LINE};1H"

      if bookmarks.empty?
        print "  No bookmarks found"
        (height - 1).times { puts ' ' * width }
        return
      end

      selected_name = @project_mode.selected_name

      bookmarks.each_with_index do |bookmark, index|
        line_num = CONTENT_START_LINE + index
        break if index >= height

        # 選択マーク（通常モードと同じ）
        is_project_selected = (bookmark[:name] == selected_name)
        selection_mark = is_project_selected ? "✓ " : "  "

        # ブックマーク名を表示
        name = bookmark[:name]
        max_name_length = width - 4  # selection_mark分を除く
        display_name = name.length > max_name_length ? name[0...max_name_length - 3] + '...' : name
        line_content = "#{selection_mark}#{display_name}".ljust(width)

        if index == current_index
          # カーソル位置は選択色でハイライト
          selected_color = ColorHelper.color_to_selected_ansi(ConfigLoader.colors[:selected])
          print "\e[#{line_num};1H#{selected_color}#{line_content[0...width]}#{ColorHelper.reset}"
        else
          # 選択済みブックマークは緑背景、黒文字
          if is_project_selected
            print "\e[#{line_num};1H\e[42m\e[30m#{line_content[0...width]}\e[0m"
          else
            print "\e[#{line_num};1H#{line_content[0...width]}"
          end
        end
      end

      # 残りの行をクリア
      remaining_lines = height - bookmarks.length
      remaining_lines.times do |i|
        line_num = CONTENT_START_LINE + bookmarks.length + i
        print "\e[#{line_num};1H#{' ' * width}"
      end
    end

    # ブックマーク詳細を描画
    def draw_bookmark_detail(width, height, left_offset)
      bookmarks = @project_mode.list_bookmarks
      current_index = @keybind_handler.current_index

      return if bookmarks.empty? || current_index >= bookmarks.length

      bookmark = bookmarks[current_index]
      path = bookmark[:path]

      # ディレクトリ内容を取得
      details = [
        "Project: #{bookmark[:name]}",
        "Path: #{path}",
        "",
        "Directory contents:",
        ""
      ]

      # ディレクトリが存在する場合、内容を表示
      if Dir.exist?(path)
        begin
          entries = Dir.entries(path).reject { |e| e == '.' || e == '..' }.sort

          # 最大表示数を計算（ヘッダー分を引く）
          max_entries = height - details.length

          entries.take(max_entries).each do |entry|
            full_path = File.join(path, entry)
            icon = File.directory?(full_path) ? '📁' : '📄'
            details << "  #{icon} #{entry}"
          end

          # 表示しきれない場合
          if entries.length > max_entries
            details << "  ... and #{entries.length - max_entries} more"
          end
        rescue => e
          details << "  Error reading directory: #{e.message}"
        end
      else
        details << "  Directory does not exist"
      end

      # 各行にセパレータと内容を表示（通常モードと同じ）
      height.times do |i|
        line_num = CONTENT_START_LINE + i

        # セパレータを表示
        cursor_position = left_offset + CURSOR_OFFSET
        print "\e[#{line_num};#{cursor_position}H"
        print '│'

        # 右画面の内容を表示
        if i < details.length
          line = details[i]
          safe_width = width - 2
          content = " #{line}"
          content = content[0...safe_width] if content.length > safe_width
          print content

          # 残りをスペースで埋める
          remaining = safe_width - content.length
          print ' ' * remaining if remaining > 0
        else
          # 空行
          print ' ' * (width - 2)
        end
      end
    end

    # ログファイル一覧を描画
    def draw_log_list(width, height)
      log_files = @project_log.list_log_files
      current_index = @keybind_handler.current_index

      print "\e[#{CONTENT_START_LINE};1H"

      if log_files.empty?
        print "  No log files found"
        (height - 1).times { puts ' ' * width }
        return
      end

      log_files.each_with_index do |filename, index|
        line_num = CONTENT_START_LINE + index
        break if index >= height

        cursor_mark = index == current_index ? '>' : ' '
        display_name = filename.ljust(width - 3)

        if index == current_index
          print "\e[#{line_num};1H\e[7m#{cursor_mark} #{display_name[0...width-3]}\e[0m"
        else
          print "\e[#{line_num};1H #{display_name[0...width-3]}"
        end
      end

      # 残りの行をクリア
      remaining_lines = height - log_files.length
      remaining_lines.times do |i|
        line_num = CONTENT_START_LINE + log_files.length + i
        print "\e[#{line_num};1H#{' ' * width}"
      end
    end

    # ログプレビューを描画
    def draw_log_preview(width, height, left_offset)
      log_files = @project_log.list_log_files
      current_index = @keybind_handler.current_index

      return if log_files.empty? || current_index >= log_files.length

      filename = log_files[current_index]
      content = @project_log.preview(filename)

      lines = content.split("\n")

      # 各行にセパレータと内容を表示（通常モードと同じ）
      height.times do |i|
        line_num = CONTENT_START_LINE + i

        # セパレータを表示
        cursor_position = left_offset + CURSOR_OFFSET
        print "\e[#{line_num};#{cursor_position}H"
        print '│'

        # 右画面の内容を表示
        if i < lines.length
          line = lines[i]
          safe_width = width - 2
          content = " #{line}"
          content = content[0...safe_width] if content.length > safe_width
          print content

          # 残りをスペースで埋める
          remaining = safe_width - content.length
          print ' ' * remaining if remaining > 0
        else
          # 空行
          print ' ' * (width - 2)
        end
      end
    end

    # ログモードを終了してプロジェクトモードに戻る
    def exit_log_mode
      @in_log_mode = false
      refresh_display
      draw_screen
    end

    # プロジェクト未選択メッセージ
    def show_project_not_selected_message
      content_lines = [
        '',
        'Please select a project first by pressing SPACE',
        '',
        'Press any key to continue...'
      ]

      width = 50
      height = 8
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, 'No Project Selected', content_lines, {
        border_color: "\e[33m",    # Yellow (warning)
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })

      require 'io/console'
      IO.console.getch
      @dialog_renderer.clear_area(x, y, width, height)

      # 画面を再描画
      refresh_display
      draw_screen
    end

    # プロジェクトモードでコマンドを実行
    def activate_project_command_mode(project_mode, project_command, project_log)
      return unless project_mode.selected_path

      # スクリプトまたはコマンドを選択
      choice = show_script_or_command_dialog(project_mode.selected_name, project_command)
      return unless choice

      command = nil
      result = nil

      if choice[:type] == :script
        # スクリプトを実行
        command = "ruby script: #{choice[:value]}"
        result = project_command.execute_script(choice[:value], project_mode.selected_path)
      else
        # 通常のコマンドを実行
        command = choice[:value]
        result = project_command.execute(command, project_mode.selected_path)
      end

      # ログを保存
      project_log.save(project_mode.selected_name, command, result[:output])

      # 結果を表示
      show_project_command_result_dialog(command, result)

      # 画面を再描画
      refresh_display
      draw_screen
    end

    # スクリプトまたはコマンドを選択
    def show_script_or_command_dialog(project_name, project_command)
      scripts = project_command.list_scripts

      content_lines = [
        '',
        "Project: #{project_name}",
        ''
      ]

      if scripts.empty?
        content_lines << 'No scripts found in scripts directory'
        content_lines << "  (#{project_command.scripts_dir})"
        content_lines << ''
        content_lines << 'Press C to enter custom command'
        content_lines << 'Press ESC to cancel'
      else
        content_lines << 'Available scripts:'
        content_lines << ''
        scripts.each_with_index do |script, index|
          content_lines << "  #{index + 1}. #{script}"
        end
        content_lines << ''
        content_lines << 'Press 1-9 to select script'
        content_lines << 'Press C to enter custom command'
        content_lines << 'Press ESC to cancel'
      end

      width = 70
      height = [content_lines.length + 4, 25].min
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, 'Execute in Project', content_lines, {
        border_color: "\e[32m",
        title_color: "\e[1;32m",
        content_color: "\e[37m"
      })

      require 'io/console'
      choice = nil

      loop do
        input = IO.console.getch.downcase

        case input
        when "\e" # ESC
          break
        when 'c' # Custom command
          @dialog_renderer.clear_area(x, y, width, height)
          command = show_project_command_input_dialog(project_name)
          choice = { type: :command, value: command } if command && !command.empty?
          break
        when '1'..'9'
          number = input.to_i
          if number > 0 && number <= scripts.length
            choice = { type: :script, value: scripts[number - 1] }
            break
          end
        end
      end

      @dialog_renderer.clear_area(x, y, width, height)
      choice
    end

    # プロジェクトコマンド入力ダイアログ
    def show_project_command_input_dialog(project_name)
      title = "Execute Command in: #{project_name}"
      prompt = "Enter command:"

      @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[32m",    # Green
        title_color: "\e[1;32m",   # Bold green
        content_color: "\e[37m"    # White
      })
    end

    # プロジェクトコマンド結果ダイアログ
    def show_project_command_result_dialog(command, result)
      title = result[:success] ? "Command Success" : "Command Failed"

      # 出力を最初の10行まで表示
      output_lines = (result[:output] || result[:error] || '').split("\n").take(10)

      content_lines = [
        '',
        "Command: #{command}",
        '',
        "Output:",
        ''
      ] + output_lines

      if output_lines.length >= 10
        content_lines << '... (see log for full output)'
      end

      content_lines << ''
      content_lines << 'Press any key to continue...'

      width = 80
      height = [content_lines.length + 4, 20].min
      x, y = @dialog_renderer.calculate_center(width, height)

      border_color = result[:success] ? "\e[32m" : "\e[31m"  # Green or Red
      title_color = result[:success] ? "\e[1;32m" : "\e[1;31m"

      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      })

      require 'io/console'
      IO.console.getch
      @dialog_renderer.clear_area(x, y, width, height)
    end

    # プロジェクト選択時の表示
    def show_project_selected
      # 選択完了メッセージを表示
      content_lines = [
        '',
        'Project selected!',
        '',
        'You can now press : to execute commands',
        '',
        'Press any key to continue...'
      ]

      width = 50
      height = 10
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, 'Project Selected', content_lines, {
        border_color: "\e[32m",    # Green
        title_color: "\e[1;32m",   # Bold green
        content_color: "\e[37m"    # White
      })

      require 'io/console'
      IO.console.getch
      @dialog_renderer.clear_area(x, y, width, height)

      # 画面を再描画
      refresh_display
      draw_screen
    end
  end
end

