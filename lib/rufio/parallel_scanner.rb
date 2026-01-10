# frozen_string_literal: true

require 'thread'

module Rufio
  # 並列スキャン最適化クラス
  #
  # 複数のディレクトリを並列にスキャンし、結果をマージします。
  # スレッドプールを使用して効率的に並列処理を行います。
  #
  # 使用例:
  #   parallel_scanner = ParallelScanner.new(max_workers: 4)
  #   results = parallel_scanner.scan_all(['/path1', '/path2', '/path3'])
  #   all_entries = parallel_scanner.scan_all_merged(['/path1', '/path2'])
  #
  class ParallelScanner
    DEFAULT_MAX_WORKERS = 4

    # @param max_workers [Integer] 最大ワーカー数
    # @param backend [Symbol] バックエンド (:ruby or :zig)
    def initialize(max_workers: DEFAULT_MAX_WORKERS, backend: :ruby)
      @max_workers = max_workers
      @backend = backend
    end

    # 複数のディレクトリを並列スキャン
    #
    # @param paths [Array<String>] スキャンするディレクトリパスのリスト
    # @return [Array<Hash>] 各ディレクトリのスキャン結果
    #   [{path:, entries:, success:, error:}, ...]
    def scan_all(paths)
      return [] if paths.empty?

      results = []
      mutex = Mutex.new
      queue = Queue.new

      # キューにパスを追加
      paths.each { |path| queue << path }

      # ワーカースレッドを作成
      workers = []
      worker_count = [@max_workers, paths.length].min

      worker_count.times do
        workers << Thread.new do
          loop do
            path = queue.pop(true) rescue nil
            break if path.nil?

            result = scan_single_directory(path)
            mutex.synchronize { results << result }
          end
        end
      end

      # 全ワーカーの完了を待つ
      workers.each(&:join)

      results
    end

    # 複数のディレクトリを並列スキャンし、結果をマージ
    #
    # @param paths [Array<String>] スキャンするディレクトリパスのリスト
    # @yield [entry] 各エントリをフィルタリングするブロック（オプション）
    # @return [Array<Hash>] 全エントリのマージされた配列
    def scan_all_merged(paths, &filter)
      results = scan_all(paths)

      # 成功した結果のみを取得
      all_entries = results
        .select { |r| r[:success] }
        .flat_map { |r| r[:entries] }

      # フィルタが指定されている場合は適用
      all_entries = all_entries.select(&filter) if block_given?

      all_entries
    end

    # 進捗報告付き並列スキャン
    #
    # @param paths [Array<String>] スキャンするディレクトリパスのリスト
    # @yield [completed, total] 進捗情報を受け取るブロック
    # @return [Array<Hash>] 各ディレクトリのスキャン結果
    def scan_all_with_progress(paths, &block)
      return [] if paths.empty?

      results = []
      mutex = Mutex.new
      queue = Queue.new
      completed = 0
      total = paths.length

      # キューにパスを追加
      paths.each { |path| queue << path }

      # ワーカースレッドを作成
      workers = []
      worker_count = [@max_workers, paths.length].min

      worker_count.times do
        workers << Thread.new do
          loop do
            path = queue.pop(true) rescue nil
            break if path.nil?

            result = scan_single_directory(path)

            mutex.synchronize do
              results << result
              completed += 1
              yield(completed, total) if block_given?
            end
          end
        end
      end

      # 全ワーカーの完了を待つ
      workers.each(&:join)

      results
    end

    private

    # 単一のディレクトリをスキャン
    #
    # @param path [String] スキャンするディレクトリパス
    # @return [Hash] スキャン結果 {path:, entries:, success:, error:}
    def scan_single_directory(path)
      scanner = create_scanner

      begin
        scanner.scan_async(path)
        entries = scanner.wait(timeout: 60)

        {
          path: path,
          entries: entries,
          success: true
        }
      rescue StandardError => e
        {
          path: path,
          entries: [],
          success: false,
          error: e.message
        }
      ensure
        scanner.close
      end
    end

    # バックエンドに応じたスキャナーを作成
    #
    # @return [NativeScannerRubyCore, NativeScannerZigCore] スキャナーインスタンス
    def create_scanner
      case @backend
      when :zig
        if defined?(NativeScannerZigFFI) && NativeScannerZigFFI.available?
          NativeScannerZigCore.new
        else
          # Zigが利用できない場合はRubyにフォールバック
          NativeScannerRubyCore.new
        end
      else
        NativeScannerRubyCore.new
      end
    end
  end
end
