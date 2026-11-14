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

# Mac/Linux の読み取り経路でも、TerminalUI から選択位置の更新まで検証する。
# ESC だけを先に渡し、後続バイトは読み取り待機に入ってから届ける。
class TestGlobalSearchUnixTerminalInput < TestGlobalSearchTerminalInput
  def setup
    skip 'Unix input path requires IO.select on pipes' if RUBY_PLATFORM =~ /mswin|mingw/

    super
    @ui.define_singleton_method(:windows?) { false }
    @input_reader, @input_writer = IO.pipe
    @ui.instance_variable_set(:@multibyte_reader, Rufio::MultibyteInputReader.new(@input_reader))
  end

  def teardown
    @input_reader&.close
    @input_writer&.close
    super if @search
  end

  def feed(sequence)
    query = @search.query.dup
    @input_writer.write(sequence.byteslice(0, 1))
    continuation = sequence.byteslice(1..-1)
    select_method = IO.method(:select)
    select_input = lambda do |ios, *args|
      if !continuation.empty? && args.last > 0
        @input_writer.write(continuation)
        continuation = ''
      end
      select_method.call(ios.map { |io| io.equal?(STDIN) ? @input_reader : io }, *args)
    end
    IO.stub(:select, select_input) do
      STDIN.stub(:read_nonblock, ->(length) { @input_reader.read_nonblock(length) }) do
        assert @ui.send(:handle_input_nonblocking)
      end
    end
    assert @search.active?, "G mode closed for #{sequence.inspect}"
    assert_equal query, @search.query
    assert_empty continuation, 'escape continuation was never read'
    assert_nil select_method.call([@input_reader], nil, nil, 0), 'unconsumed input remains'
  end

  def test_cursor_movement_stops_at_first_and_last_result_and_preserves_query
    @search.instance_variable_set(:@query, 'needle')
    [["\e[B", "\e[A"], ["\eOB", "\eOA"], ["\x0a", "\x0b"],
     ["\e[106;5u", "\e[107;5u"]].each do |down, up|
      2.times { feed(down) }
      assert_equal 1, @search.selected_index
      2.times { feed(up) }
      assert_equal 0, @search.selected_index
    end
  end

  def test_cursor_movement_with_no_results
    @search.instance_variable_set(:@results, [])
    ["\e[B", "\e[A", "\x0a", "\x0b"].each do |key|
      feed(key)
      assert_equal 0, @search.selected_index
    end
  end
end
