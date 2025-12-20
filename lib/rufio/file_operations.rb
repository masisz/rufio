# frozen_string_literal: true

require 'fileutils'

module Rufio
  # Handles file operations (move, copy, delete)
  class FileOperations
    # Operation result structure
    # @return [Hash] { success: Boolean, message: String, count: Integer }
    OperationResult = Struct.new(:success, :message, :count, :errors, keyword_init: true)

    # Move files/directories to destination
    # @param items [Array<String>] Item names to move
    # @param source_directory [String] Source directory path
    # @param destination [String] Destination directory path
    # @return [OperationResult]
    def move(items, source_directory, destination)
      perform_operation(:move, items, source_directory, destination)
    end

    # Copy files/directories to destination
    # @param items [Array<String>] Item names to copy
    # @param source_directory [String] Source directory path
    # @param destination [String] Destination directory path
    # @return [OperationResult]
    def copy(items, source_directory, destination)
      perform_operation(:copy, items, source_directory, destination)
    end

    # Delete files/directories
    # @param items [Array<String>] Item names to delete
    # @param source_directory [String] Source directory path
    # @return [OperationResult]
    def delete(items, source_directory)
      success_count = 0
      error_messages = []

      items.each do |item_name|
        item_path = File.join(source_directory, item_name)

        begin
          # Check if file/directory exists
          unless File.exist?(item_path)
            error_messages << "#{item_name}: File not found"
            next
          end

          is_directory = File.directory?(item_path)

          if is_directory
            FileUtils.rm_rf(item_path)
          else
            FileUtils.rm(item_path)
          end

          # Verify deletion
          sleep(0.01) # Wait for file system sync
          if File.exist?(item_path)
            error_messages << "#{item_name}: Deletion failed"
          else
            success_count += 1
          end
        rescue StandardError => e
          error_messages << "#{item_name}: #{e.message}"
        end
      end

      OperationResult.new(
        success: error_messages.empty?,
        message: build_delete_message(success_count, items.length),
        count: success_count,
        errors: error_messages
      )
    end

    # Create a new file
    # @param directory [String] Directory path
    # @param filename [String] File name
    # @return [OperationResult]
    def create_file(directory, filename)
      # Validate filename
      if filename.include?('/') || filename.include?('\\')
        return OperationResult.new(
          success: false,
          message: 'Invalid filename: cannot contain path separators',
          count: 0,
          errors: []
        )
      end

      file_path = File.join(directory, filename)

      # Check if file already exists
      if File.exist?(file_path)
        return OperationResult.new(
          success: false,
          message: 'File already exists',
          count: 0,
          errors: []
        )
      end

      begin
        File.write(file_path, '')
        OperationResult.new(
          success: true,
          message: "File created: #{filename}",
          count: 1,
          errors: []
        )
      rescue StandardError => e
        OperationResult.new(
          success: false,
          message: "Creation error: #{e.message}",
          count: 0,
          errors: [e.message]
        )
      end
    end

    # Create a new directory
    # @param parent_directory [String] Parent directory path
    # @param dirname [String] Directory name
    # @return [OperationResult]
    def create_directory(parent_directory, dirname)
      # Validate dirname
      if dirname.include?('/') || dirname.include?('\\')
        return OperationResult.new(
          success: false,
          message: 'Invalid directory name: cannot contain path separators',
          count: 0,
          errors: []
        )
      end

      dir_path = File.join(parent_directory, dirname)

      # Check if directory already exists
      if File.exist?(dir_path)
        return OperationResult.new(
          success: false,
          message: 'Directory already exists',
          count: 0,
          errors: []
        )
      end

      begin
        Dir.mkdir(dir_path)
        OperationResult.new(
          success: true,
          message: "Directory created: #{dirname}",
          count: 1,
          errors: []
        )
      rescue StandardError => e
        OperationResult.new(
          success: false,
          message: "Creation error: #{e.message}",
          count: 0,
          errors: [e.message]
        )
      end
    end

    private

    # Perform move or copy operation
    # @param operation [Symbol] :move or :copy
    # @param items [Array<String>] Item names
    # @param source_directory [String] Source directory path
    # @param destination [String] Destination directory path
    # @return [OperationResult]
    def perform_operation(operation, items, source_directory, destination)
      success_count = 0
      error_messages = []

      items.each do |item_name|
        source_path = File.join(source_directory, item_name)
        dest_path = File.join(destination, item_name)

        begin
          if File.exist?(dest_path)
            error_messages << "#{item_name}: Already exists in destination"
            next
          end

          case operation
          when :move
            FileUtils.mv(source_path, dest_path)
          when :copy
            if File.directory?(source_path)
              FileUtils.cp_r(source_path, dest_path)
            else
              FileUtils.cp(source_path, dest_path)
            end
          end

          success_count += 1
        rescue StandardError => e
          operation_name = operation == :move ? 'move' : 'copy'
          error_messages << "#{item_name}: Failed to #{operation_name} (#{e.message})"
        end
      end

      operation_name = operation == :move ? 'Moved' : 'Copied'
      message = "#{operation_name} #{success_count} item(s)"
      message += " (#{error_messages.length} failed)" unless error_messages.empty?

      OperationResult.new(
        success: error_messages.empty?,
        message: message,
        count: success_count,
        errors: error_messages
      )
    end

    # Build delete operation message
    # @param success_count [Integer] Number of successfully deleted items
    # @param total_count [Integer] Total number of items
    # @return [String]
    def build_delete_message(success_count, total_count)
      if success_count == total_count
        "Deleted #{success_count} item(s)"
      else
        failed_count = total_count - success_count
        "#{success_count} deleted, #{failed_count} failed"
      end
    end
  end
end
