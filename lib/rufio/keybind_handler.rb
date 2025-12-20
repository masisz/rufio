# frozen_string_literal: true

require 'shellwords'
require_relative 'file_opener'
require_relative 'filter_manager'
require_relative 'selection_manager'
require_relative 'file_operations'
require_relative 'bookmark_manager'
require_relative 'zoxide_integration'
require_relative 'dialog_renderer'
require_relative 'logger'

module Rufio
  class KeybindHandler
    attr_reader :current_index

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
      @current_index = 0
      @directory_listing = nil
      @terminal_ui = nil
      @file_opener = FileOpener.new

      # New manager classes
      @filter_manager = FilterManager.new
      @selection_manager = SelectionManager.new
      @file_operations = FileOperations.new
      @dialog_renderer = DialogRenderer.new
      @bookmark_manager = BookmarkManager.new(Bookmark.new, @dialog_renderer)
      @zoxide_integration = ZoxideIntegration.new(@dialog_renderer)

      # Legacy fields for backward compatibility
      @base_directory = nil
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
      @current_index = 0
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_base_directory(base_dir)
      @base_directory = File.expand_path(base_dir)
    end

    def selected_items
      @selection_manager.selected_items
    end

    def is_selected?(entry_name)
      @selection_manager.selected?(entry_name)
    end

    def handle_key(key)
      return false unless @directory_listing

      # フィルターモード中は他のキーバインドを無効化
      return handle_filter_input(key) if @filter_manager.filter_mode

      case key
      when 'j'
        move_down
      when 'k'
        move_up
      when 'h'
        navigate_parent
      when 'l', "\r", "\n" # l, Enter
        navigate_enter
      when 'g'
        move_to_top
      when 'G'
        move_to_bottom
      when 'r'
        refresh
      when 'o'  # o
        open_current_file
      when 'e'  # e - open directory in file explorer
        open_directory_in_explorer
      when 'f'  # f - filter files
        if @filter_manager.filter_active?
          # フィルタが設定されている場合は再編集モードに入る
          @filter_manager.restart_filter_mode(@directory_listing.list_entries)
        else
          # 新規フィルターモード開始
          start_filter_mode
        end
      when ' ' # Space - toggle selection
        toggle_selection
      when "\e" # ESC
        if @filter_manager.filter_active?
          # フィルタが設定されている場合はクリア
          clear_filter_mode
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
        create_file
      when 'A'  # A
        create_directory
      when 'm'  # m - move selected files to base directory
        move_selected_to_base
      when 'p'  # p - copy selected files to base directory
        copy_selected_to_base
      when 'x'  # x - delete selected files
        delete_selected_files
      when 'b'  # b - bookmark operations
        show_bookmark_menu
      when 'z'  # z - zoxide history navigation
        show_zoxide_menu
      when '1', '2', '3', '4', '5', '6', '7', '8', '9'  # number keys - go to bookmark
        goto_bookmark(key.to_i)
      when ':'  # : - command mode
        activate_command_mode
      else
        false # #{ConfigLoader.message('keybind.invalid_key')}
      end
    end

    def select_index(index)
      entries = get_active_entries
      @current_index = [[index, 0].max, entries.length - 1].min
    end

    def current_entry
      entries = get_active_entries
      entries[@current_index]
    end

    def filter_active?
      @filter_manager.filter_active?
    end

    def get_active_entries
      if @filter_manager.filter_active?
        @filter_manager.filtered_entries
      else
        @directory_listing&.list_entries || []
      end
    end

    private

    def move_down
      entries = get_active_entries
      @current_index = [@current_index + 1, entries.length - 1].min
      true
    end

    def move_up
      @current_index = [@current_index - 1, 0].max
      true
    end

    def move_to_top
      @current_index = 0
      true
    end

    def move_to_bottom
      entries = get_active_entries
      @current_index = entries.length - 1
      true
    end

    def navigate_enter
      entry = current_entry
      return false unless entry

      if entry[:type] == 'directory'
        result = @directory_listing.navigate_to(entry[:name])
        if result
          @current_index = 0  # select first entry in new directory
          clear_filter_mode   # ディレクトリ移動時にフィルタをリセット
        end
        result
      else
        # do nothing for files (file opening feature may be added in the future)
        false
      end
    end

    def navigate_parent
      result = @directory_listing.navigate_to_parent
      if result
        @current_index = 0  # select first entry in parent directory
        clear_filter_mode   # ディレクトリ移動時にフィルタをリセット
      end
      result
    end

    def refresh
      # ウィンドウサイズを更新して画面を再描画
      @terminal_ui&.refresh_display

      @directory_listing.refresh
      if @filter_manager.filter_active?
        # Re-apply filter with new directory contents
        @filter_manager.update_entries(@directory_listing.list_entries)
      else
        # adjust index to stay within bounds after refresh
        entries = @directory_listing.list_entries
        @current_index = [@current_index, entries.length - 1].min if entries.any?
      end
      true
    end

    def open_current_file
      entry = current_entry
      return false unless entry

      if entry[:type] == 'file'
        @file_opener.open_file(entry[:path])
        true
      else
        false
      end
    end

    def open_directory_in_explorer
      current_path = @directory_listing&.current_path || Dir.pwd
      @file_opener.open_directory_in_explorer(current_path)
      true
    end

    def exit_request
      true # request exit
    end

    def fzf_search
      return false unless fzf_available?

      current_path = @directory_listing&.current_path || Dir.pwd

      # fzfでファイル検索を実行
      # Dir.chdirを使用してディレクトリ移動を安全に行う
      selected_file = nil
      Dir.chdir(current_path) do
        selected_file = `find . -type f | fzf --preview 'cat {}'`.strip
      end

      # ファイルが選択された場合、そのファイルを開く
      if !selected_file.empty?
        full_path = File.expand_path(selected_file, current_path)
        @file_opener.open_file(full_path) if File.exist?(full_path)
      end

      true
    end

    def fzf_available?
      system('which fzf > /dev/null 2>&1')
    end

    def rga_search
      return false unless rga_available?

      current_path = @directory_listing&.current_path || Dir.pwd

      # input search keyword
      print ConfigLoader.message('keybind.search_text')
      search_query = STDIN.gets.chomp
      return false if search_query.empty?

      # execute rga file content search
      # Dir.chdirを使用してディレクトリ移動を安全に行う
      search_results = nil
      Dir.chdir(current_path) do
        # Shellwords.escapeで検索クエリをエスケープ
        escaped_query = Shellwords.escape(search_query)
        search_results = `rga --line-number --with-filename #{escaped_query} . 2>/dev/null`
      end

      if search_results.empty?
        puts "\n#{ConfigLoader.message('keybind.no_matches')}"
        print ConfigLoader.message('keybind.press_any_key')
        STDIN.getch
        return true
      end

      # pass results to fzf for selection
      selected_result = IO.popen('fzf', 'r+') do |fzf|
        fzf.write(search_results)
        fzf.close_write
        fzf.read.strip
      end

      # extract file path and line number from selected result
      if !selected_result.empty? && selected_result.match(/^(.+?):(\d+):/)
        file_path = ::Regexp.last_match(1)
        line_number = ::Regexp.last_match(2).to_i
        full_path = File.expand_path(file_path, current_path)

        @file_opener.open_file_with_line(full_path, line_number) if File.exist?(full_path)
      end

      true
    end

    def rga_available?
      system('which rga > /dev/null 2>&1')
    end

    def start_filter_mode
      @filter_manager.start_filter_mode(@directory_listing.list_entries)
      @current_index = 0
      true
    end

    def handle_filter_input(key)
      result = @filter_manager.handle_filter_input(key)

      case result
      when :exit_clear
        clear_filter_mode
      when :exit_keep
        exit_filter_mode_keep_filter
      when :backspace_exit
        clear_filter_mode
      when :continue
        @current_index = [@current_index, [@filter_manager.filtered_entries.length - 1, 0].max].min
      end

      true
    end

    def exit_filter_mode_keep_filter
      # フィルタを維持したまま通常モードに戻る
      @filter_manager.exit_filter_mode_keep_filter
    end

    def clear_filter_mode
      # フィルタをクリアして通常モードに戻る
      @filter_manager.clear_filter
      @current_index = 0
    end

    def exit_filter_mode
      # 既存メソッド（後方互換用）
      clear_filter_mode
    end

    def create_file
      current_path = @directory_listing&.current_path || Dir.pwd

      # カーソルを画面下部に移動して入力プロンプトを表示
      move_to_input_line
      print ConfigLoader.message('keybind.input_filename')
      STDOUT.flush

      filename = read_line_with_escape
      return false if filename.nil? || filename.empty?

      # FileOperationsを使用してファイルを作成
      result = @file_operations.create_file(current_path, filename)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # 作成したファイルを選択状態にする
        entries = @directory_listing.list_entries
        new_file_index = entries.find_index { |entry| entry[:name] == filename }
        @current_index = new_file_index if new_file_index
      end

      # 結果を表示
      puts "\n#{result.message}"
      print ConfigLoader.message('keybind.press_any_key')
      STDIN.getch
      result.success
    end

    def create_directory
      current_path = @directory_listing&.current_path || Dir.pwd

      # カーソルを画面下部に移動して入力プロンプトを表示
      move_to_input_line
      print ConfigLoader.message('keybind.input_dirname')
      STDOUT.flush

      dirname = read_line_with_escape
      return false if dirname.nil? || dirname.empty?

      # FileOperationsを使用してディレクトリを作成
      result = @file_operations.create_directory(current_path, dirname)

      # ディレクトリ表示を更新
      if result.success
        @directory_listing.refresh

        # 作成したディレクトリを選択状態にする
        entries = @directory_listing.list_entries
        new_dir_index = entries.find_index { |entry| entry[:name] == dirname }
        @current_index = new_dir_index if new_dir_index
      end

      # 結果を表示
      puts "\n#{result.message}"
      print ConfigLoader.message('keybind.press_any_key')
      STDIN.getch
      result.success
    end

    def toggle_selection
      entry = current_entry
      return false unless entry

      @selection_manager.toggle_selection(entry)
      true
    end

    def move_selected_to_base
      return false if @selection_manager.empty? || @base_directory.nil?

      if show_confirmation_dialog('Move', @selection_manager.count)
        current_path = @directory_listing&.current_path || Dir.pwd
        result = @file_operations.move(@selection_manager.selected_items, current_path, @base_directory)

        # Show result and refresh
        show_operation_result(result)
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    def copy_selected_to_base
      return false if @selection_manager.empty? || @base_directory.nil?

      if show_confirmation_dialog('Copy', @selection_manager.count)
        current_path = @directory_listing&.current_path || Dir.pwd
        result = @file_operations.copy(@selection_manager.selected_items, current_path, @base_directory)

        # Show result and refresh
        show_operation_result(result)
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

    def show_delete_confirmation(count)
      show_floating_delete_confirmation(count)
    end

    def show_floating_delete_confirmation(count)
      # コンテンツの準備
      title = 'Delete Confirmation'
      content_lines = [
        '',
        "Delete #{count} item(s)?",
        '',
        '  [Y]es - Delete',
        '  [N]o  - Cancel',
        ''
      ]

      # ダイアログのサイズ設定（コンテンツに合わせて調整）
      dialog_width = CONFIRMATION_DIALOG_WIDTH
      # タイトルあり: 上枠1 + タイトル1 + 区切り1 + コンテンツ + 下枠1
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      # ダイアログの位置を中央に設定
      x, y = @dialog_renderer.calculate_center(dialog_width, dialog_height)

      # ダイアログの描画
      @dialog_renderer.draw_floating_window(x, y, dialog_width, dialog_height, title, content_lines, {
                             border_color: "\e[31m", # 赤色（警告）
                             title_color: "\e[1;31m",   # 太字赤色
                             content_color: "\e[37m"    # 白色
                           })

      # フラッシュしてユーザーの注意を引く
      print "\a" # ベル音

      # キー入力待機
      loop do
        input = STDIN.getch.downcase

        case input
        when 'y'
          # ダイアログをクリア
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          @terminal_ui&.refresh_display # 画面を再描画
          return true
        when 'n', "\e", "\x03" # n, ESC, Ctrl+C
          # ダイアログをクリア
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          @terminal_ui&.refresh_display # 画面を再描画
          return false
        when 'q' # qキーでもキャンセル
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          @terminal_ui&.refresh_display
          return false
        end
        # 無効なキー入力の場合は再度ループ
      end
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

      # ダイアログの位置を中央に設定
      x, y = @dialog_renderer.calculate_center(dialog_width, dialog_height)

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

      # ダイアログの描画
      @dialog_renderer.draw_floating_window(x, y, dialog_width, dialog_height, title, content_lines, {
                             border_color: border_color,
                             title_color: title_color,
                             content_color: "\e[37m"
                           })

      # キー入力待機
      STDIN.getch

      # ダイアログをクリア
      @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
      @terminal_ui&.refresh_display
    end


    # ブックマーク機能
    def show_bookmark_menu
      current_path = @directory_listing&.current_path || Dir.pwd
      result = @bookmark_manager.show_menu(current_path)

      @terminal_ui&.refresh_display

      case result[:action]
      when :add
        success = @bookmark_manager.add_interactive(result[:path])
        wait_for_keypress
        success
      when :list
        @bookmark_manager.list_interactive
        wait_for_keypress
        true
      when :remove
        @bookmark_manager.remove_interactive
        wait_for_keypress
        true
      when :navigate
        goto_bookmark(result[:number])
      else
        false
      end
    end

    def goto_bookmark(number)
      bookmark = @bookmark_manager.find_by_number(number)

      return show_error_and_wait('bookmark.not_found', number) unless bookmark
      return show_error_and_wait('bookmark.path_not_exist', bookmark[:path]) unless @bookmark_manager.path_exists?(bookmark)

      # ディレクトリに移動
      if navigate_to_directory(bookmark[:path])
        puts "\n#{ConfigLoader.message('bookmark.navigated') || 'Navigated to bookmark'}: #{bookmark[:name]}"
        sleep(0.5) # 短時間表示
        true
      else
        show_error_and_wait('bookmark.navigate_failed', bookmark[:name])
      end
    end

    # ヘルパーメソッド
    def wait_for_keypress
      print ConfigLoader.message('keybind.press_any_key') || 'Press any key to continue...'
      STDIN.getch
    end

    def show_error_and_wait(message_key, value)
      puts "\n#{ConfigLoader.message(message_key) || message_key}: #{value}"
      wait_for_keypress
      false
    end

    def navigate_to_directory(path)
      result = @directory_listing.navigate_to_path(path)
      if result
        @current_index = 0
        clear_filter_mode
        true
      else
        false
      end
    end

    # zoxide 機能
    def show_zoxide_menu
      selected_path = @zoxide_integration.show_menu

      if selected_path && Dir.exist?(selected_path)
        if navigate_to_directory(selected_path)
          @zoxide_integration.add_to_history(selected_path)
          true
        else
          false
        end
      else
        @terminal_ui&.refresh_display
        false
      end
    end

    # コマンドモードを起動
    def activate_command_mode
      @terminal_ui&.activate_command_mode
      true
    end

    private

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
  end
end
