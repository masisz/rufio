# frozen_string_literal: true

module Rufio
  # コマンド履歴管理クラス
  class CommandHistory
    DEFAULT_MAX_SIZE = 1000

    attr_reader :size

    # 初期化
    # @param history_file [String] 履歴ファイルのパス
    # @param max_size [Integer] 履歴の最大保存数
    def initialize(history_file, max_size: DEFAULT_MAX_SIZE)
      @history_file = history_file
      @max_size = max_size
      @history = []
      @position = -1  # -1 = 最新の位置（履歴の外）

      load_from_file if File.exist?(@history_file)
    end

    # コマンドを履歴に追加
    # @param command [String] 追加するコマンド
    def add(command)
      # 空のコマンドは無視
      return if command.nil? || command.strip.empty?

      # 連続する重複は無視
      return if !@history.empty? && @history.last == command

      @history << command

      # 最大サイズを超えたら古いものを削除
      @history.shift if @history.size > @max_size

      # 位置をリセット
      reset_position
    end

    # 前のコマンドを取得（上矢印キー相当）
    # @return [String, nil] 前のコマンド、存在しない場合はnil
    def previous
      return nil if @history.empty?

      # 初回は最後のコマンドを返す
      if @position == -1
        @position = @history.size - 1
        return @history[@position]
      end

      # これ以上前がない場合
      return nil if @position <= 0

      # 一つ前に移動
      @position -= 1
      @history[@position]
    end

    # 次のコマンドを取得（下矢印キー相当）
    # @return [String] 次のコマンド、最新位置の場合は空文字列
    def next
      return "" if @history.empty? || @position == -1

      # 一つ次に移動
      @position += 1

      # 最新位置を超えた場合は空文字列を返す
      if @position >= @history.size
        @position = -1
        return ""
      end

      @history[@position]
    end

    # 履歴をファイルに保存
    def save
      File.write(@history_file, @history.join("\n") + "\n")
    end

    # 位置をリセット（新しいコマンド入力時などに使用）
    def reset_position
      @position = -1
    end

    # 履歴のサイズを取得
    def size
      @history.size
    end

    private

    # ファイルから履歴を読み込む
    def load_from_file
      return unless File.exist?(@history_file)

      File.readlines(@history_file, chomp: true).each do |line|
        next if line.strip.empty?

        @history << line
      end

      # 最大サイズを超えている場合は調整
      while @history.size > @max_size
        @history.shift
      end
    end
  end
end
