# frozen_string_literal: true

require 'shellwords'
require_relative 'file_opener'
require_relative 'filter_manager'
require_relative 'navigation_controller'
require_relative 'file_operation_controller'
require_relative 'bookmark_controller'
require_relative 'search_controller'
require_relative 'selection_manager'
require_relative 'file_operations'
require_relative 'bookmark_manager'
require_relative 'zoxide_integration'
require_relative 'dialog_renderer'
require_relative 'logger'

module Rufio
  class KeybindHandler
    # NavigationController への委譲
    def current_index
      @nav_controller.current_index
    end

    def preview_focused?
      @nav_controller.preview_focused?
    end

    def preview_scroll_offset
      @nav_controller.preview_scroll_offset
    end

    def filter_query
      @filter_manager.filter_query
    end

    # ASCII character range constants
    ASCII_PRINTABLE_START = 32
    ASCII_PRINTABLE_END = 127
    MULTIBYTE_THRESHOLD = 1

    # Dialog size constants
    CONFIRMATION_DIALOG_WIDTH = 45
    DIALOG_BORDER_HEIGHT = 4

    # File system operation constants
    FILESYSTEM_SYNC_DELAY = 0.01  # 10ms wait for filesystem sync

    def initialize
      @directory_listing = nil
      @terminal_ui = nil
      @file_opener = FileOpener.new

      # Manager classes
      @filter_manager = FilterManager.new
      @selection_manager = SelectionManager.new
      @file_operations = FileOperations.new
      @dialog_renderer = DialogRenderer.new
      @bookmark_manager = BookmarkManager.new(Bookmark.new, @dialog_renderer)
      @zoxide_integration = ZoxideIntegration.new(@dialog_renderer)
      @notification_manager = NotificationManager.new
      @script_path_manager = ScriptPathManager.new(Config::SCRIPT_PATHS_YML)

      # Job mode
      @job_manager = JobManager.new(notification_manager: @notification_manager)
      @job_mode = JobMode.new(job_manager: @job_manager)

      # NavigationController（移動・フィルタ・プレビュースクロールを担当）
      @nav_controller = NavigationController.new(nil, @filter_manager)

      # FileOperationController（ファイル操作を担当）
      @file_op_controller = FileOperationController.new(
        nil, @file_operations, @dialog_renderer, @nav_controller, @selection_manager
      )

      # BookmarkController（ブックマーク・zoxide・スクリプトパス管理を担当）
      @bookmark_controller = BookmarkController.new(
        nil, @bookmark_manager, @dialog_renderer, @nav_controller,
        @script_path_manager, @notification_manager, @zoxide_integration
      )

      # SearchController（fzf・rga検索を担当）
      @search_controller = SearchController.new(nil, @file_opener)

      # Help mode
      @in_help_mode = false
      @pre_help_directory = nil

      # Log viewer mode
      @in_log_viewer_mode = false
      @pre_log_viewer_directory = nil
      @log_dir = File.join(Dir.home, '.config', 'rufio', 'logs')

      # キーマップを構築（ConfigLoader.keybinds から逆引きマップを作成）
      build_key_map
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
      @nav_controller.set_directory_listing(directory_listing)
      @file_op_controller.set_directory_listing(directory_listing)
      @bookmark_controller.set_directory_listing(directory_listing)
      @search_controller.set_directory_listing(directory_listing)
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
      @nav_controller.set_terminal_ui(terminal_ui)
      @file_op_controller.set_terminal_ui(terminal_ui)
      @bookmark_controller.set_terminal_ui(terminal_ui)
      # terminal_ui が設定されたら、bookmark_manager と zoxide_integration にも渡す
      @bookmark_manager.set_terminal_ui(terminal_ui)
      @zoxide_integration.set_terminal_ui(terminal_ui)
    end

    def selected_items
      @selection_manager.selected_items
    end

    def is_selected?(entry_name)
      # Only show as selected if we're in the same directory where selection happened
      current_path = @directory_listing&.current_path || Dir.pwd
      source_path = @selection_manager.source_directory

      # If no source directory or different directory, nothing is selected
      return false if source_path.nil? || current_path != source_path

      @selection_manager.selected?(entry_name)
    end

    def handle_key(key)
      return false unless @directory_listing

      # ジョブモード中の特別処理
      if @job_mode.active?
        return handle_job_mode_key(key)
      end

      # プレビューペインフォーカス中の特別処理
      if @nav_controller.preview_focused?
        return @nav_controller.handle_preview_focus_key(key)
      end

      # ヘルプモード中のESCキー特別処理
      if @in_help_mode && key == "\e"
        return exit_help_mode
      end

      # ログビューワモード中のESCキー特別処理
      if @in_log_viewer_mode && key == "\e"
        return exit_log_viewer_mode
      end

      # フィルターモード中は他のキーバインドを無効化
      return @nav_controller.handle_filter_input(key) if @filter_manager.filter_mode

      entries = get_active_entries

      # Enter キー（特殊処理: プレビューペインフォーカスまたはナビゲーション）
      if key == "\r" || key == "\n"
        return @nav_controller.handle_enter_key(current_entry, @in_help_mode, @in_log_viewer_mode)
      end

      # ESC キー（特殊処理: フィルタクリア）
      if key == "\e"
        if @filter_manager.filter_active?
          @nav_controller.clear_filter_mode
          return true
        else
          return false
        end
      end

      # 数字キー（1-9）: ブックマーク番号によるジャンプ（設定化の対象外）
      return goto_bookmark(key.to_i) if key.match?(/^[1-9]$/)

      # キーマップでアクションを検索してdispatch
      action = @key_map[key]
      return false unless action

      dispatch(action, entries)
    end

    def select_index(index)
      entries = get_active_entries
      @nav_controller.select_index([[index, 0].max, entries.length - 1].min)
    end

    def current_entry
      entries = get_active_entries
      entries[@nav_controller.current_index]
    end

    def filter_active?
      @filter_manager.filter_active?
    end

    def get_active_entries
      entries = if @filter_manager.filter_active?
                  @filter_manager.filtered_entries
                else
                  @directory_listing&.list_entries || []
                end
      if @in_help_mode || @in_log_viewer_mode
        entries.reject { |e| e[:name] == '..' }
      else
        entries
      end
    end

    # ヘルプモード関連メソッド

    # ヘルプモード中かどうか
    def help_mode?
      @in_help_mode
    end

    # ヘルプモードに入る
    def enter_help_mode
      return false unless @directory_listing

      # 現在のディレクトリを保存
      @pre_help_directory = @directory_listing.current_path

      # info ディレクトリに移動
      rufio_root = File.expand_path('../..', __dir__)
      info_dir = File.join(rufio_root, 'info')

      # info ディレクトリが存在することを確認
      return false unless Dir.exist?(info_dir)

      # ヘルプモードを有効化
      @in_help_mode = true

      # info ディレクトリに移動
      navigate_to_directory(info_dir)

      true
    end

    # ヘルプモードを終了
    def exit_help_mode
      return false unless @in_help_mode
      return false unless @pre_help_directory

      # ヘルプモードを無効化
      @in_help_mode = false

      # 元のディレクトリに戻る
      navigate_to_directory(@pre_help_directory)

      # 保存したディレクトリをクリア
      @pre_help_directory = nil

      true
    end

    # ログビューワモード関連メソッド

    # ログビューワモード中かどうか
    def log_viewer_mode?
      @in_log_viewer_mode
    end

    # ログビューワモードに入る
    def enter_log_viewer_mode
      return false unless @directory_listing

      # 現在のディレクトリを保存
      @pre_log_viewer_directory = @directory_listing.current_path

      # log ディレクトリを作成（存在しない場合）
      FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)

      # log ディレクトリに移動
      navigate_to_directory(@log_dir)

      # ログビューワモードを有効化
      @in_log_viewer_mode = true

      true
    end

    # ログビューワモードを終了
    def exit_log_viewer_mode
      return false unless @in_log_viewer_mode
      return false unless @pre_log_viewer_directory

      # ログビューワモードを無効化
      @in_log_viewer_mode = false

      # 元のディレクトリに戻る
      navigate_to_directory(@pre_log_viewer_directory)

      # 保存したディレクトリをクリア
      @pre_log_viewer_directory = nil

      true
    end

    # ヘルプモード時の制限付き親ディレクトリナビゲーション
    def navigate_parent_with_restriction
      if @in_help_mode
        # info ディレクトリより上には移動できない
        rufio_root = File.expand_path('../..', __dir__)
        info_dir = File.join(rufio_root, 'info')

        current_path = @directory_listing.current_path

        # 現在のパスが info ディレクトリ以下でない場合は移動を許可しない
        unless current_path.start_with?(info_dir)
          return false
        end

        # 現在のパスが info ディレクトリそのものの場合は移動を許可しない
        if current_path == info_dir
          return false
        end

        # info ディレクトリ配下であれば、通常のナビゲーションを実行
        navigate_parent
      elsif @in_log_viewer_mode
        # log ディレクトリより上には移動できない
        current_path = @directory_listing.current_path

        # 現在のパスが log ディレクトリ以下でない場合は移動を許可しない
        unless current_path.start_with?(@log_dir)
          return false
        end

        # 現在のパスが log ディレクトリそのものの場合は移動を許可しない
        if current_path == @log_dir
          return false
        end

        # log ディレクトリ配下であれば、通常のナビゲーションを実行
        navigate_parent
      else
        # ヘルプモード・ログビューワモード外では通常のナビゲーション
        navigate_parent
      end
    end

    # プレビューペイン関連メソッド（NavigationController に委譲）

    def focus_preview_pane
      @nav_controller.focus_preview_pane(current_entry)
    end

    def unfocus_preview_pane
      @nav_controller.unfocus_preview_pane
    end

    def scroll_preview_down
      @nav_controller.scroll_preview_down
    end

    def scroll_preview_up
      @nav_controller.scroll_preview_up
    end

    def scroll_preview_page_down
      @nav_controller.scroll_preview_page_down
    end

    def scroll_preview_page_up
      @nav_controller.scroll_preview_page_up
    end

    def reset_preview_scroll
      @nav_controller.reset_preview_scroll
    end

    # Tabキー: 次のブックマークへ循環移動
    def goto_next_bookmark
      bookmarks = @bookmark_manager.list
      return nil unless bookmarks&.any?

      current_path = @directory_listing.current_path
      current_idx = bookmarks.find_index { |bm| bm[:path] == current_path }

      next_idx = current_idx ? (current_idx + 1) % bookmarks.length : 0
      next_bookmark = bookmarks[next_idx]
      navigate_to_directory(next_bookmark[:path])
      next_idx
    end

    private

    # オーバーレイダイアログを表示してキー入力を待つヘルパーメソッド
    # terminal_ui が利用可能な場合はオーバーレイを使用、そうでなければ従来の方法を使用
    # @param title [String] ダイアログタイトル
    # @param content_lines [Array<String>] コンテンツ行
    # @param options [Hash] オプション
    # @yield キー入力処理（ブロックが与えられた場合）
    # @return [String] 入力されたキー
    def show_overlay_dialog(title, content_lines, options = {}, &block)
      # terminal_ui が利用可能で、screen と renderer が存在する場合のみオーバーレイを使用
      use_overlay = @terminal_ui &&
                    @terminal_ui.respond_to?(:screen) &&
                    @terminal_ui.respond_to?(:renderer) &&
                    @terminal_ui.screen &&
                    @terminal_ui.renderer

      if use_overlay
        # オーバーレイを使用
        @terminal_ui.show_overlay_dialog(title, content_lines, options, &block)
      else
        # フォールバック: 従来の方法
        width = options[:width]
        height = options[:height]

        unless width && height
          width, height = @dialog_renderer.calculate_dimensions(content_lines, {
            title: title,
            min_width: options[:min_width] || 40,
            max_width: options[:max_width] || 80
          })
        end

        x, y = @dialog_renderer.calculate_center(width, height)

        @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
          border_color: options[:border_color] || "\e[37m",
          title_color: options[:title_color] || "\e[1;33m",
          content_color: options[:content_color] || "\e[37m"
        })

        key = block_given? ? yield : STDIN.getch

        @dialog_renderer.clear_area(x, y, width, height)
        @terminal_ui&.refresh_display

        key
      end
    end

    def navigate_parent
      @nav_controller.navigate_parent
    end

    # キーマップを構築（ConfigLoader.keybinds の逆引きマップ: key_char => action_symbol）
    def build_key_map
      @key_map = ConfigLoader.keybinds.each_with_object({}) do |(action, key), map|
        map[key.to_s] = action
      end
    end

    def key_map
      @key_map
    end

    # アクションシンボルに対応する処理を実行
    def dispatch(action, entries)
      case action
      when :move_up         then @nav_controller.move_up
      when :move_down       then @nav_controller.move_down(entries)
      when :navigate_parent then navigate_parent_with_restriction
      when :navigate_enter  then @nav_controller.navigate_enter(current_entry, @in_help_mode, @in_log_viewer_mode)
      when :top             then @nav_controller.move_to_top
      when :bottom          then @nav_controller.move_to_bottom(entries)
      when :refresh         then @nav_controller.refresh
      when :open_file       then @nav_controller.open_current_file(current_entry)
      when :open_explorer   then @nav_controller.open_directory_in_explorer
      when :rename          then @file_op_controller.rename_current_file(current_entry)
      when :delete          then @file_op_controller.delete_current_file_with_confirmation(current_entry, method(:get_active_entries))
      when :create_file     then @file_op_controller.create_file
      when :create_dir      then @file_op_controller.create_directory
      when :move_selected   then @file_op_controller.move_selected_to_current
      when :copy_selected   then @file_op_controller.copy_selected_to_current
      when :delete_selected then @file_op_controller.delete_selected_files
      when :select          then toggle_selection
      when :filter
        if @filter_manager.filter_active?
          @filter_manager.restart_filter_mode(@directory_listing.list_entries)
        else
          @nav_controller.start_filter_mode
        end
      when :fzf_search, :fzf_search_alt then fzf_search
      when :rga_search      then rga_search
      when :add_bookmark    then add_bookmark
      when :bookmark_menu   then show_bookmark_menu
      when :zoxide          then show_zoxide_menu
      when :start_dir       then goto_start_directory
      when :job_mode        then enter_job_mode
      when :help            then enter_help_mode
      when :log_viewer      then enter_log_viewer_mode
      when :command_mode    then activate_command_mode
      when :quit            then exit_request
      else
        false
      end
    end

    def exit_request
      @file_op_controller.show_exit_confirmation
    end

    def fzf_search
      @search_controller.fzf_search
    end

    def rga_search
      @search_controller.rga_search
    end

    def start_filter_mode
      @nav_controller.start_filter_mode
    end

    def handle_filter_input(key)
      @nav_controller.handle_filter_input(key)
    end

    def exit_filter_mode_keep_filter
      @nav_controller.exit_filter_mode_keep_filter
    end

    def clear_filter_mode
      @nav_controller.clear_filter_mode
    end

    def exit_filter_mode
      @nav_controller.exit_filter_mode
    end

    def toggle_selection
      entry = current_entry
      return false unless entry

      current_path = @directory_listing&.current_path || Dir.pwd
      @selection_manager.toggle_selection(entry, current_path)
      true
    end



    def goto_start_directory
      @bookmark_controller.goto_start_directory
    end

    def goto_bookmark(number)
      @bookmark_controller.goto_bookmark(number)
    end


    def add_bookmark
      @bookmark_controller.add_bookmark
    end

    # ブックマークメニューを表示（スクリプトパス機能を含む）
    def show_bookmark_menu
      @bookmark_controller.show_bookmark_menu
    end

    # カレントディレクトリをスクリプトパスに追加
    def add_to_script_paths
      @bookmark_controller.add_to_script_paths
    end

    # スクリプトパス管理UIを表示
    def show_script_paths_manager
      @bookmark_controller.show_script_paths_manager
    end

    def navigate_to_directory(path)
      return false unless @directory_listing

      result = @directory_listing.navigate_to_path(path)
      if result
        @nav_controller.select_index(0)
        @nav_controller.clear_filter_mode
        true
      else
        false
      end
    end

    # zoxide 機能
    def show_zoxide_menu
      @bookmark_controller.show_zoxide_menu
    end

    # コマンドモードを起動
    def activate_command_mode
      @terminal_ui&.activate_command_mode
      true
    end

    # カーソルを画面下部の入力行に移動
    def move_to_input_line
      # 画面の最終行にカーソルを移動
      # terminal_uiから画面の高さを取得できない場合は、24行目（デフォルト）を使用
      screen_height = @terminal_ui&.instance_variable_get(:@screen_height) || 24
      print "\e[#{screen_height};1H"  # 最終行の先頭にカーソル移動
      print "\e[2K"  # 行全体をクリア
    end

    # Escキーでキャンセル可能な入力処理
    # 戻り値: 入力された文字列 (Escでキャンセルした場合はnil)
    def read_line_with_escape
      require 'io/console'
      input = []

      loop do
        char = STDIN.getch

        case char
        when "\e" # Escape
          # 入力をクリア
          print "\r" + ' ' * (input.length + 50) + "\r"
          return nil
        when "\r", "\n" # Enter
          puts
          return input.join
        when "\u007F", "\b" # Backspace/Delete
          unless input.empty?
            input.pop
            # カーソルを1つ戻して文字を消去
            print "\b \b"
          end
        when "\u0003" # Ctrl+C
          puts
          raise Interrupt
        else
          # 印字可能文字のみ受け付ける
          if char.ord >= ASCII_PRINTABLE_START && char.ord < ASCII_PRINTABLE_END ||
             char.bytesize > MULTIBYTE_THRESHOLD # マルチバイト文字（日本語など）
            input << char
            print char
          end
        end
      end
    end

    # ヘルプダイアログを表示
    def show_help_dialog
      @terminal_ui&.show_help_dialog if @terminal_ui
      true
    end

    # ジョブモード関連メソッド（publicに戻す）
    public

    # ジョブマネージャを取得
    attr_reader :job_manager, :job_mode, :notification_manager

    # ジョブモードに入る
    def enter_job_mode
      @job_mode.activate
      @terminal_ui&.set_job_mode(@job_mode, @job_manager, @notification_manager) if @terminal_ui
      true
    end

    # ジョブモードを終了
    def exit_job_mode
      @job_mode.deactivate
      @terminal_ui&.exit_job_mode if @terminal_ui
      @nav_controller.refresh
      true
    end

    # ジョブモード中のキー処理
    def handle_job_mode_key(key)
      result = @job_mode.handle_key(key)

      case result
      when :exit
        exit_job_mode
        true
      when :show_log
        # ログ表示は将来実装
        @terminal_ui&.trigger_job_mode_redraw if @terminal_ui
        true
      when true, false
        @terminal_ui&.trigger_job_mode_redraw if @terminal_ui
        result
      else
        result
      end
    end

    # ジョブモード中かどうか
    def in_job_mode?
      @job_mode.active?
    end

    # ジョブがあるかどうか
    def has_jobs?
      @job_manager.has_jobs?
    end

    # ジョブのステータスバーテキストを取得
    def job_status_bar_text
      return nil unless @job_manager.has_jobs?

      @job_manager.status_bar_text
    end
  end
end
