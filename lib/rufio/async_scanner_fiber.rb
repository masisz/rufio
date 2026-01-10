# frozen_string_literal: true

begin
  require 'async'
  ASYNC_GEM_AVAILABLE = true
rescue LoadError
  ASYNC_GEM_AVAILABLE = false
end

module Rufio
  # Fiber（Asyncライブラリ）統合用ラッパークラス
  #
  # Asyncライブラリと統合し、ノンブロッキングで非同期スキャンを実行します。
  #
  # 使用例:
  #   Async do
  #     scanner = NativeScannerRubyCore.new
  #     wrapper = AsyncScannerFiberWrapper.new(scanner)
  #     entries = wrapper.scan_async('/path')
  #     puts "Found #{entries.length} entries"
  #   end
  #
  class AsyncScannerFiberWrapper
    def initialize(scanner)
      @scanner = scanner
    end

    # 非同期スキャンを開始し、Fiberで完了を待つ
    #
    # @param path [String] スキャンするディレクトリのパス
    # @param timeout [Integer, nil] タイムアウト秒数（オプション）
    # @return [Array<Hash>] スキャン結果
    def scan_async(path, timeout: nil)
      # スキャンを開始
      @scanner.scan_async(path)

      # Fiberでポーリング
      poll_until_complete(timeout: timeout)
    end

    # 高速スキャン（エントリ数制限付き）
    #
    # @param path [String] スキャンするディレクトリのパス
    # @param max_entries [Integer] 最大エントリ数
    # @param timeout [Integer, nil] タイムアウト秒数（オプション）
    # @return [Array<Hash>] スキャン結果
    def scan_fast_async(path, max_entries, timeout: nil)
      # スキャンを開始
      @scanner.scan_fast_async(path, max_entries)

      # Fiberでポーリング
      poll_until_complete(timeout: timeout)
    end

    # 進捗報告付きスキャン
    #
    # @param path [String] スキャンするディレクトリのパス
    # @param timeout [Integer, nil] タイムアウト秒数（オプション）
    # @yield [current, total] 進捗情報を受け取るブロック
    # @return [Array<Hash>] スキャン結果
    def scan_async_with_progress(path, timeout: nil, &block)
      # スキャンを開始
      @scanner.scan_async(path)

      # 進捗付きでポーリング
      poll_until_complete_with_progress(timeout: timeout, &block)
    end

    # スキャンをキャンセル
    def cancel
      @scanner.cancel
    end

    # 状態を取得
    #
    # @return [Symbol] 現在の状態
    def get_state
      @scanner.get_state
    end

    # 進捗を取得
    #
    # @return [Hash] 進捗情報 {current:, total:}
    def get_progress
      @scanner.get_progress
    end

    private

    # 完了までポーリング（Fiberでスリープ）
    def poll_until_complete(timeout: nil)
      start_time = Time.now

      loop do
        state = @scanner.get_state

        case state
        when :done
          result = @scanner.get_results
          @scanner.close
          return result
        when :failed
          @scanner.close
          raise StandardError, "Scan failed"
        when :cancelled
          @scanner.close
          raise StandardError, "Scan cancelled"
        end

        if timeout && (Time.now - start_time) > timeout
          @scanner.close
          raise StandardError, "Timeout"
        end

        # Fiberでスリープ（ノンブロッキング）
        sleep 0.01
      end
    end

    # 進捗報告付きでポーリング
    def poll_until_complete_with_progress(timeout: nil, &block)
      start_time = Time.now

      loop do
        state = @scanner.get_state
        progress = @scanner.get_progress

        # 進捗コールバック実行
        yield(progress[:current], progress[:total]) if block_given?

        case state
        when :done
          result = @scanner.get_results
          @scanner.close
          return result
        when :failed
          @scanner.close
          raise StandardError, "Scan failed"
        when :cancelled
          @scanner.close
          raise StandardError, "Scan cancelled"
        end

        if timeout && (Time.now - start_time) > timeout
          @scanner.close
          raise StandardError, "Timeout"
        end

        # Fiberでスリープ（ノンブロッキング）
        sleep 0.01
      end
    end
  end
end
