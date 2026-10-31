# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestKeyInput < Minitest::Test
  def teardown
    Rufio::KeyInput.detach
  end

  def test_reads_stdin_when_no_queue_is_attached
    STDIN.stub(:getch, 'a') do
      assert_equal 'a', Rufio::KeyInput.getch
    end
  end

  # Windows では入力スレッドが STDIN を読み続けるため、ダイアログもキューから読む
  def test_reads_from_attached_queue_instead_of_stdin
    queue = Queue.new
    'ab'.bytes.each { |b| queue << b }
    Rufio::KeyInput.attach(queue)

    STDIN.stub(:getch, -> { flunk 'STDIN must not be read while a queue is attached' }) do
      assert_equal 'a', Rufio::KeyInput.getch
      assert_equal 'b', Rufio::KeyInput.getch
    end
  end

  def test_assembles_multibyte_characters_from_queue
    queue = Queue.new
    'あ'.bytes.each { |b| queue << b }
    Rufio::KeyInput.attach(queue)

    assert_equal 'あ', Rufio::KeyInput.getch
  end

  def test_waits_for_input_from_queue
    queue = Queue.new
    Rufio::KeyInput.attach(queue)
    reader = Thread.new { Rufio::KeyInput.getch }

    sleep 0.01
    queue << 'x'.ord
    assert_equal 'x', reader.value
  end

  def test_input_dialog_reads_every_key_from_attached_queue
    queue = Queue.new
    "abc\r".bytes.each { |b| queue << b }
    Rufio::KeyInput.attach(queue)
    renderer = Rufio::DialogRenderer.new

    result = nil
    capture_io do
      STDIN.stub(:getch, -> { flunk 'STDIN must not be read while a queue is attached' }) do
        result = renderer.show_input_dialog('Add Bookmark', 'Enter bookmark name:')
      end
    end
    assert_equal 'abc', result
  end

  def test_build_char_returns_nil_for_incomplete_multibyte
    assert_nil Rufio::KeyInput.build_char(0xE3, Queue.new)
  end
end
