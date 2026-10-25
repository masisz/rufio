# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/rufio/help_menu'

class TestHelpMenu < Minitest::Test
  def setup
    @menu = Rufio::HelpMenu.new
    @menu.open
  end

  def test_sections_and_close
    assert @menu.active?
    assert_equal 'Controls', @menu.section
    @menu.handle_key('2')
    assert_equal 'Modes', @menu.section
    @menu.handle_key("\t")
    assert_equal 'Scripts', @menu.section
    @menu.handle_key("\e")
    refute @menu.active?
  end

  def test_small_window_wraps_and_scrolls_without_hiding_navigation
    screen = Rufio::Screen.new(40, 12)
    @menu.draw(screen)
    assert_includes screen.row(10), 'ESC: Close'
    before = (0...12).map { |y| screen.row(y) }
    100.times { @menu.handle_key('j') }
    @menu.draw(screen)
    refute_equal before, (0...12).map { |y| screen.row(y) }
    assert_includes screen.row(10), 'ESC: Close'
    @menu.handle_key('2')
    assert_equal 0, @menu.scroll_offset
  end

  def test_scripts_explains_locations_and_execution
    @menu.handle_key('3')
    content = @menu.content.join("\n")
    assert_includes content, '~/.config/rufio/scripts'
    assert_includes content, 'script_paths.yml'
    assert_includes content, 'rufio.rb'
    assert_includes content, ':hello'
  end

  def test_help_key_opens_overlay_without_changing_directory_or_logs
    Dir.mktmpdir do |root|
      handler = Rufio::KeybindHandler.new
      listing = Rufio::DirectoryListing.new(root)
      handler.set_directory_listing(listing)
      ui = Rufio::TerminalUI.new
      handler.set_terminal_ui(ui)
      handler.instance_variable_set(:@log_dir, File.join(root, 'logs'))
      handler.handle_key('L')
      handler.handle_key('?')
      assert ui.help_dialog_active?
      assert handler.log_viewer_mode?
      assert_equal File.join(root, 'logs'), listing.current_path
      ui.handle_help_input("\e")
      refute ui.help_dialog_active?
      handler.handle_key("\e")
      assert_equal root, listing.current_path
    end
  end
end
