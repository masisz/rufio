# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# Files モードでは現在のパスを最上段（ブックマーク一覧の上）に表示する
class TestPathHeader < Minitest::Test
  WIDTH = 200
  HEIGHT = 20

  def setup
    @test_dir = File.realpath(Dir.mktmpdir('rufio_path_header'))
    %w[alpha.txt beta.txt gamma.txt].each { |name| File.write(File.join(@test_dir, name), name) }
    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @keybind_handler = Rufio::KeybindHandler.new
    @keybind_handler.set_directory_listing(@directory_listing)
    @ui_renderer = Rufio::UIRenderer.new(
      screen_width: WIDTH,
      screen_height: HEIGHT,
      keybind_handler: @keybind_handler,
      directory_listing: @directory_listing,
      file_preview: Rufio::FilePreview.new
    )
    @screen = Rufio::Screen.new(WIDTH, HEIGHT)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def row(y)
    Rufio::ColorHelper.strip_ansi(@screen.row(y))
  end

  def test_path_is_drawn_above_bookmark_list
    @ui_renderer.draw_screen(@screen)
    assert_includes row(0), @test_dir
    assert_match(/\A0\./, row(1).strip)
    refute_includes row(1), @test_dir
  end

  def test_file_list_starts_below_bookmark_list
    @ui_renderer.draw_screen(@screen)
    first_entry = @keybind_handler.send(:get_active_entries).first[:name]
    second_entry = @keybind_handler.send(:get_active_entries)[1][:name]
    assert_includes row(2), first_entry
    assert_includes row(3), second_entry
  end

  def test_bottom_tab_line_no_longer_shows_path
    @ui_renderer.draw_screen(@screen)
    bottom = row(HEIGHT - 1)
    assert_includes bottom, "rufio v#{Rufio::VERSION}"
    refute_includes bottom, File.basename(@test_dir)
  end

  def test_job_mode_keeps_path_on_tab_line
    @ui_renderer.draw_screen(@screen, in_job_mode: true, job_manager: Rufio::JobManager.new)
    assert_includes row(HEIGHT - 1), File.basename(@test_dir)
  end

  def test_header_path_uses_tilde_and_truncates_from_left
    home = Dir.home
    assert_equal '~/projects/app', @ui_renderer.format_header_path(File.join(home, 'projects', 'app'), 80)
    assert_equal '~', @ui_renderer.format_header_path(home, 80)
    assert_equal '/usr/local/bin', @ui_renderer.format_header_path('/usr/local/bin', 80)
    long = "/#{'very_long_directory/' * 10}target"
    shown = @ui_renderer.format_header_path(long, 30)
    assert_operator Rufio::TextUtils.display_width(shown), :<=, 30
    assert shown.start_with?('…')
    assert shown.end_with?('/target')
  end

  def test_mouse_click_maps_rows_below_the_two_header_lines
    ui = Rufio::TerminalUI.new(test_mode: true)
    ui.instance_variable_set(:@keybind_handler, @keybind_handler)
    ui.instance_variable_set(:@screen_height, HEIGHT)
    entries = @keybind_handler.send(:get_active_entries)

    # ターミナル行は 1 始まり: 1=パス, 2=ブックマーク, 3=最初のエントリ
    ui.send(:handle_mouse_file_click, 3)
    assert_equal 0, @keybind_handler.current_index
    ui.send(:handle_mouse_file_click, 4)
    assert_equal 1, @keybind_handler.current_index
    assert_equal entries[1][:name], @keybind_handler.send(:get_active_entries)[@keybind_handler.current_index][:name]

    # ブックマーク行のクリックではファイル選択を変えない
    ui.send(:handle_mouse_file_click, 2)
    assert_equal 1, @keybind_handler.current_index
  end
end
