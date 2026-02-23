# frozen_string_literal: true

require 'yaml'
require 'json'
require_relative 'config'

module Rufio
  class ConfigLoader
    # 新しいパス定数（Configから取得）
    CONFIG_PATH = Config::CONFIG_RB_PATH
    SCRIPT_PATHS_YML = Config::SCRIPT_PATHS_YML
    BOOKMARKS_YML = Config::BOOKMARKS_YML

    # 後方互換性のためのパス（非推奨）
    YAML_CONFIG_PATH = Config::YAML_CONFIG_PATH
    LOCAL_YAML_PATH = Config::LOCAL_YAML_PATH

    class << self
      def load_config
        @config ||= if File.exist?(CONFIG_PATH)
                      load_config_file
                    else
                      default_config
                    end
      end

      def reload_config!
        @config = nil
        @script_paths = nil
        load_config
      end

      def applications
        load_config[:applications]
      end

      def colors
        load_config[:colors]
      end

      # デフォルトキーバインド（全アクションの単一キー定義）
      def default_keybinds
        {
          # ナビゲーション
          move_up:         'k',
          move_down:       'j',
          navigate_parent: 'h',
          navigate_enter:  'l',
          top:             'g',
          bottom:          'G',
          refresh:         'R',
          # ファイル操作
          open_file:       'o',
          rename:          'r',
          delete:          'd',
          create_file:     'a',
          create_dir:      'A',
          move_selected:   'm',
          copy_selected:   'c',
          delete_selected: 'x',
          open_explorer:   'e',
          # 選択・検索
          select:          ' ',
          filter:          'f',
          fzf_search:      's',
          fzf_search_alt:  '/',
          rga_search:      'F',
          # ブックマーク
          add_bookmark:    'b',
          bookmark_menu:   'B',
          zoxide:          'z',
          start_dir:       '0',
          # モード・ツール
          job_mode:        'J',
          help:            '?',
          log_viewer:      'L',
          command_mode:    ':',
          quit:            'q'
        }.freeze
      end

      # デフォルトUI設定
      def default_ui_options
        {
          panel_ratio:     0.5,   # 左パネル幅比率（0.3〜0.7）
          preview_enabled: true   # ファイルプレビューのON/OFF
        }.freeze
      end

      # UI設定（デフォルト＋ユーザー設定のマージ）
      def ui_options
        user_opts = load_config[:ui_options] || {}
        default_ui_options.merge(user_opts)
      end

      def keybinds
        raw_user_keybinds = load_config[:keybinds] || {}
        # 新フォーマット（単一文字列値）のみ受け入れ、古いフォーマット（配列値）は無視
        user_keybinds = raw_user_keybinds.select { |_, v| v.is_a?(String) }
        default_keybinds.merge(user_keybinds)
      end

      def language
        load_config[:language] || Config.current_language
      end

      def set_language(lang)
        Config.current_language = lang
        if @config
          @config[:language] = lang
        end
      end

      def message(key, **interpolations)
        Config.message(key, **interpolations)
      end

      def scripts_dir
        load_config[:scripts_dir] || default_scripts_dir
      end

      def default_scripts_dir
        File.expand_path('~/.config/rufio/scripts')
      end

      def command_history_size
        load_config[:command_history_size] || 1000
      end

      # スクリプトパスの配列を取得（ローカル > ユーザー設定の優先順位でマージ）
      # @return [Array<String>] 展開済みのスクリプトパス
      def script_paths
        @script_paths ||= load_merged_script_paths
      end

      # デフォルトのスクリプトパス
      # @return [Array<String>] デフォルトパス
      def default_script_paths
        [File.expand_path('~/.config/rufio/scripts')]
      end

      # スクリプトパスを展開
      # @param paths [Array<String>] パスの配列
      # @return [Array<String>] 展開済みのパス
      def expand_script_paths(paths)
        paths.map { |p| File.expand_path(p) }
      end

      # スクリプトパスを追加
      # @param path [String] 追加するパス
      # @return [Boolean] 追加成功したか
      def add_script_path(path)
        expanded = File.expand_path(path)
        current = script_paths
        return false if current.include?(expanded)

        save_script_paths_to_yaml(current + [expanded])
        @script_paths = nil
        true
      end

      # スクリプトパスを削除
      # @param path [String] 削除するパス
      # @return [Boolean] 削除成功したか
      def remove_script_path(path)
        expanded = File.expand_path(path)
        current = script_paths
        return false unless current.include?(expanded)

        save_script_paths_to_yaml(current - [expanded])
        @script_paths = nil
        true
      end

      # YAML設定ファイルを読み込む（Config経由）
      # @param path [String, nil] 設定ファイルのパス（nilの場合はデフォルト）
      # @return [Hash] 設定内容
      def load_yaml_config(path = nil)
        config_path = path || YAML_CONFIG_PATH
        Config.load_yaml_config(config_path)
      end

      # ブックマークを読み込む（新形式: bookmarks.yml）
      # @return [Array<Hash>] ブックマークの配列
      def load_bookmarks
        # 新形式を優先
        bookmarks = Config.load_bookmarks_from_yml(BOOKMARKS_YML)
        return bookmarks unless bookmarks.empty?

        # 後方互換: 古いconfig.ymlから読み込み
        yaml_config = load_yaml_config
        filter_valid_bookmarks(yaml_config[:bookmarks] || [])
      end

      # ブックマークを保存（新形式: bookmarks.yml）
      # @param bookmarks [Array<Hash>] ブックマークの配列
      # @return [Boolean] 保存成功したか
      def save_bookmarks(bookmarks)
        Config.save_bookmarks_to_yml(BOOKMARKS_YML, bookmarks)
        true
      rescue StandardError => e
        warn "Failed to save bookmarks: #{e.message}"
        false
      end

      # ブックマークストレージを取得
      # @return [YamlBookmarkStorage] ブックマークストレージ
      def bookmark_storage
        @bookmark_storage ||= YamlBookmarkStorage.new(BOOKMARKS_YML)
      end

      # 古いconfig.ymlからのマイグレーション
      def migrate_bookmarks_if_needed
        # 新形式が存在する場合はスキップ
        return if File.exist?(BOOKMARKS_YML)
        return unless File.exist?(YAML_CONFIG_PATH)

        Config.migrate_from_config_yml(YAML_CONFIG_PATH, SCRIPT_PATHS_YML, BOOKMARKS_YML)
      end

      private

      # マージされたスクリプトパスを読み込む
      # @return [Array<String>] マージされたスクリプトパス
      def load_merged_script_paths
        paths = []
        seen = Set.new

        # ローカル設定（優先）
        if File.exist?(LOCAL_YAML_PATH)
          local_config = load_yaml_config(LOCAL_YAML_PATH)
          local_paths = local_config[:script_paths] || []
          add_unique_paths(paths, seen, expand_script_paths(local_paths))
        end

        # 新形式: script_paths.yml から読み込み
        script_paths_from_yml = Config.load_script_paths(SCRIPT_PATHS_YML)
        add_unique_paths(paths, seen, script_paths_from_yml)

        # 後方互換: 古いconfig.ymlから読み込み
        if paths.empty?
          user_config = load_yaml_config
          user_paths = user_config[:script_paths] || []
          add_unique_paths(paths, seen, expand_script_paths(user_paths))
        end

        # デフォルトパス（何も設定されていない場合）
        if paths.empty?
          add_unique_paths(paths, seen, default_script_paths)
        end

        paths
      end

      # ユニークなパスを追加
      def add_unique_paths(paths, seen, new_paths)
        new_paths.each do |path|
          expanded = File.expand_path(path)
          next if seen.include?(expanded)

          seen.add(expanded)
          paths << expanded
        end
      end

      # スクリプトパスをYAMLに保存（新形式: script_paths.yml）
      def save_script_paths_to_yaml(paths)
        Config.save_script_paths(SCRIPT_PATHS_YML, paths)
      end

      # YAMLファイルにセクションを保存（Config経由）
      def save_to_yaml(key, value)
        Config.save_yaml_config(YAML_CONFIG_PATH, key, value)
      end

      def filter_valid_bookmarks(bookmarks)
        return [] unless bookmarks.is_a?(Array)

        bookmarks.select do |b|
          b.is_a?(Hash) && b[:path] && b[:name]
        end
      end

      def load_config_file
        load CONFIG_PATH
        config = {
          applications: safe_const_get(:APPLICATIONS, default_config[:applications]),
          colors: safe_const_get(:COLORS, default_config[:colors]),
          keybinds: safe_const_get(:KEYBINDS, {})
        }

        if Object.const_defined?(:LANGUAGE)
          language = Object.const_get(:LANGUAGE)
          config[:language] = language
          Config.current_language = language if Config.available_languages.include?(language.to_s)
        end

        if Object.const_defined?(:SCRIPTS_DIR)
          config[:scripts_dir] = Object.const_get(:SCRIPTS_DIR)
        end

        if Object.const_defined?(:COMMAND_HISTORY_SIZE)
          config[:command_history_size] = Object.const_get(:COMMAND_HISTORY_SIZE)
        end

        if Object.const_defined?(:UI_OPTIONS)
          config[:ui_options] = safe_const_get(:UI_OPTIONS, {})
        end

        config
      rescue StandardError => e
        warn "Failed to load config file: #{e.message}"
        warn 'Using default configuration'
        default_config
      end

      def safe_const_get(name, default)
        Object.const_defined?(name) ? Object.const_get(name) : default
      end

      def default_config
        {
          applications: {
            %w[txt md rb py js html css json xml yaml yml] => 'code',
            %w[jpg jpeg png gif bmp svg webp] => 'open',
            %w[mp4 avi mkv mov wmv] => 'open',
            %w[pdf] => 'open',
            %w[doc docx xls xlsx ppt pptx] => 'open',
            :default => 'open'
          },
          colors: {
            directory: { hsl: [220, 80, 60] },
            file: { hsl: [0, 0, 90] },
            executable: { hsl: [120, 70, 50] },
            selected: { hsl: [50, 90, 70] },
            preview: { hsl: [180, 60, 65] }
          },
          keybinds: {},    # ユーザーの上書きのみ格納（デフォルトはdefault_keybindsを参照）
          ui_options: {}   # ユーザーの上書きのみ格納（デフォルトはdefault_ui_optionsを参照）
        }
      end
    end
  end
end
