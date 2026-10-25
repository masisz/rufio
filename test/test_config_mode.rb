# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestConfigMode < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-config-mode')
    @config = File.join(@root, 'config')
    @listing = Rufio::DirectoryListing.new(@root)
    @handler = Rufio::KeybindHandler.new
    @handler.set_directory_listing(@listing)
    config = @config
    @handler.define_singleton_method(:config_directory) { config }
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_C_creates_and_opens_config_directory
    assert @handler.handle_key('C')
    assert Dir.exist?(@config)
    assert_equal @config, @listing.current_path
    assert @handler.config_mode?
    @handler.handle_key('C')
    assert_equal @config, @listing.current_path
  end

  def test_config_mode_uses_normal_file_navigation_and_preview
    FileUtils.mkdir_p(File.join(@config, 'scripts'))
    File.write(File.join(@config, 'config.rb'), '# settings')
    @handler.handle_key('C')
    @handler.select_index(@handler.get_active_entries.index { |entry| entry[:name] == 'scripts' })
    @handler.handle_key('l')
    assert_equal File.join(@config, 'scripts'), @listing.current_path
    assert @handler.config_mode?
    @handler.handle_key('h')
    @handler.select_index(@handler.get_active_entries.index { |entry| entry[:name] == 'config.rb' })
    @handler.handle_key("\r")
    assert @handler.preview_focused?
    @handler.handle_key("\e")
    refute @handler.preview_focused?
    assert_equal @config, @listing.current_path
    @handler.handle_key('h')
    refute @handler.config_mode?
  end

  def test_C_exits_logs_and_preview
    logs = File.join(@root, 'logs')
    FileUtils.mkdir_p(logs)
    File.write(File.join(logs, 'run.log'), 'log')
    @handler.instance_variable_set(:@log_dir, logs)
    @handler.handle_key('L')
    @handler.select_index(0)
    @handler.handle_key("\r")
    assert @handler.preview_focused?
    @handler.handle_key('C')
    refute @handler.log_viewer_mode?
    refute @handler.preview_focused?
    assert_equal @config, @listing.current_path
  end

  def test_C_is_text_while_filtering
    @handler.handle_key('f')
    @handler.handle_key('C')
    assert_equal @root, @listing.current_path
    assert_equal 'C', @handler.filter_query
  end

  def test_bottom_bar_highlights_config
    @handler.handle_key('C')
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 24,
                                   keybind_handler: @handler, directory_listing: @listing)
    screen = Rufio::Screen.new(100, 24)
    renderer.draw_mode_tabs_to_buffer(screen, 23)
    assert_includes Rufio::ColorHelper.strip_ansi(screen.row(23)), '[C] Config'
    assert_equal :config, renderer.tab_mode_manager.current_mode
  end
end
