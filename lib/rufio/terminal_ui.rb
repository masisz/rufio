# frozen_string_literal: true

require 'io/console'
require_relative 'text_utils'

module Rufio
  class TerminalUI
    # Layout constants
    HEADER_HEIGHT = 2              # Header占有行数（2段目のモードタブを含む）
    FOOTER_HEIGHT = 1              # Footer占有行数（ブックマーク一覧 + ステータス情報）
    HEADER_FOOTER_MARGIN = 3       # Header(2行) + Footer(1行)分のマージン

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
    CONTENT_START_LINE = 1         # コンテンツ開始行（フッタ1行: Y=0）

    def initialize(test_mode: false)
      console = IO.console
      if console
        @screen_width, @screen_height = console.winsize.reverse
      else
        # fallback values (for test environments etc.)
        @screen_width = DEFAULT_SCREEN_WIDTH
        @screen_height = DEFAULT_SCREEN_HEIGHT
      end
      @running = false
      @test_mode = test_mode
      @command_mode_active = false
      @command_input = ""
      @command_mode = CommandMode.new
      @dialog_renderer = DialogRenderer.new
      @command_mode_ui = CommandModeUI.new(@command_mode, @dialog_renderer)

      # コマンド履歴と補完
      history_file = File.join(Dir.home, '.rufio', 'command_history.txt')
      FileUtils.mkdir_p(File.dirname(history_file))
      @command_history = CommandHistory.new(history_file, max_size: ConfigLoader.command_history_size)
      @command_completion = CommandCompletion.new(@command_history, @command_mode)

      # Job mode
      @job_mode_instance = nil
      @job_manager = nil
      @notification_manager = nil
      @in_job_mode = false
      @job_mode_needs_redraw = false

      # Preview cache
      @preview_cache = {}
      @last_preview_path = nil

      # シンタックスハイライター（bat が利用可能な場合のみ動作）
      @syntax_highlighter = SyntaxHighlighter.new
      # 非同期ハイライト完了フラグ（Thread → メインループへの通知）
      @highlight_updated = false

      # Footer cache (bookmark list)
      @cached_bookmarks = nil
      @cached_bookmark_time = nil
      @bookmark_cache_ttl = 1.0  # 1秒間キャッシュ

      # Command execution lamp (footer indicator)
      @completion_lamp_message = nil
      @completion_lamp_time = nil

      # Tab mode manager
      @tab_mode_manager = TabModeManager.new
    end

    def start(directory_listing, keybind_handler, file_preview, background_executor = nil)
      @directory_listing = directory_listing
      @keybind_handler = keybind_handler
      @file_preview = file_preview
      @background_executor = background_executor
      @keybind_handler.set_directory_listing(@directory_listing)
      @keybind_handler.set_terminal_ui(self)

      # command_mode_ui にも terminal_ui を設定
      @command_mode_ui.set_terminal_ui(self)

      # コマンドモードにバックグラウンドエグゼキュータを設定
      @command_mode.background_executor = @background_executor if @background_executor

      # スクリプトランナーを設定（ジョブモードと連携）
      setup_script_runner

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

      # プレビューキャッシュをクリア（ディレクトリ変更やリフレッシュ時）
      @preview_cache.clear
      @last_preview_path = nil

      # ブックマークキャッシュもクリア
      @cached_bookmarks = nil
      @cached_bookmark_time = nil

      # バッファベースの描画が利用可能な場合は全画面を再描画
      if @screen && @renderer
        # レンダラーの前フレーム情報をリセット（差分レンダリングを強制的に全体描画にする）
        @renderer.clear
        @screen.clear
        draw_screen_to_buffer(@screen, nil, nil)
        @renderer.render(@screen)
        # カーソルを画面外に移動
        print "\e[#{@screen_height};#{@screen_width}H"
      end
    end

    # スクリプトランナーを設定
    def setup_script_runner
      return unless @keybind_handler

      # KeybindHandlerからジョブマネージャーを取得
      job_manager = @keybind_handler.job_manager

      # 設定からスクリプトパスを取得
      script_paths = ConfigLoader.script_paths

      # CommandModeにスクリプトランナーを設定
      @command_mode.setup_script_runner(
        script_paths: script_paths,
        job_manager: job_manager
      )
    end

    private

    def setup_terminal
      # terminal setup
      system('tput smcup')  # alternate screen
      system('tput civis')  # cursor invisible
      print "\e[2J\e[H"     # clear screen, cursor to home (first time only)

      # rawモードに設定（ゲームループのノンブロッキング入力用）
      if STDIN.tty?
        STDIN.raw!
      end

      # re-acquire terminal size (just in case)
      update_screen_size
    end

    def update_screen_size
      console = IO.console
      return unless console

      @screen_width, @screen_height = console.winsize.reverse
    end

    def cleanup_terminal
      # rawモードを解除
      if STDIN.tty?
        STDIN.cooked!
      end

      system('tput rmcup')  # normal screen
      system('tput cnorm')  # cursor normal
      puts ConfigLoader.message('app.terminated')
    end

    # ゲームループパターンのmain_loop（CPU最適化版：フレームスキップ対応）
    # UPDATE → DRAW → RENDER → SLEEP のサイクル
    # 変更がない場合は描画をスキップしてCPU使用率を削減
    def main_loop
      # CPU最適化: 固定FPSをやめて、イベントドリブンに変更
      # 最小スリープ時間（入力チェック間隔）
      min_sleep_interval = 0.0333  # 30FPS（約33.33ms/フレーム）
      check_interval = 0.1  # バックグラウンドタスクのチェック間隔

      # Phase 3: Screen/Rendererを初期化
      @screen = Screen.new(@screen_width, @screen_height)
      @renderer = Renderer.new(@screen_width, @screen_height)

      # 初回描画
      @screen.clear
      draw_screen_to_buffer(@screen, nil, nil)
      @renderer.render(@screen)

      last_notification_check = Time.now
      last_lamp_check = Time.now
      notification_message = nil
      notification_time = nil
      previous_notification = nil
      previous_lamp_message = @completion_lamp_message

      # FPS計測用
      frame_times = []
      last_frame_time = Time.now
      current_fps = 0.0
      last_fps_update = Time.now
      @last_displayed_fps = 0.0

      # 再描画フラグ
      needs_redraw = false

      while @running
        start = Time.now

        # FPS計算（毎フレームで記録）- ループの最初で計測してsleep時間を含める
        if @test_mode
          frame_time = start - last_frame_time
          last_frame_time = start
          frame_times << frame_time
          frame_times.shift if frame_times.size > 60  # 直近60フレームで平均

          # FPS表示の更新は1秒ごと
          if (start - last_fps_update) > 1.0
            avg_frame_time = frame_times.sum / frame_times.size
            current_fps = 1.0 / avg_frame_time if avg_frame_time > 0
            last_fps_update = start
          end

          # FPS表示の更新タイミングで再描画（1秒ごと）
          if current_fps != @last_displayed_fps
            @last_displayed_fps = current_fps
            needs_redraw = true
          end
        end

        # UPDATE phase - ノンブロッキング入力処理
        # 入力があった場合は再描画が必要
        had_input = handle_input_nonblocking
        needs_redraw = true if had_input

        # バックグラウンドコマンドの完了チェック（0.1秒ごと）
        if @background_executor && (start - last_notification_check) > check_interval
          if !@background_executor.running? && @background_executor.get_completion_message
            completion_msg = @background_executor.get_completion_message
            # 通知メッセージとして表示
            notification_message = completion_msg
            notification_time = start
            # フッターのランプ表示用にも設定
            @completion_lamp_message = completion_msg
            @completion_lamp_time = start
            @background_executor.instance_variable_set(:@completion_message, nil)  # メッセージをクリア
            needs_redraw = true
          end
          last_notification_check = start
        end

        # バックグラウンドコマンドの実行状態が変わった場合も再描画
        if @background_executor
          current_running = @background_executor.running?
          if @last_bg_running != current_running
            @last_bg_running = current_running
            needs_redraw = true
          end
        end

        # 完了ランプの表示状態をチェック（0.5秒ごと）
        if (start - last_lamp_check) > 0.5
          current_lamp = @completion_lamp_message
          if current_lamp != previous_lamp_message
            previous_lamp_message = current_lamp
            needs_redraw = true
          end
          # 完了ランプのタイムアウトチェック
          if @completion_lamp_message && @completion_lamp_time && (start - @completion_lamp_time) >= 3.0
            @completion_lamp_message = nil
            needs_redraw = true
          end
          last_lamp_check = start
        end

        # 通知メッセージの変化をチェック
        current_notification = notification_message && (start - notification_time) < 3.0 ? notification_message : nil
        if current_notification != previous_notification
          previous_notification = current_notification
          notification_message = nil if current_notification.nil?
          needs_redraw = true
        end

        # 非同期シンタックスハイライト完了チェック（バックグラウンドスレッドからの通知）
        if @highlight_updated
          @highlight_updated = false
          needs_redraw = true
        end

        # DRAW & RENDER phase - 変更があった場合のみ描画
        if needs_redraw
          # Screenバッファに描画（clearは呼ばない。必要な部分だけ更新）
          if notification_message && (start - notification_time) < 3.0
            draw_screen_to_buffer(@screen, notification_message, current_fps)
          else
            draw_screen_to_buffer(@screen, nil, current_fps)
          end

          # コマンドモードがアクティブな場合はオーバーレイにダイアログを描画
          if @command_mode_active
            # 前回のオーバーレイ残留を防ぐためクリアしてから描画
            @screen.clear_overlay if @screen.overlay_enabled?
            draw_command_mode_to_overlay
          else
            # コマンドモードでない場合はオーバーレイをクリア
            @screen.clear_overlay if @screen.overlay_enabled?
          end

          # 差分レンダリング（dirty rowsのみ、オーバーレイを含む）
          @renderer.render(@screen)

          # 描画後にカーソルを画面外に移動
          if !@command_mode_active
            print "\e[#{@screen_height};#{@screen_width}H"
          end

          needs_redraw = false
        end

        # SLEEP phase - CPU使用率削減のため適切にスリープ
        elapsed = Time.now - start
        sleep_time = [min_sleep_interval - elapsed, 0].max
        sleep sleep_time if sleep_time > 0
      end
    end

    def draw_screen
      # 処理時間測定開始
      start_time = Time.now

      # move cursor to top of screen (don't clear)
      print "\e[H"

      # ジョブモードの場合は専用の画面を描画
      if @in_job_mode
        draw_job_mode_screen
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

      # footer (統合されたステータス情報を含む)
      render_time = Time.now - start_time
      draw_footer(render_time)

      # コマンドモードがアクティブな場合はコマンド入力ウィンドウを表示
      if @command_mode_active
        # フローティングウィンドウで表示
        @command_mode_ui.show_input_prompt(@command_input)
      else
        # move cursor to invisible position
        print "\e[#{@screen_height};#{@screen_width}H"
      end

      # 通知を描画（右上にオーバーレイ）
      draw_notifications
    end

    # Phase 3: Screenバッファに描画する新しいメソッド
    def draw_screen_to_buffer(screen, notification_message = nil, fps = nil)
      # calculate height with header and footer margin
      content_height = @screen_height - HEADER_FOOTER_MARGIN

      if @in_job_mode
        # ジョブモード: フッタ y=0（上部）、コンテンツ y=1〜h-3、モードタブ y=h-2、ヘッダ y=h-1（下部）
        draw_job_footer_to_buffer(screen, 0)
        draw_job_list_to_buffer(screen, content_height)
        draw_mode_tabs_to_buffer(screen, @screen_height - 2)
        draw_header_to_buffer(screen, @screen_height - 1)
      else
        # 通常モード: フッタ y=0（上部）、コンテンツ y=1〜h-3、モードタブ y=h-2、ヘッダ y=h-1（下部）
        draw_footer_to_buffer(screen, 0, fps)

        entries = get_display_entries
        selected_entry = entries[@keybind_handler.current_index]

        left_width = (@screen_width * LEFT_PANEL_RATIO).to_i
        right_width = @screen_width - left_width

        # adjust so right panel doesn't overflow into left panel
        right_width = @screen_width - left_width if left_width + right_width > @screen_width

        draw_directory_list_to_buffer(screen, entries, left_width, content_height)
        draw_file_preview_to_buffer(screen, selected_entry, right_width, content_height, left_width)

        draw_mode_tabs_to_buffer(screen, @screen_height - 2)
        draw_header_to_buffer(screen, @screen_height - 1)
      end

      # 通知メッセージがある場合は表示
      if notification_message
        notification_line = @screen_height - 1
        message_display = " #{notification_message} "
        if message_display.length > @screen_width
          message_display = message_display[0...(@screen_width - 3)] + "..."
        end
        screen.put_string(0, notification_line, message_display.ljust(@screen_width), fg: "\e[7m")
      end
    end

    # ジョブ一覧をバッファに描画
    def draw_job_list_to_buffer(screen, height)
      return unless @job_manager

      jobs = @job_manager.jobs
      selected_index = @job_mode_instance&.selected_index || 0

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE

        if i < jobs.length
          job = jobs[i]
          draw_job_line_to_buffer(screen, job, i == selected_index, line_num)
        else
          # 空行
          screen.put_string(0, line_num, ' ' * @screen_width)
        end
      end
    end

    # ジョブ行をバッファに描画
    def draw_job_line_to_buffer(screen, job, is_selected, y)
      icon = job.status_icon
      name = job.name
      path = "(#{job.path})"
      duration = job.formatted_duration
      duration_text = duration.empty? ? "" : "[#{duration}]"

      status_text = case job.status
                    when :running then "Running"
                    when :completed then "Done"
                    when :failed then "Failed"
                    when :waiting then "Waiting"
                    when :cancelled then "Cancelled"
                    else ""
                    end

      # ステータスに応じた色
      status_color = case job.status
                     when :running then "\e[33m"    # Yellow
                     when :completed then "\e[32m"  # Green
                     when :failed then "\e[31m"     # Red
                     else "\e[37m"                  # White
                     end

      # 行を構築
      line_content = "#{icon} #{name} #{path}".ljust(40)
      line_content += "#{duration_text.ljust(12)} #{status_text}"
      line_content = line_content[0...@screen_width].ljust(@screen_width)

      if is_selected
        # 選択中: 反転表示
        line_content.each_char.with_index do |char, x|
          screen.put(x, y, char, fg: "\e[30m", bg: "\e[47m")
        end
      else
        # 非選択: ステータス色
        line_content.each_char.with_index do |char, x|
          screen.put(x, y, char, fg: status_color)
        end
      end
    end

    # ジョブモード用フッターをバッファに描画
    def draw_job_footer_to_buffer(screen, y)
      job_count = @job_manager&.job_count || 0
      help_text = "[Space] View Log | [x] Cancel | [Tab] Switch Mode | Jobs: #{job_count}"
      footer_content = help_text.center(@screen_width)[0...@screen_width]

      footer_content.each_char.with_index do |char, x|
        screen.put(x, y, char, fg: "\e[30m", bg: "\e[47m")
      end
    end

    def draw_screen_with_notification(notification_message)
      # 通常の画面を描画
      draw_screen

      # 通知メッセージを画面下部に表示
      notification_line = @screen_height - 1
      print "\e[#{notification_line};1H"  # カーソルを画面下部に移動

      # 通知メッセージを反転表示で目立たせる
      message_display = " #{notification_message} "
      if message_display.length > @screen_width
        message_display = message_display[0...(@screen_width - 3)] + "..."
      end

      print "\e[7m#{message_display.ljust(@screen_width)}\e[0m"
    end

    # Phase 3: Screenバッファにヘッダーを描画
    def draw_header_to_buffer(screen, y)
      current_path = @directory_listing.current_path
      header = "💎 rufio v#{VERSION} - #{current_path}"

      # Add help mode indicator if in help mode
      if @keybind_handler.help_mode?
        header += " [Help Mode - Press ESC to exit]"
      end

      # Add filter indicator if in filter mode
      if @keybind_handler.filter_active?
        filter_text = " [Filter: #{@keybind_handler.filter_query}]"
        header += filter_text
      end

      # abbreviate if path is too long
      if header.length > @screen_width - HEADER_PADDING
        if @keybind_handler.help_mode?
          # prioritize showing help mode indicator
          help_text = " [Help Mode - Press ESC to exit]"
          base_length = @screen_width - help_text.length - FILTER_TEXT_RESERVED
          header = "💎 rufio v#{VERSION} - ...#{current_path[-base_length..-1]}#{help_text}"
        elsif @keybind_handler.filter_active?
          # prioritize showing filter when active
          filter_text = " [Filter: #{@keybind_handler.filter_query}]"
          base_length = @screen_width - filter_text.length - FILTER_TEXT_RESERVED
          header = "💎 rufio v#{VERSION} - ...#{current_path[-base_length..-1]}#{filter_text}"
        else
          header = "💎 rufio v#{VERSION} - ...#{current_path[-(@screen_width - FILTER_TEXT_RESERVED)..-1]}"
        end
      end

      screen.put_string(0, y, header.ljust(@screen_width), fg: "\e[7m")
    end

    # Phase 3: Screenバッファにモードタブを描画
    def draw_mode_tabs_to_buffer(screen, y)
      # タブモードマネージャの状態を同期
      sync_tab_mode_with_keybind_handler

      current_x = 0
      modes = @tab_mode_manager.available_modes
      labels = @tab_mode_manager.mode_labels
      current_mode = @tab_mode_manager.current_mode

      modes.each_with_index do |mode, index|
        label = " #{labels[mode]} "

        if mode == current_mode
          # 現在のモード: シアン背景 + 黒文字 + 太字
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[30m\e[1m", bg: "\e[46m")
            current_x += 1
          end
        else
          # 非選択モード: グレー文字
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[90m")
            current_x += 1
          end
        end

        # 区切り線（最後のモード以外）
        if index < modes.length - 1
          screen.put(current_x, y, '│', fg: "\e[90m")
          current_x += 1
        end
      end

      # 残りをスペースで埋める
      while current_x < @screen_width
        screen.put(current_x, y, ' ')
        current_x += 1
      end
    end

    # キーバインドハンドラの状態とタブモードを同期
    def sync_tab_mode_with_keybind_handler
      return unless @keybind_handler

      current_mode = if @keybind_handler.help_mode?
                       :help
                     elsif @keybind_handler.log_viewer_mode?
                       :logs
                     elsif @keybind_handler.in_job_mode?
                       :jobs
                     else
                       :files
                     end

      @tab_mode_manager.switch_to(current_mode) if @tab_mode_manager.current_mode != current_mode
    end

    def draw_header
      current_path = @directory_listing.current_path
      header = "💎 rufio v#{VERSION} - #{current_path}"

      # Add help mode indicator if in help mode
      if @keybind_handler.help_mode?
        header += " [Help Mode - Press ESC to exit]"
      end

      # Add filter indicator if in filter mode
      if @keybind_handler.filter_active?
        filter_text = " [Filter: #{@keybind_handler.filter_query}]"
        header += filter_text
      end

      # abbreviate if path is too long
      if header.length > @screen_width - HEADER_PADDING
        if @keybind_handler.help_mode?
          # prioritize showing help mode indicator
          help_text = " [Help Mode - Press ESC to exit]"
          base_length = @screen_width - help_text.length - FILTER_TEXT_RESERVED
          header = "💎 rufio v#{VERSION} - ...#{current_path[-base_length..-1]}#{help_text}"
        elsif @keybind_handler.filter_active?
          # prioritize showing filter when active
          filter_text = " [Filter: #{@keybind_handler.filter_query}]"
          base_length = @screen_width - filter_text.length - FILTER_TEXT_RESERVED
          header = "💎 rufio v#{VERSION} - ...#{current_path[-base_length..-1]}#{filter_text}"
        else
          header = "💎 rufio v#{VERSION} - ...#{current_path[-(@screen_width - FILTER_TEXT_RESERVED)..-1]}"
        end
      end

      puts "\e[7m#{header.ljust(@screen_width)}\e[0m" # reverse display
    end



    # Phase 3: Screenバッファにディレクトリリストを描画
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
          # 空行
          safe_width = [width - CURSOR_OFFSET, (@screen_width * LEFT_PANEL_RATIO).to_i - CURSOR_OFFSET].min
          screen.put_string(0, line_num, ' ' * safe_width)
        end
      end
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

    # Phase 3: Screenバッファにエントリ行を描画
    def draw_entry_line_to_buffer(screen, entry, width, is_selected, x, y)
      # アイコンと色の設定
      icon, color = get_entry_display_info(entry)

      # 左ペイン専用の安全な幅を計算
      safe_width = [width - CURSOR_OFFSET, (@screen_width * LEFT_PANEL_RATIO).to_i - CURSOR_OFFSET].min

      # 選択マークの追加
      selection_mark = @keybind_handler.is_selected?(entry[:name]) ? "✓ " : "  "

      # ファイル名（必要に応じて切り詰め）
      name = entry[:name]
      max_name_length = safe_width - ICON_SIZE_PADDING
      name = name[0...max_name_length - 3] + '...' if max_name_length > 0 && name.length > max_name_length

      # サイズ情報
      size_info = format_size(entry[:size])

      # 行の内容を構築
      content_without_size = "#{selection_mark}#{icon} #{name}"
      available_for_content = safe_width - size_info.length

      line_content = if available_for_content > 0
                       content_without_size.ljust(available_for_content) + size_info
                     else
                       content_without_size
                     end

      # 確実に safe_width を超えないよう切り詰め
      line_content = line_content[0...safe_width]

      # 色を決定
      if is_selected
        fg_color = ColorHelper.color_to_selected_ansi(ConfigLoader.colors[:selected])
        screen.put_string(x, y, line_content, fg: fg_color)
      elsif @keybind_handler.is_selected?(entry[:name])
        # 選択されたアイテムは緑背景、黒文字
        screen.put_string(x, y, line_content, fg: "\e[42m\e[30m")
      else
        screen.put_string(x, y, line_content, fg: color)
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

    # Phase 3: Screenバッファにファイルプレビューを描画
    def draw_file_preview_to_buffer(screen, selected_entry, width, height, left_offset)
      # 事前計算
      cursor_position = left_offset + CURSOR_OFFSET
      max_chars_from_cursor = @screen_width - cursor_position
      safe_width = [max_chars_from_cursor - 2, width - 2, 0].max

      # プレビューコンテンツをキャッシュから取得（毎フレームのファイルI/Oを回避）
      preview_content = nil
      wrapped_lines = nil
      highlighted_wrapped_lines = nil

      if selected_entry && selected_entry[:type] == 'file'
        # キャッシュチェック: 選択ファイルが変わった場合のみプレビューを更新
        if @last_preview_path != selected_entry[:path]
          full_preview = @file_preview.preview_file(selected_entry[:path])
          preview_content = extract_preview_lines(full_preview)
          @preview_cache[selected_entry[:path]] = {
            content: preview_content,
            preview_data: full_preview,
            highlighted: nil,       # nil = 未取得
            wrapped: {},
            highlighted_wrapped: {}
          }
          @last_preview_path = selected_entry[:path]
        else
          # キャッシュから取得
          cache_entry = @preview_cache[selected_entry[:path]]
          preview_content = cache_entry[:content] if cache_entry
        end

        # bat が利用可能な場合はシンタックスハイライトを取得（非同期）
        if @syntax_highlighter&.available? && preview_content
          cache_entry = @preview_cache[selected_entry[:path]]
          if cache_entry
            preview_data = cache_entry[:preview_data]
            if preview_data && preview_data[:type] == 'code' && preview_data[:encoding] == 'UTF-8'
              # ハイライト行を未取得なら非同期で bat を呼び出す
              # nil = 未リクエスト、false = リクエスト済み（結果待ち）、Array = 取得済み
              if cache_entry[:highlighted].nil?
                # 即座に false をセットしてペンディング状態にする（重複リクエスト防止）
                cache_entry[:highlighted] = false
                file_path = selected_entry[:path]
                @syntax_highlighter.highlight_async(file_path) do |lines|
                  # バックグラウンドスレッドからキャッシュを更新
                  if (ce = @preview_cache[file_path])
                    ce[:highlighted] = lines
                    ce[:highlighted_wrapped] = {}  # 折り返しキャッシュをクリア
                  end
                  @highlight_updated = true  # メインループに再描画を通知
                end
                # このフレームはプレーンテキストで表示（次フレームでハイライト表示）
              end

              highlighted = cache_entry[:highlighted]
              if highlighted.is_a?(Array) && !highlighted.empty? && safe_width > 0
                if cache_entry[:highlighted_wrapped][safe_width]
                  highlighted_wrapped_lines = cache_entry[:highlighted_wrapped][safe_width]
                else
                  # 各ハイライト行をトークン化して折り返す
                  hl_wrapped = highlighted.flat_map do |hl_line|
                    tokens = AnsiLineParser.parse(hl_line)
                    tokens.empty? ? [[]] : AnsiLineParser.wrap(tokens, safe_width - 1)
                  end
                  cache_entry[:highlighted_wrapped][safe_width] = hl_wrapped
                  highlighted_wrapped_lines = hl_wrapped
                end
              end
            end
          end
        end

        # プレーンテキストの折り返し（ハイライトなしのフォールバック）
        if preview_content && safe_width > 0 && highlighted_wrapped_lines.nil?
          cache_entry = @preview_cache[selected_entry[:path]]
          if cache_entry && cache_entry[:wrapped][safe_width]
            wrapped_lines = cache_entry[:wrapped][safe_width]
          else
            wrapped_lines = TextUtils.wrap_preview_lines(preview_content, safe_width - 1)
            cache_entry[:wrapped][safe_width] = wrapped_lines if cache_entry
          end
        end
      end

      content_x = cursor_position + 1

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE

        # 区切り線
        screen.put(cursor_position, line_num, '│')

        next if safe_width <= 0

        if selected_entry && i == 0
          # プレビューヘッダー
          header = " #{selected_entry[:name]} "
          header += "[PREVIEW MODE]" if @keybind_handler&.preview_focused?
          header = TextUtils.truncate_to_width(header, safe_width) if TextUtils.display_width(header) > safe_width
          remaining_space = safe_width - TextUtils.display_width(header)
          header += ' ' * remaining_space if remaining_space > 0
          screen.put_string(content_x, line_num, header)

        elsif i >= 2 && highlighted_wrapped_lines
          # シンタックスハイライト付きコンテンツ
          scroll_offset = @keybind_handler&.preview_scroll_offset || 0
          display_line_index = i - 2 + scroll_offset

          if display_line_index < highlighted_wrapped_lines.length
            draw_highlighted_line_to_buffer(screen, content_x, line_num,
                                            highlighted_wrapped_lines[display_line_index], safe_width)
          else
            screen.put_string(content_x, line_num, ' ' * safe_width)
          end

        elsif i >= 2 && wrapped_lines
          # プレーンテキストコンテンツ
          scroll_offset = @keybind_handler&.preview_scroll_offset || 0
          display_line_index = i - 2 + scroll_offset

          content_to_print = if display_line_index < wrapped_lines.length
                               " #{wrapped_lines[display_line_index] || ''}"
                             else
                               ' '
                             end
          content_to_print = TextUtils.truncate_to_width(content_to_print, safe_width) if TextUtils.display_width(content_to_print) > safe_width
          remaining_space = safe_width - TextUtils.display_width(content_to_print)
          content_to_print += ' ' * remaining_space if remaining_space > 0
          screen.put_string(content_x, line_num, content_to_print)

        else
          screen.put_string(content_x, line_num, ' ' * safe_width)
        end
      end
    end

    def draw_file_preview(selected_entry, width, height, left_offset)
      # 事前計算（ループの外で一度だけ）
      cursor_position = left_offset + CURSOR_OFFSET
      max_chars_from_cursor = @screen_width - cursor_position
      safe_width = [max_chars_from_cursor - 2, width - 2, 0].max

      # プレビューコンテンツをキャッシュから取得（毎フレームのファイルI/Oを回避）
      preview_content = nil
      wrapped_lines = nil

      if selected_entry && selected_entry[:type] == 'file'
        # キャッシュチェック: 選択ファイルが変わった場合のみプレビューを更新
        if @last_preview_path != selected_entry[:path]
          preview_content = get_preview_content(selected_entry)
          @preview_cache[selected_entry[:path]] = {
            content: preview_content,
            wrapped: {}  # 幅ごとにキャッシュ
          }
          @last_preview_path = selected_entry[:path]
        else
          # キャッシュから取得
          cache_entry = @preview_cache[selected_entry[:path]]
          preview_content = cache_entry[:content] if cache_entry
        end

        # 折り返し処理もキャッシュ
        if preview_content && safe_width > 0
          cache_entry = @preview_cache[selected_entry[:path]]
          if cache_entry && cache_entry[:wrapped][safe_width]
            wrapped_lines = cache_entry[:wrapped][safe_width]
          else
            wrapped_lines = TextUtils.wrap_preview_lines(preview_content, safe_width - 1)
            cache_entry[:wrapped][safe_width] = wrapped_lines if cache_entry
          end
        end
      end

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE

        print "\e[#{line_num};#{cursor_position}H" # カーソル位置設定
        print '│' # 区切り線

        content_to_print = ''

        if selected_entry && i == 0
          # プレビューヘッダー
          header = " #{selected_entry[:name]} "
          # プレビューフォーカス中は表示を追加
          if @keybind_handler&.preview_focused?
            header += "[PREVIEW MODE]"
          end
          content_to_print = header
        elsif wrapped_lines && i >= 2
          # ファイルプレビュー（折り返し対応）
          # スクロールオフセットを適用
          scroll_offset = @keybind_handler&.preview_scroll_offset || 0
          display_line_index = i - 2 + scroll_offset

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
      extract_preview_lines(preview)
    rescue StandardError
      ["(#{ConfigLoader.message('file.preview_error')})"]
    end

    # FilePreview の結果ハッシュからプレーンテキスト行を抽出する
    def extract_preview_lines(preview)
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

    # ハイライト済みトークン列を1行分 Screen バッファに描画する
    # 先頭に1スペースを追加し、残りをスペースで埋める
    def draw_highlighted_line_to_buffer(screen, x, y, tokens, max_width)
      current_x = x
      max_x = x + max_width

      # 先頭スペース
      if current_x < max_x
        screen.put(current_x, y, ' ')
        current_x += 1
      end

      # トークンを描画
      tokens&.each do |token|
        break if current_x >= max_x
        token[:text].each_char do |char|
          char_w = TextUtils.char_width(char)
          break if current_x + char_w > max_x
          screen.put(current_x, y, char, fg: token[:fg])
          current_x += char_w
        end
      end

      # 残りをスペースで埋める
      while current_x < max_x
        screen.put(current_x, y, ' ')
        current_x += 1
      end
    end


    def get_display_entries
      entries = if @keybind_handler.filter_active?
                  # Get filtered entries from keybind_handler
                  all_entries = @directory_listing.list_entries
                  query = @keybind_handler.filter_query.downcase
                  query.empty? ? all_entries : all_entries.select { |entry| entry[:name].downcase.include?(query) }
                else
                  @directory_listing.list_entries
                end

      # ヘルプモードとLogsモードでは..を非表示にする
      if @keybind_handler.help_mode? || @keybind_handler.log_viewer_mode?
        entries.reject { |entry| entry[:name] == '..' }
      else
        entries
      end
    end

    # Phase 3: Screenバッファにフッターを描画
    def draw_footer_to_buffer(screen, y, fps = nil)
      if @keybind_handler.filter_active?
        if @keybind_handler.instance_variable_get(:@filter_mode)
          help_text = "Filter mode: Type to filter, ESC to clear, Enter to apply, Backspace to delete"
        else
          help_text = "Filtered view active - Space to edit filter, ESC to clear filter"
        end
        # フィルタモードでは通常のフッタを表示
        footer_content = help_text.ljust(@screen_width)[0...@screen_width]
        screen.put_string(0, y, footer_content, fg: "\e[7m")
      else
        # 通常モードではブックマーク一覧、ステータス情報、?:helpを1行に表示
        # ブックマークをキャッシュ（毎フレームのファイルI/Oを回避）
        current_time = Time.now
        if @cached_bookmarks.nil? || @cached_bookmark_time.nil? || (current_time - @cached_bookmark_time) > @bookmark_cache_ttl
          require_relative 'bookmark'
          bookmark = Bookmark.new
          @cached_bookmarks = bookmark.list
          @cached_bookmark_time = current_time
        end
        bookmarks = @cached_bookmarks

        # 起動ディレクトリを取得
        start_dir = @directory_listing&.start_directory
        start_dir_name = if start_dir
                           File.basename(start_dir)
                         else
                           "start"
                         end

        # ブックマーク一覧を作成（0.起動dir を先頭に追加）
        bookmark_parts = ["0.#{start_dir_name}"]
        unless bookmarks.empty?
          bookmark_parts.concat(bookmarks.take(9).map.with_index(1) { |bm, idx| "#{idx}.#{bm[:name]}" })
        end
        bookmark_text = bookmark_parts.join(" ")

        # 右側の情報: ジョブ数 | コマンド実行ランプ | FPS（test modeの時のみ）| ?:help
        right_parts = []

        # ジョブ数を表示（ジョブがある場合のみ）
        if @keybind_handler.has_jobs?
          job_text = @keybind_handler.job_status_bar_text
          right_parts << "[#{job_text}]" if job_text
        end

        # バックグラウンドコマンドの実行状態をランプで表示
        if @background_executor
          if @background_executor.running?
            # 実行中ランプ（緑色の回転矢印）
            command_name = @background_executor.current_command || "処理中"
            right_parts << "\e[32m🔄\e[0m #{command_name}"
          elsif @completion_lamp_message && @completion_lamp_time
            # 完了ランプ（3秒間表示）
            if (Time.now - @completion_lamp_time) < 3.0
              right_parts << @completion_lamp_message
            else
              @completion_lamp_message = nil
              @completion_lamp_time = nil
            end
          end
        end

        # FPS表示（test modeの時のみ）
        if @test_mode && fps
          right_parts << "#{fps.round(1)} FPS"
        end

        right_info = right_parts.join(" | ")

        # ブックマーク一覧を利用可能な幅に収める
        if right_info.empty?
          available_width = @screen_width
        else
          available_width = @screen_width - right_info.length - 3
        end
        if bookmark_text.length > available_width && available_width > 3
          bookmark_text = bookmark_text[0...available_width - 3] + "..."
        elsif available_width <= 3
          bookmark_text = ""
        end

        # フッタ全体を構築（左にブックマーク、右に情報がある場合のみ右寄せ）
        if right_info.empty?
          footer_content = bookmark_text.ljust(@screen_width)[0...@screen_width]
        else
          padding = @screen_width - bookmark_text.length - right_info.length
          footer_content = "#{bookmark_text}#{' ' * padding}#{right_info}"
          footer_content = footer_content.ljust(@screen_width)[0...@screen_width]
        end
        screen.put_string(0, y, footer_content, fg: "\e[7m")
      end
    end

    def draw_footer(render_time = nil)
      # フッタは最下行に表示
      footer_line = @screen_height - FOOTER_HEIGHT + 1
      print "\e[#{footer_line};1H"

      if @keybind_handler.filter_active?
        if @keybind_handler.instance_variable_get(:@filter_mode)
          help_text = "Filter mode: Type to filter, ESC to clear, Enter to apply, Backspace to delete"
        else
          help_text = "Filtered view active - Space to edit filter, ESC to clear filter"
        end
        # フィルタモードでは通常のフッタを表示
        footer_content = help_text.ljust(@screen_width)[0...@screen_width]
        print "\e[7m#{footer_content}\e[0m"
      else
        # 通常モードではブックマーク一覧、ステータス情報、?:helpを1行に表示
        # ブックマークをキャッシュ（毎フレームのファイルI/Oを回避）
        current_time = Time.now
        if @cached_bookmarks.nil? || @cached_bookmark_time.nil? || (current_time - @cached_bookmark_time) > @bookmark_cache_ttl
          require_relative 'bookmark'
          bookmark = Bookmark.new
          @cached_bookmarks = bookmark.list
          @cached_bookmark_time = current_time
        end
        bookmarks = @cached_bookmarks

        # 起動ディレクトリを取得
        start_dir = @directory_listing&.start_directory
        start_dir_name = if start_dir
                           File.basename(start_dir)
                         else
                           "start"
                         end

        # ブックマーク一覧を作成（0.起動dir を先頭に追加）
        bookmark_parts = ["0.#{start_dir_name}"]
        unless bookmarks.empty?
          bookmark_parts.concat(bookmarks.take(9).map.with_index(1) { |bm, idx| "#{idx}.#{bm[:name]}" })
        end
        bookmark_text = bookmark_parts.join(" ")

        # フッタ全体を構築（ブックマーク左寄せ）
        footer_content = bookmark_text.ljust(@screen_width)[0...@screen_width]
        print "\e[7m#{footer_content}\e[0m"
      end
    end

    # ノンブロッキング入力処理（ゲームループ用）
    # IO.selectでタイムアウト付きで入力をチェック
    def handle_input_nonblocking
      # 0msタイムアウトで即座にチェック（30FPS = 33.33ms/frame）
      ready = IO.select([STDIN], nil, nil, 0)
      return false unless ready

      begin
        # read_nonblockを使ってノンブロッキングで1文字読み取る
        input = STDIN.read_nonblock(1)
      rescue IO::WaitReadable, IO::EAGAINWaitReadable
        # 入力が利用できない
        return false
      rescue Errno::ENOTTY, Errno::ENODEV
        # ターミナルでない環境
        return false
      end

      # コマンドモードがアクティブな場合は、エスケープシーケンス処理をスキップ
      # ESCキーをそのまま handle_command_input に渡す
      if @command_mode_active
        handle_command_input(input)
        return true
      end

      # 特殊キーの処理（エスケープシーケンス）（コマンドモード外のみ）
      if input == "\e"
        next_char = begin
          STDIN.read_nonblock(1)
        rescue StandardError
          nil
        end
        if next_char == '['
          # 矢印キーなどのシーケンス
          third_char = begin
            STDIN.read_nonblock(1)
          rescue StandardError
            nil
          end
          input = case third_char
          when 'A' then 'k'  # Up arrow
          when 'B' then 'j'  # Down arrow
          when 'C' then 'l'  # Right arrow
          when 'D' then 'h'  # Left arrow
          when 'Z' then handle_shift_tab; return true  # Shift+Tab
          else "\e"  # ESCキー（そのまま保持）
          end
        else
          input = "\e"  # ESCキー（そのまま保持）
        end
      end

      # Tabキーでモード切り替え
      if input == "\t"
        handle_tab_key
        return true
      end

      # キーバインドハンドラーに処理を委譲
      result = @keybind_handler.handle_key(input) if input

      # 外部ターミナルアプリ（vim等）から戻った後は画面全体を再描画
      if result == :needs_refresh
        refresh_display
      end

      # 終了処理（qキーのみ、確認ダイアログの結果を確認）
      if input == 'q' && result == true
        @running = false
      end

      # 入力があったことを返す
      true
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

      # コマンドモードがアクティブな場合は、エスケープシーケンス処理をスキップ
      # ESCキーをそのまま handle_command_input に渡す
      if @command_mode_active
        handle_command_input(input)
        return
      end

      # 特殊キーの処理（コマンドモード外のみ）
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

      # キーバインドハンドラーに処理を委譲
      result = @keybind_handler.handle_key(input)

      # 外部ターミナルアプリ（vim等）から戻った後は画面全体を再描画
      if result == :needs_refresh
        refresh_display
      end

      # 終了処理（qキーのみ、確認ダイアログの結果を確認）
      if input == 'q' && result == true
        @running = false
      end
    end

    # Tabキー: 次のブックマークへ循環移動
    def handle_tab_key
      @keybind_handler.goto_next_bookmark
    end

    # Shift+Tabによる逆順モード切り替え
    def handle_shift_tab
      @tab_mode_manager.previous_mode
      apply_mode_change(@tab_mode_manager.current_mode)
    end

    # モード変更を適用
    def apply_mode_change(mode)
      case mode
      when :files
        # ヘルプモードまたはログビューワモードから戻る
        if @keybind_handler.help_mode?
          @keybind_handler.send(:exit_help_mode)
        elsif @keybind_handler.log_viewer_mode?
          @keybind_handler.send(:exit_log_viewer_mode)
        elsif @keybind_handler.in_job_mode?
          @keybind_handler.send(:exit_job_mode)
        end
      when :help
        # ヘルプモードに入る
        unless @keybind_handler.help_mode?
          @keybind_handler.send(:exit_log_viewer_mode) if @keybind_handler.log_viewer_mode?
          @keybind_handler.send(:exit_job_mode) if @keybind_handler.in_job_mode?
          @keybind_handler.send(:enter_help_mode)
        end
      when :logs
        # ログビューワモードに入る
        unless @keybind_handler.log_viewer_mode?
          @keybind_handler.send(:exit_help_mode) if @keybind_handler.help_mode?
          @keybind_handler.send(:exit_job_mode) if @keybind_handler.in_job_mode?
          @keybind_handler.send(:enter_log_viewer_mode)
        end
      when :jobs
        # ジョブモードに入る
        unless @keybind_handler.in_job_mode?
          @keybind_handler.send(:exit_help_mode) if @keybind_handler.help_mode?
          @keybind_handler.send(:exit_log_viewer_mode) if @keybind_handler.log_viewer_mode?
          @keybind_handler.enter_job_mode
        end
      end
    end

    # コマンドモード関連のメソッドは public にする
    public

    # コマンドモードを起動
    def activate_command_mode
      @command_mode_active = true
      @command_input = ""
      # 閲覧中ディレクトリをコマンドモードに通知（ローカルスクリプト・Rakefileの検出用）
      browsing_dir = @directory_listing&.current_path || Dir.pwd
      @command_mode.update_browsing_directory(browsing_dir)
    end

    # コマンドモードを終了
    def deactivate_command_mode
      @command_mode_active = false
      @command_input = ""
      # オーバーレイをクリア
      @screen&.clear_overlay if @screen&.overlay_enabled?
    end

    # コマンドモードダイアログをオーバーレイに描画
    def draw_command_mode_to_overlay
      return unless @screen

      title = "Command Mode"
      content_lines = [
        "",
        "#{@command_input}_",  # カーソル表示
        "",
        "Tab: Complete | Enter: Execute | ESC: Cancel"
      ]

      border_color = "\e[34m"      # Blue
      title_color = "\e[1;34m"     # Bold blue
      content_color = "\e[37m"     # White

      # ウィンドウサイズを計算
      width, height = @dialog_renderer.calculate_dimensions(content_lines, {
        title: title,
        min_width: 50,
        max_width: 80
      })

      # 中央位置を計算
      x, y = @dialog_renderer.calculate_center(width, height)

      # オーバーレイにダイアログを描画
      @dialog_renderer.draw_floating_window_to_overlay(@screen, x, y, width, height, title, content_lines, {
        border_color: border_color,
        title_color: title_color,
        content_color: content_color
      })
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
        # コマンド実行後、入力をクリアして再度コマンドモードに戻る
        @command_input = ""
      when "\e"
        # Escape キーでコマンドモードをキャンセル
        # まずコマンドウィンドウをクリア
        @command_mode_ui.clear_prompt
        deactivate_command_mode
        # ファイラー画面を再描画（バッファベース）
        if @screen && @renderer
          # レンダラーの前フレーム情報をリセット（差分レンダリングを強制的に全体描画にする）
          @renderer.clear
          @screen.clear
          draw_screen_to_buffer(@screen, nil, nil)
          @renderer.render(@screen)
          # カーソルを画面外に移動（メインループと同じ処理）
          print "\e[#{@screen_height};#{@screen_width}H"
        else
          # フォールバック（古い実装）
          draw_screen
        end
      when "\t"
        # Tab キーで補完
        handle_tab_completion
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

      # コマンド履歴に追加
      @command_history.add(command_string)

      # 現在のディレクトリを取得
      working_dir = @directory_listing&.current_path || Dir.pwd

      result = @command_mode.execute(command_string, working_dir: working_dir)

      # バックグラウンドコマンドの場合は結果表示をスキップ
      # (完了通知は別途メインループで表示される)
      if result && !result.to_s.include?("🔄 Running in background")
        # コマンド実行結果をフローティングウィンドウで表示
        @command_mode_ui.show_result(result)
      end

      # メインループの次フレームで再描画される（draw_screenは使わない）
      # draw_screen（レガシー直接出力）はバッファベースのオーバーレイと座標系が異なるため、
      # 使用するとコマンドプロンプトの枠線が残る不具合が発生する
    end

    # Tab補完を処理
    def handle_tab_completion
      # 補完候補を取得
      candidates = @command_completion.complete(@command_input)

      # 候補がない場合は何もしない
      return if candidates.empty?

      # 候補が1つの場合はそれに補完
      if candidates.size == 1
        @command_input = candidates.first
        return
      end

      # 複数の候補がある場合、共通プレフィックスまで補完
      prefix = @command_completion.common_prefix(@command_input)

      # 入力が変わる場合は補完して終了
      if prefix != @command_input
        @command_input = prefix
        return
      end

      # 入力が変わらない場合は候補リストを表示
      show_completion_candidates(candidates)
    end

    # 補完候補を一時的に表示
    def show_completion_candidates(candidates)
      title = "Completions (#{candidates.size})"

      # 候補を表示用にフォーマット（最大20件）
      display_candidates = candidates.first(20)
      content_lines = [""]
      display_candidates.each do |candidate|
        content_lines << "  #{candidate}"
      end

      if candidates.size > 20
        content_lines << ""
        content_lines << "  ... 他 #{candidates.size - 20} 件"
      end

      content_lines << ""
      content_lines << "Press any key to continue..."

      # オーバーレイダイアログを表示
      show_overlay_dialog(title, content_lines, {
        min_width: 40,
        max_width: 80,
        border_color: "\e[33m",    # Yellow
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })
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

      # オーバーレイダイアログを表示
      show_overlay_dialog(notice[:title], notice[:content], {
        width: width,
        height: height,
        border_color: "\e[36m",  # Cyan
        title_color: "\e[1;36m", # Bold cyan
        content_color: "\e[37m"  # White
      })

      # Mark as shown
      info_notice.mark_as_shown(notice[:file])
    end

    # ログモードに入る（廃止済み: 空のメソッド）
    def enter_log_mode(_project_log)
      # プロジェクトモード廃止により何もしない
    end

    # ログモードを終了（廃止済み: 空のメソッド）
    def exit_log_mode
      # プロジェクトモード廃止により何もしない
    end

    # ジョブモードを設定
    def set_job_mode(job_mode, job_manager, notification_manager)
      @job_mode_instance = job_mode
      @job_manager = job_manager
      @notification_manager = notification_manager
      @in_job_mode = true
      # 画面を一度クリアしてレンダラーをリセット
      print "\e[2J\e[H"
      @renderer.clear if @renderer
      # 再描画フラグを立てる
      @job_mode_needs_redraw = true
    end

    # ジョブモードを終了
    def exit_job_mode
      @in_job_mode = false
      @job_mode_instance = nil
      @job_manager = nil
      # バッファベースの全画面再描画を使用
      update_screen_size
      print "\e[2J\e[H"
      if @screen && @renderer
        @renderer.clear
        @screen.clear
        draw_screen_to_buffer(@screen, nil, nil)
        @renderer.render(@screen)
        print "\e[#{@screen_height};#{@screen_width}H"
      else
        draw_screen
      end
    end

    # ジョブモード再描画をトリガー
    def trigger_job_mode_redraw
      @job_mode_needs_redraw = true
    end

    # ジョブモード画面を描画（バッファベース描画への橋渡し）
    def draw_job_mode_screen
      return unless @in_job_mode && @job_mode_instance && @job_manager
      return unless @screen && @renderer

      # バッファベースの描画を使用
      draw_screen_to_buffer(@screen, nil, nil)
      @renderer.render(@screen)
      print "\e[#{@screen_height};#{@screen_width}H"

      STDOUT.flush
      @job_mode_needs_redraw = false
    end

    # Noice風の通知を描画
    def draw_notifications
      nm = @notification_manager || @keybind_handler&.notification_manager
      return unless nm

      # 期限切れの通知を削除
      nm.expire_old_notifications

      notifications = nm.notifications
      return if notifications.empty?

      # 通知の幅と位置
      notification_width = 22
      x = @screen_width - notification_width - 2  # 右端から2文字マージン

      notifications.each_with_index do |notif, i|
        y = 2 + (i * 5)  # 各通知4行 + 間隔1行

        # 色設定
        border_color = notif[:border_color] == :green ? "\e[32m" : "\e[31m"
        reset = "\e[0m"

        # ステータスアイコン
        icon = notif[:type] == :success ? '✓' : '✗'

        # 通知の内容を作成
        name_line = "#{icon} #{notif[:name]}"[0...notification_width - 4]
        status_line = notif[:status_text][0...notification_width - 4]

        # 上部ボーダー
        print "\e[#{y};#{x}H#{border_color}╭#{'─' * (notification_width - 2)}╮#{reset}"

        # 1行目: アイコン + 名前
        print "\e[#{y + 1};#{x}H#{border_color}│#{reset} #{name_line.ljust(notification_width - 4)} #{border_color}│#{reset}"

        # 2行目: ステータス
        print "\e[#{y + 2};#{x}H#{border_color}│#{reset}   #{status_line.ljust(notification_width - 6)} #{border_color}│#{reset}"

        # Exit code行（失敗時のみ）
        if notif[:type] == :error && notif[:exit_code]
          exit_line = "Exit code: #{notif[:exit_code]}"[0...notification_width - 6]
          print "\e[#{y + 3};#{x}H#{border_color}│#{reset}   #{exit_line.ljust(notification_width - 6)} #{border_color}│#{reset}"
          print "\e[#{y + 4};#{x}H#{border_color}╰#{'─' * (notification_width - 2)}╯#{reset}"
        else
          # 下部ボーダー
          print "\e[#{y + 3};#{x}H#{border_color}╰#{'─' * (notification_width - 2)}╯#{reset}"
        end
      end
    end

    # オーバーレイダイアログを表示してキー入力を待つヘルパーメソッド
    # @param title [String] ダイアログタイトル
    # @param content_lines [Array<String>] コンテンツ行
    # @param options [Hash] オプション
    # @option options [String] :border_color ボーダー色
    # @option options [String] :title_color タイトル色
    # @option options [String] :content_color コンテンツ色
    # @option options [Integer] :width 幅（省略時は自動計算）
    # @option options [Integer] :height 高さ（省略時は自動計算）
    # @option options [Integer] :min_width 最小幅
    # @option options [Integer] :max_width 最大幅
    # @yield キー入力処理（ブロックが与えられた場合）
    # @return [String] 入力されたキー
    def show_overlay_dialog(title, content_lines, options = {}, &block)
      return nil unless @screen && @renderer

      # オーバーレイを有効化し、前回のダイアログ残留を除去
      @screen.enable_overlay
      @screen.clear_overlay

      # ウィンドウサイズを計算
      if options[:width] && options[:height]
        width = options[:width]
        height = options[:height]
      else
        width, height = @dialog_renderer.calculate_dimensions(content_lines, {
          title: title,
          min_width: options[:min_width] || 40,
          max_width: options[:max_width] || 80
        })
      end

      # 中央位置を計算
      x, y = @dialog_renderer.calculate_center(width, height)

      # オーバーレイにダイアログを描画
      @dialog_renderer.draw_floating_window_to_overlay(@screen, x, y, width, height, title, content_lines, {
        border_color: options[:border_color] || "\e[37m",
        title_color: options[:title_color] || "\e[1;33m",
        content_color: options[:content_color] || "\e[37m"
      })

      # レンダリング
      @renderer.render(@screen)

      # キー入力を待つ
      key = block_given? ? yield : STDIN.getch

      # オーバーレイを無効化
      @screen.disable_overlay

      # 画面を再描画
      @renderer.render(@screen)

      key
    end

    # Screen と Renderer のアクセサ（他のクラスから利用可能に）
    attr_reader :screen, :renderer

    # ヘルプダイアログを表示
    def show_help_dialog
      content_lines = [
        '',
        "rufio v#{VERSION}",
        '',
        'Key Bindings:',
        '',
        'j/k      - Move up/down',
        'h/l      - Navigate back/enter',
        'g/G      - Go to top/bottom',
        'o        - Open file',
        'f        - Filter files',
        's        - Search with fzf',
        'F        - Content search (rga)',
        'a/A      - Create file/directory',
        'm/c/x    - Move/Copy/Delete',
        'b        - Add bookmark',
        'z        - Zoxide navigation',
        '0        - Go to start directory',
        '1-9      - Go to bookmark',
        'J        - Job mode',
        ':        - Command mode',
        'q        - Quit',
        ''
      ]

      # お知らせ情報を追加
      require_relative 'info_notice'
      info_notice = InfoNotice.new
      all_notices = Dir.glob(File.join(info_notice.info_dir, '*.txt'))

      if !all_notices.empty?
        content_lines << 'Recent Updates:'
        content_lines << ''
        all_notices.take(3).each do |file|
          title = info_notice.extract_title(file)
          content_lines << "  • #{title}"
        end
        content_lines << ''
      end

      content_lines << 'Press any key to continue...'

      width = 60
      height = [content_lines.length + 4, @screen_height - 4].min

      # オーバーレイダイアログを表示
      show_overlay_dialog('rufio - Help', content_lines, {
        width: width,
        height: height,
        border_color: "\e[36m",    # Cyan
        title_color: "\e[1;36m",   # Bold cyan
        content_color: "\e[37m"    # White
      })
    end

  end
end

