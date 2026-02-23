# frozen_string_literal: true

require 'io/console'
require_relative 'text_utils'

module Rufio
  class TerminalUI
    # Layout constants
    HEADER_HEIGHT = 1              # Header占有行数（モードタブ+パス+バージョン 1行に統合）
    FOOTER_HEIGHT = 1              # Footer占有行数（ブックマーク一覧 + ステータス情報）
    HEADER_FOOTER_MARGIN = 2       # Header(1行) + Footer(1行)分のマージン

    # Panel layout ratios
    LEFT_PANEL_RATIO = 0.5         # 左パネルの幅比率
    RIGHT_PANEL_RATIO = 1.0 - LEFT_PANEL_RATIO

    # Display constants
    DEFAULT_SCREEN_WIDTH = 80      # デフォルト画面幅
    DEFAULT_SCREEN_HEIGHT = 24     # デフォルト画面高さ
    HEADER_PADDING = 2             # ヘッダーのパディング
    FILTER_TEXT_RESERVED = 15      # フィルタテキスト表示の予約幅
    TAB_SEPARATOR = ">"              # タブ間セパレータ

    # File display constants
    ICON_SIZE_PADDING = 12         # アイコン、選択マーク、サイズ情報分
    CURSOR_OFFSET = 1              # カーソル位置のオフセット

    # Size display constants (bytes)
    KILOBYTE = 1024
    MEGABYTE = KILOBYTE * 1024
    GIGABYTE = MEGABYTE * 1024

    # Bookmark highlight duration (seconds)
    BOOKMARK_HIGHLIGHT_DURATION = 0.5

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


      # Tab mode manager
      @tab_mode_manager = TabModeManager.new

      # UIRenderer（描画ロジックを担当）
      ui_opts = ConfigLoader.ui_options
      @ui_renderer = UIRenderer.new(
        screen_width: @screen_width,
        screen_height: @screen_height,
        test_mode: @test_mode,
        left_panel_ratio: ui_opts[:panel_ratio],
        preview_enabled: ui_opts[:preview_enabled]
      )
    end

    attr_reader :ui_renderer

    def start(directory_listing, keybind_handler, file_preview, background_executor = nil)
      @directory_listing = directory_listing
      @keybind_handler = keybind_handler
      @file_preview = file_preview
      @background_executor = background_executor
      @keybind_handler.set_directory_listing(@directory_listing)
      @keybind_handler.set_terminal_ui(self)

      # UIRenderer に依存を注入
      @ui_renderer.keybind_handler = @keybind_handler
      @ui_renderer.directory_listing = @directory_listing
      @ui_renderer.file_preview = @file_preview
      @ui_renderer.background_executor = @background_executor

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

    # ブックマークハイライトが期限切れかどうか
    # @return [Boolean] true=期限切れ or ハイライト中でない, false=ハイライト中
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
      previous_lamp_message = @ui_renderer.completion_lamp_message

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
            # フッターのランプ表示用にも設定（UIRenderer が管理）
            @ui_renderer.completion_lamp_message = completion_msg
            @ui_renderer.completion_lamp_time = start
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
          current_lamp = @ui_renderer.completion_lamp_message
          if current_lamp != previous_lamp_message
            previous_lamp_message = current_lamp
            needs_redraw = true
          end
          # 完了ランプのタイムアウトチェック
          if @ui_renderer.completion_lamp_message && @ui_renderer.completion_lamp_time &&
             (start - @ui_renderer.completion_lamp_time) >= 3.0
            @ui_renderer.completion_lamp_message = nil
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

        # ブックマークハイライトのタイムアウトチェック（500ms 後に自動消去）
        if @ui_renderer.bookmark_highlight_expired?
          @ui_renderer.clear_highlighted_bookmark
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
    public

    # UIRenderer に全描画処理を委譲
    def draw_screen_to_buffer(screen, notification_message = nil, fps = nil)
      @ui_renderer.draw_screen_to_buffer(
        screen, notification_message, fps,
        in_job_mode: @in_job_mode,
        job_manager: @job_manager,
        job_mode_instance: @job_mode_instance
      )
    end

    private

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

      # TabキーはFilesモードの時のみブックマーク循環移動
      if input == "\t" && @tab_mode_manager.current_mode == :files
        handle_tab_key
        return true
      end

      # Jobsモード中のモード切替キーをインターセプト（L:Logs, ?:Help, J:Files復帰）
      if @in_job_mode
        case input
        when 'L' then apply_mode_change(:logs); return true
        when '?' then apply_mode_change(:help); return true
        when 'J' then apply_mode_change(:files); return true
        end
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
    # Tabキー: 次のブックマークへ循環移動
    def handle_tab_key
      next_idx = @keybind_handler.goto_next_bookmark
      if next_idx
        # display_index: 0=start_dir, 1..9=bookmarks（next_idx は 0-based bookmarks 配列）
        @ui_renderer.set_highlighted_bookmark(next_idx + 1)
        # ブックマークキャッシュを即時クリア（移動先を反映させる）
        @ui_renderer.clear_bookmark_cache
      end
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

