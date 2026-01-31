# frozen_string_literal: true

require 'yaml'
require_relative 'config'

module Rufio
  # スクリプトパスを管理するクラス
  # 設定ファイルからパスを読み込み、スクリプト名で解決する
  class ScriptPathManager
    attr_reader :paths

    # サポートするスクリプト拡張子
    SUPPORTED_EXTENSIONS = %w[.sh .rb .py .pl .js .ts .ps1].freeze

    # 履歴の最大サイズ
    MAX_HISTORY_SIZE = 100

    # @param config_path [String] 設定ファイルのパス（script_paths.yml または config.yml）
    def initialize(config_path = nil)
      @config_path = config_path || Config::SCRIPT_PATHS_YML
      @paths = load_paths_from_config
      @cache = {}
      @scripts_cache = nil
      @execution_history = []
      @execution_count = Hash.new(0)
    end

    private

    # 設定ファイルからパスを読み込む（新旧形式対応）
    def load_paths_from_config
      # 新形式: script_paths.yml（リスト形式）
      if @config_path.end_with?('script_paths.yml')
        return Config.load_script_paths(@config_path)
      end

      # 後方互換: 古いconfig.yml形式
      return [] unless File.exist?(@config_path)

      yaml = YAML.safe_load(File.read(@config_path), symbolize_names: false)
      return [] unless yaml.is_a?(Hash)

      paths = yaml['script_paths'] || []
      paths.map { |p| File.expand_path(p) }
    rescue StandardError
      []
    end

    public

    # スクリプト名で解決
    # @param command_name [String] スクリプト名（拡張子あり/なし）
    # @return [String, nil] スクリプトのフルパス、見つからない場合はnil
    def resolve(command_name)
      return @cache[command_name] if @cache.key?(command_name)

      scripts = find_scripts(command_name)

      case scripts.size
      when 0
        nil
      when 1
        @cache[command_name] = scripts.first
      else
        @cache[command_name] = scripts.first
      end
    end

    # 全スクリプト一覧を取得（タブ補完用）
    # @return [Array<String>] スクリプト名（拡張子なし）の配列
    def all_scripts
      scripts = []
      seen = Set.new

      @paths.each do |path|
        next unless Dir.exist?(path)

        Dir.glob(File.join(path, '*')).each do |file|
          next unless File.file?(file)

          basename = File.basename(file)
          next if basename.start_with?('.')
          next unless executable_script?(file)

          name = File.basename(file, '.*')
          next if seen.include?(name)

          seen.add(name)
          scripts << name
        end
      end

      scripts.sort
    end

    # パスを追加
    # @param path [String] 追加するディレクトリパス
    # @return [Boolean] 追加成功した場合true、重複の場合false
    def add_path(path)
      expanded_path = File.expand_path(path)
      return false if @paths.include?(expanded_path)

      @paths << expanded_path
      save_config
      invalidate_cache
      true
    end

    # パスを削除
    # @param path [String] 削除するディレクトリパス
    # @return [Boolean] 削除成功した場合true
    def remove_path(path)
      expanded_path = File.expand_path(path)
      result = @paths.delete(expanded_path)
      if result
        save_config
        invalidate_cache
      end
      !!result
    end

    # すべてのマッチを取得（複数マッチ対応）
    def find_all_matches(command_name)
      find_scripts_all_paths(command_name)
    end

    # スクリプト名を補完
    def complete(prefix)
      scripts = all_scripts
      return scripts if prefix.empty?

      scripts.select { |name| name.downcase.start_with?(prefix.downcase) }
    end

    # fuzzy matchingで候補を取得
    def fuzzy_match(query)
      return all_scripts if query.empty?

      scripts = all_scripts
      query_chars = query.downcase.chars

      scored = scripts.map do |name|
        score = fuzzy_score(name.downcase, query_chars)
        [name, score]
      end

      scored.select { |_, score| score > 0 }
            .sort_by { |_, score| -score }
            .map { |name, _| name }
    end

    # キャッシュを無効化
    def invalidate_cache
      @cache.clear
      @scripts_cache = nil
    end

    # 実行を記録
    def record_execution(script_name)
      @execution_history.unshift(script_name)
      @execution_history = @execution_history.take(MAX_HISTORY_SIZE)
      @execution_count[script_name] += 1
    end

    # 実行履歴を取得
    def execution_history
      @execution_history.dup
    end

    # 実行頻度順にスクリプトを取得
    def scripts_by_frequency
      scripts = all_scripts
      scripts.sort_by { |name| -@execution_count[name] }
    end

    # 類似スクリプトの候補を取得
    def suggest(query)
      scripts = all_scripts
      return [] if scripts.empty?

      scored = scripts.map do |name|
        distance = levenshtein_distance(query.downcase, name.downcase)
        [name, distance]
      end

      scored.select { |_, dist| dist <= 3 }
            .sort_by { |_, dist| dist }
            .map { |name, _| name }
    end

    # ファイルが実行可能かどうかをチェック
    def executable?(path)
      return false unless File.exist?(path)

      File.executable?(path)
    end

    # ファイルに実行権限を付与
    def fix_permissions(path)
      return false unless File.exist?(path)

      current_mode = File.stat(path).mode
      new_mode = current_mode | 0111
      File.chmod(new_mode, path)
      true
    rescue StandardError
      false
    end

    private

    # 設定ファイルにスクリプトパスを保存（新旧形式対応）
    def save_config
      # 新形式: script_paths.yml
      if @config_path.end_with?('script_paths.yml')
        Config.save_script_paths(@config_path, @paths)
        return
      end

      # 後方互換: 古いconfig.yml形式
      existing = if File.exist?(@config_path)
                   YAML.safe_load(File.read(@config_path), symbolize_names: false) || {}
                 else
                   {}
                 end
      existing['script_paths'] = @paths
      FileUtils.mkdir_p(File.dirname(@config_path))
      File.write(@config_path, YAML.dump(existing))
    end

    def expand_paths(paths)
      paths.map { |p| File.expand_path(p) }
    end

    def find_scripts(command_name)
      scripts = []
      basename_without_ext = command_name.sub(/\.[^.]+$/, '')
      has_extension = command_name.include?('.')

      @paths.each do |path|
        next unless Dir.exist?(path)

        Dir.glob(File.join(path, '*')).each do |file|
          next unless File.file?(file)

          file_basename = File.basename(file)
          next if file_basename.start_with?('.')
          next unless executable_script?(file)

          if has_extension
            scripts << file if file_basename.downcase == command_name.downcase
          else
            file_name_without_ext = File.basename(file, '.*')
            scripts << file if file_name_without_ext.downcase == basename_without_ext.downcase
          end
        end

        return scripts unless scripts.empty?
      end

      scripts
    end

    def executable_script?(path)
      ext = File.extname(path).downcase
      return true if SUPPORTED_EXTENSIONS.include?(ext)

      File.executable?(path)
    end

    def find_scripts_all_paths(command_name)
      scripts = []
      basename_without_ext = command_name.sub(/\.[^.]+$/, '')
      has_extension = command_name.include?('.')

      @paths.each do |path|
        next unless Dir.exist?(path)

        Dir.glob(File.join(path, '*')).each do |file|
          next unless File.file?(file)

          file_basename = File.basename(file)
          next if file_basename.start_with?('.')
          next unless executable_script?(file)

          if has_extension
            scripts << file if file_basename.downcase == command_name.downcase
          else
            file_name_without_ext = File.basename(file, '.*')
            scripts << file if file_name_without_ext.downcase == basename_without_ext.downcase
          end
        end
      end

      scripts
    end

    def levenshtein_distance(s1, s2)
      m = s1.length
      n = s2.length
      return n if m == 0
      return m if n == 0

      d = Array.new(m + 1) { Array.new(n + 1, 0) }

      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }

      (1..m).each do |i|
        (1..n).each do |j|
          cost = s1[i - 1] == s2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,
            d[i][j - 1] + 1,
            d[i - 1][j - 1] + cost
          ].min
        end
      end

      d[m][n]
    end

    def fuzzy_score(text, query_chars)
      score = 0
      text_index = 0

      query_chars.each do |char|
        found_index = text.index(char, text_index)
        return 0 unless found_index

        if found_index == text_index
          score += 2
        else
          score += 1
        end

        if found_index == 0 || text[found_index - 1] == '_' || text[found_index - 1] == '-'
          score += 1
        end

        text_index = found_index + 1
      end

      score
    end
  end
end
