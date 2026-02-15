# frozen_string_literal: true

module Rufio
  # Rakefileをパースしてタスク名を抽出するパーサー
  # 正規表現ベースでtask定義を検出し、コマンドモードから
  # rake:task_name 形式で実行可能にする
  class RakefileParser
    RAKEFILE_NAMES = %w[Rakefile rakefile Rakefile.rb].freeze
    TASK_PATTERN = /^\s*task\s+[:'"]?(\w+)/.freeze

    # @param directory [String, nil] スキャン対象ディレクトリ
    def initialize(directory = nil)
      @directory = directory
      @tasks_cache = nil
    end

    # ディレクトリ変更時にキャッシュを無効化
    # @param directory [String] 新しいディレクトリ
    def update_directory(directory)
      return if @directory == directory

      @directory = directory
      @tasks_cache = nil
    end

    # Rakefileが存在するかどうか
    # @return [Boolean]
    def rakefile_exists?
      !!find_rakefile
    end

    # Rakefileからタスク名を抽出
    # @return [Array<String>] タスク名の配列（ソート済み・ユニーク）
    def tasks
      @tasks_cache ||= parse_tasks
    end

    # Tab補完候補を取得
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] 補完候補のタスク名
    def complete(prefix)
      tasks.select { |name| name.start_with?(prefix) }
    end

    private

    # Rakefileのパスを検索
    # @return [String, nil] Rakefileのパス、見つからない場合nil
    def find_rakefile
      return nil unless @directory && Dir.exist?(@directory)

      RAKEFILE_NAMES.each do |name|
        path = File.join(@directory, name)
        return path if File.file?(path)
      end

      nil
    end

    # Rakefileをパースしてタスク名を抽出
    # @return [Array<String>] タスク名の配列
    def parse_tasks
      rakefile = find_rakefile
      return [] unless rakefile

      content = File.read(rakefile)
      task_names = []

      content.each_line do |line|
        match = line.match(TASK_PATTERN)
        task_names << match[1] if match
      end

      task_names.uniq.sort
    end
  end
end
