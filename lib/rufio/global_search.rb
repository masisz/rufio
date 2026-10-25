# frozen_string_literal: true

require 'thread'
require_relative 'text_utils'

module Rufio
  # ブックマーク配下をバックグラウンドで列挙し、ファイル名を横断検索する。
  class GlobalSearch
    attr_reader :query, :results, :errors, :selected_index

    def initialize
      @active = false
      @scanning = false
      @worker = nil
    end

    def active?
      @active
    end

    def scanning?
      @scanning
    end

    def open(bookmarks)
      close
      @active = true
      @scanning = true
      @query = ''
      @entries = []
      @results = []
      @errors = []
      @selected_index = 0
      @bookmark_count = bookmarks.length
      @events = SizedQueue.new(256)
      roots = bookmarks.map { |bookmark| [bookmark[:name].to_s, bookmark[:path].to_s] }
      events = @events
      @worker = Thread.new do
        begin
          scan_roots(roots, events)
        rescue StandardError => e
          events << [:error, e.message]
        end
        events << [:done, nil]
      end
      true
    end

    def close
      @active = false
      @scanning = false
      @worker&.kill
      @worker&.join
      @worker = nil
    end

    # 1フレーム当たりの処理量を制限し、検索中も入力を受け付ける。
    def poll
      return false unless active?

      changed = false
      256.times do
        event = begin
          @events.pop(true)
        rescue ThreadError
          break
        end
        changed = true
        type, value = event
        case type
        when :entry
          @entries << value
          @results << value if matches_query?(value)
        when :error then @errors << value
        when :done then @scanning = false
        end
      end
      changed
    end

    def handle_key(key)
      case key
      when "\e" then close
      when "\r", "\n" then return @results[@selected_index]
      when :down then @selected_index = [@selected_index + 1, [@results.length - 1, 0].max].min
      when :up then @selected_index = [@selected_index - 1, 0].max
      when "\x0e" then handle_key(:down) # Ctrl+N
      when "\x10" then handle_key(:up)   # Ctrl+P
      when "\x15" then update_query('')  # Ctrl+U
      when "\u007f", "\b" then update_query(@query[0...-1])
      else
        update_query(@query + key) if key.is_a?(String) && !key.empty? && key.each_codepoint.all? { |c| c >= 32 && c != 127 }
      end
      nil
    end

    def draw(screen)
      screen.clear
      width = screen.width
      write_line(screen, 0, 'G mode - Search files across all bookmarks', width, "\e[1;36m")
      write_line(screen, 1, "Search: #{@query}_", width)
      state = scanning? ? 'Scanning...' : 'Ready'
      write_line(screen, 2, "#{state} | #{@bookmark_count} bookmarks | #{@results.length} matches | #{@errors.length} skipped", width)
      capacity = [screen.height - 6, 0].max
      first = [@selected_index - capacity + 1, 0].max
      @results.slice(first, capacity).to_a.each_with_index do |entry, index|
        selected = first + index == @selected_index
        text = "#{selected ? '>' : ' '} [#{entry[:bookmark]}] #{entry[:relative_path]}"
        write_line(screen, index + 3, text, width, selected ? "\e[1;36m" : nil)
      end
      if @results.empty?
        message = if @bookmark_count.zero?
                    'No bookmarks. Add directories with b in Files mode.'
                  elsif scanning?
                    'Searching bookmarked directories...'
                  elsif !@errors.empty? && @entries.empty?
                    'No readable files in bookmarked directories.'
                  else
                    'No matching files. Edit your search to try again.'
                  end
        write_line(screen, 3, message, width)
      end
      write_line(screen, screen.height - 3, @results[@selected_index]&.[](:path) || @errors.first.to_s, width, "\e[90m")
      write_line(screen, screen.height - 2, 'ESC: Back | Enter: Go to file | Up/Down: Select | Type: Search', width)
    end

    private

    def update_query(query)
      @query = query
      @selected_index = 0
      filter_results
    end

    def filter_results
      query = @query.downcase
      @results = @entries.select { |entry| entry[:relative_path].scrub.downcase.include?(query) }
      @selected_index = [[@selected_index, @results.length - 1].min, 0].max
    end

    def matches_query?(entry)
      entry[:relative_path].scrub.downcase.include?(@query.downcase)
    end

    def scan_roots(roots, events)
      visited_dirs = {}
      roots.each do |name, root|
        begin
          root = File.expand_path(root)
          raise Errno::ENOTDIR, root unless File.directory?(root)

          pending = [root]
          until pending.empty?
            directory = pending.pop
            canonical = File.realpath(directory)
            next if visited_dirs[canonical]

            visited_dirs[canonical] = true
            begin
              Dir.each_child(directory) do |child|
                path = File.join(directory, child)
                # ディレクトリシンボリックリンクは追わず、循環・範囲外の走査を防ぐ。
                if File.directory?(path)
                  pending << path unless File.symlink?(path)
                elsif File.file?(path)
                  events << [:entry, { path: path, bookmark: name, relative_path: path.delete_prefix(root + File::SEPARATOR) }]
                end
              end
            rescue SystemCallError, IOError => e
              events << [:error, "#{directory}: #{e.message}"]
            end
          end
        rescue SystemCallError, IOError => e
          events << [:error, "#{name}: #{e.message}"]
        end
      end
    end

    def write_line(screen, y, text, width, color = nil)
      safe_text = text.scrub.gsub(/[[:cntrl:]]/, ' ')
      screen.put_string(0, y, TextUtils.truncate_to_width(safe_text, width), fg: color)
    end
  end
end
