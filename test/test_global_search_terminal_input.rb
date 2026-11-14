# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestGlobalSearchTerminalInput < Minitest::Test
  def setup
    @ui = Rufio::TerminalUI.new(test_mode: true)
    @ui.instance_variable_set(:@keybind_handler, Rufio::KeybindHandler.new)
    @search = @ui.instance_variable_get(:@global_search)
    @search.open([])
    @search.instance_variable_set(:@results, [
      { path: '/first', relative_path: 'first', bookmark: 'test' },
      { path: '/second', relative_path: 'second', bookmark: 'test' }
    ])
    @queue = Queue.new
    @ui.instance_variable_set(:@input_queue, @queue)
    @ui.define_singleton_method(:windows?) { true }
  end

  def teardown
    @search.close
  end

  def feed(sequence)
    sequence.bytes.each { |byte| @queue << byte }
    assert @ui.send(:handle_input_nonblocking)
    assert @search.active?, "G mode closed for #{sequence.inspect}"
    assert_equal '', @search.query
    assert @queue.empty?, 'escape sequence was not fully consumed'
  end

  def test_legacy_ctrl_and_csi_arrows
    ["\x0a", "\e[B"].each do |down|
      feed(down)
      assert_equal 1, @search.selected_index
      feed("\x0b")
      assert_equal 0, @search.selected_index
    end
    feed("\e[B")
    feed("\e[A")
    assert_equal 0, @search.selected_index
  end

  def test_application_cursor_arrows
    feed("\eOB")
    assert_equal 1, @search.selected_index
    feed("\eOA")
    assert_equal 0, @search.selected_index
  end

  def test_extended_ctrl_j_and_k
    feed("\e[106;5u")
    assert_equal 1, @search.selected_index
    feed("\e[107;5u")
    assert_equal 0, @search.selected_index
  end

  def test_modified_arrows_and_repeat_events
    feed("\e[1;5B")
    assert_equal 1, @search.selected_index
    feed("\e[1;5A")
    assert_equal 0, @search.selected_index
    feed("\e[106;5:2u")
    assert_equal 1, @search.selected_index
  end

  def test_release_and_unknown_sequences_do_not_close_search
    feed("\e[107;5:3u")
    assert_equal 0, @search.selected_index
    feed("\e[99;5u")
    assert_equal 0, @search.selected_index
  end

  def test_unix_waits_for_escape_continuation
    @ui.define_singleton_method(:windows?) { false }
    waited = false
    IO.stub(:select, ->(*args) { waited = true; assert_equal 0.025, args.last; [[STDIN], [], []] }) do
      STDIN.stub(:read_nonblock, '[') do
        assert_equal '[', @ui.send(:read_next_input_byte)
        assert waited, 'Unix must wait briefly for escape continuation'
      end
    end
  end
end
