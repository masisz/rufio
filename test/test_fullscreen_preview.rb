# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/rufio'

class TestFullscreenPreview < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    File.write(File.join(@root, 'preview.txt'), "#{'wide content ' * 8}\nsecond line")
    Dir.mkdir(File.join(@root, 'folder'))
    @handler = Rufio::KeybindHandler.new
    @listing = Rufio::DirectoryListing.new(@root)
    @handler.set_directory_listing(@listing)
    @handler.select_index(@handler.get_active_entries.index { |entry| entry[:name] == 'preview.txt' })
    @screen = Rufio::Screen.new(80, 24)
    @ui = Rufio::TerminalUI.new
    @ui.instance_variable_set(:@screen_width, 80)
    @ui.instance_variable_set(:@keybind_handler, @handler)
    @handler.set_terminal_ui(@ui)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_p_opens_and_escape_restores_selection
    index = @handler.current_index
    assert @handler.handle_key('P')
    assert @handler.preview_focused?
    @handler.handle_key('j')
    assert_equal 1, @handler.preview_scroll_offset
    @handler.handle_key("\e")
    refute @handler.preview_focused?
    assert_equal index, @handler.current_index
  end

  def test_enter_does_not_preview_files_but_enters_directories
    @handler.handle_key("\r")
    refute @handler.preview_focused?
    @handler.select_index(@handler.get_active_entries.index { |entry| entry[:name] == 'folder' })
    refute @handler.handle_key('P')
    assert @handler.handle_key("\r")
    assert_equal File.join(@root, 'folder'), @listing.current_path
  end

  def test_fullscreen_hides_list_and_separator_even_when_preview_disabled
    renderer = Rufio::UIRenderer.new(screen_width: 80, screen_height: 24,
      keybind_handler: @handler, directory_listing: @listing,
      file_preview: Rufio::FilePreview.new, preview_enabled: false)
    @handler.focus_preview_pane
    renderer.draw_screen(@screen)
    rows = (2..22).map { |y| Rufio::ColorHelper.strip_ansi(@screen.row(y)) }
    refute_includes rows.join, 'folder'
    refute_includes rows.join, '│'
    assert_includes rows.first, '[PREVIEW MODE]'
    assert_operator rows[2].rstrip.length, :>, 40
    @handler.handle_key("\e")
    renderer.draw_screen(@screen)
    assert_includes (2..22).map { |y| Rufio::ColorHelper.strip_ansi(@screen.row(y)) }.join, 'folder'
  end

  def test_fullscreen_click_cannot_select_hidden_files
    @handler.focus_preview_pane
    index = @handler.current_index
    @ui.send(:handle_mouse_left_click, 1, 6)
    assert @handler.preview_focused?
    assert_equal index, @handler.current_index
  end

  def test_fullscreen_wheel_scrolls_on_both_sides
    @handler.focus_preview_pane
    @ui.send(:handle_mouse_scroll, :down, 1, 6)
    @ui.send(:handle_mouse_scroll, :down, 79, 6)
    assert_equal 2, @handler.preview_scroll_offset
  end
end
