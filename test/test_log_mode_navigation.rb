# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

class TestLogModeNavigation < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-log-mode')
    @listing = Rufio::DirectoryListing.new(@root)
    @handler = Rufio::KeybindHandler.new
    @handler.set_directory_listing(@listing)
    @logs = File.join(@root, 'logs')
    @handler.instance_variable_set(:@log_dir, @logs)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_repeated_logs_key_does_not_lose_return_directory
    @handler.handle_key('L')
    @handler.handle_key('L')
    @handler.handle_key("\e")

    refute @handler.log_viewer_mode?
    assert_equal @root, @listing.current_path
  end

  def test_help_from_logs_returns_to_original_directory
    @handler.handle_key('L')
    @handler.enter_help_mode

    assert @handler.help_mode?
    refute @handler.log_viewer_mode?

    @handler.handle_key("\e")
    assert_equal @root, @listing.current_path
  end

  def test_logs_from_help_returns_to_original_directory
    @handler.enter_help_mode
    @handler.handle_key('L')

    assert @handler.log_viewer_mode?
    refute @handler.help_mode?

    @handler.handle_key("\e")
    assert_equal @root, @listing.current_path
  end
end
