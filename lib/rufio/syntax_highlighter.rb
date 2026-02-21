# frozen_string_literal: true

module Rufio
  # bat コマンドを使ってファイルのシンタックスハイライトを行うクラス。
  # bat が存在しない場合は available? が false を返し、highlight は [] を返す。
  # mtime ベースのキャッシュを持ち、同じファイルの2回目以降は0msで返す。
  class SyntaxHighlighter
    def initialize
      @bat_available = bat_available?
      @cache = {}    # file_path => { mtime: Time, lines: Array<String> }
      @pending = {}  # file_path => true（非同期実行中フラグ）
      @mutex = Mutex.new
    end

    # bat コマンドが利用可能かどうか
    #
    # @return [Boolean]
    def available?
      @bat_available
    end

    # ファイルをシンタックスハイライトして ANSI 付き行の配列を返す（同期版）。
    # bat が使えない場合、ファイルが存在しない場合は []。
    #
    # @param file_path [String] ハイライト対象のファイルパス
    # @param max_lines [Integer] 取得する最大行数
    # @return [Array<String>] ANSI エスケープコード付きの行配列
    def highlight(file_path, max_lines: 50)
      return [] unless @bat_available
      return [] unless File.exist?(file_path)

      mtime = File.mtime(file_path)
      @mutex.synchronize do
        cache = @cache[file_path]
        return cache[:lines] if cache && cache[:mtime] == mtime
      end

      lines = run_bat(file_path, max_lines)
      @mutex.synchronize { @cache[file_path] = { mtime: mtime, lines: lines } }
      lines
    rescue => _e
      []
    end

    # ファイルをバックグラウンドスレッドでシンタックスハイライトする（非同期版）。
    # メインループをブロックせず、bat 完了時にコールバックを呼ぶ。
    # キャッシュヒット時はコールバックを即時（同期的に）呼ぶ。
    # 同一ファイルへの重複呼び出しは無視する（ペンディングガード）。
    #
    # @param file_path [String] ハイライト対象のファイルパス
    # @param max_lines [Integer] 取得する最大行数
    # @yieldparam lines [Array<String>] ANSI付き行配列（エラー時は []）
    def highlight_async(file_path, max_lines: 50, &callback)
      return unless @bat_available
      return unless File.exist?(file_path)

      mtime = File.mtime(file_path)

      @mutex.synchronize do
        # キャッシュヒット → 即時コールバック
        cache = @cache[file_path]
        if cache && cache[:mtime] == mtime
          callback&.call(cache[:lines])
          return
        end

        # 既にペンディング中 → 重複スレッドを立てない
        return if @pending[file_path]

        @pending[file_path] = true
      end

      Thread.new do
        begin
          lines = run_bat(file_path, max_lines)
          @mutex.synchronize do
            @cache[file_path] = { mtime: mtime, lines: lines }
            @pending.delete(file_path)
          end
          callback&.call(lines)
        rescue => _e
          @mutex.synchronize { @pending.delete(file_path) }
          callback&.call([])
        end
      end

      nil
    end

    private

    def bat_available?
      system('which bat > /dev/null 2>&1')
    end

    def run_bat(file_path, max_lines)
      output = IO.popen(
        ['bat', '--color=always', '--plain', '--line-range', "1:#{max_lines}", file_path],
        err: File::NULL
      ) { |io| io.read }

      return [] unless output

      output
        .encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
        .split("\n")
    rescue => _e
      []
    end
  end
end
