# frozen_string_literal: true

require_relative 'fuzzy_search_session'
require_relative 'rga_result_source'

module Rufio
  # 検索（内蔵ファジー検索・rga）専用コントローラ
  # 選択画面は TerminalUI の内蔵検索画面（FuzzyFinder）を使う
  class SearchController
    def initialize(directory_listing, file_opener, dialog_renderer = nil)
      @directory_listing = directory_listing
      @file_opener = file_opener
      @dialog_renderer = dialog_renderer
      @terminal_ui = nil
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
    end

    # ============================
    # 内蔵ファジー検索（s / /）
    # ============================

    # 現在のディレクトリ配下のファイルを内蔵検索画面で絞り込み、選択したファイルを開く
    def file_search
      return false unless @terminal_ui

      current_path = @directory_listing&.current_path || Dir.pwd
      session = FuzzySearchSession.new(root: current_path)
      @terminal_ui.start_fuzzy_finder(session, title: "Files: #{current_path}") do |entry|
        @file_opener.open_file(entry[:path]) if File.file?(entry[:path])
        :needs_refresh
      end
      true
    end

    # 旧アクション名（ユーザー設定の fzf_search）との互換
    alias fzf_search file_search

    # ============================
    # rga 検索（F）
    # ============================

    # rga の結果を内蔵検索画面に流し、選択した行でファイルを開く
    def rga_search
      return false unless rga_available? && @terminal_ui && @dialog_renderer

      current_path = @directory_listing&.current_path || Dir.pwd
      search_query = @dialog_renderer.show_input_dialog('Content search (rga)', ConfigLoader.message('keybind.search_text'), {
        border_color: "\e[36m",
        title_color: "\e[1;36m",
        content_color: "\e[37m"
      })
      return false if search_query.nil? || search_query.empty?

      session = FuzzySearchSession.new(source: RgaResultSource.new(search_query, current_path))
      @terminal_ui.start_fuzzy_finder(session, title: "Content: #{search_query}") do |entry|
        @file_opener.open_file_with_line(entry[:path], entry[:line_number]) if File.file?(entry[:path])
        :needs_refresh
      end
      true
    end

    def rga_available?
      system('which rga > /dev/null 2>&1')
    end
  end
end
