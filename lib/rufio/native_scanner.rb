# frozen_string_literal: true

module Rufio
  # 非同期スキャナークラス（Pure Ruby実装、ポーリングベース）
  class NativeScannerRubyCore
    POLL_INTERVAL = 0.01 # 10ms

    def initialize
      @thread = nil
      @state = :idle
      @results = []
      @error = nil
      @current_progress = 0
      @total_progress = 0
      @mutex = Mutex.new
    end

    # 非同期スキャン開始
    def scan_async(path)
      raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)
      raise StandardError, "Scanner is already running" unless @state == :idle

      @mutex.synchronize do
        @state = :scanning
        @results = []
        @error = nil
        @current_progress = 0
        @total_progress = 0
      end

      @thread = Thread.new do
        begin
          # ディレクトリをスキャン
          entries = []
          Dir.foreach(path) do |entry|
            next if entry == '.' || entry == '..'

            # キャンセルチェック
            break if @state == :cancelled

            full_path = File.join(path, entry)
            stat = File.lstat(full_path)

            entries << {
              name: entry,
              type: file_type(stat),
              size: stat.size,
              mtime: stat.mtime.to_i,
              mode: stat.mode,
              executable: stat.executable?,
              hidden: entry.start_with?('.')
            }

            # 進捗を更新
            @mutex.synchronize do
              @current_progress += 1
              @total_progress = entries.length + 1
            end
          end

          # 結果を保存
          @mutex.synchronize do
            if @state == :cancelled
              @state = :cancelled
            else
              @results = entries
              @state = :done
            end
          end
        rescue StandardError => e
          @mutex.synchronize do
            @error = e
            @state = :failed
          end
        end
      end

      self
    end

    # 高速スキャン（エントリ数制限付き）
    def scan_fast_async(path, max_entries)
      raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)
      raise StandardError, "Scanner is already running" unless @state == :idle

      @mutex.synchronize do
        @state = :scanning
        @results = []
        @error = nil
        @current_progress = 0
        @total_progress = max_entries
      end

      @thread = Thread.new do
        begin
          entries = []
          count = 0

          Dir.foreach(path) do |entry|
            next if entry == '.' || entry == '..'
            break if count >= max_entries

            # キャンセルチェック
            break if @state == :cancelled

            full_path = File.join(path, entry)
            stat = File.lstat(full_path)

            entries << {
              name: entry,
              type: file_type(stat),
              size: stat.size,
              mtime: stat.mtime.to_i,
              mode: stat.mode,
              executable: stat.executable?,
              hidden: entry.start_with?('.')
            }
            count += 1

            # 進捗を更新
            @mutex.synchronize do
              @current_progress = count
            end
          end

          # 結果を保存
          @mutex.synchronize do
            if @state == :cancelled
              @state = :cancelled
            else
              @results = entries
              @state = :done
            end
          end
        rescue StandardError => e
          @mutex.synchronize do
            @error = e
            @state = :failed
          end
        end
      end

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
          raise @error || StandardError.new("Scan failed")
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
          raise @error || StandardError.new("Scan failed")
        when :cancelled
          raise StandardError, "Scan cancelled"
        end

        sleep POLL_INTERVAL
      end
    end

    # 状態確認
    def get_state
      @mutex.synchronize { @state }
    end

    # 進捗取得
    def get_progress
      @mutex.synchronize do
        {
          current: @current_progress,
          total: @total_progress
        }
      end
    end

    # キャンセル
    def cancel
      @mutex.synchronize do
        @state = :cancelled if @state == :scanning
      end
    end

    # 結果取得（完了後）
    def get_results
      @mutex.synchronize { @results.dup }
    end

    # スキャナーを明示的に破棄
    def close
      @thread&.join if @thread&.alive?
      @thread = nil
    end

    private

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
  end

  # NativeScanner - Rubyベースのディレクトリスキャナー（ネイティブライブラリは削除済み）
  class NativeScanner
    @mode = 'ruby'
    @current_library = nil

    class << self
      # モード設定（常にRubyモードを使用）
      def mode=(value)
        @mode = 'ruby'
        @current_library = nil
      end

      # 現在のモード取得
      def mode
        @mode ||= 'ruby'
      end

      # 利用可能なライブラリをチェック（Rubyのみ）
      def available_libraries
        {
          ruby: true
        }
      end

      # ディレクトリをスキャン
      def scan_directory(path)
        scan_with_ruby(path)
      end

      # 高速スキャン（エントリ数制限付き）
      def scan_directory_fast(path, max_entries = 1000)
        scan_fast_with_ruby(path, max_entries)
      end

      # バージョン情報取得
      def version
        "Ruby #{RUBY_VERSION}"
      end

      private

      # Rubyでスキャン（ポーリング方式）
      def scan_with_ruby(path)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        # 非同期スキャナーを作成してスキャン
        scanner = NativeScannerRubyCore.new
        begin
          scanner.scan_async(path)
          scanner.wait(timeout: 60)
        ensure
          scanner.close
        end
      rescue StandardError => e
        raise StandardError, "Ruby scan failed: #{e.message}"
      end

      # Ruby高速スキャン（エントリ数制限付き、ポーリング方式）
      def scan_fast_with_ruby(path, max_entries)
        raise StandardError, "Directory does not exist: #{path}" unless Dir.exist?(path)

        scanner = NativeScannerRubyCore.new
        begin
          scanner.scan_fast_async(path, max_entries)
          scanner.wait(timeout: 60)
        ensure
          scanner.close
        end
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
    end
  end
end
