# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestHeaderVersion < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # モードタブバーにバージョンが含まれることを確認（draw_mode_tabs_to_buffer）
    def test_draw_mode_tabs_includes_version
      ui = TerminalUI.new(test_mode: true)
      directory_listing = DirectoryListing.new(@temp_dir)
      keybind_handler = KeybindHandler.new
      keybind_handler.set_directory_listing(directory_listing)

      ui.instance_variable_set(:@directory_listing, directory_listing)
      ui.instance_variable_set(:@keybind_handler, keybind_handler)
      ui.instance_variable_set(:@screen_width, 120)

      ur = ui.ui_renderer
      ur.keybind_handler = keybind_handler
      ur.directory_listing = directory_listing
      ur.instance_variable_set(:@screen_width, 120)
      ur.instance_variable_set(:@screen_height, 24)

      screen = Screen.new(120, 24)
      ui.ui_renderer.draw_mode_tabs_to_buffer(screen, 23)

      footer_row = screen.row(23).gsub(/\e\[[0-9;]*m/, '')
      assert_match(/rufio v#{Regexp.escape(VERSION)}/, footer_row,
        "モードタブバーにバージョン v#{VERSION} が含まれるべき")
    end
  end
end
