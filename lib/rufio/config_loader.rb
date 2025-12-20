# frozen_string_literal: true

require_relative 'config'

module Rufio
  class ConfigLoader
    CONFIG_PATH = File.expand_path('~/.config/rufio/config.rb').freeze

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

