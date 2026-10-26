# frozen_string_literal: true

require_relative 'dialog_support'

require_relative 'file_operations'
require_relative 'dialog_renderer'
require_relative 'logger'

module Rufio
  # ファイル操作専用コントローラ
  # KeybindHandler からファイル作成・削除・リネーム・移動・コピー系メソッドを分離し、単一責任原則に準拠
  class FileOperationController
    include DialogSupport

    # Dialog size constants
    CONFIRMATION_DIALOG_WIDTH = 45
    DIALOG_BORDER_HEIGHT = 4
    FILESYSTEM_SYNC_DELAY = 0.01  # 10ms wait for filesystem sync

    def initialize(directory_listing, file_operations, dialog_renderer, nav_controller, selection_manager)
      @directory_listing = directory_listing
      @file_operations = file_operations
      @dialog_renderer = dialog_renderer
      @nav_controller = nav_controller
      @selection_manager = selection_manager
      @terminal_ui = nil
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
    end

    # ============================
    # ファイル作成
    # ============================

    def create_file
      prompt_and_select_entry("Create File", "Enter file name:", "\e[32m", "\e[1;32m") do |path, name|
        @file_operations.create_file(path, name)
      end
    end

    def create_directory
      prompt_and_select_entry("Create Directory", "Enter directory name:", "\e[34m", "\e[1;34m") do |path, name|
        @file_operations.create_directory(path, name)
      end
    end

    # ============================
    # リネーム
    # ============================

    # @param entry [Hash] 対象エントリ（current_entry を呼び出し元で渡す）
    def rename_current_file(entry)
      return false unless entry

      current_name = entry[:name]
      prompt_and_select_entry("Rename: #{current_name}", "Enter new name:", "\e[33m", "\e[1;33m") do |path, new_name|
        @file_operations.rename(path, current_name, new_name)
      end
    end

    # ============================
    # 削除
    # ============================

    # @param entry [Hash] 削除対象エントリ
    # @param get_active_entries [Proc] アクティブエントリ取得ラムダ
    def delete_current_file_with_confirmation(entry, get_active_entries)
      return false if entry.nil?
      return false if entry[:name] == '..'

      current_path = @directory_listing&.current_path || Dir.pwd

      # 選択アイテムがある場合はそちらを優先
      unless @selection_manager.empty?
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

      current_name = entry[:name]
      is_directory = entry[:type] == :directory

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

      confirmed = confirm_dialog('Confirm Delete', content_lines, {
        width: [50, current_name.length + 10].max,
        height: content_lines.length + 4,
        border_color: "\e[31m",
        title_color: "\e[1;31m",
        content_color: "\e[37m"
      })

      return false unless confirmed

      result = @file_operations.delete([current_name], current_path)

      if result.success
        @directory_listing.refresh
        entries = get_active_entries.call
        idx = @nav_controller.current_index
        @nav_controller.select_index([[idx, 0].max, [entries.length - 1, 0].max].min)
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def delete_selected_files
      return false if @selection_manager.empty?

      if show_delete_confirmation(@selection_manager.count)
        current_path = @directory_listing&.current_path || Dir.pwd
        result = @file_operations.delete(@selection_manager.selected_items, current_path)
        show_deletion_result(result.count, @selection_manager.count, result.errors)
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    # ============================
    # 移動・コピー
    # ============================

    def move_selected_to_current
      return false if @selection_manager.empty?

      current_path = @directory_listing&.current_path || Dir.pwd
      source_path = @selection_manager.source_directory || current_path

      if show_move_confirmation(@selection_manager.count, source_path, current_path)
        @file_operations.move(@selection_manager.selected_items, source_path, current_path)
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

      if show_copy_confirmation(@selection_manager.count, source_path, current_path)
        @file_operations.copy(@selection_manager.selected_items, source_path, current_path)
        @selection_manager.clear
        @directory_listing.refresh if @directory_listing
        true
      else
        false
      end
    end

    # ============================
    # 終了確認
    # ============================

    def show_exit_confirmation
      content_lines = [
        '',
        'Are you sure you want to exit?',
        '',
        '  [Y]es - Exit',
        '  [N]o  - Cancel',
        ''
      ]

      confirm_dialog('Exit Confirmation', content_lines, {
        width: CONFIRMATION_DIALOG_WIDTH,
        height: DIALOG_BORDER_HEIGHT + content_lines.length,
        border_color: "\e[33m",
        title_color: "\e[1;33m",
        content_color: "\e[37m"
      }, cancel_on_quit: false)
    end

    private

    def prompt_and_select_entry(title, prompt, border_color, title_color)
      current_path = @directory_listing&.current_path || Dir.pwd

      name = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      })

      return false if name.nil? || name.empty?

      result = yield(current_path, name)

      if result.success
        @directory_listing.refresh
        entries = @directory_listing.list_entries
        new_index = entries.find_index { |e| e[:name] == name }
        @nav_controller.select_index(new_index) if new_index
      end

      @terminal_ui&.refresh_display
      result.success
    end

    def show_delete_confirmation(count, source_path = nil)
      title = 'Delete Confirmation'
      source_display = source_path ? shorten_path(source_path, 35) : ''

      content_lines = [
        '',
        "Delete #{count} item(s)?",
        '',
      ]
      content_lines += ["From: #{source_display}", ''] if source_path
      content_lines += ['  [Y]es - Delete', '  [N]o  - Cancel', '']

      dialog_width = CONFIRMATION_DIALOG_WIDTH
      dialog_height = DIALOG_BORDER_HEIGHT + content_lines.length

      print "\a"

      confirm_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: "\e[31m",
        title_color: "\e[1;31m",
        content_color: "\e[37m"
      })
    end

    def show_move_confirmation(count, source_path, dest_path)
      show_transfer_confirmation('Move', count, source_path, dest_path, '34')
    end

    def show_copy_confirmation(count, source_path, dest_path)
      show_transfer_confirmation('Copy', count, source_path, dest_path, '32')
    end

    def show_transfer_confirmation(action, count, source_path, dest_path, color)
      content_lines = [
        '', "#{action} #{count} item(s)?", '',
        "From: #{shorten_path(source_path, 35)}",
        "To:   #{shorten_path(dest_path, 35)}", '',
        "  [Y]es - #{action}", '  [N]o  - Cancel', ''
      ]
      confirm_dialog("#{action} Confirmation", content_lines, {
        width: CONFIRMATION_DIALOG_WIDTH,
        height: DIALOG_BORDER_HEIGHT + content_lines.length,
        border_color: "\e[#{color}m",
        title_color: "\e[1;#{color}m",
        content_color: "\e[37m"
      })
    end

    def show_deletion_result(success_count, total_count, error_messages = [])
      has_errors = !error_messages.empty?
      dialog_width = has_errors ? 50 : 35
      dialog_height = has_errors ? [8 + error_messages.length, 15].min : 6

      if success_count == total_count && !has_errors
        border_color = "\e[32m"
        title_color = "\e[1;32m"
        title = 'Delete Complete'
        message = "Deleted #{success_count} item(s)"
      else
        border_color = "\e[33m"
        title_color = "\e[1;33m"
        title = 'Delete Result'
        failed_count = total_count - success_count
        message = "#{success_count} deleted, #{failed_count} failed"
      end

      content_lines = ['', message]

      if has_errors
        content_lines << ''
        content_lines << 'Error details:'
        error_messages.each { |error| content_lines << "  #{error}" }
      end

      content_lines << ''

      show_overlay_dialog(title, content_lines, {
        width: dialog_width,
        height: dialog_height,
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      }) do
        KeyInput.getch
        nil
      end
    end

    def shorten_path(path, max_length)
      TextUtils.shorten_path_from_end(path, max_length)
    end
  end
end
