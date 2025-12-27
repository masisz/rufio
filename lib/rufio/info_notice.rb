# frozen_string_literal: true

require 'fileutils'

module Rufio
  # Manages info notices from the info directory
  class InfoNotice
    INFO_DIR = File.join(File.dirname(__FILE__), '..', '..', 'info')
    NOTICE_TRACKING_DIR = File.join(Dir.home, '.config', 'rufio', 'notices')

    attr_accessor :info_dir, :tracking_dir

    def initialize(info_dir: nil, tracking_dir: nil)
      @info_dir = info_dir || INFO_DIR
      @tracking_dir = tracking_dir || NOTICE_TRACKING_DIR
      ensure_tracking_directory
    end

    # Get all available notices that haven't been shown
    # @return [Array<Hash>] Array of notice hashes with :file, :title, :content
    def unread_notices
      return [] unless Dir.exist?(@info_dir)

      Dir.glob(File.join(@info_dir, '*.txt')).map do |file_path|
        next if shown?(file_path)

        {
          file: file_path,
          filename: File.basename(file_path),
          title: extract_title(file_path),
          content: read_content(file_path)
        }
      end.compact
    end

    # Check if a notice has been shown
    # @param file_path [String] Path to the notice file
    # @return [Boolean] true if already shown
    def shown?(file_path)
      tracking_file = tracking_file_path(file_path)
      File.exist?(tracking_file)
    end

    # Mark a notice as shown
    # @param file_path [String] Path to the notice file
    def mark_as_shown(file_path)
      tracking_file = tracking_file_path(file_path)
      FileUtils.touch(tracking_file)
    end

    # Extract title from the first line of the file
    # @param file_path [String] Path to the notice file
    # @return [String] The title
    def extract_title(file_path)
      first_line = File.open(file_path, &:readline).strip
      # Remove markdown heading markers if present
      first_line.gsub(/^#+\s*/, '')
    rescue StandardError
      File.basename(file_path, '.txt')
    end

    # Read the content of a notice file
    # @param file_path [String] Path to the notice file
    # @return [Array<String>] Content lines
    def read_content(file_path)
      lines = File.readlines(file_path, chomp: true)

      # Skip the first line if it's a markdown heading (title)
      lines = lines.drop(1) if lines.first&.start_with?('#')

      # Add empty lines at the beginning and end for padding
      [''] + lines + ['', 'Press any key to continue...', '']
    rescue StandardError => e
      [
        '',
        "Error reading notice: #{e.message}",
        '',
        'Press any key to continue...',
        ''
      ]
    end

    private

    def ensure_tracking_directory
      FileUtils.mkdir_p(@tracking_dir) unless Dir.exist?(@tracking_dir)
    end

    # Get the tracking file path for a given notice file
    # @param file_path [String] Path to the notice file
    # @return [String] Path to the tracking file
    def tracking_file_path(file_path)
      filename = File.basename(file_path)
      # Use MD5 hash of the filename to avoid issues with special characters
      require 'digest'
      hash = Digest::MD5.hexdigest(filename)
      File.join(@tracking_dir, ".#{hash}_shown")
    end
  end
end
