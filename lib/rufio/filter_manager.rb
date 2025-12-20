# frozen_string_literal: true

module Rufio
  # Manages filtering of directory entries
  class FilterManager
    attr_reader :filter_query, :filter_mode

    def initialize
      @filter_mode = false
      @filter_query = ''
      @original_entries = []
      @filtered_entries = []
    end

    # Start filter mode with the given entries
    # @param entries [Array<Hash>] Directory entries to filter
    def start_filter_mode(entries)
      @filter_mode = true
      @filter_query = ''
      @original_entries = entries.dup
      @filtered_entries = @original_entries.dup
      true
    end

    # Handle filter input character
    # @param key [String] Input key
    # @return [Symbol] :exit_clear, :exit_keep, :continue, or :backspace_exit
    def handle_filter_input(key)
      case key
      when "\e" # ESC - clear filter and exit
        :exit_clear
      when "\r", "\n" # Enter - keep filter and exit
        :exit_keep
      when "\u007f", "\b" # Backspace
        if @filter_query.length > 0
          @filter_query = @filter_query[0...-1]
          apply_filter
          :continue
        else
          :backspace_exit
        end
      else
        # Printable characters (alphanumeric, symbols, Japanese, etc.)
        if key.length == 1 && key.ord >= 32 && key.ord < 127 # ASCII printable
          @filter_query += key
          apply_filter
          :continue
        elsif key.bytesize > 1 # Multi-byte characters (Japanese, etc.)
          @filter_query += key
          apply_filter
          :continue
        else
          # Ignore other keys (Ctrl+c, etc.)
          :continue
        end
      end
    end

    # Apply filter to entries
    # @return [Array<Hash>] Filtered entries
    def apply_filter
      if @filter_query.empty?
        @filtered_entries = @original_entries.dup
      else
        query_downcase = @filter_query.downcase
        @filtered_entries = @original_entries.select do |entry|
          entry[:name].downcase.include?(query_downcase)
        end
      end
      @filtered_entries
    end

    # Clear filter mode
    def clear_filter
      @filter_mode = false
      @filter_query = ''
      @filtered_entries = []
      @original_entries = []
    end

    # Exit filter mode while keeping the filter
    def exit_filter_mode_keep_filter
      @filter_mode = false
      # Keep @filter_query and @filtered_entries
    end

    # Check if filter is active
    # @return [Boolean]
    def filter_active?
      @filter_mode || !@filter_query.empty?
    end

    # Get filtered entries
    # @return [Array<Hash>]
    def filtered_entries
      @filtered_entries
    end

    # Update original entries (e.g., after directory refresh)
    # @param entries [Array<Hash>] New entries
    def update_entries(entries)
      @original_entries = entries.dup
      apply_filter if filter_active?
    end

    # Restart filter mode with existing query
    # @param entries [Array<Hash>] Directory entries
    def restart_filter_mode(entries)
      @filter_mode = true
      @original_entries = entries.dup if @original_entries.empty?
      apply_filter
    end
  end
end
