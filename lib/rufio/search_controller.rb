# frozen_string_literal: true

require 'shellwords'

module Rufio
  # 検索（fzf・rga）専用コントローラ
  # KeybindHandler から fzf/rga 検索系メソッドを分離し、単一責任原則に準拠
  class SearchController
    def initialize(directory_listing, file_opener)
      @directory_listing = directory_listing
      @file_opener = file_opener
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
    end

    # ============================
    # fzf 検索
    # ============================

    def fzf_search
      return false unless fzf_available?

      current_path = @directory_listing&.current_path || Dir.pwd

      selected_file = nil
      Dir.chdir(current_path) do
        selected_file = `find . -type f | fzf --preview 'cat {}'`.strip
      end

      if !selected_file.empty?
        full_path = File.expand_path(selected_file, current_path)
        @file_opener.open_file(full_path) if File.exist?(full_path)
      end

      :needs_refresh
    end

    def fzf_available?
      system('which fzf > /dev/null 2>&1')
    end

    # ============================
    # rga 検索
    # ============================

    def rga_search
      return false unless rga_available?

      current_path = @directory_listing&.current_path || Dir.pwd

      print ConfigLoader.message('keybind.search_text')
      search_query = STDIN.gets.chomp
      return false if search_query.empty?

      search_results = nil
      Dir.chdir(current_path) do
        escaped_query = Shellwords.escape(search_query)
        search_results = `rga --line-number --with-filename #{escaped_query} . 2>/dev/null`
      end

      if search_results.empty?
        puts "\n#{ConfigLoader.message('keybind.no_matches')}"
        print ConfigLoader.message('keybind.press_any_key')
        STDIN.getch
        return true
      end

      selected_result = IO.popen('fzf', 'r+') do |fzf|
        fzf.write(search_results)
        fzf.close_write
        fzf.read.strip
      end

      if !selected_result.empty? && selected_result.match(/^(.+?):(\d+):/)
        file_path = ::Regexp.last_match(1)
        line_number = ::Regexp.last_match(2).to_i
        full_path = File.expand_path(file_path, current_path)

        @file_opener.open_file_with_line(full_path, line_number) if File.exist?(full_path)
      end

      :needs_refresh
    end

    def rga_available?
      system('which rga > /dev/null 2>&1')
    end
  end
end
