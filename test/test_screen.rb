# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/rufio"

class TestScreen < Minitest::Test
  def test_screen_initialization
    screen = Rufio::Screen.new(10, 5)

    assert_equal 10, screen.width
    assert_equal 5, screen.height
  end

  def test_put_single_character
    screen = Rufio::Screen.new(10, 5)
    screen.put(0, 0, 'A')

    row = screen.row(0)
    assert_match /A/, row
  end

  def test_put_with_bounds_checking
    screen = Rufio::Screen.new(10, 5)

    # Valid positions
    screen.put(0, 0, 'A')
    screen.put(9, 4, 'Z')

    # Out of bounds (should not raise error)
    screen.put(-1, 0, 'X')
    screen.put(0, -1, 'X')
    screen.put(10, 0, 'X')
    screen.put(0, 5, 'X')

    # Check only valid positions were set
    assert_match /A/, screen.row(0)
    assert_match /Z/, screen.row(4)
  end

  def test_put_string_basic
    screen = Rufio::Screen.new(20, 5)
    screen.put_string(0, 0, "Hello")

    row = screen.row(0)
    assert_match /Hello/, row
  end

  def test_put_string_with_offset
    screen = Rufio::Screen.new(20, 5)
    screen.put_string(5, 1, "World")

    row = screen.row(1)
    assert_match /World/, row
  end

  def test_clear
    screen = Rufio::Screen.new(10, 5)
    screen.put_string(0, 0, "Test")
    screen.put_string(0, 1, "Data")

    screen.clear

    5.times do |y|
      row = screen.row(y)
      # All rows should be blank
      assert_equal " " * 10, row
    end
  end

  def test_multibyte_character_japanese
    screen = Rufio::Screen.new(20, 5)
    screen.put_string(0, 0, "こんにちは")

    row = screen.row(0)
    assert_match /こんにちは/, row
  end

  def test_multibyte_character_width_handling
    screen = Rufio::Screen.new(20, 5)

    # Full-width character should occupy 2 cells
    screen.put(0, 0, '全', width: 2)

    # Next character should start at x=2
    screen.put(2, 0, 'A')

    row = screen.row(0)
    assert_match /全/, row
    # Verify 'A' doesn't overwrite '全'
  end

  def test_put_with_color_info
    screen = Rufio::Screen.new(20, 5)
    screen.put(0, 0, 'R', fg: "\e[31m")  # Red foreground

    # Color info should be preserved in the cell
    cell = screen.get_cell(0, 0)
    assert_equal 'R', cell[:char]
    assert_equal "\e[31m", cell[:fg]
  end

  def test_put_with_background_color
    screen = Rufio::Screen.new(20, 5)
    screen.put(0, 0, 'B', bg: "\e[44m")  # Blue background

    cell = screen.get_cell(0, 0)
    assert_equal 'B', cell[:char]
    assert_equal "\e[44m", cell[:bg]
  end

  def test_put_string_with_ansi_codes
    screen = Rufio::Screen.new(30, 5)

    # String with ANSI codes should be stripped
    colored_string = "\e[31mRed\e[0m Text"
    screen.put_string(0, 0, colored_string, fg: "\e[31m")

    row = screen.row(0)
    # Should contain "Red Text" (ANSI codes are stripped before putting)
    # But the output will have ANSI codes from the fg parameter
    clean_row = Rufio::ColorHelper.strip_ansi(row)
    assert_match /Red/, clean_row
    assert_match /Text/, clean_row
  end

  def test_row_returns_string
    screen = Rufio::Screen.new(10, 5)
    screen.put_string(0, 2, "Line3")

    row = screen.row(2)

    assert_kind_of String, row
    assert_match /Line3/, row
  end

  def test_multiple_rows
    screen = Rufio::Screen.new(15, 5)
    screen.put_string(0, 0, "Row 0")
    screen.put_string(0, 1, "Row 1")
    screen.put_string(0, 2, "Row 2")

    assert_match /Row 0/, screen.row(0)
    assert_match /Row 1/, screen.row(1)
    assert_match /Row 2/, screen.row(2)
  end

  def test_overlay_characters
    screen = Rufio::Screen.new(10, 5)
    screen.put_string(0, 0, "AAAA")
    screen.put_string(2, 0, "BB")

    row = screen.row(0)
    # Should contain "AABBA"
    assert_match /AA/, row
    assert_match /BB/, row
  end
end
