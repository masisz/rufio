# frozen_string_literal: true

module Rufio
  class Application
    # Error display constants
    BACKTRACE_LINES = 5  # Number of backtrace lines to show

    def initialize(start_directory = Dir.pwd)
      @start_directory = File.expand_path(start_directory)
      # Load configuration including language settings
      ConfigLoader.load_config
    end

    def run
      # 各コンポーネントを初期化
      directory_listing = DirectoryListing.new(@start_directory)
      keybind_handler = KeybindHandler.new
      file_preview = FilePreview.new
      terminal_ui = TerminalUI.new

      # アプリケーション開始
      terminal_ui.start(directory_listing, keybind_handler, file_preview)
    rescue Interrupt
      puts "\n\n#{ConfigLoader.message('app.interrupted')}"
    rescue StandardError => e
      puts "\n#{ConfigLoader.message('app.error_occurred')}: #{e.message}"
      puts e.backtrace.first(BACKTRACE_LINES).join("\n")
    end
  end
end

