# frozen_string_literal: true

require 'thread'
require_relative 'text_utils'
require_relative 'config_loader'
require_relative 'document_text_extractor'
require_relative 'native_content_search'
require_relative 'fuzzy_search_session'

module Rufio
  # ブックマーク配下のファイル名・テキスト内容をバックグラウンドで横断検索する。
  # ファイル名は s と同じあいまい検索（FuzzySearchSession）、本文は大文字小文字を無視したリテラル検索。
  class GlobalSearch
    SPINNER_FRAMES = ['|', '/', '-', '\\'].freeze
    SPINNER_INTERVAL = 0.12
    # 検索語に一致した部分の表示（黒の太字・黄色背景）
    MATCH_FG = "\e[30m\e[1m"
    MATCH_BG = "\e[43m"
    # ファイル名検索で一覧に保持する上位件数
    FILE_RESULT_LIMIT = 1_000

    attr_reader :query, :results, :errors, :selected_index, :search_type, :skipped_files

    class << self
      # nil: 利用可能なら Zig 実装を使う（RUFIO_NATIVE_SEARCH=0 で無効化）
      attr_writer :native_search

      def native_search?
        enabled = @native_search.nil? ? ENV['RUFIO_NATIVE_SEARCH'] != '0' : @native_search
        enabled && NativeContentSearch.available?
      end
    end

    def initialize
      @active = false
      @scanning = false
      @worker = nil
      @session = nil
      @document_extractor = DocumentTextExtractor.new
      @document_cache = DocumentTextCache.new(extractor: @document_extractor)
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
      @query = ''
      @search_type = :filename
      @excluded_extensions = ConfigLoader.global_search_excluded_extensions
      @bookmark_count = bookmarks.length
      @roots = bookmarks.map { |bookmark| [bookmark[:name].to_s, bookmark[:path].to_s] }
      start_scan
      true
    end

    def close
      @active = false
      @scanning = false
      stop_search
    end

    # 1フレーム当たりの処理量を制限し、検索中も入力を受け付ける。
    def poll
      return false unless active?

      changed = @session ? poll_session : poll_events
      if scanning?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - @last_spinner_update >= SPINNER_INTERVAL
          @spinner_index = (@spinner_index + 1) % SPINNER_FRAMES.length
          @last_spinner_update = now
          changed = true
        end
      end
      changed
    end

    def handle_key(key)
      case key
      when "\e" then close
      when "\t"
        @search_type = @search_type == :filename ? :content : :filename
        start_scan
      when "\r" then return @results[@selected_index]
      when :down then select_index(@selected_index + 1)
      when :up then select_index(@selected_index - 1)
      when "\x0a", "\x0e" then handle_key(:down) # Ctrl+J / Ctrl+N
      when "\x0b", "\x10" then handle_key(:up)   # Ctrl+K / Ctrl+P
      when "\x15" then update_query('')  # Ctrl+U
      when "\u007f", "\b" then update_query(@query[0...-1])
      else
        update_query(@query + key) if key.is_a?(String) && !key.empty? && key.valid_encoding? &&
                                      key.each_codepoint.all? { |c| c >= 32 && c != 127 }
      end
      nil
    end

    def draw(screen)
      screen.clear(mark_dirty: true)
      width = screen.width
      type = @search_type == :content ? 'Content' : 'File names'
      write_line(screen, 0, "G mode - #{type} | Tab: Switch name/content search", width, "\e[1;36m")
      write_line(screen, 1, "Search: #{@query}_", width)
      state = if scanning?
                "[#{SPINNER_FRAMES[@spinner_index]}] Searching..."
              elsif @search_type == :content && @query.empty?
                'Ready'
              else
                'Search complete'
              end
      color = scanning? ? "\e[1;33m" : "\e[32m"
      matches = @session ? @total_matches : @results.length
      write_line(screen, 2, "#{state} | #{@bookmark_count} bookmarks | #{matches} matches | #{@errors.length} errors | #{@skipped_files} skipped", width, color)
      row_height = @search_type == :content ? 2 : 1
      capacity = [screen.height - 6, 0].max / row_height
      first = [@selected_index - capacity + 1, 0].max
      @results.slice(first, capacity).to_a.each_with_index do |entry, index|
        selected = first + index == @selected_index
        prefix = "#{selected ? '>' : ' '} [#{entry[:bookmark]}] "
        text = "#{prefix}#{entry[:relative_path]}"
        text += if entry[:location]
                  " - #{entry[:location]}"
                elsif entry[:line_number]
                  ":#{entry[:line_number]}"
                else
                  ''
                end
        y = index * row_height + 3
        # ファイル名検索はあいまい検索の一致位置、本文検索はスニペットの一致箇所をハイライトする
        write_line(screen, y, text, width, selected ? "\e[1;36m" : nil)
        highlight_positions(screen, y, prefix, entry, width) if @search_type == :filename
        write_line(screen, y + 1, "    #{entry[:match_text]}", width, highlight_from: 4) if entry[:match_text]
      end
      if @results.empty?
        message = if @bookmark_count.zero?
                    'No bookmarks. Add directories with b in Files mode.'
                  elsif scanning?
                    'Searching bookmarked directories...'
                  elsif @search_type == :content && @query.empty?
                    'Type a string to search inside text files.'
                  elsif !@errors.empty? && candidate_count.zero?
                    'No readable files in bookmarked directories.'
                  else
                    'No matching files. Edit your search to try again.'
                  end
        write_line(screen, 3, message, width)
      end
      write_line(screen, screen.height - 3, @results[@selected_index]&.[](:path) || @errors.first.to_s, width, "\e[90m")
      write_line(screen, screen.height - 2, 'ESC: Back | Enter: Go to file | Up/Down or Ctrl+J/K: Select | Type: Search', width)
    end

    private

    # 本文検索の走査スレッドとファイル名検索のセッションを止める。セッションは待たずに閉じる
    def stop_search
      @worker&.kill
      @worker&.join
      @worker = nil
      @session&.close
      @session = nil
      @file_source = nil
    end

    def candidate_count
      @session ? @candidate_count : @entries.length
    end

    def start_scan
      stop_search
      @entries = []
      @results = []
      @result_ids = []
      @errors = []
      @skipped_files = 0
      @selected_index = 0
      @selected_id = nil
      @total_matches = 0
      @candidate_count = 0
      @shown = nil
      @events = SizedQueue.new(256)
      @spinner_index = 0
      @last_spinner_update = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @scanning = !(@search_type == :content && @query.empty?)
      return unless @scanning
      return start_file_name_session if @search_type == :filename

      roots, events, query = @roots, @events, @query.downcase
      native = self.class.native_search?
      native_cache = native ? (@native_cache ||= NativeContentSearch::Cache.new) : nil
      @worker = Thread.new do
        begin
          if native && NativeContentSearch.supports_query?(query)
            scan_roots_natively(roots, events, query, native_cache)
          else
            scan_roots(roots, events, :content, query)
          end
        rescue StandardError => e
          events << [:error, e.message]
        end
        events << [:done, nil]
      end
    end

    # ファイル名は走査と照合を FuzzySearchSession のワーカーに任せ、UI スレッドでは絞り込まない
    def start_file_name_session
      @file_source = FileNameSource.new(self, @roots, self.class.native_search?)
      @session = FuzzySearchSession.new(source: @file_source, limit: FILE_RESULT_LIMIT).start
      @session.update_query(@query) unless @query.empty?
      # 開いた直後の状態は描画済みなので、変化があったときだけ poll で再描画させる
      @shown = @session.snapshot
    end

    def update_query(query)
      @query = query
      @selected_index = 0
      @selected_id = nil
      return start_scan if @search_type == :content || @session.nil?

      # 前の検索語の結果を選べないよう、新しい結果が届くまで一覧を空にする
      @session.update_query(query)
      @results = []
      @result_ids = []
      @scanning = true
    rescue IOError
      nil
    end

    def select_index(index)
      @selected_index = index.clamp(0, [@results.length - 1, 0].max)
      @selected_id = @result_ids&.[](@selected_index)
    end

    def poll_session
      @session.poll
      state = @session.snapshot
      @skipped_files = @file_source.skipped
      @scanning = state.scanning || state.searching
      return false if state.equal?(@shown)

      @shown = state
      @results = state.results.map { |result| result[:entry].merge(positions: result[:positions]) }
      @result_ids = state.results.map { |result| result[:id] }
      @errors = state.errors
      @total_matches = state.total_matches
      @candidate_count = state.candidate_count
      # 候補の追加で順位が変わっても、選択中のファイルを追い続ける
      index = @selected_id && @result_ids.index(@selected_id)
      @selected_index = (index || @selected_index).clamp(0, [@results.length - 1, 0].max)
      true
    end

    # 本文検索の走査スレッドからのイベントを 1 フレーム当たり最大 256 件取り込む
    def poll_events
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
          @results << value
        when :entries
          # Zig 実装の結果はまとめて届くので、1 フレーム 256 件の上限に縛られない
          @entries.concat(value)
          @results.concat(value)
        when :error then @errors << value
        when :skipped then @skipped_files += value || 1
        when :done then @scanning = false
        end
      end
      changed
    end

    # あいまい検索の一致位置（UTF-8 の先頭バイトオフセット）を表示桁に変換してハイライトする
    def highlight_positions(screen, y, prefix, entry, width)
      offsets = entry[:positions]
      return if offsets.nil? || offsets.empty?

      targets = offsets.each_with_object({}) { |offset, set| set[offset] = true }
      line = "#{prefix}#{entry[:text]}"
      limit = TextUtils.display_width(line) > width ? width - TextUtils::ELLIPSIS_MIN_WIDTH : width
      x = TextUtils.display_width(prefix)
      byte = 0
      entry[:text].each_char do |char|
        shown = char.match?(/[[:cntrl:]]/) ? ' ' : char
        char_width = TextUtils.display_width(shown)
        break if x + char_width > limit

        screen.put(x, y, shown, fg: MATCH_FG, bg: MATCH_BG, width: char_width) if targets[byte]
        x += char_width
        byte += char.bytesize
      end
    end

    def scan_roots(roots, events, type, query)
      visited_dirs = {}
      excluded_names = @excluded_extensions.select { |e| e.start_with?('/') }.map { |e| e.delete_prefix('/') }
      excluded_suffixes = @excluded_extensions.reject { |e| e.start_with?('/') }
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
                folded_child = child.scrub.downcase
                # ディレクトリシンボリックリンクは追わず、循環・範囲外の走査を防ぐ。
                if File.directory?(path)
                  pending << path unless File.symlink?(path) || excluded_names.include?(folded_child)
                elsif File.file?(path)
                  if excluded_names.include?(folded_child) || (!excluded_suffixes.empty? && folded_child.end_with?(*excluded_suffixes))
                    events << [:skipped, nil]
                    next
                  end

                  entry = { path: path, bookmark: name, relative_path: path.delete_prefix(root + File::SEPARATOR) }
                  if type == :content
                    scan_content(entry, query, events)
                  else
                    events << [:entry, entry]
                  end
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

    # Zig 実装でブックマーク配下のファイル一覧を並列走査する
    def scan_files_natively(roots, events, cancelled: nil)
      valid_roots = []
      roots.each do |name, root|
        root = File.expand_path(root)
        raise Errno::ENOTDIR, root unless File.directory?(root)

        valid_roots << [name, root]
      rescue SystemCallError, IOError => e
        events << [:error, "#{name}: #{e.message}"]
      end
      return if valid_roots.empty?

      engine = NativeContentSearch.new(roots: valid_roots.map(&:last), query: nil,
                                       excluded_extensions: @excluded_extensions)
      engine.each_batch(cancelled: cancelled) do |batch|
        entries = []
        batch.each do |kind, *args|
          case kind
          when :file, :match
            name, root = valid_roots[args[0]]
            path = args[1]
            entries << { path: path, bookmark: name, relative_path: path.delete_prefix(root + File::SEPARATOR) }
          when :error then events << [:error, args[1]]
          when :skipped then events << [:skipped, args[0]]
          end
        end
        events << [:entries, entries] unless entries.empty?
      end
    ensure
      engine&.close
    end

    # Zig 実装で走査・検索し、PDF などのドキュメントだけ Ruby 側で抽出する
    def scan_roots_natively(roots, events, query, cache)
      valid_roots = []
      roots.each do |name, root|
        root = File.expand_path(root)
        raise Errno::ENOTDIR, root unless File.directory?(root)

        valid_roots << [name, root]
      rescue SystemCallError, IOError => e
        events << [:error, "#{name}: #{e.message}"]
      end
      return if valid_roots.empty?

      engine = NativeContentSearch.new(roots: valid_roots.map(&:last), query: query,
                                       excluded_extensions: @excluded_extensions,
                                       document_extensions: DocumentTextExtractor::EXTENSIONS, cache: cache)
      engine.each_batch do |batch|
        entries = []
        batch.each do |kind, *args|
          case kind
          when :match, :document
            name, root = valid_roots[args[0]]
            path = args[1]
            entry = { path: path, bookmark: name, relative_path: path.delete_prefix(root + File::SEPARATOR) }
            if kind == :document
              scan_content(entry, query, events)
            else
              entries << entry.merge(line_number: args[2], match_text: args[3])
            end
          when :error then events << [:error, args[1]]
          when :skipped then events << [:skipped, args[0]]
          end
        end
        events << [:entries, entries] unless entries.empty?
      end
    ensure
      engine&.close
    end

    def scan_content(entry, query, events)
      if @document_extractor.supported?(entry[:path])
        @document_cache.each_record(entry[:path]) do |record|
          match_index = record[:search_text].index(query)
          next unless match_index

          snippet = record[:text][[match_index - 30, 0].max, 200].to_s.strip
          metadata = record.reject { |key, _| key == :text || key == :search_text }
          events << [:entry, entry.merge(metadata).merge(match_text: snippet)]
        end
        return
      end

      File.open(entry[:path], 'rb') do |file|
        sample = file.read(8192).to_s
        if sample.include?("\0")
          events << [:skipped, nil]
          return
        end

        file.rewind
        file.each_line.with_index(1) do |raw_line, number|
          line = raw_line.force_encoding(Encoding::UTF_8).scrub
          match_index = line.downcase.index(query)
          next unless match_index

          snippet_start = [match_index - 30, 0].max
          snippet = line[snippet_start, 200].strip
          events << [:entry, entry.merge(line_number: number, match_text: snippet)]
        end
      end
    rescue SystemCallError, IOError, DocumentTextExtractor::ExtractionError => e
      events << [:error, "#{entry[:path]}: #{e.message}"]
    end

    def write_line(screen, y, text, width, color = nil, highlight_from: nil)
      safe_text = text.scrub.gsub(/[[:cntrl:]]/, ' ')
      visible = TextUtils.truncate_to_width(safe_text, width)
      screen.put_string(0, y, visible, fg: color)
      return unless highlight_from

      match_ranges(visible, highlight_from).each do |start, length|
        x = TextUtils.display_width(visible[0, start])
        screen.put_string(x, y, visible[start, length], fg: MATCH_FG, bg: MATCH_BG)
      end
    end

    # 検索と同じく大文字小文字を区別せず、from 文字目以降の一致位置を [開始, 長さ] で返す
    def match_ranges(text, from)
      needle = @query.to_s.downcase.chars
      return [] if needle.empty?

      folded = text.chars.map(&:downcase)
      ranges = []
      index = from
      while index + needle.length <= folded.length
        if folded[index, needle.length] == needle
          ranges << [index, needle.length]
          index += needle.length
        else
          index += 1
        end
      end
      ranges
    end

    # ファイル名検索の候補を FuzzySearchSession に流す。既存の走査（Zig / Ruby）のイベントを
    # バッチに変換し、停止要求があれば次のイベントで走査を打ち切る。
    class FileNameSource
      BATCH_SIZE = 256
      Cancelled = Class.new(StandardError)

      attr_reader :skipped

      def initialize(search, roots, native)
        @search = search
        @roots = roots
        @native = native
        @skipped = 0
      end

      def each_batch(cancelled:, on_error:, &emit)
        sink = Sink.new(self, cancelled, on_error, emit)
        if @native && NativeContentSearch.files_available?
          @search.send(:scan_files_natively, @roots, sink, cancelled: cancelled)
        else
          @search.send(:scan_roots, @roots, sink, :filename, '')
        end
        sink.flush
      rescue Cancelled
        nil
      end

      def add_skipped(count)
        @skipped += count
      end

      # scan_roots / scan_files_natively が使う events << [種類, 値] を受け取る
      class Sink
        def initialize(source, cancelled, on_error, emit)
          @source = source
          @cancelled = cancelled
          @on_error = on_error
          @emit = emit
          @pending = []
        end

        def <<(event)
          raise Cancelled if @cancelled.call

          type, value = event
          case type
          when :entry then add(value)
          when :entries then value.each { |entry| add(entry) }
          when :error then @on_error.call(value)
          when :skipped then @source.add_skipped(value || 1)
          end
          flush if type == :entries
          self
        end

        def flush
          return if @pending.empty?

          batch = @pending
          @pending = []
          @emit.call(batch)
        end

        private

        def frozen(value)
          value.is_a?(String) && !value.frozen? ? value.dup.freeze : value
        end

        def add(entry)
          relative = entry[:relative_path]
          # 凍結しておくと、セッションがコピーせずにそのまま保持できる
          @pending << { text: relative.dup.force_encoding(Encoding::UTF_8).scrub.freeze, path: frozen(entry[:path]),
                        bookmark: frozen(entry[:bookmark]), relative_path: frozen(relative) }.freeze
          flush if @pending.length >= BATCH_SIZE
        end
      end
    end
  end
end
