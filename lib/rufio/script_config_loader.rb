# frozen_string_literal: true

require 'yaml'

module Rufio
  # 複数の設定ファイルからscript_pathsをロード・マージするクラス
  # 優先順位: ローカル > ユーザー > システム
  class ScriptConfigLoader
    # デフォルトの設定ファイルパス
    DEFAULT_LOCAL_PATH = './rufio.yml'
    DEFAULT_USER_PATH = File.expand_path('~/.config/rufio/config.yml')
    DEFAULT_SYSTEM_PATH = '/etc/rufio/config.yml'

    # @param local_path [String, nil] ローカル設定ファイルのパス
    # @param user_path [String, nil] ユーザー設定ファイルのパス
    # @param system_path [String, nil] システム設定ファイルのパス
    def initialize(local_path: nil, user_path: nil, system_path: nil)
      @local_path = local_path || DEFAULT_LOCAL_PATH
      @user_path = user_path || DEFAULT_USER_PATH
      @system_path = system_path || DEFAULT_SYSTEM_PATH
    end

    # マージされたscript_pathsを取得
    # @return [Array<String>] スクリプトパスの配列（優先順位順、重複なし）
    def script_paths
      paths = []
      seen = Set.new

      # 優先順位順に読み込み（ローカル > ユーザー > システム）
      [@local_path, @user_path, @system_path].each do |config_path|
        next unless config_path && File.exist?(config_path)

        config_paths = load_paths_from_file(config_path)
        config_paths.each do |path|
          expanded = File.expand_path(path)
          next if seen.include?(expanded)

          seen.add(expanded)
          paths << expanded
        end
      end

      paths
    end

    # 全設定をマージして取得
    # @return [Hash] マージされた設定
    def merged_config
      config = {}

      # 逆順で読み込み（システム < ユーザー < ローカル）
      [@system_path, @user_path, @local_path].each do |config_path|
        next unless config_path && File.exist?(config_path)

        file_config = load_config(config_path)
        config = deep_merge(config, file_config)
      end

      # script_pathsは特別処理（マージではなく優先順位付き結合）
      config['script_paths'] = script_paths
      config
    end

    private

    # 設定ファイルからscript_pathsを読み込む
    # @param path [String] 設定ファイルのパス
    # @return [Array<String>] パスの配列
    def load_paths_from_file(path)
      config = load_config(path)
      config['script_paths'] || []
    end

    # 設定ファイルを読み込む
    # @param path [String] 設定ファイルのパス
    # @return [Hash] 設定内容
    def load_config(path)
      return {} unless File.exist?(path)

      yaml = YAML.safe_load(File.read(path), symbolize_names: false)
      yaml || {}
    rescue StandardError => e
      warn "Warning: Failed to load config #{path}: #{e.message}"
      {}
    end

    # ハッシュを深くマージ
    # @param base [Hash] ベースとなるハッシュ
    # @param override [Hash] 上書きするハッシュ
    # @return [Hash] マージされたハッシュ
    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
