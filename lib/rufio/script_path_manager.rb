# frozen_string_literal: true

require 'yaml'

module Rufio
  # スクリプトパスを管理するクラス
  # 設定ファイルからパスを読み込み、スクリプト名で解決する
  class ScriptPathManager
    attr_reader :paths

    # サポートするスクリプト拡張子
    SUPPORTED_EXTENSIONS = %w[.sh .rb .py .pl .js .ts .ps1].freeze

    # 履歴の最大サイズ
    MAX_HISTORY_SIZE = 100

    # @param config_path [String] 設定ファイルのパス
    def initialize(config_path)
      @config_path = config_path
      @config = load_config
      @paths = expand_paths(@config['script_paths'] || [])
      @cache = {}
      @scripts_cache = nil
      @execution_history = []
      @execution_count = Hash.new(0)
    end

    # スクリプト名で解決
    # @param command_name [String] スクリプト名（拡張子あり/なし）
    # @return [String, nil] スクリプトのフルパス、見つからない場合はnil
    def resolve(command_name)
      # キャッシュをチェック
      return @cache[command_name] if @cache.key?(command_name)

      scripts = find_scripts(command_name)

      case scripts.size
      when 0
        nil
      when 1
        @cache[command_name] = scripts.first
      else
        # 複数見つかった場合は最初のものを返す（on_multiple_match: 'first'）
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

    # --- Phase 4: 複数マッチ ---

    # すべてのマッチを取得（複数マッチ対応）
    # @param command_name [String] コマンド名
    # @return [Array<String>] マッチしたスクリプトのパス
    def find_all_matches(command_name)
      find_scripts_all_paths(command_name)
    end

    # --- Phase 4: タブ補完 ---

    # スクリプト名を補完
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] 補完候補（拡張子なし）
    def complete(prefix)
      scripts = all_scripts
      return scripts if prefix.empty?

      scripts.select { |name| name.downcase.start_with?(prefix.downcase) }
    end

    # --- Phase 4: fuzzy matching ---

    # fuzzy matchingで候補を取得
    # @param query [String] 検索クエリ
    # @return [Array<String>] マッチしたスクリプト名
    def fuzzy_match(query)
      return all_scripts if query.empty?

      scripts = all_scripts
      query_chars = query.downcase.chars

      # スコア計算してソート
      scored = scripts.map do |name|
        score = fuzzy_score(name.downcase, query_chars)
        [name, score]
      end

      # スコアが0より大きいものをスコア降順で返す
      scored.select { |_, score| score > 0 }
            .sort_by { |_, score| -score }
            .map { |name, _| name }
    end

    # --- Phase 4: キャッシュ ---

    # キャッシュを無効化（public）
    def invalidate_cache
      @cache.clear
      @scripts_cache = nil
    end

    # --- Phase 4: 実行履歴 ---

    # 実行を記録
    # @param script_name [String] スクリプト名
    def record_execution(script_name)
      # 履歴の先頭に追加
      @execution_history.unshift(script_name)
      @execution_history = @execution_history.take(MAX_HISTORY_SIZE)

      # カウントを増やす
      @execution_count[script_name] += 1
    end

    # 実行履歴を取得
    # @return [Array<String>] 最近実行したスクリプト名（新しい順）
    def execution_history
      @execution_history.dup
    end

    # 実行頻度順にスクリプトを取得
    # @return [Array<String>] スクリプト名（頻度順）
    def scripts_by_frequency
      scripts = all_scripts
      scripts.sort_by { |name| -@execution_count[name] }
    end

    # --- セクション9: エラーハンドリング ---

    # 類似スクリプトの候補を取得
    # @param query [String] 検索クエリ（typoを含む可能性あり）
    # @return [Array<String>] 類似スクリプト名
    def suggest(query)
      scripts = all_scripts
      return [] if scripts.empty?

      # レーベンシュタイン距離でソート
      scored = scripts.map do |name|
        distance = levenshtein_distance(query.downcase, name.downcase)
        [name, distance]
      end

      # 距離が3以下のものを距離順で返す
      scored.select { |_, dist| dist <= 3 }
            .sort_by { |_, dist| dist }
            .map { |name, _| name }
    end

    # ファイルが実行可能かどうかをチェック
    # @param path [String] ファイルパス
    # @return [Boolean]
    def executable?(path)
      return false unless File.exist?(path)

      File.executable?(path)
    end

    # ファイルに実行権限を付与
    # @param path [String] ファイルパス
    # @return [Boolean] 成功した場合true
    def fix_permissions(path)
      return false unless File.exist?(path)

      current_mode = File.stat(path).mode
      new_mode = current_mode | 0111  # 実行権限を追加
      File.chmod(new_mode, path)
      true
    rescue StandardError
      false
    end

    private

    # 設定ファイルを読み込む
    # @return [Hash] 設定内容
    def load_config
      return {} unless File.exist?(@config_path)

      yaml = YAML.safe_load(File.read(@config_path), symbolize_names: false)
      yaml || {}
    rescue StandardError => e
      warn "Failed to load config: #{e.message}"
      {}
    end

    # 設定ファイルを保存
    def save_config
      @config['script_paths'] = @paths
      File.write(@config_path, YAML.dump(@config))
    end

    # パスを展開（チルダ展開）
    # @param paths [Array<String>] パスの配列
    # @return [Array<String>] 展開済みのパス
    def expand_paths(paths)
      paths.map { |p| File.expand_path(p) }
    end

    # スクリプトを検索
    # @param command_name [String] コマンド名
    # @return [Array<String>] 見つかったスクリプトのパス
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
            # 拡張子付きで完全一致
            scripts << file if file_basename.downcase == command_name.downcase
          else
            # 拡張子なしで比較
            file_name_without_ext = File.basename(file, '.*')
            scripts << file if file_name_without_ext.downcase == basename_without_ext.downcase
          end
        end

        # 最初のパスで見つかったらそれを優先（on_multiple_match: 'first'相当）
        return scripts unless scripts.empty?
      end

      scripts
    end

    # 実行可能なスクリプトかどうかを判定
    # @param path [String] ファイルパス
    # @return [Boolean]
    def executable_script?(path)
      ext = File.extname(path).downcase
      return true if SUPPORTED_EXTENSIONS.include?(ext)

      File.executable?(path)
    end

    # すべてのパスからスクリプトを検索（最初のパスで止まらない）
    # @param command_name [String] コマンド名
    # @return [Array<String>] 見つかったスクリプトのパス
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

    # レーベンシュタイン距離を計算
    # @param s1 [String] 文字列1
    # @param s2 [String] 文字列2
    # @return [Integer] 編集距離
    def levenshtein_distance(s1, s2)
      m = s1.length
      n = s2.length
      return n if m == 0
      return m if n == 0

      # 動的計画法でテーブルを構築
      d = Array.new(m + 1) { Array.new(n + 1, 0) }

      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }

      (1..m).each do |i|
        (1..n).each do |j|
          cost = s1[i - 1] == s2[j - 1] ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,      # 削除
            d[i][j - 1] + 1,      # 挿入
            d[i - 1][j - 1] + cost # 置換
          ].min
        end
      end

      d[m][n]
    end

    # fuzzy matchingのスコアを計算
    # @param text [String] 対象テキスト
    # @param query_chars [Array<String>] クエリの文字配列
    # @return [Integer] スコア（マッチしない場合は0）
    def fuzzy_score(text, query_chars)
      score = 0
      text_index = 0

      query_chars.each do |char|
        # テキスト内で文字を探す
        found_index = text.index(char, text_index)
        return 0 unless found_index  # マッチしない場合は0

        # 連続していればボーナス
        if found_index == text_index
          score += 2
        else
          score += 1
        end

        # 単語の先頭ならボーナス
        if found_index == 0 || text[found_index - 1] == '_' || text[found_index - 1] == '-'
          score += 1
        end

        text_index = found_index + 1
      end

      score
    end
  end
end
