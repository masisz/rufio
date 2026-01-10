# frozen_string_literal: true

module Rufio
  # Promise風インターフェースで非同期スキャンを扱うクラス
  #
  # 使用例:
  #   scanner = NativeScannerRubyCore.new
  #   AsyncScannerPromise.new(scanner)
  #     .scan_async('/path')
  #     .then { |entries| entries.select { |e| e[:type] == 'file' } }
  #     .then { |files| files.map { |f| f[:name] } }
  #     .wait
  #
  class AsyncScannerPromise
    def initialize(scanner)
      @scanner = scanner
      @callbacks = []
    end

    # 非同期スキャンを開始
    #
    # @param path [String] スキャンするディレクトリのパス
    # @return [AsyncScannerPromise] self（メソッドチェーン用）
    def scan_async(path)
      @scanner.scan_async(path)
      self
    end

    # 高速スキャンを開始（エントリ数制限付き）
    #
    # @param path [String] スキャンするディレクトリのパス
    # @param max_entries [Integer] 最大エントリ数
    # @return [AsyncScannerPromise] self（メソッドチェーン用）
    def scan_fast_async(path, max_entries)
      @scanner.scan_fast_async(path, max_entries)
      self
    end

    # コールバックを登録
    #
    # @yield [result] 前のステップの結果を受け取るブロック
    # @return [AsyncScannerPromise] self（メソッドチェーン用）
    def then(&block)
      @callbacks << block if block_given?
      self
    end

    # スキャン完了を待ち、コールバックを順次実行
    #
    # @param timeout [Integer, nil] タイムアウト秒数（オプション）
    # @return [Object] 最後のコールバックの戻り値、またはスキャン結果
    def wait(timeout: nil)
      result = @scanner.wait(timeout: timeout)

      # 登録されたコールバックを順次実行
      @callbacks.each do |callback|
        result = callback.call(result)
      end

      result
    ensure
      # 完了後はスキャナーを自動的にクローズ
      @scanner.close
    end
  end
end
