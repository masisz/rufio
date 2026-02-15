# frozen_string_literal: true

module Rufio
  # 閲覧中ディレクトリのスクリプトファイルを検出するスキャナー
  # カレントディレクトリ直下のスクリプトファイル（.sh, .rb, .py等）を検出し、
  # コマンドモードから @script.sh 形式で実行可能にする
  class LocalScriptScanner
    # サポートするスクリプト拡張子
    SUPPORTED_EXTENSIONS = %w[.sh .rb .py .pl .js .ts .ps1].freeze

    # @param directory [String, nil] スキャン対象ディレクトリ
    def initialize(directory = nil)
      @directory = directory
      @scripts_cache = nil
    end

    # ディレクトリ変更時にキャッシュを無効化
    # @param directory [String] 新しいディレクトリ
    def update_directory(directory)
      return if @directory == directory

      @directory = directory
      @scripts_cache = nil
    end

    # 利用可能なスクリプト一覧を取得
    # @return [Array<Hash>] スクリプト情報の配列 [{ name:, path:, dir: }, ...]
    def available_scripts
      @scripts_cache ||= scan_scripts
    end

    # 名前でスクリプトを検索
    # @param name [String] スクリプト名（拡張子あり/なし）
    # @return [Hash, nil] スクリプト情報 { name:, path:, dir: } または nil
    def find_script(name)
      # 完全一致を優先
      script = available_scripts.find { |s| s[:name] == name }
      return script if script

      # 拡張子なしで検索
      SUPPORTED_EXTENSIONS.each do |ext|
        script = available_scripts.find { |s| s[:name] == "#{name}#{ext}" }
        return script if script
      end

      nil
    end

    # Tab補完候補を取得
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] 補完候補のスクリプト名
    def complete(prefix)
      available_scripts
        .map { |s| s[:name] }
        .select { |name| name.start_with?(prefix) }
        .sort
    end

    private

    # ディレクトリをスキャンしてスクリプトファイルを収集
    # @return [Array<Hash>] スクリプト情報の配列
    def scan_scripts
      return [] unless @directory && Dir.exist?(@directory)

      scripts = []

      Dir.foreach(@directory) do |entry|
        next if entry.start_with?('.')
        path = File.join(@directory, entry)
        next unless File.file?(path)
        next unless script_file?(entry)

        scripts << {
          name: entry,
          path: path,
          dir: @directory
        }
      end

      scripts.sort_by { |s| s[:name] }
    end

    # スクリプトファイルかどうかを判定
    # @param filename [String] ファイル名
    # @return [Boolean]
    def script_file?(filename)
      ext = File.extname(filename).downcase
      SUPPORTED_EXTENSIONS.include?(ext)
    end
  end
end
