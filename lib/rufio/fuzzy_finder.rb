# frozen_string_literal: true

require_relative 'text_utils'
require_relative 'fuzzy_search'

module Rufio
  # s / / / F の内蔵検索画面。FuzzySearchSession の最新スナップショットを描画し、
  # Enter で選択中の候補（entry）を返す。セッションの起動・終了もこの画面が受け持つ。
  class FuzzyFinder
    SPINNER_FRAMES = ['|', '/', '-', '\\'].freeze
    SPINNER_INTERVAL = 0.12
    MATCH_FG = "\e[30m\e[1m"
    MATCH_BG = "\e[43m"
    EMPTY = [].freeze

    attr_reader :query, :selected_index, :title

    def initialize
      @session = nil
      @query = ''
      @selected_index = 0
    end

    def open(session, title:)
      close
      @session = session
      @title = title.to_s
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

    # セッションの停止は非同期。所有ワーカーが後処理を続けるため、ここでは待たない。
    def close
      session = @session
      @session = nil
      session&.close
      nil
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

      case key
      when "\e" then close
      when "\r"
        return results[@selected_index]&.[](:entry)
      when :down then select_index(@selected_index + 1)
      when :up then select_index(@selected_index - 1)
      when "\x0a", "\x0e" then handle_key(:down) # Ctrl+J / Ctrl+N
      when "\x0b", "\x10" then handle_key(:up)   # Ctrl+K / Ctrl+P
      when "\x15" then update_query('')          # Ctrl+U
      when "\u007f", "\b" then update_query(@query.chop)
      else
        update_query(@query + key) if printable?(key)
      end
      nil
    end

    def draw(screen)
      screen.clear(mark_dirty: true)
      width = screen.width
      state = @session&.snapshot
      return unless state

      write_line(screen, 0, "#{@title} | ESC: Back", width, "\e[1;36m")
      write_line(screen, 1, "> #{@query}_", width)
      busy = state.scanning || state.searching
      status = busy ? "[#{SPINNER_FRAMES[@spinner_index]}] Searching..." : 'Search complete'
      write_line(screen, 2, "#{status} | #{state.results.length}/#{state.total_matches} matches | " \
                            "#{state.candidate_count} candidates | #{state.errors.length} errors",
                 width, busy ? "\e[1;33m" : "\e[32m")

      capacity = [screen.height - 6, 0].max
      first = [@selected_index - capacity + 1, 0].max
      state.results.slice(first, capacity).to_a.each_with_index do |result, index|
        selected = first + index == @selected_index
        draw_result(screen, index + 3, result, selected, width)
      end
      if state.results.empty?
        message = busy ? 'Searching...' : 'No matching candidates. Edit your search to try again.'
        write_line(screen, 3, message, width)
      end

      entry = state.results[@selected_index]&.[](:entry)
      footer = if entry
                 entry[:line_number] ? "#{entry[:path]}:#{entry[:line_number]}" : entry[:path].to_s
               else
                 state.errors.first.to_s
               end
      write_line(screen, screen.height - 3, footer, width, "\e[90m")
      write_line(screen, screen.height - 2,
                 'ESC: Back | Enter: Open | Up/Down or Ctrl+J/K: Select | Ctrl+U: Clear | Type: Search', width)
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

    def write_line(screen, y, text, width, color = nil)
      safe_text = text.to_s.scrub.gsub(/[[:cntrl:]]/, ' ')
      screen.put_string(0, y, TextUtils.truncate_to_width(safe_text, width), fg: color)
    end
  end
end
