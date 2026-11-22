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
    # 1.6.0 で改名したアクション（旧名 => 新名）。ユーザー設定の旧名も受け付ける
    LEGACY_KEYBIND_ACTIONS = { fzf_search: :file_search, fzf_search_alt: :file_search_alt }.freeze
    # s / / の一覧キャッシュ（FuzzyCandidateCache）。FUZZY_SEARCH_CACHE で MAX_FUZZY_SEARCH_CACHE まで変更できる
    DEFAULT_FUZZY_SEARCH_CACHE = { max_entries: 200_000, max_roots: 4, ttl: 300 }.freeze
    MAX_FUZZY_SEARCH_CACHE = { max_entries: 1_000_000, max_roots: 16, ttl: 86_400 }.freeze

    # 表プレビュー（CSV / TSV, 将来は Excel / SQLite）の読み込み上限と表示設定
    DEFAULT_TABLE_PREVIEW = {
      max_bytes: 64 * 1024, max_rows: 1000, max_columns: 256, max_column_width: 32
    }.freeze
    MIN_TABLE_PREVIEW = {
      max_bytes: 1024, max_rows: 1, max_columns: 1, max_column_width: 3
    }.freeze
    MAX_TABLE_PREVIEW = {
      max_bytes: 1024 * 1024, max_rows: 100_000, max_columns: 4096, max_column_width: 200
    }.freeze

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
          bottom:          '}',
          refresh:         'R',
          # ファイル操作
          open_file:       'o',
          preview:         'P',
          rename:          'r',
          delete:          'd',
          create_file:     'a',
          create_dir:      'A',
          move_selected:   'm',
          copy_selected:   'c',
          copy_to_clipboard: 'y',
          delete_selected: 'x',
          open_explorer:   'e',
          # 選択・検索
          select:          ' ',
          filter:          'f',
          file_search:     's',
          file_search_alt: '/',
          rga_search:      'F',
          # ブックマーク
          add_bookmark:    'b',
          bookmark_menu:   'B',
          zoxide:          'z',
          start_dir:       '0',
          # モード・ツール
          job_mode:        'J',
          global_search:   'G',
          config_mode:     'C',
          help:            '?',
          log_viewer:      'L',
          command_mode:    ':',
          quit:            'q',
          quit_cd:         'T'
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
        # 旧アクション名は新しい名前の別名として扱う（新しい名前の指定を優先）
        legacy = user_keybinds.select { |action, _| LEGACY_KEYBIND_ACTIONS.key?(action) }
        current = user_keybinds.reject { |action, _| LEGACY_KEYBIND_ACTIONS.key?(action) }
        renamed = legacy.each_with_object({}) { |(action, key), map| map[LEGACY_KEYBIND_ACTIONS[action]] = key }
        default_keybinds.merge(renamed).merge(current)
      end

      # クリップボードへコピーするコマンド（文字列または argv 配列）。
      # 未設定なら OS ごとの既定コマンド → OSC 52 の順で試す。
      def clipboard_command
        value = load_config[:clipboard_command]
        return value if value.is_a?(String) && !value.empty?
        return value if value.is_a?(Array) && value.all? { |item| item.is_a?(String) } && !value.empty?

        nil
      end

      # 表プレビュー設定（整数は min..max に丸め、不正な値は既定値のまま）
      def table_preview
        values = load_config[:table_preview]
        values = {} unless values.is_a?(Hash)

        settings = DEFAULT_TABLE_PREVIEW.each_with_object({}) do |(key, default), acc|
          value = values[key]
          acc[key] = value.is_a?(Integer) ? value.clamp(MIN_TABLE_PREVIEW[key], MAX_TABLE_PREVIEW[key]) : default
        end

        settings[:header] = values[:header] != false
        settings[:delimiter] = values[:delimiter].is_a?(String) ? values[:delimiter] : 'auto'
        settings[:encoding] = values[:encoding].is_a?(String) ? values[:encoding] : 'auto'
        settings
      end

      # 0 以上の整数だけを受け付け、上限を超える値は上限に丸める。不正な値は既定値のまま
      def fuzzy_search_cache
        values = load_config[:fuzzy_search_cache]
        values = {} unless values.is_a?(Hash)
        DEFAULT_FUZZY_SEARCH_CACHE.each_with_object({}) do |(key, default), settings|
          value = values[key]
          settings[key] = value.is_a?(Integer) && value >= 0 ? [value, MAX_FUZZY_SEARCH_CACHE[key]].min : default
        end
      end

      def global_search_excluded_extensions
        values = load_config[:global_search_excluded_extensions]
        return [] unless values.is_a?(Array)

        values.select { |value| value.is_a?(String) }.map do |value|
          extension = value.strip.downcase
          next if extension.empty? || extension == '.' || extension == '/'

          extension.start_with?('.', '/') ? extension : ".#{extension}"
        end.compact.uniq
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

      def filter_valid_bookmarks(bookmarks)
        Config.filter_valid_bookmarks(bookmarks)
      end

      def load_config_file
        load CONFIG_PATH
        config = {
          applications: safe_const_get(:APPLICATIONS, default_config[:applications]),
          colors: safe_const_get(:COLORS, default_config[:colors]),
          keybinds: safe_const_get(:KEYBINDS, {}),
          global_search_excluded_extensions: safe_const_get(:GLOBAL_SEARCH_EXCLUDED_EXTENSIONS, []),
          fuzzy_search_cache: safe_const_get(:FUZZY_SEARCH_CACHE, {}),
          table_preview: safe_const_get(:TABLE_PREVIEW, {}),
          clipboard_command: safe_const_get(:CLIPBOARD_COMMAND, nil)
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
          global_search_excluded_extensions: [],
          keybinds: {},      # ユーザーの上書きのみ格納（デフォルトはdefault_keybindsを参照）
          ui_options: {},    # ユーザーの上書きのみ格納（デフォルトはdefault_ui_optionsを参照）
          table_preview: {},      # ユーザーの上書きのみ格納（デフォルトはDEFAULT_TABLE_PREVIEWを参照）
          clipboard_command: nil  # 未設定なら OS 既定のコマンド → OSC 52
        }
      end
    end
  end
end
