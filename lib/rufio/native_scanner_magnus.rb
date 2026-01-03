# frozen_string_literal: true

module Rufio
  # Magnus拡張のラッパー
  # FFIを使わずに直接Rubyオブジェクトとして扱える
  module NativeScannerMagnusLoader
    LIB_PATH = File.expand_path('native/rufio_native.bundle', __dir__)

    @loaded = false
    @available = false

    class << self
      def load!
        return @available if @loaded

        @loaded = true

        if File.exist?(LIB_PATH)
          begin
            # .bundleファイルを直接ロード
            # 拡張子を外してrequireする
            lib_path_without_ext = LIB_PATH.sub(/\.bundle$/, '')
            require lib_path_without_ext
            @available = defined?(Rufio::NativeScannerMagnus)
          rescue LoadError => e
            warn "Failed to load magnus extension: #{e.message}" if ENV['RUFIO_DEBUG']
            @available = false
          end
        else
          @available = false
        end

        @available
      end

      def available?
        load! unless @loaded
        @available
      end
    end
  end

  # Magnus拡張が利用可能な場合のみロード
  if NativeScannerMagnusLoader.load!
    # NativeScannerにmagnusモードを追加
    class NativeScanner
      class << self
        # magnusモードを追加
        alias_method :original_mode=, :mode=

        def mode=(value)
          case value
          when 'magnus'
            if NativeScannerMagnusLoader.available?
              @mode = 'magnus'
              @current_library = nil  # magnus は FFI を使わない
            else
              @mode = 'ruby'
              @current_library = nil
            end
          else
            original_mode=(value)
          end
        end

        # magnusスキャン
        def scan_directory_with_magnus(path)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          entries = NativeScannerMagnus.scan_directory(path)

          # 結果の形式を統一（すでに正しい形式だが念のため）
          entries.map do |entry|
            {
              name: entry[:name],
              type: entry[:is_dir] ? 'directory' : 'file',
              size: entry[:size],
              mtime: entry[:mtime],
              mode: 0,
              executable: entry[:executable],
              hidden: entry[:hidden]
            }
          end
        rescue StandardError => e
          raise StandardError, "Magnus scan failed: #{e.message}"
        end

        # magnusで高速スキャン
        def scan_directory_fast_with_magnus(path, max_entries)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          entries = NativeScannerMagnus.scan_directory_fast(path, max_entries)

          entries.map do |entry|
            {
              name: entry[:name],
              type: entry[:is_dir] ? 'directory' : 'file',
              size: entry[:size],
              mtime: entry[:mtime],
              mode: 0,
              executable: entry[:executable],
              hidden: entry[:hidden]
            }
          end
        rescue StandardError => e
          raise StandardError, "Magnus fast scan failed: #{e.message}"
        end

        # scan_directoryメソッドを拡張
        alias_method :original_scan_directory, :scan_directory

        def scan_directory(path)
          mode if @mode.nil?

          case @mode
          when 'magnus'
            scan_directory_with_magnus(path)
          else
            original_scan_directory(path)
          end
        end

        # scan_directory_fastメソッドを拡張
        alias_method :original_scan_directory_fast, :scan_directory_fast

        def scan_directory_fast(path, max_entries = 1000)
          mode if @mode.nil?

          case @mode
          when 'magnus'
            scan_directory_fast_with_magnus(path, max_entries)
          else
            original_scan_directory_fast(path, max_entries)
          end
        end

        # versionメソッドを拡張
        alias_method :original_version, :version

        def version
          mode if @mode.nil?

          case @mode
          when 'magnus'
            NativeScannerMagnus.version
          else
            original_version
          end
        end

        # available_librariesを更新
        alias_method :original_available_libraries, :available_libraries

        def available_libraries
          original = original_available_libraries
          original.merge(magnus: NativeScannerMagnusLoader.available?)
        end

        # autoモードの優先順位を更新（magnus > rust > go > ruby）
        alias_method :original_auto_mode, :mode=

        def mode=(value)
          case value
          when 'auto'
            # 優先順位: Magnus > Rust > Go > Ruby
            if NativeScannerMagnusLoader.available?
              @mode = 'magnus'
              @current_library = nil
            elsif RustLib.available?
              @mode = 'rust'
              @current_library = RustLib
            elsif GoLib.available?
              @mode = 'go'
              @current_library = GoLib
            else
              @mode = 'ruby'
              @current_library = nil
            end
          when 'magnus'
            if NativeScannerMagnusLoader.available?
              @mode = 'magnus'
              @current_library = nil
            else
              @mode = 'ruby'
              @current_library = nil
            end
          else
            original_auto_mode(value)
          end
        end
      end
    end
  end
end
