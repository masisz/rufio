# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/rufio"

# write / print の呼び出し回数を記録するスパイ
class OutputSpy
  attr_reader :writes, :prints

  def initialize
    @buffer = String.new
    @writes = []
    @prints = []
  end

  def write(str)
    @writes << str
    @buffer << str.to_s
    str.to_s.length
  end

  def print(str)
    @prints << str
    @buffer << str.to_s
    nil
  end

  def flush; nil; end
  def string; @buffer; end
end

class TestRenderer < Minitest::Test
  def test_renderer_initialization
    output = StringIO.new
    renderer = Rufio::Renderer.new(10, 5, output: output)

    assert_kind_of Rufio::Renderer, renderer
  end

  def test_render_with_content
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)
    screen.put_string(0, 0, "Hello")

    renderer.render(screen)

    # Should contain "Hello"
    assert_match /Hello/, output.string
  end

  def test_diff_rendering_skips_unchanged_lines
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    # First render
    screen.put_string(0, 0, "Line 0")
    renderer.render(screen)
    output.string.clear

    # Second render (no changes)
    renderer.render(screen)

    # Should not output anything (no changes)
    assert_equal "", output.string
  end

  def test_diff_rendering_updates_changed_lines
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    # First render
    screen.put_string(0, 0, "Original")
    renderer.render(screen)
    output.string.clear

    # Change line 0
    screen.clear
    screen.put_string(0, 0, "Modified")

    renderer.render(screen)

    # Should update only changed line
    assert_match /Modified/, output.string
  end

  def test_render_multiple_lines
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    screen.put_string(0, 0, "Line 0")
    screen.put_string(0, 1, "Line 1")
    screen.put_string(0, 2, "Line 2")

    renderer.render(screen)

    result = output.string
    assert_match /Line 0/, result
    assert_match /Line 1/, result
    assert_match /Line 2/, result
  end

  def test_resize_clears_front_buffer
    output = StringIO.new
    renderer = Rufio::Renderer.new(10, 5, output: output)
    screen = Rufio::Screen.new(10, 5)

    # Render something
    screen.put_string(0, 0, "Test")
    renderer.render(screen)
    output.string.clear

    # Resize
    renderer.resize(20, 10)

    # Should clear the screen
    assert_match /\e\[2J/, output.string  # Clear screen code
  end

  def test_clear_resets_front_buffer
    output = StringIO.new
    renderer = Rufio::Renderer.new(10, 5, output: output)
    screen = Rufio::Screen.new(10, 5)

    # Render something
    screen.put_string(0, 0, "Test")
    renderer.render(screen)
    output.string.clear

    # Clear
    renderer.clear

    # Should clear the screen
    assert_match /\e\[2J/, output.string
  end

  def test_render_with_ansi_colors
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    screen.put_string(0, 0, "Red", fg: "\e[31m")

    renderer.render(screen)

    result = output.string
    # Should contain ANSI color codes
    assert_match /\e\[31m/, result
    # Each character is wrapped in ANSI codes, so check for 'R'
    assert_match /R/, result
    assert_match /e/, result
    assert_match /d/, result
  end

  def test_incremental_updates
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    # First frame
    screen.put_string(0, 0, "Frame 1")
    renderer.render(screen)
    output1 = output.string.dup
    output.string.clear

    # Second frame (change line 1)
    screen.put_string(0, 1, "Frame 2")
    renderer.render(screen)
    output2 = output.string

    # First output should contain line 0
    assert_match /Frame 1/, output1

    # Second output should only contain line 1 (diff rendering)
    refute_match /Frame 1/, output2
    assert_match /Frame 2/, output2
  end

  def test_render_returns_false_when_nothing_to_render
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    result = renderer.render(screen)

    assert_equal false, result
    assert_equal "", output.string
  end

  def test_render_returns_true_when_rows_updated
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)
    screen.put_string(0, 0, "Hello")

    result = renderer.render(screen)

    assert_equal true, result
  end

  def test_render_with_fullwidth_chars
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    screen.put_string(0, 0, "日本語")
    renderer.render(screen)

    result = output.string
    assert_match(/日/, result)
    assert_match(/本/, result)
    assert_match(/語/, result)
  end

  def test_render_fullwidth_diff_update
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 5, output: output)
    screen = Rufio::Screen.new(20, 5)

    screen.put_string(0, 0, "ASCII only")
    renderer.render(screen)
    output.string.clear

    screen.clear
    screen.put_string(0, 0, "日本語テスト")
    renderer.render(screen)

    assert_match(/日本語テスト/, Rufio::ColorHelper.strip_ansi(output.string))
  end

  def test_resize_allows_rendering_with_new_dimensions
    output = StringIO.new
    renderer = Rufio::Renderer.new(10, 5, output: output)
    screen = Rufio::Screen.new(20, 8)

    renderer.resize(20, 8)
    output.string.clear

    screen.put_string(0, 0, "After resize")
    renderer.render(screen)

    assert_match(/After resize/, output.string)
  end
end
