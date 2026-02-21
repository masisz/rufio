# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Rufio
  class Config
    # Default language settings
    DEFAULT_LANGUAGE = 'en'
    AVAILABLE_LANGUAGES = %w[en ja].freeze

    # 設定ディレクトリとファイルパス
    CONFIG_DIR = File.expand_path('~/.config/rufio').freeze
    CONFIG_RB_PATH = File.join(CONFIG_DIR, 'config.rb').freeze
    SCRIPT_PATHS_YML = File.join(CONFIG_DIR, 'script_paths.yml').freeze
    BOOKMARKS_YML = File.join(CONFIG_DIR, 'bookmarks.yml').freeze

    # 後方互換性のためのパス（非推奨）
    YAML_CONFIG_PATH = File.join(CONFIG_DIR, 'config.yml').freeze
    LOCAL_YAML_PATH = './rufio.yml'

    # Multi-language message definitions
    MESSAGES = {
      'en' => {
        # Application messages
        'app.interrupted' => 'rufio interrupted',
        'app.error_occurred' => 'Error occurred',
        'app.terminated' => 'rufio terminated',

        # File operations
        'file.not_found' => 'File not found',
        'file.not_readable' => 'File not readable',
        'file.read_error' => 'File read error',
        'file.binary_file' => 'Binary file',
        'file.cannot_preview' => 'Cannot preview',
        'file.encoding_error' => 'Character encoding error - cannot read file',
        'file.preview_error' => 'Preview error',
        'file.error_prefix' => 'Error',

        # Keybind messages
        'keybind.invalid_key' => 'invalid key',
        'keybind.search_text' => 'Search text: ',
        'keybind.no_matches' => 'No matches found.',
        'keybind.press_any_key' => 'Press any key to continue...',
        'keybind.input_filename' => 'Enter filename: ',
        'keybind.input_dirname' => 'Enter directory name: ',
        'keybind.invalid_filename' => 'Invalid filename (cannot contain / or \\)',
        'keybind.invalid_dirname' => 'Invalid directory name (cannot contain / or \\)',
        'keybind.file_exists' => 'File already exists',
        'keybind.directory_exists' => 'Directory already exists',
        'keybind.file_created' => 'File created',
        'keybind.directory_created' => 'Directory created',
        'keybind.creation_error' => 'Creation error',

        # UI messages
        'ui.operation_prompt' => 'Operation: ',

        # Help text
        'help.full' => 'j/k:move h:back l:enter o:open g/G:top/bottom r:refresh f:filter s:search F:content a/A:create m/p/x:ops b:bookmark z:zoxide 1-9:goto q:quit',
        'help.short' => 'j/k:move h:back l:enter o:open f:filter s:search b:bookmark z:zoxide 1-9:goto q:quit',

        # Health check messages
        'health.title' => 'rufio Health Check',
        'health.ruby_version' => 'Ruby version',
        'health.required_gems' => 'Required gems',
        'health.fzf' => 'fzf (file search)',
        'health.rga' => 'rga (content search)',
        'health.zoxide' => 'zoxide (directory history)',
        'health.bat' => 'bat (syntax highlight)',
        'health.file_opener' => 'System file opener',
        'health.summary' => 'Summary:',
        'health.ok' => 'OK',
        'health.warnings' => 'Warnings',
        'health.errors' => 'Errors',
        'health.all_passed' => 'All checks passed! rufio is ready to use.',
        'health.critical_missing' => 'Some critical components are missing. rufio may not work properly.',
        'health.optional_missing' => 'Some optional features are unavailable. Basic functionality will work.',
        'health.all_gems_installed' => 'All required gems installed',
        'health.missing_gems' => 'Missing gems',
        'health.gem_install_instruction' => 'Run: gem install',
        'health.tool_not_found' => 'not found',
        'health.unknown_platform' => 'Unknown platform',
        'health.file_open_may_not_work' => 'File opening may not work properly',
        'health.macos_opener' => 'macOS file opener',
        'health.linux_opener' => 'Linux file opener',
        'health.windows_opener' => 'Windows file opener',
        'health.install_brew' => 'Install: brew install',
        'health.install_apt' => 'Install: apt install',
        'health.install_guide' => 'Check installation guide for your platform',
        'health.rga_releases' => 'Install: https://github.com/phiresky/ripgrep-all/releases',
        'health.ruby_upgrade_needed' => 'Please upgrade Ruby to version 2.7.0 or higher'
      },

      'ja' => {
        # Application messages
        'app.interrupted' => 'rufio interrupted',
        'app.error_occurred' => 'Error occurred',
        'app.terminated' => 'rufio terminated',

        # File operations
        'file.not_found' => 'File not found',
        'file.not_readable' => 'File not readable',
        'file.read_error' => 'File read error',
        'file.binary_file' => 'Binary file',
        'file.cannot_preview' => 'Cannot preview',
        'file.encoding_error' => 'Encoding error - cannot read file',
        'file.preview_error' => 'Preview error',
        'file.error_prefix' => 'Error',

        # Keybind messages
        'keybind.invalid_key' => 'Invalid key',
        'keybind.search_text' => 'Search: ',
        'keybind.no_matches' => 'No matches found.',
        'keybind.press_any_key' => 'Press any key to continue...',
        'keybind.input_filename' => 'Enter filename: ',
        'keybind.input_dirname' => 'Enter directory name: ',
        'keybind.invalid_filename' => 'Invalid filename (cannot contain / or \\)',
        'keybind.invalid_dirname' => 'Invalid directory name (cannot contain / or \\)',
        'keybind.file_exists' => 'File already exists',
        'keybind.directory_exists' => 'Directory already exists',
        'keybind.file_created' => 'File created',
        'keybind.directory_created' => 'Directory created',
        'keybind.creation_error' => 'Creation error',

        # UI messages
        'ui.operation_prompt' => 'Operation: ',

        # Help text
        'help.full' => 'j/k:move h:back l:enter o:open g/G:top/end r:refresh f:filter s:search F:content a/A:create m/c/x:ops b:bookmark z:zoxide 1-9:jump q:quit',
        'help.short' => 'j/k:move h:back l:enter o:open f:filter s:search b:bookmark z:zoxide 1-9:jump q:quit',

        # Health check messages
        'health.title' => 'rufio Health Check',
        'health.ruby_version' => 'Ruby version',
        'health.required_gems' => 'Required gems',
        'health.fzf' => 'fzf (file search)',
        'health.rga' => 'rga (content search)',
        'health.zoxide' => 'zoxide (directory history)',
        'health.bat' => 'bat (syntax highlight)',
        'health.file_opener' => 'System file opener',
        'health.summary' => 'Summary:',
        'health.ok' => 'OK',
        'health.warnings' => 'Warnings',
        'health.errors' => 'Errors',
        'health.all_passed' => 'All checks passed! rufio is ready to use.',
        'health.critical_missing' => 'Critical components missing. rufio may not work properly.',
        'health.optional_missing' => 'Optional features unavailable. Basic features will work.',
        'health.all_gems_installed' => 'All required gems are installed',
        'health.missing_gems' => 'Missing gems',
        'health.gem_install_instruction' => 'Run: gem install',
        'health.tool_not_found' => 'not found',
        'health.unknown_platform' => 'Unknown platform',
        'health.file_open_may_not_work' => 'File open may not work properly',
        'health.macos_opener' => 'macOS file opener',
        'health.linux_opener' => 'Linux file opener',
        'health.windows_opener' => 'Windows file opener',
        'health.install_brew' => 'Install: brew install',
        'health.install_apt' => 'Install: apt install',
        'health.install_guide' => 'Check installation guide for your platform',
        'health.rga_releases' => 'Install: https://github.com/phiresky/ripgrep-all/releases',
        'health.ruby_upgrade_needed' => 'Please upgrade Ruby to version 2.7.0 or higher'
      }
    }.freeze

    class << self
      def current_language
        @current_language ||= detect_language
      end

      def current_language=(lang)
        if AVAILABLE_LANGUAGES.include?(lang.to_s)
          @current_language = lang.to_s
        else
          raise ArgumentError, "Unsupported language: #{lang}. Available: #{AVAILABLE_LANGUAGES.join(', ')}"
        end
      end

      def message(key, **interpolations)
        msg = MESSAGES.dig(current_language, key) || MESSAGES.dig(DEFAULT_LANGUAGE, key) || key
        
        # Simple interpolation support
        interpolations.each do |placeholder, value|
          msg = msg.gsub("%{#{placeholder}}", value.to_s)
        end
        
        msg
      end

      def available_languages
        AVAILABLE_LANGUAGES.dup
      end

      def reset_language!
        @current_language = nil
      end

      # YAML設定を取得（キャッシュあり）
      # @return [Hash] YAML設定
      def yaml_config
        @yaml_config ||= load_yaml_config(YAML_CONFIG_PATH)
      end

      # YAML設定をリロード
      def reload_yaml_config!
        @yaml_config = nil
      end

      # 全設定をリセット
      def reset_config!
        @yaml_config = nil
        @script_paths = nil
        @bookmarks = nil
      end

      # ========================================
      # script_paths.yml の操作
      # ========================================

      # スクリプトパスを読み込む
      # @param path [String] YAMLファイルのパス
      # @return [Array<String>] 展開済みのパス配列
      def load_script_paths(path = SCRIPT_PATHS_YML)
        return [] unless File.exist?(path)

        yaml = YAML.safe_load(File.read(path))
        return [] unless yaml.is_a?(Array)

        yaml.map { |p| File.expand_path(p) }
      rescue StandardError => e
        warn "Failed to load script paths: #{e.message}"
        []
      end

      # スクリプトパスを保存
      # @param path [String] YAMLファイルのパス
      # @param paths [Array<String>] パス配列
      def save_script_paths(path, paths)
        ensure_config_directory(path)
        File.write(path, YAML.dump(paths))
      end

      # スクリプトパスを追加
      # @param path [String] YAMLファイルのパス
      # @param new_path [String] 追加するパス
      def add_script_path(path, new_path)
        paths = load_script_paths(path)
        expanded = File.expand_path(new_path)
        return if paths.include?(expanded)

        paths << expanded
        save_script_paths(path, paths)
      end

      # スクリプトパスを削除
      # @param path [String] YAMLファイルのパス
      # @param remove_path [String] 削除するパス
      def remove_script_path(path, remove_path)
        paths = load_script_paths(path)
        expanded = File.expand_path(remove_path)
        paths.delete(expanded)
        save_script_paths(path, paths)
      end

      # ========================================
      # bookmarks.yml の操作
      # ========================================

      # ブックマークを読み込む
      # @param path [String] YAMLファイルのパス
      # @return [Array<Hash>] ブックマーク配列
      def load_bookmarks_from_yml(path = BOOKMARKS_YML)
        return [] unless File.exist?(path)

        yaml = YAML.safe_load(File.read(path), symbolize_names: true)
        return [] unless yaml.is_a?(Array)

        yaml.select { |b| b.is_a?(Hash) && b[:path] && b[:name] }
      rescue StandardError => e
        warn "Failed to load bookmarks: #{e.message}"
        []
      end

      # ブックマークを保存
      # @param path [String] YAMLファイルのパス
      # @param bookmarks [Array<Hash>] ブックマーク配列
      def save_bookmarks_to_yml(path, bookmarks)
        ensure_config_directory(path)
        data = bookmarks.map { |b| { 'path' => b[:path], 'name' => b[:name] } }
        File.write(path, YAML.dump(data))
      end

      # ブックマークを追加
      # @param path [String] YAMLファイルのパス
      # @param bookmark_path [String] ブックマークするパス
      # @param name [String] ブックマーク名
      def add_bookmark(path, bookmark_path, name)
        bookmarks = load_bookmarks_from_yml(path)
        bookmarks << { path: bookmark_path, name: name }
        save_bookmarks_to_yml(path, bookmarks)
      end

      # ブックマークを削除
      # @param path [String] YAMLファイルのパス
      # @param name [String] 削除するブックマーク名
      def remove_bookmark(path, name)
        bookmarks = load_bookmarks_from_yml(path)
        bookmarks.reject! { |b| b[:name] == name }
        save_bookmarks_to_yml(path, bookmarks)
      end

      # ========================================
      # config.rb (DSL) の操作
      # ========================================

      # config.rb を読み込む
      # @param path [String] config.rb のパス
      def load_config_rb(path = CONFIG_RB_PATH)
        return unless File.exist?(path)

        load path
      rescue StandardError => e
        warn "Failed to load config.rb: #{e.message}"
      end

      # ========================================
      # マイグレーション
      # ========================================

      # 古い config.yml から新形式にマイグレーション
      # @param old_config_yml [String] 古い config.yml のパス
      # @param script_paths_yml [String] 新しい script_paths.yml のパス
      # @param bookmarks_yml [String] 新しい bookmarks.yml のパス
      def migrate_from_config_yml(old_config_yml, script_paths_yml, bookmarks_yml)
        return unless File.exist?(old_config_yml)

        old_config = load_yaml_config(old_config_yml)

        # script_paths のマイグレーション
        if old_config[:script_paths].is_a?(Array) && !old_config[:script_paths].empty?
          save_script_paths(script_paths_yml, old_config[:script_paths])
        end

        # bookmarks のマイグレーション
        if old_config[:bookmarks].is_a?(Array) && !old_config[:bookmarks].empty?
          save_bookmarks_to_yml(bookmarks_yml, old_config[:bookmarks])
        end
      end

      # YAML設定ファイルを読み込む
      # @param path [String] 設定ファイルのパス
      # @return [Hash] 設定内容（シンボルキー）
      def load_yaml_config(path)
        return {} unless File.exist?(path)

        yaml = YAML.safe_load(File.read(path), symbolize_names: true)
        yaml || {}
      rescue StandardError => e
        warn "Failed to load YAML config: #{e.message}"
        {}
      end

      # YAML設定ファイルにセクションを保存
      # @param path [String] 設定ファイルのパス
      # @param key [Symbol, String] 保存するキー
      # @param value [Object] 保存する値
      def save_yaml_config(path, key, value)
        ensure_config_directory(path)

        existing = if File.exist?(path)
                     YAML.safe_load(File.read(path), symbolize_names: true) || {}
                   else
                     {}
                   end

        existing[key.to_sym] = value
        File.write(path, YAML.dump(stringify_keys(existing)))
        reload_yaml_config! if path == YAML_CONFIG_PATH
      end

      private

      def ensure_config_directory(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def stringify_keys(hash)
        hash.transform_keys(&:to_s).transform_values do |value|
          case value
          when Hash
            stringify_keys(value)
          when Array
            value.map { |v| v.is_a?(Hash) ? stringify_keys(v) : v }
          else
            value
          end
        end
      end

      def detect_language
        # Only BENIYA_LANG environment variable takes precedence
        # This ensures English is default unless explicitly requested
        env_lang = ENV['BENIYA_LANG']
        
        if env_lang && !env_lang.empty?
          # Extract language code (e.g., 'ja_JP.UTF-8' -> 'ja')
          lang_code = env_lang.split(/[_.]/).first&.downcase
          return lang_code if AVAILABLE_LANGUAGES.include?(lang_code)
        end
        
        DEFAULT_LANGUAGE
      end
    end
  end
end
