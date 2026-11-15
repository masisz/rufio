# frozen_string_literal: true

require_relative 'text_utils'
require_relative 'fuzzy_search'
require_relative 'fuzzy_preview_loader'

module Rufio
  # s / / / F の内蔵検索画面。FuzzySearchSession の最新スナップショットを描画し、
  # Enter で選択中の候補（entry）を返す。セッションの起動・終了もこの画面が受け持つ。
  # 幅が PREVIEW_MIN_WIDTH 以上でプレビューを有効にした場合は、右半分に選択中のファイルを表示する。
  class FuzzyFinder
    SPINNER_FRAMES = ['|', '/', '-', '\\'].freeze
    SPINNER_INTERVAL = 0.12
    MATCH_FG = "\e[30m\e[1m"
    MATCH_BG = "\e[43m"
    EMPTY = [].freeze
    PREVIEW_MIN_WIDTH = 80
    PREVIEW_LINE_BG = "\e[100m"
    TAB = '    '

    attr_reader :query, :selected_index, :title, :cached_at

    def initialize(preview_loader_factory: -> { FuzzyPreviewLoader.new })
      @preview_loader_factory = preview_loader_factory
      @session = nil
      @preview_loader = nil
      @query = ''
      @selected_index = 0
    end

    # cached_at: キャッシュした候補を流す場合の保存時刻（monotonic）。rescan: Ctrl+R で
    # 作り直すセッションを返す Proc。preview: true でプレビューを読み込む。
    def open(session, title:, cached_at: nil, rescan: nil, preview: false)
      close
      @session = session
      @title = title.to_s
      @cached_at = cached_at
      @rescan = rescan
      @notice = nil
      @preview_loader = preview ? @preview_loader_factory.call : nil
      @query = ''
      @selected_index = 0
      @selected_id = nil
      @spinner_index = 0
      @last_spinner_update = monotonic
      @shown = nil
      session.start
      true
    end

    def active?
      !@session.nil?
    end

    # セッションとプレビューの停止は非同期。所有ワーカーが後処理を続けるため、ここでは待たない。
    def close
      session = @session
      @session = nil
      session&.close
      @preview_loader&.close
      @preview_loader = nil
      nil
    end

    def preview?
      !@preview_loader.nil?
    end

    def preview_pending?
      @preview_loader ? @preview_loader.pending? : false
    end

    # 選択結果を開けなかったときなどに、次のキー入力までフッターに表示する
    def show_notice(text)
      @notice = text.to_s
    end

    def results
      @session ? @session.results : EMPTY
    end

    def busy?
      return false unless @session

      state = @session.snapshot
      state.scanning || state.searching
    end

    def poll
      return false unless @session

      @session.poll
      state = @session.snapshot
      changed = !state.equal?(@shown)
      if changed
        @shown = state
        follow_selection(state.results)
      end
      request_preview
      changed = true if @preview_loader&.poll
      if state.scanning || state.searching
        now = monotonic
        if now - @last_spinner_update >= SPINNER_INTERVAL
          @spinner_index = (@spinner_index + 1) % SPINNER_FRAMES.length
          @last_spinner_update = now
          changed = true
        end
      end
      changed
    end

    def handle_key(key)
      return nil unless @session

      @notice = nil
      case key
      when "\e" then close
      when "\r"
        return results[@selected_index]&.[](:entry)
      when :down then select_index(@selected_index + 1)
      when :up then select_index(@selected_index - 1)
      when "\x0a", "\x0e" then handle_key(:down) # Ctrl+J / Ctrl+N
      when "\x0b", "\x10" then handle_key(:up)   # Ctrl+K / Ctrl+P
      when "\x15" then update_query('')          # Ctrl+U
      when "\x12" then rescan                     # Ctrl+R
      when "\u007f", "\b" then update_query(@query.chop)
      else
        update_query(@query + key) if printable?(key)
      end
      request_preview
      nil
    end

    def draw(screen)
      screen.clear(mark_dirty: true)
      width = screen.width
      state = @session&.snapshot
      return unless state

      header = [@title]
      header << "Cached #{cache_age}" if @cached_at
      header << 'Ctrl+R: Rescan' if @rescan
      write_line(screen, 0, (header << 'ESC: Back').join(' | '), width, "\e[1;36m")
      write_line(screen, 1, "> #{@query}_", width)
      busy = state.scanning || state.searching
      status = busy ? "[#{SPINNER_FRAMES[@spinner_index]}] Searching..." : 'Search complete'
      write_line(screen, 2, "#{status} | #{state.results.length}/#{state.total_matches} matches | " \
                            "#{state.candidate_count} candidates | #{state.errors.length} errors",
                 width, busy ? "\e[1;33m" : "\e[32m")

      capacity = [screen.height - 6, 0].max
      list_width = preview_visible?(width) ? width / 2 : width
      first = [@selected_index - capacity + 1, 0].max
      state.results.slice(first, capacity).to_a.each_with_index do |result, index|
        selected = first + index == @selected_index
        draw_result(screen, index + 3, result, selected, list_width)
      end
      if state.results.empty?
        message = busy ? 'Searching...' : 'No matching candidates. Edit your search to try again.'
        write_line(screen, 3, message, list_width)
      end

      entry = state.results[@selected_index]&.[](:entry)
      draw_preview(screen, list_width, capacity, entry) if list_width < width
      if @notice
        notice = @rescan ? "#{@notice} | Ctrl+R: Rescan" : @notice
        write_line(screen, screen.height - 3, notice, width, "\e[1;33m")
      else
        footer = if entry
                   entry[:line_number] ? "#{entry[:path]}:#{entry[:line_number]}" : entry[:path].to_s
                 else
                   state.errors.first.to_s
                 end
        write_line(screen, screen.height - 3, footer, width, "\e[90m")
      end
      write_line(screen, screen.height - 2,
                 'ESC: Back | Enter: Open | Up/Down or Ctrl+J/K: Select | Ctrl+U: Clear | Type: Search', width)
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def cache_age
      seconds = [(monotonic - @cached_at).floor, 0].max
      if seconds < 60 then "#{seconds}s ago"
      elsif seconds < 3600 then "#{seconds / 60}m ago"
      else "#{seconds / 3600}h ago"
      end
    end

    def printable?(key)
      key.is_a?(String) && !key.empty? && key.valid_encoding? &&
        key.each_codepoint.all? { |c| c >= 32 && c != 127 }
    end

    def update_query(text)
      return if text == @query || text.bytesize > FuzzySearch::MAX_QUERY_BYTES

      @session.update_query(text)
      @query = text
      @selected_index = 0
      @selected_id = nil
    rescue IOError
      # 検索ワーカーが失敗したセッションは入力を受け付けない。エラーは画面に表示済み。
      nil
    end

    # 検索語を保ったまま、新しいセッション（キャッシュを使わない再走査）に切り替える
    def rescan
      return unless @rescan

      fresh = @rescan.call
      previous = @session
      @session = fresh
      previous.close
      fresh.start
      fresh.update_query(@query) unless @query.empty?
      @cached_at = nil
      @shown = nil
      @selected_index = 0
      @selected_id = nil
    rescue IOError
      nil
    end

    def select_index(index)
      list = results
      @selected_index = index.clamp(0, [list.length - 1, 0].max)
      @selected_id = list[@selected_index]&.[](:id)
    end

    # 候補追加で順位が変わっても、選択中の候補を追い続ける
    def follow_selection(list)
      index = @selected_id && list.index { |result| result[:id] == @selected_id }
      @selected_index = (index || @selected_index).clamp(0, [list.length - 1, 0].max)
    end

    def preview_visible?(width)
      !@preview_loader.nil? && width >= PREVIEW_MIN_WIDTH
    end

    def request_preview
      return unless @preview_loader && @session

      entry = results[@selected_index]&.[](:entry)
      @preview_loader.request(entry[:path], entry[:line_number]) if entry
    end

    def draw_result(screen, y, result, selected, width)
      prefix = selected ? '> ' : '  '
      text = result[:entry][:text].gsub(/[[:cntrl:]]/, ' ')
      write_line(screen, y, prefix + text, width, selected ? "\e[1;36m" : nil)
      # 省略記号で切り詰めた行は、省略記号の位置をハイライトで上書きしない
      limit = TextUtils.display_width(prefix + text) > width ? width - TextUtils::ELLIPSIS_MIN_WIDTH : width
      offsets = result[:positions]
      return if offsets.nil? || offsets.empty?

      # 一致位置は UTF-8 の先頭バイトオフセット。表示桁に変換してハイライトする
      targets = offsets.each_with_object({}) { |offset, set| set[offset] = true }
      x = TextUtils.display_width(prefix)
      byte = 0
      result[:entry][:text].each_char do |char|
        shown = char.match?(/[[:cntrl:]]/) ? ' ' : char
        char_width = TextUtils.display_width(shown)
        break if x + char_width > limit

        screen.put(x, y, shown, fg: MATCH_FG, bg: MATCH_BG, width: char_width) if targets[byte]
        x += char_width
        byte += char.bytesize
      end
    end

    # 右半分に選択中のファイルを表示する。行番号つきの候補（F）はその行を中央付近に出して強調する
    def draw_preview(screen, list_width, capacity, entry)
      x = list_width + 2
      width = screen.width - x
      capacity.times { |row| screen.put(list_width, row + 3, '│', fg: "\e[90m") }
      return unless entry

      preview = @preview_loader.result(entry[:path], entry[:line_number])
      unless preview
        write_at(screen, x, 3, 'Loading preview...', width, fg: "\e[90m")
        return
      end

      lines = preview[:lines] || EMPTY
      target = entry[:line_number] && entry[:line_number] - 1
      start = target ? (target - capacity / 2).clamp(0, [lines.length - capacity, 0].max) : 0
      lines[start, capacity].to_a.each_with_index do |line, index|
        text = line.to_s.scrub.gsub("\t", TAB).gsub(/[[:cntrl:]]/, ' ')
        if start + index == target
          shown = TextUtils.truncate_to_width(text, width)
          shown += ' ' * [width - TextUtils.display_width(shown), 0].max
          write_at(screen, x, index + 3, shown, width, bg: PREVIEW_LINE_BG)
        else
          write_at(screen, x, index + 3, text, width)
        end
      end
    end

    def write_line(screen, y, text, width, color = nil)
      safe_text = text.to_s.scrub.gsub(/[[:cntrl:]]/, ' ')
      screen.put_string(0, y, TextUtils.truncate_to_width(safe_text, width), fg: color)
    end

    def write_at(screen, x, y, text, width, fg: nil, bg: nil)
      screen.put_string(x, y, TextUtils.truncate_to_width(text, width), fg: fg, bg: bg)
    end
  end
end
