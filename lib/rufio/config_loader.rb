# frozen_string_literal: true

require 'yaml'
require_relative 'config'

module Rufio
  class ConfigLoader
    CONFIG_PATH = File.expand_path('~/.config/rufio/config.rb').freeze
    YAML_CONFIG_PATH = File.expand_path('~/.config/rufio/config.yml').freeze

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
        load_config
      end

      def applications
        load_config[:applications]
      end

      def colors
        load_config[:colors]
      end

      def keybinds
        load_config[:keybinds]
      end

      def language
        load_config[:language] || Config.current_language
      end

      def set_language(lang)
        Config.current_language = lang
        # Update config if it's user-defined
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

      # スクリプトパスの配列を取得
      # @return [Array<String>] 展開済みのスクリプトパス
      def script_paths
        yaml_config = load_yaml_config
        paths = yaml_config[:script_paths] || default_script_paths
        expand_script_paths(paths)
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

      # YAML設定ファイルを読み込む
      # @param path [String, nil] 設定ファイルのパス（nilの場合はデフォルト）
      # @return [Hash] 設定内容
      def load_yaml_config(path = nil)
        config_path = path || YAML_CONFIG_PATH
        return {} unless File.exist?(config_path)

        yaml = YAML.safe_load(File.read(config_path), symbolize_names: true)
        yaml || {}
      rescue StandardError => e
        warn "Failed to load YAML config: #{e.message}"
        {}
      end

      private

      def load_config_file
        # 設定ファイルを実行してグローバル定数を定義
        load CONFIG_PATH
        config = {
          applications: Object.const_get(:APPLICATIONS),
          colors: Object.const_get(:COLORS),
          keybinds: Object.const_get(:KEYBINDS)
        }

        # Load language setting if defined
        if Object.const_defined?(:LANGUAGE)
          language = Object.const_get(:LANGUAGE)
          config[:language] = language
          Config.current_language = language if Config.available_languages.include?(language.to_s)
        end

        # Load scripts directory if defined
        if Object.const_defined?(:SCRIPTS_DIR)
          config[:scripts_dir] = Object.const_get(:SCRIPTS_DIR)
        end

        # Load command history size if defined
        if Object.const_defined?(:COMMAND_HISTORY_SIZE)
          config[:command_history_size] = Object.const_get(:COMMAND_HISTORY_SIZE)
        end

        config
      rescue StandardError => e
        warn "Failed to load config file: #{e.message}"
        warn 'Using default configuration'
        default_config
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
            directory: { hsl: [220, 80, 60] },    # Blue
            file: { hsl: [0, 0, 90] },            # Light gray
            executable: { hsl: [120, 70, 50] },   # Green
            selected: { hsl: [50, 90, 70] },      # Yellow
            preview: { hsl: [180, 60, 65] }       # Cyan
          },
          keybinds: {
            quit: %w[q ESC],
            up: %w[k UP],
            down: %w[j DOWN],
            left: %w[h LEFT],
            right: %w[l RIGHT ENTER],
            top: %w[g],
            bottom: %w[G],
            refresh: %w[r],
            search: %w[/],
            open_file: %w[o SPACE]
          }
        }
      end
    end
  end
end

