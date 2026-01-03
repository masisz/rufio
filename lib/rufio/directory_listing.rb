# frozen_string_literal: true

require 'fileutils'

module Rufio
  class DirectoryListing
    attr_reader :current_path, :start_directory

    def initialize(path = Dir.pwd)
      @current_path = File.expand_path(path)
      @start_directory = @current_path  # 起動時のディレクトリを保存
      @entries = []
      refresh
    end

    def list_entries
      @entries
    end

    def refresh
      return unless File.directory?(@current_path)

      @entries = []

      # NativeScannerが利用可能な場合は使用
      if use_native_scanner?
        scan_with_native_scanner
      else
        scan_with_ruby
      end

      sort_entries!
    end

    def navigate_to(target)
      return false if target.nil? || target.empty?

      new_path = File.join(@current_path, target)

      if File.directory?(new_path) && File.readable?(new_path)
        @current_path = File.expand_path(new_path)
        refresh
        true
      else
        false
      end
    end

    def navigate_to_parent
      parent_path = File.dirname(@current_path)

      # 同じパスの場合は移動しない（ルートディレクトリに到達）
      return false if parent_path == @current_path

      if File.directory?(parent_path) && File.readable?(parent_path)
        @current_path = parent_path
        refresh
        true
      else
        false
      end
    end

    def navigate_to_path(path)
      return false if path.nil? || path.empty?

      expanded_path = File.expand_path(path)

      if File.directory?(expanded_path) && File.readable?(expanded_path)
        @current_path = expanded_path
        refresh
        true
      else
        false
      end
    end

    private

    # NativeScannerを使用するかどうか
    def use_native_scanner?
      defined?(Rufio::NativeScanner) && Rufio::NativeScanner.mode != 'ruby'
    end

    # NativeScannerでスキャン
    def scan_with_native_scanner
      entries = Rufio::NativeScanner.scan_directory(@current_path)

      entries.each do |entry|
        next if entry[:name] == '.'

        full_path = File.join(@current_path, entry[:name])

        # NativeScannerのエントリをDirectoryListingの形式に変換
        converted_entry = {
          name: entry[:name],
          path: full_path,
          type: convert_type(entry[:type], entry[:executable]),
          size: entry[:size] || 0,
          modified: entry[:mtime] ? Time.at(entry[:mtime]) : Time.now
        }
        @entries << converted_entry
      end
    rescue StandardError => e
      # エラーが発生した場合はRubyでスキャン
      Logger.debug "NativeScanner failed: #{e.message}, falling back to Ruby" if defined?(Logger)
      scan_with_ruby
    end

    # Rubyの標準機能でスキャン
    def scan_with_ruby
      Dir.entries(@current_path).each do |name|
        next if name == '.'

        full_path = File.join(@current_path, name)
        entry = {
          name: name,
          path: full_path,
          type: determine_file_type(full_path),
          size: safe_file_size(full_path),
          modified: safe_file_mtime(full_path)
        }
        @entries << entry
      end
    end

    # NativeScannerのタイプをDirectoryListingのタイプに変換
    def convert_type(type, executable)
      return type if type == 'directory'
      return 'executable' if executable

      'file'
    end

    def determine_file_type(path)
      return 'directory' if File.directory?(path)
      return 'executable' if File.executable?(path) && !File.directory?(path)

      'file'
    end

    def safe_file_size(path)
      File.size(path)
    rescue StandardError
      0
    end

    def safe_file_mtime(path)
      File.mtime(path)
    rescue StandardError
      Time.now
    end

    def sort_entries!
      @entries.sort_by! do |entry|
        # ディレクトリを最初に、その後ファイル名でソート
        [entry[:type] == 'directory' ? 0 : 1, entry[:name].downcase]
      end
    end
  end
end

