# frozen_string_literal: true

require_relative 'dialog_support'
require_relative 'text_utils'
require_relative 'bookmark'
require_relative 'bookmark_storage'
require_relative 'config_loader'

module Rufio
  # Manages bookmark operations with interactive UI
  class BookmarkManager
    include DialogSupport

    def initialize(bookmark = nil, dialog_renderer = nil)
      @bookmark = bookmark || create_default_bookmark
      @dialog_renderer = dialog_renderer
      @terminal_ui = nil
    end

    # terminal_ui を設定
    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    private

    def create_default_bookmark
      # 必要に応じて古いconfig.ymlからマイグレーション
      ConfigLoader.migrate_bookmarks_if_needed

      # 新形式のYAMLストレージを使用（bookmarks.yml）
      storage = ConfigLoader.bookmark_storage
      Bookmark.new(ConfigLoader::BOOKMARKS_YML, storage: storage)
    end

    public

    # List all bookmarks interactively
    # @return [Hash, nil] Selected bookmark path or nil
    def list_interactive
      select_bookmark_from_dialog(
        title: 'Bookmarks',
        header: 'Select a bookmark:',
        border_color: "\e[34m",
        title_color: "\e[1;34m"
      )
    end

    # Rename a bookmark interactively
    # @return [Boolean] Success status
    def rename_interactive
      selected = select_bookmark_from_dialog(
        title: 'Rename Bookmark',
        header: 'Select bookmark to rename:',
        border_color: "\e[33m",
        title_color: "\e[1;33m"
      )
      return false unless selected

      old_name = selected[:name]
      new_name = @dialog_renderer.show_input_dialog("Rename: #{old_name}", "Enter new name:", {
        border_color: "\e[33m",    # Yellow
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })

      return false if new_name.nil? || new_name.empty?

      @bookmark.rename(old_name, new_name)
    end

    # Remove a bookmark interactively
    # @return [Boolean] Success status
    def remove_interactive
      selected = select_bookmark_from_dialog(
        title: 'Delete Bookmark',
        header: 'Select bookmark to delete:',
        border_color: "\e[31m",
        title_color: "\e[1;31m"
      )
      return false unless selected

      if show_remove_confirmation(selected[:name])
        @bookmark.remove(selected[:name])
      else
        false
      end
    end

    # Get bookmark by number
    # @param number [Integer] Bookmark number (1-9)
    # @return [Hash, nil] Bookmark hash with :path and :name
    def find_by_number(number)
      @bookmark.find_by_number(number)
    end

    # Validate bookmark path exists
    # @param bookmark [Hash] Bookmark hash
    # @return [Boolean]
    def path_exists?(bookmark)
      return false unless bookmark

      Dir.exist?(bookmark[:path])
    end

    # Get all bookmarks
    # @return [Array<Hash>]
    def list
      @bookmark.list
    end

    # Add bookmark
    # @param path [String] Path to bookmark
    # @param name [String] Bookmark name
    # @return [Boolean] Success status
    def add(path, name)
      @bookmark.add(path, name)
    end

    # Remove bookmark
    # @param name [String] Bookmark name
    # @return [Boolean] Success status
    def remove(name)
      @bookmark.remove(name)
    end

    # Get left pane display data for bookmarks
    # @return [Array<String>] Formatted bookmark list
    def get_left_pane_data
      bookmarks = @bookmark.list
      bookmarks.map.with_index(1) do |bookmark, index|
        "#{index}. #{bookmark[:name]}"
      end
    end

    # Get right pane display data for a selected bookmark
    # @param number [Integer] Bookmark number (1-based)
    # @return [String] Bookmark details
    def get_right_pane_data(number)
      bookmark = @bookmark.find_by_number(number)
      return '' unless bookmark

      "Name: #{bookmark[:name]}\nPath: #{bookmark[:path]}"
    end

    # Get bookmark count
    # @return [Integer] Number of bookmarks
    def count
      @bookmark.list.length
    end

    private

    def select_bookmark_from_dialog(title:, header:, border_color:, title_color:)
      bookmarks = @bookmark.list

      if bookmarks.empty?
        show_result_dialog('No Bookmarks', 'No bookmarks found', :error)
        return nil
      end

      return nil unless @dialog_renderer

      content_lines = ['', header, '']
      bookmarks.each_with_index do |bookmark, index|
        display_path = TextUtils.shorten_path_from_end(bookmark[:path], 35, tilde: true)
        content_lines << "  #{index + 1}. #{bookmark[:name]}"
        content_lines << "      #{display_path}"
      end
      content_lines << ''
      content_lines << 'Press 1-9 to select, ESC to cancel'

      width = 60
      height = [content_lines.length + 4, 20].min

      selected_bookmark = nil
      show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      }) do
        loop do
          input = KeyInput.getch.downcase

          if input >= '1' && input <= '9'
            number = input.to_i
            if number > 0 && number <= bookmarks.length
              selected_bookmark = bookmarks[number - 1]
              break
            end
          elsif input == "\e"
            break
          end
        end
        nil
      end

      selected_bookmark
    end

    # Show result dialog with success or error styling
    # @param title [String] Dialog title
    # @param message [String] Result message
    # @param type [Symbol] :success or :error
    def show_result_dialog(title, message, type)
      return unless @dialog_renderer

      # Set colors based on result type
      if type == :success
        border_color = "\e[32m"    # Green
        title_color = "\e[1;32m"   # Bold green
      else
        border_color = "\e[31m"    # Red
        title_color = "\e[1;31m"   # Bold red
      end

      content_lines = [
        '',
        message,
        '',
        'Press any key to continue...'
      ]

      width = 50
      height = 6

      # オーバーレイダイアログを表示
      show_overlay_dialog(title, content_lines, {
        width: width,
        height: height,
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      })
    end

    # Show confirmation dialog for bookmark removal
    # @param bookmark_name [String] Name of bookmark to remove
    # @return [Boolean] true if confirmed, false if cancelled
    def show_remove_confirmation(bookmark_name)
      return false unless @dialog_renderer

      content_lines = [
        '',
        "Delete bookmark '#{bookmark_name}'?",
        '',
        '  [Y]es - Delete',
        '  [N]o  - Cancel',
        ''
      ]

      confirm_dialog('Confirm Delete', content_lines, {
        width: 50,
        height: content_lines.length + 4,
        border_color: "\e[33m",    # Yellow (warning)
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })
    end
  end
end
