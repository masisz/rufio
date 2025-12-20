# frozen_string_literal: true

require_relative 'bookmark'
require_relative 'config_loader'

module Rufio
  # Manages bookmark operations with interactive UI
  class BookmarkManager
    def initialize(bookmark = nil, dialog_renderer = nil)
      @bookmark = bookmark || Bookmark.new
      @dialog_renderer = dialog_renderer
    end

    # Show bookmark menu and handle user selection
    # @param current_path [String] Current directory path
    # @return [Symbol, nil] Action to perform (:navigate, :add, :list, :remove, :cancel)
    def show_menu(current_path)
      return :cancel unless @dialog_renderer

      title = 'Bookmark Menu'
      content_lines = [
        '',
        '[A]dd current directory to bookmarks',
        '[L]ist bookmarks',
        '[R]emove bookmark',
        '',
        'Press 1-9 to go to bookmark directly',
        '',
        'Press any other key to cancel'
      ]

      dialog_width = 45
      dialog_height = 4 + content_lines.length
      x, y = @dialog_renderer.calculate_center(dialog_width, dialog_height)

      @dialog_renderer.draw_floating_window(x, y, dialog_width, dialog_height, title, content_lines, {
                                               border_color: "\e[34m", # Blue
                                               title_color: "\e[1;34m",   # Bold blue
                                               content_color: "\e[37m"    # White
                                             })

      # Wait for key input
      loop do
        input = STDIN.getch.downcase

        case input
        when 'a'
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return { action: :add, path: current_path }
        when 'l'
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return { action: :list }
        when 'r'
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return { action: :remove }
        when '1', '2', '3', '4', '5', '6', '7', '8', '9'
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return { action: :navigate, number: input.to_i }
        else
          # Cancel
          @dialog_renderer.clear_area(x, y, dialog_width, dialog_height)
          return { action: :cancel }
        end
      end
    end

    # Add a bookmark interactively
    # @param path [String] Path to bookmark
    # @return [Boolean] Success status
    def add_interactive(path)
      return false unless @dialog_renderer

      # Show floating input dialog
      title = 'Add Bookmark'
      prompt = 'Enter bookmark name:'
      name = @dialog_renderer.show_input_dialog(title, prompt, {
        border_color: "\e[34m",    # Blue
        title_color: "\e[1;34m",   # Bold blue
        content_color: "\e[37m"    # White
      })

      return false if name.nil? || name.empty?

      # Add bookmark (name is already trimmed in show_input_dialog)
      if @bookmark.add(path, name)
        show_result_dialog('Bookmark Added', "Added: #{name}", :success)
        true
      else
        show_result_dialog('Add Failed', 'Failed to add bookmark', :error)
        false
      end
    end

    # Remove a bookmark interactively
    # @return [Boolean] Success status
    def remove_interactive
      bookmarks = @bookmark.list

      if bookmarks.empty?
        show_result_dialog('No Bookmarks', 'No bookmarks found', :error)
        return false
      end

      return false unless @dialog_renderer

      # Build content lines for bookmark selection
      content_lines = ['', 'Select bookmark to remove:', '']
      bookmarks.each_with_index do |bookmark, index|
        # Truncate path if too long
        display_path = bookmark[:path]
        if display_path.start_with?(Dir.home)
          display_path = display_path.sub(Dir.home, '~')
        end
        if display_path.length > 35
          display_path = "...#{display_path[-32..]}"
        end
        content_lines << "  #{index + 1}. #{bookmark[:name]}"
        content_lines << "      #{display_path}"
      end
      content_lines << ''
      content_lines << 'Press 1-9 to select, ESC to cancel'

      title = 'Remove Bookmark'
      width = 60
      height = [content_lines.length + 4, 20].min
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
        border_color: "\e[31m",    # Red (warning)
        title_color: "\e[1;31m",   # Bold red
        content_color: "\e[37m"    # White
      })

      # Wait for selection
      selected_number = nil
      loop do
        input = STDIN.getch.downcase

        if input >= '1' && input <= '9'
          number = input.to_i
          if number > 0 && number <= bookmarks.length
            selected_number = number
            break
          end
        elsif input == "\e" # ESC
          @dialog_renderer.clear_area(x, y, width, height)
          return false
        end
      end

      @dialog_renderer.clear_area(x, y, width, height)

      # Confirm deletion
      bookmark_to_remove = bookmarks[selected_number - 1]
      if show_remove_confirmation(bookmark_to_remove[:name])
        if @bookmark.remove(bookmark_to_remove[:name])
          show_result_dialog('Bookmark Removed', "Removed: #{bookmark_to_remove[:name]}", :success)
          true
        else
          show_result_dialog('Remove Failed', 'Failed to remove bookmark', :error)
          false
        end
      else
        false
      end
    end

    # List all bookmarks interactively
    # @return [Hash, nil] Selected bookmark path or nil
    def list_interactive
      bookmarks = @bookmark.list

      if bookmarks.empty?
        show_result_dialog('No Bookmarks', 'No bookmarks found', :error)
        return nil
      end

      return nil unless @dialog_renderer

      # Build content lines
      content_lines = ['', 'Select a bookmark:','']
      bookmarks.each_with_index do |bookmark, index|
        # Truncate path if too long
        display_path = bookmark[:path]
        if display_path.start_with?(Dir.home)
          display_path = display_path.sub(Dir.home, '~')
        end
        if display_path.length > 35
          display_path = "...#{display_path[-32..]}"
        end
        content_lines << "  #{index + 1}. #{bookmark[:name]}"
        content_lines << "      #{display_path}"
      end
      content_lines << ''
      content_lines << 'Press 1-9 to select, ESC to cancel'

      title = 'Bookmarks'
      width = 60
      height = [content_lines.length + 4, 20].min
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
        border_color: "\e[34m",    # Blue
        title_color: "\e[1;34m",   # Bold blue
        content_color: "\e[37m"    # White
      })

      # Wait for selection
      selected_bookmark = nil
      loop do
        input = STDIN.getch.downcase

        if input >= '1' && input <= '9'
          number = input.to_i
          if number > 0 && number <= bookmarks.length
            selected_bookmark = bookmarks[number - 1]
            break
          end
        elsif input == "\e" # ESC
          break
        end
      end

      @dialog_renderer.clear_area(x, y, width, height)
      selected_bookmark
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

    private

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
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
        border_color: border_color,
        title_color: title_color,
        content_color: "\e[37m"
      })

      STDIN.getch
      @dialog_renderer.clear_area(x, y, width, height)
    end

    # Show confirmation dialog for bookmark removal
    # @param bookmark_name [String] Name of bookmark to remove
    # @return [Boolean] true if confirmed, false if cancelled
    def show_remove_confirmation(bookmark_name)
      return false unless @dialog_renderer

      content_lines = [
        '',
        "Remove bookmark '#{bookmark_name}'?",
        '',
        '  [Y]es - Remove',
        '  [N]o  - Cancel',
        ''
      ]

      title = 'Confirm Remove'
      width = 50
      height = content_lines.length + 4
      x, y = @dialog_renderer.calculate_center(width, height)

      @dialog_renderer.draw_floating_window(x, y, width, height, title, content_lines, {
        border_color: "\e[33m",    # Yellow (warning)
        title_color: "\e[1;33m",   # Bold yellow
        content_color: "\e[37m"    # White
      })

      # Wait for confirmation
      confirmed = false
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

      @dialog_renderer.clear_area(x, y, width, height)
      confirmed
    end
  end
end
