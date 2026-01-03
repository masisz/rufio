# frozen_string_literal: true

module Rufio
  # Zig拡張のラッパー
  # FFIを使わずに直接Rubyオブジェクトとして扱える
  module NativeScannerZigLoader
    LIB_PATH = File.expand_path('native/rufio_zig.bundle', __dir__)

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
            @available = defined?(Rufio::NativeScannerZig)
          rescue LoadError => e
            warn "Failed to load zig extension: #{e.message}" if ENV['RUFIO_DEBUG']
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

  # Zig拡張が利用可能な場合のみロード
  if NativeScannerZigLoader.load!
    # NativeScannerにzigモードを追加
    class NativeScanner
      class << self
        # zigモードを追加
        alias_method :original_mode=, :mode= unless method_defined?(:original_mode=)

        def mode=(value)
          case value
          when 'zig'
            if NativeScannerZigLoader.available?
              @mode = 'zig'
              @current_library = nil  # zig は FFI を使わない
            else
              @mode = 'ruby'
              @current_library = nil
            end
          else
            original_mode=(value)
          end
        end

        # zigスキャン
        def scan_directory_with_zig(path)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          entries = NativeScannerZig.scan_directory(path)

          # 結果の形式を統一
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
          raise StandardError, "Zig scan failed: #{e.message}"
        end

        # zigで高速スキャン
        def scan_directory_fast_with_zig(path, max_entries)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          entries = NativeScannerZig.scan_directory_fast(path, max_entries)

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
          raise StandardError, "Zig fast scan failed: #{e.message}"
        end

        # scan_directoryメソッドを拡張
        alias_method :original_scan_directory, :scan_directory unless method_defined?(:original_scan_directory)

        def scan_directory(path)
          mode if @mode.nil?

          case @mode
          when 'zig'
            scan_directory_with_zig(path)
          else
            original_scan_directory(path)
          end
        end

        # scan_directory_fastメソッドを拡張
        alias_method :original_scan_directory_fast, :scan_directory_fast unless method_defined?(:original_scan_directory_fast)

        def scan_directory_fast(path, max_entries = 1000)
          mode if @mode.nil?

          case @mode
          when 'zig'
            scan_directory_fast_with_zig(path, max_entries)
          else
            original_scan_directory_fast(path, max_entries)
          end
        end

        # versionメソッドを拡張
        alias_method :original_version, :version unless method_defined?(:original_version)

        def version
          mode if @mode.nil?

          case @mode
          when 'zig'
            NativeScannerZig.version
          else
            original_version
          end
        end

        # available_librariesを更新
        alias_method :original_available_libraries, :available_libraries unless method_defined?(:original_available_libraries)

        def available_libraries
          original = original_available_libraries
          result = original.merge(zig: NativeScannerZigLoader.available?)
          # magnusが既に追加されていなければ追加
          if defined?(NativeScannerMagnusLoader) && !result.key?(:magnus)
            result = result.merge(magnus: NativeScannerMagnusLoader.available?)
          end
          result
        end

        # autoモードの優先順位を更新（magnus > zig > rust > go > ruby）
        def mode=(value)
          case value
          when 'auto'
            # 優先順位: Magnus > Zig > Rust > Go > Ruby
            if defined?(NativeScannerMagnusLoader) && NativeScannerMagnusLoader.available?
              @mode = 'magnus'
              @current_library = nil
            elsif NativeScannerZigLoader.available?
              @mode = 'zig'
              @current_library = nil
            elsif defined?(RustLib) && RustLib.available?
              @mode = 'rust'
              @current_library = RustLib
            elsif defined?(GoLib) && GoLib.available?
              @mode = 'go'
              @current_library = GoLib
            else
              @mode = 'ruby'
              @current_library = nil
            end
          when 'zig'
            if NativeScannerZigLoader.available?
              @mode = 'zig'
              @current_library = nil
            else
              @mode = 'ruby'
              @current_library = nil
            end
          when 'magnus'
            if defined?(NativeScannerMagnusLoader) && NativeScannerMagnusLoader.available?
              @mode = 'magnus'
              @current_library = nil
            else
              send(:original_mode=, value)
            end
          else
            send(:original_mode=, value)
          end
        end
      end
    end
  end
end
