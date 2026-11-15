# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# TerminalUI が内蔵検索画面へキー入力を渡し、選択結果をコールバックへ返す。
class TestFuzzyFinderTerminalInput < Minitest::Test
  class ArraySource
    def each_batch(cancelled:, on_error:)
      yield [{ text: 'first.txt', path: '/root/first.txt' }, { text: 'second.txt', path: '/root/second.txt' }]
    end
  end

  def setup
    @ui = Rufio::TerminalUI.new(test_mode: true)
    @ui.instance_variable_set(:@keybind_handler, Rufio::KeybindHandler.new)
    @selected = []
    @session = Rufio::FuzzySearchSession.new(source: ArraySource.new, native: false)
    @ui.start_fuzzy_finder(@session, title: 'Files') { |entry| @selected << entry; true }
    @finder = @ui.instance_variable_get(:@fuzzy_finder)
    settle
    @queue = Queue.new
    @ui.instance_variable_set(:@input_queue, @queue)
    @ui.define_singleton_method(:windows?) { true }
  end

  def teardown
    @finder.close
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

  def feed(sequence)
    sequence.bytes.each { |byte| @queue << byte }
    assert @ui.send(:handle_input_nonblocking)
    assert @queue.empty?, 'escape sequence was not fully consumed'
  end

  def test_finder_is_active_after_start
    assert @ui.fuzzy_finder_active?
    refute @ui.global_search_active?
  end

  def test_arrow_sequences_move_selection_without_typing
    ["\e[B", "\eOB", "\e[1;5B", "\e[106;5u"].each do |down|
      feed(down)
      assert_equal 1, @finder.selected_index, down.inspect
      assert_equal '', @finder.query
      feed("\e[A")
      assert_equal 0, @finder.selected_index
    end
  end

  def test_letters_are_typed_into_query_instead_of_keybinds
    feed('j')
    feed('?')
    assert_equal 'j?', @finder.query
    assert @ui.fuzzy_finder_active?
    refute @ui.help_dialog_active?
  end

  def test_enter_calls_callback_and_closes
    feed("\e[B")
    feed("\r")
    assert_equal ['/root/second.txt'], @selected.map { |entry| entry[:path] }
    refute @ui.fuzzy_finder_active?
    refute @session.active?
  end

  def test_escape_closes_without_selection
    feed("\e")
    refute @ui.fuzzy_finder_active?
    assert_empty @selected
  end

  def test_mouse_wheel_moves_selection
    @ui.send(:handle_mouse_event, 65, 1, 1, true)
    assert_equal 1, @finder.selected_index
    @ui.send(:handle_mouse_event, 64, 1, 1, true)
    assert_equal 0, @finder.selected_index
  end

  def test_draw_screen_uses_finder
    screen = Rufio::Screen.new(40, 10)
    @ui.draw_screen_to_buffer(screen)
    row = (0...screen.width).map { |x| screen.get_cell(x, 0).char }.join
    assert_includes row, 'Files'
  end

  def test_needs_refresh_result_redraws_after_selection
    @finder.close
    refreshed = false
    @ui.define_singleton_method(:refresh_display) { refreshed = true }
    @session = Rufio::FuzzySearchSession.new(source: ArraySource.new, native: false)
    @ui.start_fuzzy_finder(@session, title: 'Files') { :needs_refresh }
    settle
    feed("\r")
    assert refreshed
  end

  def test_starting_global_search_closes_finder
    @ui.start_global_search([])
    refute @ui.fuzzy_finder_active?
    refute @session.active?
  ensure
    @ui.instance_variable_get(:@global_search).close
  end
end
