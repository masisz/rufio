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
  end  # === Phase 4: 再表示キャッシュ・再走査・通知 ===

  def test_title_shows_cache_age_and_rescan_key
    session = Rufio::FuzzySearchSession.new(source: ArraySource.new(ITEMS), native: false)
    cached_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 65
    @finder.open(session, title: 'Files: /root', cached_at: cached_at, rescan: -> { flunk })
    settle
    screen = Rufio::Screen.new(100, 12)
    @finder.draw(screen)
    title = row_text(screen, 0)
    assert_includes title, 'Files: /root'
    assert_includes title, 'Cached 1m ago'
    assert_includes title, 'Ctrl+R: Rescan'
  end

  def test_title_without_cache_shows_rescan_only_when_available
    open
    screen = Rufio::Screen.new(100, 12)
    @finder.draw(screen)
    refute_includes row_text(screen, 0), 'Cached'
    refute_includes row_text(screen, 0), 'Ctrl+R'
  end

  def test_ctrl_r_rescans_with_new_session_and_keeps_query
    first = Rufio::FuzzySearchSession.new(source: ArraySource.new(ITEMS.first(1)), native: false)
    fresh = ITEMS + [{ text: 'lib/rufio/screen_test.rb', path: '/root/lib/rufio/screen_test.rb' }]
    rescans = 0
    rescan = lambda do
      rescans += 1
      Rufio::FuzzySearchSession.new(source: ArraySource.new(fresh), native: false)
    end
    @finder.open(first, title: 'Files', cached_at: Process.clock_gettime(Process::CLOCK_MONOTONIC), rescan: rescan)
    settle
    type('screen')
    assert_empty @finder.results
    @finder.handle_key("\x12")
    settle
    assert_equal 1, rescans
    refute first.active?
    assert_equal 'screen', @finder.query
    assert_equal ['lib/rufio/screen.rb', 'lib/rufio/screen_test.rb'], result_texts.sort
    screen = Rufio::Screen.new(100, 12)
    @finder.draw(screen)
    refute_includes row_text(screen, 0), 'Cached'
    assert_includes row_text(screen, 0), 'Ctrl+R: Rescan'
  end

  def test_ctrl_r_without_rescan_is_ignored
    open
    @finder.handle_key("\x12")
    assert @finder.active?
    assert_equal '', @finder.query
  end

  def test_notice_replaces_footer_until_next_key
    open
    @finder.show_notice('File no longer exists')
    screen = Rufio::Screen.new(60, 10)
    @finder.draw(screen)
    assert_includes row_text(screen, 7), 'File no longer exists'
    @finder.handle_key(:down)
    @finder.draw(screen)
    refute_includes row_text(screen, 7), 'File no longer exists'
  end

  def test_selection_stays_on_same_entry_while_candidates_arrive
    gate = Queue.new
    source = Object.new
    source.define_singleton_method(:each_batch) do |cancelled:, on_error:, &block|
      block.call([{ text: 'other_b.txt', path: '/b' }, { text: 'x_other_x_long_name.txt', path: '/x' }])
      gate.pop
      block.call([{ text: 'other.txt', path: '/o' }]) unless cancelled.call
    end
    @finder.open(Rufio::FuzzySearchSession.new(source: source, native: false, refresh_interval: 0), title: 'Files')
    'other'.each_char { |char| @finder.handle_key(char) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until result_texts.length == 2 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      @finder.poll
      sleep 0.005
    end
    assert_equal ['other_b.txt', 'x_other_x_long_name.txt'], result_texts
    @finder.handle_key(:down)
    gate << true
    settle
    assert_equal ['other.txt', 'other_b.txt', 'x_other_x_long_name.txt'], result_texts
    assert_equal 2, @finder.selected_index
    assert_equal 'x_other_x_long_name.txt', result_texts[@finder.selected_index]
  end

  # === Phase 4: プレビュー ===

  def with_files
    Dir.mktmpdir('rufio_finder_preview') do |dir|
      paths = {
        'a.txt' => "alpha first line\nalpha second\n",
        'long.txt' => (1..100).map { |i| "line#{i}" }.join("\n") + "\n",
        'bin.dat' => "\x00\x01\x02binary".b * 10
      }.map do |name, body|
        path = File.join(dir, name)
        File.binwrite(path, body)
        [name, path]
      end.to_h
      yield paths
    end
  end

  def open_with_preview(items)
    session = Rufio::FuzzySearchSession.new(source: ArraySource.new(items), native: false)
    @finder.open(session, title: 'Files', preview: true)
    settle_preview
  end

  def settle_preview
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      @finder.poll
      break unless @finder.busy? || @finder.preview_pending?
      flunk 'preview did not settle' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
  end

  def preview_text(screen, y)
    (51...screen.width).map { |x| screen.get_cell(x, y).char }.join.strip
  end

  def test_preview_shows_selected_file_on_the_right
    with_files do |paths|
      open_with_preview([{ text: 'a.txt', path: paths['a.txt'] }, { text: 'long.txt', path: paths['long.txt'] }])
      screen = Rufio::Screen.new(100, 14)
      @finder.draw(screen)
      assert_equal '> a.txt', row_text(screen, 3)[0, 50].rstrip
      assert_equal '│', screen.get_cell(50, 3).char
      assert_equal 'alpha first line', preview_text(screen, 3)
      assert_equal 'alpha second', preview_text(screen, 4)

      @finder.handle_key(:down)
      settle_preview
      @finder.draw(screen)
      assert_equal 'line1', preview_text(screen, 3)
    end
  end

  def test_preview_centers_and_highlights_line_number
    with_files do |paths|
      open_with_preview([{ text: 'long.txt:60:line60', path: paths['long.txt'], line_number: 60 }])
      screen = Rufio::Screen.new(100, 14)
      @finder.draw(screen)
      rows = (3..10).map { |y| preview_text(screen, y) }
      y = rows.index('line60')
      refute_nil y, rows.inspect
      refute_equal 0, y
      assert screen.get_cell(52, y + 3).bg, 'matching line should be highlighted'
      refute screen.get_cell(52, 3).bg
    end
  end

  def test_preview_shows_binary_and_missing_messages
    with_files do |paths|
      open_with_preview([{ text: 'bin.dat', path: paths['bin.dat'] }, { text: 'gone.txt', path: File.join(File.dirname(paths['a.txt']), 'gone.txt') }])
      screen = Rufio::Screen.new(100, 14)
      @finder.draw(screen)
      assert_match(/binary/i, preview_text(screen, 3))
      @finder.handle_key(:down)
      settle_preview
      @finder.draw(screen)
      refute_empty preview_text(screen, 3)
      refute_includes preview_text(screen, 3), 'binary'
    end
  end

  def test_preview_is_hidden_on_narrow_screens_and_when_disabled
    with_files do |paths|
      open_with_preview([{ text: 'a.txt', path: paths['a.txt'] }])
      narrow = Rufio::Screen.new(79, 14)
      @finder.draw(narrow)
      refute_includes row_text(narrow, 3), 'alpha'
      refute_includes row_text(narrow, 3), '│'

      session = Rufio::FuzzySearchSession.new(source: ArraySource.new([{ text: 'a.txt', path: paths['a.txt'] }]), native: false)
      @finder.open(session, title: 'Files')
      settle
      refute @finder.preview_pending?
      wide = Rufio::Screen.new(100, 14)
      @finder.draw(wide)
      refute_includes row_text(wide, 3), 'alpha'
    end
  end

  def test_preview_replaces_control_characters_and_tabs
    Dir.mktmpdir('rufio_finder_preview') do |dir|
      path = File.join(dir, 'tab.txt')
      File.write(path, "a\tb\e[31mred\n")
      open_with_preview([{ text: 'tab.txt', path: path }])
      screen = Rufio::Screen.new(100, 14)
      @finder.draw(screen)
      line = preview_text(screen, 3)
      refute_includes line, "\t"
      refute_includes line, "\e"
      assert line.start_with?('a  ')
    end
  end

  def test_close_stops_preview_loader
    with_files do |paths|
      open_with_preview([{ text: 'a.txt', path: paths['a.txt'] }])
      loader = @finder.instance_variable_get(:@preview_loader)
      @finder.close
      assert loader.wait(timeout: 5)
    end
  end
end
