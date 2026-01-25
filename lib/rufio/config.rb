# frozen_string_literal: true

module Rufio
  class Config
    # Default language settings
    DEFAULT_LANGUAGE = 'en'
    AVAILABLE_LANGUAGES = %w[en ja].freeze

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

      private

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
