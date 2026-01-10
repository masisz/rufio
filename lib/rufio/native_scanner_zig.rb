# frozen_string_literal: true

require 'fiddle'
require 'fiddle/import'

module Rufio
  # Zig拡張の非同期FFI層
  # Ruby側は「ハンドル（u64）だけ」を持つ
  module NativeScannerZigFFI
    extend Fiddle::Importer

    LIB_PATH = File.expand_path('native/rufio_zig.bundle', __dir__)

    @loaded = false
    @available = false

    class << self
      def load!
        return @available if @loaded

        @loaded = true

        if File.exist?(LIB_PATH)
          begin
            # 動的ライブラリをロード
            dlload LIB_PATH

            # ABI Boundary: Ruby ABI非依存のC関数（非同期版）
            extern 'uint64_t core_async_create()'
            extern 'int32_t core_async_scan(uint64_t, const char*)'
            extern 'int32_t core_async_scan_fast(uint64_t, const char*, size_t)'
            extern 'uint8_t core_async_get_state(uint64_t)'
            extern 'void core_async_get_progress(uint64_t, void*, void*)'
            extern 'void core_async_cancel(uint64_t)'
            extern 'size_t core_async_get_count(uint64_t)'
            extern 'size_t core_async_get_name(uint64_t, size_t, void*, size_t)'
            extern 'int32_t core_async_get_attrs(uint64_t, size_t, void*, void*, void*, void*, void*)'
            extern 'void core_async_destroy(uint64_t)'
            extern 'char* core_async_version()'

            @available = true
          rescue StandardError => e
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

      # バージョン取得
      def version
        core_async_version.to_s
      end
    end
  end

  # 非同期スキャナークラス（ポーリングベース）
  class NativeScannerZigCore
    POLL_INTERVAL = 0.01 # 10ms

    def initialize
      @handle = NativeScannerZigFFI.core_async_create
      raise StandardError, "Failed to create scanner" if @handle.zero?
    end

    # 非同期スキャン開始
    def scan_async(path)
      result = NativeScannerZigFFI.core_async_scan(@handle, path)
      raise StandardError, "Failed to start scan" if result != 0
      self
    end

    # 高速スキャン（エントリ数制限付き）
    def scan_fast_async(path, max_entries)
      result = NativeScannerZigFFI.core_async_scan_fast(@handle, path, max_entries)
      raise StandardError, "Failed to start scan" if result != 0
      self
    end

    # ポーリングして完了待ち
    def wait(timeout: nil)
      start_time = Time.now
      loop do
        state = get_state

        case state
        when :done
          return get_results
        when :failed
          raise StandardError, "Scan failed"
        when :cancelled
          raise StandardError, "Scan cancelled"
        end

        if timeout && (Time.now - start_time) > timeout
          raise StandardError, "Timeout"
        end

        sleep POLL_INTERVAL
      end
    end

    # 進捗報告付きで完了待ち
    def wait_with_progress(&block)
      loop do
        state = get_state
        progress = get_progress

        yield(progress[:current], progress[:total]) if block_given?

        case state
        when :done
          return get_results
        when :failed
          raise StandardError, "Scan failed"
        when :cancelled
          raise StandardError, "Scan cancelled"
        end

        sleep POLL_INTERVAL
      end
    end

    # 状態確認
    def get_state
      state_code = NativeScannerZigFFI.core_async_get_state(@handle)
      [:idle, :scanning, :done, :cancelled, :failed][state_code] || :failed
    end

    # 進捗取得
    def get_progress
      current = Fiddle::Pointer.malloc(8)
      total = Fiddle::Pointer.malloc(8)
      NativeScannerZigFFI.core_async_get_progress(@handle, current, total)
      {
        current: current[0, 8].unpack1('Q'),
        total: total[0, 8].unpack1('Q')
      }
    end

    # キャンセル
    def cancel
      NativeScannerZigFFI.core_async_cancel(@handle)
    end

    # 結果取得（完了後）
    def get_results
      count = NativeScannerZigFFI.core_async_get_count(@handle)
      entries = []
      count.times { |i| entries << get_entry(i) }
      entries
    end

    # スキャナーを明示的に破棄
    def close
      return if @handle.zero?

      NativeScannerZigFFI.core_async_destroy(@handle)
      @handle = 0
    end

    private

    # 指定インデックスのエントリを取得
    def get_entry(index)
      # 名前を取得
      name_buf = Fiddle::Pointer.malloc(256)
      name_len = NativeScannerZigFFI.core_async_get_name(@handle, index, name_buf, 256)
      name = name_buf[0, name_len].force_encoding('UTF-8')

      # 属性を取得
      is_dir = Fiddle::Pointer.malloc(1)
      size = Fiddle::Pointer.malloc(8)
      mtime = Fiddle::Pointer.malloc(8)
      executable = Fiddle::Pointer.malloc(1)
      hidden = Fiddle::Pointer.malloc(1)

      NativeScannerZigFFI.core_async_get_attrs(@handle, index, is_dir, size, mtime, executable, hidden)

      {
        name: name,
        is_dir: is_dir[0, 1].unpack1('C') != 0,
        size: size[0, 8].unpack1('Q'),
        mtime: mtime[0, 8].unpack1('q'),
        executable: executable[0, 1].unpack1('C') != 0,
        hidden: hidden[0, 1].unpack1('C') != 0
      }
    end
  end

  # Zig拡張が利用可能な場合のみ、NativeScannerに統合
  if NativeScannerZigFFI.load!
    class NativeScanner
      class << self
        # zigモードを追加
        alias_method :original_mode=, :mode= unless method_defined?(:original_mode=)

        def mode=(value)
          case value
          when 'zig'
            if NativeScannerZigFFI.available?
              @mode = 'zig'
              @current_library = nil
            else
              @mode = 'ruby'
              @current_library = nil
            end
          else
            original_mode=(value)
          end
        end

        # zigスキャン（ポーリング方式）
        def scan_directory_with_zig(path)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          # 非同期スキャナーを作成してスキャン
          scanner = NativeScannerZigCore.new
          begin
            scanner.scan_async(path)
            entries = scanner.wait(timeout: 60)

            # 結果の形式を統一（type フィールドを追加）
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
          ensure
            scanner.close
          end
        rescue StandardError => e
          raise StandardError, "Zig scan failed: #{e.message}"
        end

        # zigで高速スキャン（ポーリング方式）
        def scan_directory_fast_with_zig(path, max_entries)
          raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

          scanner = NativeScannerZigCore.new
          begin
            scanner.scan_fast_async(path, max_entries)
            entries = scanner.wait(timeout: 60)

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
          ensure
            scanner.close
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
            NativeScannerZigFFI.version
          else
            original_version
          end
        end

        # available_librariesを更新
        alias_method :original_available_libraries, :available_libraries unless method_defined?(:original_available_libraries)

        def available_libraries
          original = original_available_libraries
          original.merge(zig: NativeScannerZigFFI.available?)
        end

        # autoモードの優先順位を更新（zig > ruby）
        def mode=(value)
          case value
          when 'auto'
            # 優先順位: Zig > Ruby
            if NativeScannerZigFFI.available?
              @mode = 'zig'
              @current_library = nil
            else
              @mode = 'ruby'
              @current_library = nil
            end
          when 'zig'
            if NativeScannerZigFFI.available?
              @mode = 'zig'
              @current_library = nil
            else
              @mode = 'ruby'
              @current_library = nil
            end
          else
            send(:original_mode=, value)
          end
        end
      end
    end
  end
end
