# frozen_string_literal: true

require 'fileutils'

module Rufio
  class Application
    # Error display constants
    BACKTRACE_LINES = 5  # Number of backtrace lines to show

    def initialize(start_directory = Dir.pwd)
      @start_directory = File.expand_path(start_directory)
      # Load configuration including language settings
      ConfigLoader.load_config
    end

    def run(test_mode: false)
      # 各コンポーネントを初期化
      directory_listing = DirectoryListing.new(@start_directory)
      keybind_handler = KeybindHandler.new
      file_preview = FilePreview.new
      terminal_ui = TerminalUI.new(test_mode: test_mode)

      # バックグラウンドコマンド実行用の設定
      log_dir = File.join(Dir.home, '.config', 'rufio', 'log')
      FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
      command_logger = CommandLogger.new(log_dir)
      background_executor = BackgroundCommandExecutor.new(command_logger)

      # アプリケーション開始
      terminal_ui.start(directory_listing, keybind_handler, file_preview, background_executor)
    rescue Interrupt
      puts "\n\n#{ConfigLoader.message('app.interrupted')}"
    rescue StandardError => e
      puts "\n#{ConfigLoader.message('app.error_occurred')}: #{e.message}"
      puts e.backtrace.first(BACKTRACE_LINES).join("\n")
    end
  end
end

