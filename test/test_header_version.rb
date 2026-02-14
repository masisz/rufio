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

    # タイトルバーにバージョンが含まれることを確認（draw_header_to_buffer）
    def test_draw_header_to_buffer_includes_version
      ui = TerminalUI.new(test_mode: true)
      directory_listing = DirectoryListing.new(@temp_dir)
      keybind_handler = KeybindHandler.new
      keybind_handler.set_directory_listing(directory_listing)

      # 内部変数を直接設定（startはメインループを起動するため）
      ui.instance_variable_set(:@directory_listing, directory_listing)
      ui.instance_variable_set(:@keybind_handler, keybind_handler)
      ui.instance_variable_set(:@screen_width, 120)

      screen = Screen.new(120, 24)
      ui.send(:draw_header_to_buffer, screen, 0)

      header_row = screen.row(0).gsub(/\e\[[0-9;]*m/, '')
      assert_match(/rufio v#{Regexp.escape(VERSION)}/, header_row,
        "タイトルバーにバージョン v#{VERSION} が含まれるべき")
    end

    # タイトルバーにバージョンが含まれることを確認（draw_header）
    def test_draw_header_includes_version
      ui = TerminalUI.new(test_mode: true)
      directory_listing = DirectoryListing.new(@temp_dir)
      keybind_handler = KeybindHandler.new
      keybind_handler.set_directory_listing(directory_listing)

      ui.instance_variable_set(:@directory_listing, directory_listing)
      ui.instance_variable_set(:@keybind_handler, keybind_handler)
      ui.instance_variable_set(:@screen_width, 120)

      output = StringIO.new
      $stdout = output
      begin
        ui.send(:draw_header)
      ensure
        $stdout = STDOUT
      end

      assert_match(/rufio v#{Regexp.escape(VERSION)}/, output.string,
        "タイトルバーにバージョン v#{VERSION} が含まれるべき")
    end
  end
end
