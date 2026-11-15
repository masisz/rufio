# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# s / / / F の内蔵検索画面。FuzzySearchSession の結果を描画し、選択結果を返す。
class TestFuzzyFinder < Minitest::Test
  class ArraySource
    def initialize(items, errors: [])
      @items = items
      @errors = errors
    end

    def each_batch(cancelled:, on_error:)
      @errors.each { |message| on_error.call(message) }
      yield @items unless cancelled.call
    end
  end

  ITEMS = [
    { text: 'lib/rufio/search_controller.rb', path: '/root/lib/rufio/search_controller.rb' },
    { text: 'lib/rufio/screen.rb', path: '/root/lib/rufio/screen.rb' },
    { text: 'README.md', path: '/root/README.md' },
    { text: '日本語/メモ.txt', path: '/root/日本語/メモ.txt' }
  ].freeze

  def setup
    @finder = Rufio::FuzzyFinder.new
  end

  def teardown
    @finder.close
  end

  def open(items = ITEMS, errors: [], title: 'Files')
    session = Rufio::FuzzySearchSession.new(source: ArraySource.new(items, errors: errors), native: false)
    @finder.open(session, title: title)
    settle
    session
  end

  def settle
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      @finder.poll
      break unless @finder.busy?
      flunk 'fuzzy finder did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def type(text)
    text.each_char { |char| @finder.handle_key(char) }
    settle
  end

  def result_texts
    @finder.results.map { |result| result[:entry][:text] }
  end

  def row_text(screen, y)
    (0...screen.width).map { |x| screen.get_cell(x, y).char }.join.rstrip
  end

  def test_open_lists_all_candidates_in_insertion_order
    open
    assert @finder.active?
    assert_equal '', @finder.query
    assert_equal ITEMS.map { |item| item[:text] }, result_texts
  end

  def test_typing_filters_with_fuzzy_subsequence
    open
    type('sctrl')
    assert_equal ['lib/rufio/search_controller.rb'], result_texts
    assert_equal 'sctrl', @finder.query
  end

  def test_backspace_and_ctrl_u_edit_query
    open
    type('scx')
    assert_empty @finder.results
    @finder.handle_key("\u007f")
    settle
    assert_equal 'sc', @finder.query
    refute_empty @finder.results
    @finder.handle_key("\x15")
    settle
    assert_equal '', @finder.query
    assert_equal ITEMS.length, @finder.results.length
  end

  def test_selection_moves_and_clamps
    open
    @finder.handle_key(:up)
    assert_equal 0, @finder.selected_index
    ["\x0a", :down, "\x0e"].each { |key| @finder.handle_key(key) }
    assert_equal 3, @finder.selected_index
    @finder.handle_key(:down)
    assert_equal 3, @finder.selected_index
    ["\x0b", "\x10"].each { |key| @finder.handle_key(key) }
    assert_equal 1, @finder.selected_index
  end

  def test_query_change_resets_selection
    open
    @finder.handle_key(:down)
    type('r')
    assert_equal 0, @finder.selected_index
  end

  def test_enter_returns_selected_entry
    open
    @finder.handle_key(:down)
    entry = @finder.handle_key("\r")
    assert_equal '/root/lib/rufio/screen.rb', entry[:path]
    assert_equal 'lib/rufio/screen.rb', entry[:text]
  end

  def test_enter_without_results_returns_nil
    open
    type('zzzz')
    assert_nil @finder.handle_key("\r")
    assert @finder.active?
  end

  def test_escape_closes_finder_and_session
    session = open
    assert_nil @finder.handle_key("\e")
    refute @finder.active?
    refute session.active?
  end

  def test_printable_keys_including_help_key_are_typed
    open
    type('?')
    assert_equal '?', @finder.query
    assert @finder.active?
  end

  def test_reopen_closes_previous_session
    first = open
    open
    refute first.active?
    assert @finder.active?
  end

  def test_draw_shows_title_prompt_status_and_results
    open(title: 'Files: /root')
    screen = Rufio::Screen.new(60, 12)
    @finder.draw(screen)
    assert_includes row_text(screen, 0), 'Files: /root'
    assert_equal '> _', row_text(screen, 1)
    assert_includes row_text(screen, 2), '4/4 matches'
    assert_includes row_text(screen, 2), '4 candidates'
    assert_equal '> lib/rufio/search_controller.rb', row_text(screen, 3)
    assert_equal '  lib/rufio/screen.rb', row_text(screen, 4)
    assert_includes row_text(screen, 10), 'Enter'
  end

  def test_draw_highlights_matched_characters
    open
    type('rme')
    screen = Rufio::Screen.new(40, 10)
    @finder.draw(screen)
    assert_equal '> README.md', row_text(screen, 3)
    highlighted = (0...screen.width).select { |x| screen.get_cell(x, 3).bg }
    assert_equal [2, 6, 7], highlighted
  end

  def test_draw_converts_utf8_byte_offsets_to_display_columns
    open
    type('メ')
    screen = Rufio::Screen.new(40, 10)
    @finder.draw(screen)
    assert_equal '> 日本語/メモ.txt', row_text(screen, 3)
    highlighted = (0...screen.width).select { |x| screen.get_cell(x, 3).bg }
    assert_equal [9], highlighted
  end

  def test_draw_shows_empty_message_and_first_error
    open([], errors: ['/root/secret: Permission denied'])
    screen = Rufio::Screen.new(60, 10)
    @finder.draw(screen)
    assert_includes row_text(screen, 2), '1 errors'
    assert_includes row_text(screen, 3), 'No matching'
    assert_includes row_text(screen, 7), 'Permission denied'
  end

  def test_draw_scrolls_to_keep_selection_visible
    items = (1..20).map { |i| { text: format('file%02d', i), path: "/root/file#{i}" } }
    open(items)
    screen = Rufio::Screen.new(30, 10)
    10.times { @finder.handle_key(:down) }
    @finder.draw(screen)
    rows = (3..6).map { |y| row_text(screen, y) }
    assert_includes rows, '> file11'
  end

  def test_draw_shows_line_number_metadata
    open([{ text: 'a.txt:3:hello', path: '/root/a.txt', line_number: 3 }], title: 'Content: hello')
    screen = Rufio::Screen.new(40, 10)
    @finder.draw(screen)
    assert_equal '> a.txt:3:hello', row_text(screen, 3)
    assert_includes row_text(screen, 7), '/root/a.txt:3'
  end

  def test_poll_reports_changes_only_when_snapshot_changes
    open
    refute @finder.poll
    @finder.handle_key('r')
    changed = false
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until changed || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      changed = @finder.poll
      sleep 0.005
    end
    assert changed
  end
end
