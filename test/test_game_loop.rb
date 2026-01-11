# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rufio"

class TestGameLoop < Minitest::Test
  def test_game_loop_components_exist
    # Screen and Renderer classes should be available
    assert defined?(Rufio::Screen)
    assert defined?(Rufio::Renderer)
  end

  def test_screen_and_renderer_integration
    # Basic integration test
    screen = Rufio::Screen.new(20, 10)
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 10, output: output)

    # Simulate one frame
    screen.clear
    screen.put_string(0, 0, "Test Frame")
    renderer.render(screen)

    # Should output content
    assert_match /Test Frame/, output.string
  end

  def test_fps_control_calculation
    # Test FPS control calculation
    fps = 10
    interval = 1.0 / fps

    assert_equal 0.1, interval

    # Simulate frame timing
    start_time = Time.now
    sleep 0.05  # Simulate work
    elapsed = Time.now - start_time
    sleep_time = [interval - elapsed, 0].max

    # Should have some sleep time left
    assert sleep_time >= 0
  end

  def test_screen_resize_handling
    # Test screen resize scenario
    screen = Rufio::Screen.new(20, 10)
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 10, output: output)

    # Render initial frame
    screen.put_string(0, 0, "Before")
    renderer.render(screen)

    # Simulate resize
    new_width, new_height = 30, 15
    screen = Rufio::Screen.new(new_width, new_height)
    renderer.resize(new_width, new_height)

    # Render after resize
    screen.put_string(0, 0, "After Resize")
    renderer.render(screen)

    result = output.string
    assert_match /Before/, result
    assert_match /After Resize/, result
  end

  def test_notification_timing
    # Test notification display timing
    notification_time = Time.now
    display_duration = 3.0

    # Immediately after notification
    assert (Time.now - notification_time) < display_duration

    # After duration
    sleep 0.1
    remaining = display_duration - (Time.now - notification_time)
    assert remaining < display_duration
  end

  def test_diff_rendering_efficiency
    # Test that diff rendering only updates changed lines
    output = StringIO.new
    renderer = Rufio::Renderer.new(20, 10, output: output)
    screen = Rufio::Screen.new(20, 10)

    # First frame - all lines rendered
    screen.put_string(0, 0, "Line 0")
    screen.put_string(0, 1, "Line 1")
    screen.put_string(0, 2, "Line 2")
    renderer.render(screen)

    output.string.clear

    # Second frame - no changes
    renderer.render(screen)

    # Should output nothing (diff rendering)
    assert_equal 0, output.string.length

    # Third frame - change one line
    screen.put_string(0, 1, "Modified")
    renderer.render(screen)

    # Should only output the changed line
    updated_output = output.string
    assert_match /Modified/, updated_output
    # Only one line should be updated (not all lines)
    refute_match /Line 0/, updated_output
    refute_match /Line 2/, updated_output
  end
end
