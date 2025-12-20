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
      print ConfigLoader.message('bookmark.input_name') || 'Enter bookmark name: '
      name = STDIN.gets.chomp
      return false if name.empty?

      if @bookmark.add(path, name)
        puts "\n#{ConfigLoader.message('bookmark.added') || 'Bookmark added'}: #{name}"
        true
      else
        puts "\n#{ConfigLoader.message('bookmark.add_failed') || 'Failed to add bookmark'}"
        false
      end
    end

    # Remove a bookmark interactively
    # @return [Boolean] Success status
    def remove_interactive
      bookmarks = @bookmark.list

      if bookmarks.empty?
        puts "\n#{ConfigLoader.message('bookmark.no_bookmarks') || 'No bookmarks found'}"
        return false
      end

      puts "\nBookmarks:"
      bookmarks.each_with_index do |bookmark, index|
        puts "  #{index + 1}. #{bookmark[:name]} (#{bookmark[:path]})"
      end

      print ConfigLoader.message('bookmark.input_number') || 'Enter number to remove: '
      input = STDIN.gets.chomp
      number = input.to_i

      if number > 0 && number <= bookmarks.length
        bookmark_to_remove = bookmarks[number - 1]
        if @bookmark.remove(bookmark_to_remove[:name])
          puts "\n#{ConfigLoader.message('bookmark.removed') || 'Bookmark removed'}: #{bookmark_to_remove[:name]}"
          true
        else
          puts "\n#{ConfigLoader.message('bookmark.remove_failed') || 'Failed to remove bookmark'}"
          false
        end
      else
        puts "\n#{ConfigLoader.message('bookmark.invalid_number') || 'Invalid number'}"
        false
      end
    end

    # List all bookmarks interactively
    # @return [Boolean] Success status
    def list_interactive
      bookmarks = @bookmark.list

      if bookmarks.empty?
        puts "\n#{ConfigLoader.message('bookmark.no_bookmarks') || 'No bookmarks found'}"
        return false
      end

      puts "\nBookmarks:"
      bookmarks.each_with_index do |bookmark, index|
        puts "  #{index + 1}. #{bookmark[:name]} (#{bookmark[:path]})"
      end

      true
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
  end
end
