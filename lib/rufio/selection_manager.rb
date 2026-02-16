# frozen_string_literal: true

module Rufio
  # Manages selected items (files/directories) for bulk operations
  class SelectionManager
    attr_reader :source_directory

    def initialize
      @selected_items = []
      @source_directory = nil
    end

    # Toggle selection for an entry
    # @param entry [Hash] Entry with :name key
    # @param current_directory [String, nil] Current directory path (optional)
    # @return [Boolean] true if now selected, false if unselected
    def toggle_selection(entry, current_directory = nil)
      return false unless entry

      # 異なるディレクトリで選択した場合、古い選択をクリアしてリセット
      if current_directory && @source_directory && current_directory != @source_directory
        @selected_items.clear
        @source_directory = nil
      end

      if @selected_items.include?(entry[:name])
        @selected_items.delete(entry[:name])
        # Clear source_directory if no items are selected
        @source_directory = nil if @selected_items.empty?
        false
      else
        # Set source directory on first selection
        @source_directory = current_directory if @selected_items.empty? && current_directory
        @selected_items << entry[:name]
        true
      end
    end

    # Check if an entry is selected
    # @param entry_name [String] Entry name
    # @return [Boolean]
    def selected?(entry_name)
      @selected_items.include?(entry_name)
    end

    # Get all selected items
    # @return [Array<String>] Copy of selected items
    def selected_items
      @selected_items.dup
    end

    # Clear all selections
    def clear
      @selected_items.clear
      @source_directory = nil
    end

    # Check if any items are selected
    # @return [Boolean]
    def any?
      !@selected_items.empty?
    end

    # Get the count of selected items
    # @return [Integer]
    def count
      @selected_items.length
    end

    # Add an item to selection
    # @param item_name [String] Item name
    def add(item_name)
      @selected_items << item_name unless @selected_items.include?(item_name)
    end

    # Remove an item from selection
    # @param item_name [String] Item name
    def remove(item_name)
      @selected_items.delete(item_name)
    end

    # Select multiple items
    # @param item_names [Array<String>] Item names
    def select_multiple(item_names)
      item_names.each { |name| add(name) }
    end

    # Check if selection is empty
    # @return [Boolean]
    def empty?
      @selected_items.empty?
    end
  end
end
