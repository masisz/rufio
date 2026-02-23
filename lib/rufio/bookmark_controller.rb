# frozen_string_literal: true

module Rufio
  # ブックマーク・zoxide・スクリプトパス専用コントローラ
  # KeybindHandler からブックマーク系・zoxide・スクリプトパス系メソッドを分離し、単一責任原則に準拠
  class BookmarkController
    def initialize(directory_listing, bookmark_manager, dialog_renderer, nav_controller,
                   script_path_manager, notification_manager, zoxide_integration)
      @directory_listing = directory_listing
      @bookmark_manager = bookmark_manager
      @dialog_renderer = dialog_renderer
      @nav_controller = nav_controller
      @script_path_manager = script_path_manager
      @notification_manager = notification_manager
      @zoxide_integration = zoxide_integration
      @terminal_ui = nil
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
    end

    # ============================
    # ブックマーク操作
    # ============================

    def add_bookmark
      current_path = @directory_listing&.current_path || Dir.pwd

      bookmarks = @bookmark_manager.list
      existing = bookmarks.find { |b| b[:path] == current_path }

      if existing
        content_lines = [
          '',
          'This directory is already bookmarked',
          "Name: #{existing[:name]}",
          '',
          'Press any key to continue...'
        ]

        title = 'Bookmark Exists'
        width = 50
        height = content_lines.length + 4

        show_overlay_dialog(title, content_lines, {
          width: width,
          height: height,
          border_color: "\e[33m",
          title_color: "\e[1;33m",
          content_color: "\e[37m"
        })

        return false
      end

      dir_name = File.basename(current_path)

      title = "Add Bookmark: #{dir_name}"
      prompt = "Enter bookmark name:"
      bookmark_name = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[32m",
        title_color: "\e[1;32m",
        content_color: "\e[37m"
      })

      return false if bookmark_name.nil? || bookmark_name.empty?

      result = @bookmark_manager.add(current_path, bookmark_name)

      @terminal_ui&.refresh_display
      result
    end

    def show_bookmark_menu
      current_path = @directory_listing&.current_path || Dir.pwd

      menu_items = [
        '1. Add current dir to bookmarks',
        '2. Add to script paths',
        '3. Manage script paths',
        '4. View bookmarks'
      ]

      content_lines = [''] + menu_items + ['', '[1-4] Select | [Esc] Cancel']

      title = 'Bookmark Menu'
      width = 45
      height = content_lines.length + 4

      key = show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: "\e[36m",
        title_color: "\e[1;36m",
        content_color: "\e[37m"
      })

      case key
      when '1'
        add_bookmark
      when '2'
        add_to_script_paths
      when '3'
        show_script_paths_manager
      when '4'
        selected_bookmark = @bookmark_manager.list_interactive
        @terminal_ui&.refresh_display
        if selected_bookmark
          if @bookmark_manager.path_exists?(selected_bookmark)
            navigate_to_directory(selected_bookmark[:path])
          else
            show_error_and_wait('bookmark.path_not_exist', selected_bookmark[:path])
          end
        end
      else
        @terminal_ui&.refresh_display
      end

      true
    end

    def goto_bookmark(number)
      bookmark = @bookmark_manager.find_by_number(number)

      return false unless bookmark
      return false unless @bookmark_manager.path_exists?(bookmark)

      navigate_to_directory(bookmark[:path])
    end

    # パスを指定してブックマーク移動（テスト用）
    def goto_bookmark_by_path(path)
      navigate_to_directory(path)
    end

    def goto_start_directory
      start_dir = @directory_listing&.start_directory
      return false unless start_dir

      navigate_to_directory(start_dir)
    end

    # 次のブックマークに移動
    # @return [Integer, nil] 新しいブックマークインデックス、またはnil
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

    # ============================
    # zoxide 連携
    # ============================

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

    # ============================
    # スクリプトパス管理
    # ============================

    def add_to_script_paths
      current_path = @directory_listing&.current_path || Dir.pwd

      @script_path_manager ||= ScriptPathManager.new(Config::SCRIPT_PATHS_YML)

      if @script_path_manager.paths.include?(current_path)
        show_notification('Already in paths', current_path, :info)
      elsif @script_path_manager.add_path(current_path)
        show_notification('Added to scripts', current_path, :success)
      else
        show_notification('Failed to add', current_path, :error)
      end

      @terminal_ui&.refresh_display
      true
    end

    def show_script_paths_manager
      unless @script_path_manager
        show_notification('No script paths configured', '', :info)
        @terminal_ui&.refresh_display
        return false
      end

      paths = @script_path_manager.paths
      if paths.empty?
        show_notification('No script paths', 'Press B > 2 to add', :info)
        @terminal_ui&.refresh_display
        return false
      end

      selected_index = 0
      screen = @terminal_ui&.screen
      renderer = @terminal_ui&.renderer

      loop do
        menu_items = paths.each_with_index.map do |path, i|
          prefix = i == selected_index ? '> ' : '  '
          "#{prefix}#{i + 1}. #{truncate_path(path, 35)}"
        end

        content_lines = [''] + menu_items + ['', '[j/k] Move | [d] Delete | [Enter] Jump | [Esc] Back']

        title = 'Script Paths'
        width = 50
        height = content_lines.length + 4

        if screen && renderer
          screen.enable_overlay
          x, y = @dialog_renderer.calculate_center(width, height)
          @dialog_renderer.draw_floating_window_to_overlay(screen, x, y, width, height, title, content_lines, {
            border_color: "\e[35m",
            title_color: "\e[1;35m",
            content_color: "\e[37m"
          })
          renderer.render(screen)

          key = STDIN.getch
          screen.disable_overlay
          renderer.render(screen)
        else
          x, y = @dialog_renderer.calculate_center(width, height)
          @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
            border_color: "\e[35m",
            title_color: "\e[1;35m",
            content_color: "\e[37m"
          })

          key = STDIN.getch
          @dialog_renderer.clear_area(x, y, width, height)
        end

        case key
        when 'j'
          selected_index = [selected_index + 1, paths.length - 1].min
        when 'k'
          selected_index = [selected_index - 1, 0].max
        when 'd'
          path_to_delete = paths[selected_index]
          if confirm_delete_script_path(path_to_delete)
            @script_path_manager.remove_path(path_to_delete)
            paths = @script_path_manager.paths
            selected_index = [selected_index, paths.length - 1].min
            break if paths.empty?
          end
        when "\r", "\n"
          path = paths[selected_index]
          navigate_to_directory(path) if Dir.exist?(path)
          break
        when "\e"
          break
        end
      end

      @terminal_ui&.refresh_display
      true
    end

    def confirm_delete_script_path(path)
      content_lines = [
        '',
        'Delete this script path?',
        '',
        truncate_path(path, 40),
        '',
        '[y] Yes | [n] No'
      ]

      title = 'Confirm Delete'
      width = 50
      height = content_lines.length + 4

      key = show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: "\e[31m",
        title_color: "\e[1;31m",
        content_color: "\e[37m"
      })

      key.downcase == 'y'
    end

    # ============================
    # ナビゲーション（委譲）
    # ============================

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

    private

    def show_overlay_dialog(title, content_lines, options = {}, &block)
      use_overlay = @terminal_ui &&
                    @terminal_ui.respond_to?(:screen) &&
                    @terminal_ui.respond_to?(:renderer) &&
                    @terminal_ui.screen &&
                    @terminal_ui.renderer

      if use_overlay
        @terminal_ui.show_overlay_dialog(title, content_lines, options, &block)
      else
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

    def show_notification(title, message, type)
      return unless @notification_manager

      @notification_manager.add(title, type, duration: 3, exit_code: nil)
    end

    def show_error_and_wait(message_key, value)
      puts "\n#{ConfigLoader.message(message_key) || message_key}: #{value}"
      wait_for_keypress
      false
    end

    def wait_for_keypress
      print ConfigLoader.message('keybind.press_any_key') || 'Press any key to continue...'
      STDIN.getch
    end

    def truncate_path(path, max_length)
      return path if path.length <= max_length

      display_path = path.sub(Dir.home, '~')
      return display_path if display_path.length <= max_length

      "...#{display_path[-(max_length - 3)..]}"
    end
  end
end
