# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/color_helper'
require_relative '../lib/rufio/screen'
require_relative '../lib/rufio/help_menu'

class TestDialogScrollIndicator < Minitest::Test
  def render(offset, total = 20)
    screen = Rufio::Screen.new(40, 12)
    Rufio::DialogRenderer.new.draw_floating_window_to_overlay(
      screen, 0, 0, 40, 12, 'Help', [],
      scroll_offset: offset, total_lines: total, visible_lines: 5
    )
    (0...12).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
  end

  def test_start_only_shows_more_below
    text = render(0)
    assert_includes text, '▼ 下に続く'
    refute_includes text, '▲ 上に続く'
  end

  def test_middle_shows_both_directions
    text = render(7)
    assert_includes text, '▲ 上に続く'
    assert_includes text, '▼ 下に続く'
  end

  def test_end_only_shows_more_above
    text = render(15)
    assert_includes text, '▲ 上に続く'
    refute_includes text, '▼ 下に続く'
  end

  def test_fitting_content_has_no_indicators
    text = render(0, 5)
    refute_includes text, '続く'
  end

  def test_help_passes_scroll_state_to_renderer
    menu = Rufio::HelpMenu.new
    screen = Rufio::Screen.new(40, 12)
    menu.draw(screen)
    assert_includes Rufio::ColorHelper.strip_ansi(screen.row(11)), '▼ 下に続く'
    menu.handle_key('G')
    menu.draw(screen)
    assert_includes Rufio::ColorHelper.strip_ansi(screen.row(0)), '▲ 上に続く'
    refute_includes Rufio::ColorHelper.strip_ansi(screen.row(11)), '▼ 下に続く'
  end
end
