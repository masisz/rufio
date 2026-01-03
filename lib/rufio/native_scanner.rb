# frozen_string_literal: true

require 'ffi'
require 'json'

module Rufio
  # NativeScanner - Rust/Goのネイティブライブラリを使った高速ディレクトリスキャナー
  class NativeScanner
    # ライブラリパス
    LIB_DIR = File.expand_path('native', __dir__)
    RUST_LIB = File.join(LIB_DIR, 'librufio_scanner.dylib')
    GO_LIB = File.join(LIB_DIR, 'libscanner.dylib')

    @mode = nil
    @current_library = nil

    # Rustライブラリ用のFFIモジュール
    module RustLib
      extend FFI::Library

      begin
        ffi_lib RUST_LIB
        attach_function :scan_directory, [:string], :pointer
        attach_function :scan_directory_fast, [:string, :int], :pointer
        attach_function :get_version, [], :pointer
        @available = true
      rescue LoadError, FFI::NotFoundError
        @available = false
      end

      def self.available?
        @available
      end
    end

    # Goライブラリ用のFFIモジュール
    module GoLib
      extend FFI::Library

      begin
        ffi_lib GO_LIB
        attach_function :ScanDirectory, [:string], :pointer
        attach_function :ScanDirectoryFast, [:string, :int], :pointer
        attach_function :GetVersion, [], :pointer
        attach_function :FreeCString, [:pointer], :void
        @available = true
      rescue LoadError, FFI::NotFoundError
        @available = false
      end

      def self.available?
        @available
      end
    end

    class << self
      # モード設定
      def mode=(value)
        case value
        when 'rust'
          if RustLib.available?
            @mode = 'rust'
            @current_library = RustLib
          else
            @mode = 'ruby'
            @current_library = nil
          end
        when 'go'
          if GoLib.available?
            @mode = 'go'
            @current_library = GoLib
          else
            @mode = 'ruby'
            @current_library = nil
          end
        when 'auto'
          # 優先順位: Rust > Go > Ruby
          if RustLib.available?
            @mode = 'rust'
            @current_library = RustLib
          elsif GoLib.available?
            @mode = 'go'
            @current_library = GoLib
          else
            @mode = 'ruby'
            @current_library = nil
          end
        when 'ruby'
          @mode = 'ruby'
          @current_library = nil
        else
          # 無効なモードはrubyにフォールバック
          @mode = 'ruby'
          @current_library = nil
        end
      end

      # 現在のモード取得
      def mode
        # 初回アクセス時はautoモードに設定
        self.mode = 'auto' if @mode.nil?
        @mode
      end

      # 利用可能なライブラリをチェック
      def available_libraries
        {
          rust: RustLib.available?,
          go: GoLib.available?
        }
      end

      # ディレクトリをスキャン
      def scan_directory(path)
        # モードが未設定の場合は自動設定
        mode if @mode.nil?

        case @mode
        when 'rust'
          scan_with_rust(path)
        when 'go'
          scan_with_go(path)
        else
          scan_with_ruby(path)
        end
      end

      # 高速スキャン（エントリ数制限付き）
      def scan_directory_fast(path, max_entries = 1000)
        # モードが未設定の場合は自動設定
        mode if @mode.nil?

        case @mode
        when 'rust'
          scan_fast_with_rust(path, max_entries)
        when 'go'
          scan_fast_with_go(path, max_entries)
        else
          scan_fast_with_ruby(path, max_entries)
        end
      end

      # バージョン情報取得
      def version
        # モードが未設定の場合は自動設定
        mode if @mode.nil?

        case @mode
        when 'rust'
          ptr = RustLib.get_version
          ptr.read_string
        when 'go'
          ptr = GoLib.GetVersion
          result = ptr.read_string
          GoLib.FreeCString(ptr)
          result
        else
          "Ruby #{RUBY_VERSION}"
        end
      end

      private

      # Rustライブラリでスキャン
      def scan_with_rust(path)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        ptr = RustLib.scan_directory(path)
        json_str = ptr.read_string
        parse_scan_result(json_str)
      rescue StandardError => e
        raise StandardError, "Rust scan failed: #{e.message}"
      end

      # Rustライブラリで高速スキャン
      def scan_fast_with_rust(path, max_entries)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        ptr = RustLib.scan_directory_fast(path, max_entries)
        json_str = ptr.read_string
        parse_scan_result(json_str)
      rescue StandardError => e
        raise StandardError, "Rust fast scan failed: #{e.message}"
      end

      # Goライブラリでスキャン
      def scan_with_go(path)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        ptr = GoLib.ScanDirectory(path)
        json_str = ptr.read_string
        GoLib.FreeCString(ptr)
        parse_scan_result(json_str)
      rescue StandardError => e
        raise StandardError, "Go scan failed: #{e.message}"
      end

      # Goライブラリで高速スキャン
      def scan_fast_with_go(path, max_entries)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        ptr = GoLib.ScanDirectoryFast(path, max_entries)
        json_str = ptr.read_string
        GoLib.FreeCString(ptr)
        parse_scan_result(json_str)
      rescue StandardError => e
        raise StandardError, "Go fast scan failed: #{e.message}"
      end

      # Rubyでスキャン（フォールバック実装）
      def scan_with_ruby(path)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        entries = []
        Dir.foreach(path) do |entry|
          next if entry == '.' || entry == '..'

          full_path = File.join(path, entry)
          stat = File.lstat(full_path)

          entries << {
            name: entry,
            type: file_type(stat),
            size: stat.size,
            mtime: stat.mtime.to_i,
            mode: stat.mode
          }
        end
        entries
      rescue StandardError => e
        raise StandardError, "Ruby scan failed: #{e.message}"
      end

      # Ruby高速スキャン（エントリ数制限付き）
      def scan_fast_with_ruby(path, max_entries)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        entries = []
        count = 0

        Dir.foreach(path) do |entry|
          next if entry == '.' || entry == '..'
          break if count >= max_entries

          full_path = File.join(path, entry)
          stat = File.lstat(full_path)

          entries << {
            name: entry,
            type: file_type(stat),
            size: stat.size,
            mtime: stat.mtime.to_i,
            mode: stat.mode
          }
          count += 1
        end
        entries
      rescue StandardError => e
        raise StandardError, "Ruby fast scan failed: #{e.message}"
      end

      # ファイルタイプを判定
      def file_type(stat)
        if stat.directory?
          'directory'
        elsif stat.symlink?
          'symlink'
        elsif stat.file?
          'file'
        else
          'other'
        end
      end

      # JSONレスポンスをパース
      def parse_scan_result(json_str)
        entries = JSON.parse(json_str, symbolize_names: true)

        # エラーチェック（配列ではなくハッシュが返された場合）
        if entries.is_a?(Hash) && entries[:error]
          raise StandardError, entries[:error]
        end

        # 配列が返された場合は各エントリを変換
        if entries.is_a?(Array)
          return entries.map do |entry|
            {
              name: entry[:name],
              type: entry[:is_dir] ? 'directory' : 'file',
              size: entry[:size],
              mtime: entry[:mtime],
              mode: 0, # Rustライブラリはmodeを返さない
              executable: entry[:executable],
              hidden: entry[:hidden]
            }
          end
        end

        # それ以外の場合は空配列
        []
      rescue JSON::ParserError => e
        raise StandardError, "Failed to parse scan result: #{e.message}"
      end
    end
  end
end
