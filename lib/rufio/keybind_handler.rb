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

      # Job mode
      @notification_manager = NotificationManager.new
      @job_manager = JobManager.new(notification_manager: @notification_manager)
      @job_mode = JobMode.new(job_manager: @job_manager)

      # Script path manager (新形式: script_paths.yml)
      @script_path_manager = ScriptPathManager.new(Config::SCRIPT_PATHS_YML)
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

      case key
      when 'j'
        @nav_controller.move_down(entries)
      when 'k'
        @nav_controller.move_up
      when 'h'
        navigate_parent_with_restriction
      when 'l'  # l - navigate into directory
        @nav_controller.navigate_enter(current_entry, @in_help_mode, @in_log_viewer_mode)
      when "\r", "\n"  # Enter - focus preview pane or navigate
        @nav_controller.handle_enter_key(current_entry, @in_help_mode, @in_log_viewer_mode)
      when 'g'
        @nav_controller.move_to_top
      when 'G'
        @nav_controller.move_to_bottom(entries)
      when 'R'  # R - refresh
        @nav_controller.refresh
      when 'r'  # r - rename file/directory
        @file_op_controller.rename_current_file(current_entry)
      when 'd'  # d - delete file/directory with confirmation
        @file_op_controller.delete_current_file_with_confirmation(current_entry, method(:get_active_entries))
      when 'o'  # o
        @nav_controller.open_current_file(current_entry)
      when 'e'  # e - open directory in file explorer
        @nav_controller.open_directory_in_explorer
      when 'f'  # f - filter files
        if @filter_manager.filter_active?
          # フィルタが設定されている場合は再編集モードに入る
          @filter_manager.restart_filter_mode(@directory_listing.list_entries)
        else
          # 新規フィルターモード開始
          @nav_controller.start_filter_mode
        end
      when ' ' # Space - toggle selection
        toggle_selection
      when "\e" # ESC
        if @filter_manager.filter_active?
          # フィルタが設定されている場合はクリア
          @nav_controller.clear_filter_mode
          true
        else
          false
        end
      when 'q'  # q
        exit_request
      when '/'  # /
        fzf_search
      when 's'  # s - file name search with fzf
        fzf_search
      when 'F'  # F - file content search with rga
        rga_search
      when 'a'  # a
        @file_op_controller.create_file
      when 'A'  # A
        @file_op_controller.create_directory
      when 'm'  # m - move selected files to current directory
        @file_op_controller.move_selected_to_current
      when 'c'  # c - copy selected files to current directory
        @file_op_controller.copy_selected_to_current
      when 'x'  # x - delete selected files
        @file_op_controller.delete_selected_files
      when 'J'  # J - job mode
        enter_job_mode
      when 'b'  # b - add bookmark
        add_bookmark
      when 'B'  # B - bookmark menu (with script paths)
        show_bookmark_menu
      when 'z'  # z - zoxide history navigation
        show_zoxide_menu
      when '0'  # 0 - go to start directory
        goto_start_directory
      when '1', '2', '3', '4', '5', '6', '7', '8', '9'  # number keys - go to bookmark
        goto_bookmark(key.to_i)
      when '?'  # ? - enter help mode
        enter_help_mode
      when 'L'  # L - enter log viewer mode
        enter_log_viewer_mode
      when ':'  # : - command mode
        activate_command_mode
      else
        false # #{ConfigLoader.message('keybind.invalid_key')}
      end
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

    def create_file
      current_path = @directory_listing&.current_path || Dir.pwd

      # ダイアログレンダラーを使用して入力ダイアログを表示
      title = "Create File"
      prompt = "Enter file name:"
      filename = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[32m",    # Green
        title_color: "\e[1;32m",   # Bold green
        content_color: "\e[37m"    # White
      })

      return false if filename.nil? || filename.empty?

      # FileOperationsを使用してファイルを作成
      result = @file_operations.create_file(current_path, filename)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # 作成したファイルを選択状態にする
        entries = @directory_listing.list_entries
        new_file_index = entries.find_index { |entry| entry[:name] == filename }
        @nav_controller.select_index(new_file_index) if new_file_index
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def create_directory
      current_path = @directory_listing&.current_path || Dir.pwd

      # ダイアログレンダラーを使用して入力ダイアログを表示
      title = "Create Directory"
      prompt = "Enter directory name:"
      dirname = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[34m",    # Blue
        title_color: "\e[1;34m",   # Bold blue
        content_color: "\e[37m"    # White
      })

      return false if dirname.nil? || dirname.empty?

      # FileOperationsを使用してディレクトリを作成
      result = @file_operations.create_directory(current_path, dirname)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # 作成したディレクトリを選択状態にする
        entries = @directory_listing.list_entries
        new_dir_index = entries.find_index { |entry| entry[:name] == dirname }
        @nav_controller.select_index(new_dir_index) if new_dir_index
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def rename_current_file
      current_item = current_entry()
      return false unless current_item

      current_name = current_item[:name]
      current_path = @directory_listing&.current_path || Dir.pwd

      # ダイアログレンダラーを使用して入力ダイアログを表示
      title = "Rename: #{current_name}"
      prompt = "Enter new name:"
      new_name = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[33m",    # Yellow
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })

      return false if new_name.nil? || new_name.empty?

      # FileOperationsを使用してリネーム
      result = @file_operations.rename(current_path, current_name, new_name)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # リネームしたファイルを選択状態にする
        entries = @directory_listing.list_entries
        new_index = entries.find_index { |entry| entry[:name] == new_name }
        @nav_controller.select_index(new_index) if new_index
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def delete_current_file_with_confirmation
      current_path = @directory_listing&.current_path || Dir.pwd

      # Check if there are selected items
      if !@selection_manager.empty?
        # Delete multiple selected items
        source_path = @selection_manager.source_directory || current_path

        if show_delete_confirmation(@selection_manager.count, source_path)
          result = @file_operations.delete(@selection_manager.selected_items, source_path)
          @selection_manager.clear
          @directory_listing.refresh if @directory_listing
          @terminal_ui&.refresh_display
          return result.success
        else
          return false
        end
      end

      # Single file deletion (current item)
      current_item = current_entry()
      return false unless current_item

      current_name = current_item[:name]
      is_directory = current_item[:type] == :directory

      # 確認ダイアログを表示
      type_text = is_directory ? 'directory' : 'file'
      content_lines = [
        '',
        "Delete this #{type_text}?",
        "  #{current_name}",
        '',
        '  [Y]es - Delete',
        '  [N]o  - Cancel',
        ''
      ]

      title = 'Confirm Delete'
      width = [50, current_name.length + 10].max
      height = content_lines.length + 4

      # 確認を待つ
      confirmed = false
      show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: "\e[31m",    # Red (warning)
        title_color: "\e[1;31m",   # Bold red
        content_color: "\e[37m"    # White
      }) do
        loop do
          input = STDIN.getch.downcase

          case input
          when 'y'
            confirmed = true
            break
          when 'n', "\e" # n or ESC
            confirmed = false
            break
          end
        end
        nil
      end

      return false unless confirmed

      # FileOperationsを使用して削除
      result = @file_operations.delete([current_name], current_path)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # カーソル位置を調整
        entries = @directory_listing.list_entries
        idx = @nav_controller.current_index
        @nav_controller.select_index([[idx, 0].max, [entries.length - 1, 0].max].min)
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def toggle_selection
      entry = current_entry
      return false unless entry

      current_path = @directory_listing&.current_path || Dir.pwd
      @selection_manager.toggle_selection(entry, current_path)
      true
    end


    def move_selected_to_current
      return false if @selection_manager.empty?

      current_path = @directory_listing&.current_path || Dir.pwd
      source_path = @selection_manager.source_directory || current_path

      # Move selected files/directories from source directory to current directory
      # This allows moving files even after navigating to a different directory
      if show_move_confirmation(@selection_manager.count, source_path, current_path)
        result = @file_operations.move(@selection_manager.selected_items, source_path, current_path)

        # Clear selection and refresh
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    def copy_selected_to_current
      return false if @selection_manager.empty?

      current_path = @directory_listing&.current_path || Dir.pwd
      source_path = @selection_manager.source_directory || current_path

      # Copy selected files/directories from source directory to current directory
      # This allows copying files even after navigating to a different directory
      if show_copy_confirmation(@selection_manager.count, source_path, current_path)
        result = @file_operations.copy(@selection_manager.selected_items, source_path, current_path)

        # Clear selection and refresh
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    def show_confirmation_dialog(operation, count)
      print "\n#{operation} #{count} item(s)? (y/n): "
      response = STDIN.gets.chomp.downcase
      %w[y yes].include?(response)
    end

    # Helper method to show operation result
    def show_operation_result(result)
      if result.errors.any?
        puts "\n#{result.message}"
        result.errors.each { |error| puts "  - #{error}" }
      else
        puts "\n#{result.message}"
      end
      print 'Press any key to continue...'
      STDIN.getch
    end

    def delete_selected_files
      return false if @selection_manager.empty?

      if show_delete_confirmation(@selection_manager.count)
        current_path = @directory_listing&.current_path || Dir.pwd
        result = @file_operations.delete(@selection_manager.selected_items, current_path)

        # Show detailed delete result
        show_deletion_result(result.count, @selection_manager.count, result.errors)
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    def show_move_confirmation(count, source_path, dest_path)
      show_floating_move_confirmation(count, source_path, dest_path)
    end

    def show_copy_confirmation(count, source_path, dest_path)
      show_floating_copy_confirmation(count, source_path, dest_path)
    end

    def show_delete_confirmation(count, source_path)
      show_floating_delete_confirmation(count, source_path)
    end

    def show_floating_delete_confirmation(count, source_path)
      # コンテンツの準備
      title = 'Delete Confirmation'

      # パスの短縮表示
      source_display = shorten_path(source_path, 35)

      content_lines = [
        '',
        "Delete #{count} item(s)?",
        '',
        "From: #{source_display}",
        '',
        '  [Y]es - Delete',
        '  [N]o  - Cancel',
        ''
      ]

      # ダイアログのサイズ設定（コンテンツに合わせて調整）
      dialog_width = CONFIRMATION_DIALOG_WIDTH
      # タイトルあり: 上枠1 + タイトル1 + 区切り1 + コンテンツ + 下枠1
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # フラッシュしてユーザーの注意を引く
      print "\a" # ベル音

      # キー入力待機
      confirmed = false
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[31m", # 赤色（警告）
        title_color: "\e[1;31m",   # 太字赤色
        content_color: "\e[37m"    # 白色
      }) do
        loop do
          input = STDIN.getch.downcase

          case input
          when 'y'
            confirmed = true
            break
          when 'n', "\e", "\x03", 'q' # n, ESC, Ctrl+C, q
            confirmed = false
            break
          end
          # 無効なキー入力の場合は再度ループ
        end
        nil
      end

      confirmed
    end

    def show_floating_move_confirmation(count, source_path, dest_path)
      # コンテンツの準備
      title = 'Move Confirmation'

      # パスの短縮表示
      source_display = shorten_path(source_path, 35)
      dest_display = shorten_path(dest_path, 35)

      content_lines = [
        '',
        "Move #{count} item(s)?",
        '',
        "From: #{source_display}",
        "To:   #{dest_display}",
        '',
        '  [Y]es - Move',
        '  [N]o  - Cancel',
        ''
      ]

      # ダイアログのサイズ設定
      dialog_width = CONFIRMATION_DIALOG_WIDTH
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # キー入力待機
      confirmed = false
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[34m", # 青色（情報）
        title_color: "\e[1;34m",   # 太字青色
        content_color: "\e[37m"    # 白色
      }) do
        loop do
          input = STDIN.getch.downcase

          case input
          when 'y'
            confirmed = true
            break
          when 'n', "\e", "\x03", 'q' # n, ESC, Ctrl+C, q
            confirmed = false
            break
          end
          # 無効なキー入力の場合は再度ループ
        end
        nil
      end

      confirmed
    end

    def show_floating_copy_confirmation(count, source_path, dest_path)
      # コンテンツの準備
      title = 'Copy Confirmation'

      # パスの短縮表示
      source_display = shorten_path(source_path, 35)
      dest_display = shorten_path(dest_path, 35)

      content_lines = [
        '',
        "Copy #{count} item(s)?",
        '',
        "From: #{source_display}",
        "To:   #{dest_display}",
        '',
        '  [Y]es - Copy',
        '  [N]o  - Cancel',
        ''
      ]

      # ダイアログのサイズ設定
      dialog_width = CONFIRMATION_DIALOG_WIDTH
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # キー入力待機
      confirmed = false
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[32m", # 緑色（安全な操作）
        title_color: "\e[1;32m",   # 太字緑色
        content_color: "\e[37m"    # 白色
      }) do
        loop do
          input = STDIN.getch.downcase

          case input
          when 'y'
            confirmed = true
            break
          when 'n', "\e", "\x03", 'q' # n, ESC, Ctrl+C, q
            confirmed = false
            break
          end
          # 無効なキー入力の場合は再度ループ
        end
        nil
      end

      confirmed
    end

    def show_exit_confirmation
      # コンテンツの準備
      title = 'Exit Confirmation'

      content_lines = [
        '',
        'Are you sure you want to exit?',
        '',
        '  [Y]es - Exit',
        '  [N]o  - Cancel',
        ''
      ]

      # ダイアログのサイズ設定
      dialog_width = CONFIRMATION_DIALOG_WIDTH
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # キー入力待機
      confirmed = false
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[33m",    # 黄色（注意）
        title_color: "\e[1;33m",   # 太字黄色
        content_color: "\e[37m"    # 白色
      }) do
        loop do
          input = STDIN.getch.downcase

          case input
          when 'y'
            confirmed = true
            break
          when 'n', "\e", "\x03" # n, ESC, Ctrl+C
            confirmed = false
            break
          end
          # 無効なキー入力の場合は再度ループ
        end
        nil
      end

      confirmed
    end

    # パスを指定した長さに短縮
    def shorten_path(path, max_length)
      return path if path.length <= max_length
      "...#{path[-(max_length - 3)..-1]}"
    end

    def perform_delete_operation(items)
      Logger.debug('Starting delete operation', context: { items: items, count: items.length })

      success_count = 0
      error_messages = []
      current_path = @directory_listing&.current_path || Dir.pwd

      items.each do |item_name|
        item_path = File.join(current_path, item_name)
        Logger.debug("Processing deletion", context: { item: item_name, path: item_path })

        begin
          # ファイル/ディレクトリの存在確認
          unless File.exist?(item_path)
            error_messages << "#{item_name}: File not found"
            Logger.warn("File not found for deletion", context: { item: item_name })
            next
          end

          is_directory = File.directory?(item_path)
          Logger.debug("Item type determined", context: { item: item_name, type: is_directory ? 'Directory' : 'File' })

          if is_directory
            FileUtils.rm_rf(item_path)
          else
            FileUtils.rm(item_path)
          end

          # 削除が実際に成功したかを確認
          sleep(FILESYSTEM_SYNC_DELAY) # wait for filesystem sync
          still_exists = File.exist?(item_path)

          if still_exists
            error_messages << "#{item_name}: Deletion failed"
            Logger.error("Deletion failed", context: { item: item_name, still_exists: true })
          else
            success_count += 1
            Logger.debug("Deletion successful", context: { item: item_name })
          end
        rescue StandardError => e
          error_messages << "#{item_name}: #{e.message}"
          Logger.error("Exception during deletion", exception: e, context: { item: item_name })
        end
      end

      Logger.debug('Delete operation completed', context: {
        success_count: success_count,
        total_count: items.length,
        error_count: error_messages.length,
        has_errors: !error_messages.empty?
      })

      # 削除結果をフローティングウィンドウで表示
      show_deletion_result(success_count, items.length, error_messages)

      # 削除完了後の処理
      @selection_manager.clear
      @directory_listing.refresh if @directory_listing

      true
    end

    def show_deletion_result(success_count, total_count, error_messages = [])
      Logger.debug('Showing deletion result dialog', context: {
        success_count: success_count,
        total_count: total_count,
        error_messages: error_messages
      })

      # エラーメッセージがある場合はダイアログサイズを拡大
      has_errors = !error_messages.empty?
      dialog_width = has_errors ? 50 : 35
      dialog_height = has_errors ? [8 + error_messages.length, 15].min : 6

      # 成功・失敗に応じた色設定
      if success_count == total_count && !has_errors
        border_color = "\e[32m"   # 緑色（成功）
        title_color = "\e[1;32m"  # 太字緑色
        title = 'Delete Complete'
        message = "Deleted #{success_count} item(s)"
      else
        border_color = "\e[33m"   # 黄色（警告）
        title_color = "\e[1;33m"  # 太字黄色
        title = 'Delete Result'
        if success_count == total_count && has_errors
          # 全て削除成功したがエラーメッセージがある場合（本来ここに入らないはず）
          message = "#{success_count} deleted (with error info)"
        else
          failed_count = total_count - success_count
          message = "#{success_count} deleted, #{failed_count} failed"
        end
      end

      # コンテンツの準備
      content_lines = ['', message]

      # エラーメッセージがある場合は追加
      if has_errors
        content_lines << ''
        content_lines << 'Error details:'
        error_messages.each { |error| content_lines << "  #{error}" }
      end

      content_lines << ''
      content_lines << 'Press any key to continue...'

      # オーバーレイダイアログを表示
      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      })
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
