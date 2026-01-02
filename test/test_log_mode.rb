# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'
require 'tmpdir'

class TestLogMode < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @log_dir = File.join(@tmpdir, '.rufio', 'log')
    FileUtils.mkdir_p(@log_dir)

    # Create some test log files
    3.times do |i|
      timestamp = Time.now - (i * 60)
      filename = timestamp.strftime("%Y%m%d%H%M%S") + "-test#{i}.log"
      File.write(File.join(@log_dir, filename), "Test log #{i}")
    end

    @directory_listing = Rufio::DirectoryListing.new(@tmpdir)
    @keybind_handler = Rufio::KeybindHandler.new
    @keybind_handler.set_directory_listing(@directory_listing)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_log_mode_not_active_by_default
    refute @keybind_handler.log_viewer_mode?, "ログモードがデフォルトでアクティブになっています"
  end

  def test_enter_log_mode_with_L_key
    # Set log directory
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    result = @keybind_handler.handle_key('L')

    assert @keybind_handler.log_viewer_mode?, "Lキーでログモードに入れません"
  end

  def test_log_mode_changes_directory_to_log_dir
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    @keybind_handler.handle_key('L')

    current_path = @directory_listing.current_path
    assert_equal @log_dir, current_path, "ログディレクトリに移動していません"
  end

  def test_log_mode_displays_log_files
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    @keybind_handler.handle_key('L')

    entries = @directory_listing.list_entries
    log_entries = entries.select { |e| e[:name].end_with?('.log') }

    assert_equal 3, log_entries.size, "ログファイルが表示されていません"
  end

  def test_exit_log_mode_with_ESC
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    # Enter log mode
    @keybind_handler.handle_key('L')
    assert @keybind_handler.log_viewer_mode?

    # Exit with ESC
    @keybind_handler.handle_key("\e")

    refute @keybind_handler.log_viewer_mode?, "ESCキーでログモードを終了できません"
  end

  def test_exit_log_mode_returns_to_original_directory
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    # Enter log mode
    @keybind_handler.handle_key('L')

    # Exit
    @keybind_handler.handle_key("\e")

    current_path = @directory_listing.current_path
    assert_equal @tmpdir, current_path, "元のディレクトリに戻っていません"
  end

  def test_cannot_navigate_above_log_directory
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    # Enter log mode
    @keybind_handler.handle_key('L')

    # Try to go to parent directory
    current_path = @directory_listing.current_path
    @keybind_handler.handle_key('h')

    # Should still be in log directory
    assert_equal current_path, @directory_listing.current_path,
                 "ログディレクトリから上位ディレクトリに移動できてしまいます"
  end

  def test_log_mode_navigation_restricted_to_log_tree
    @keybind_handler.instance_variable_set(:@log_dir, @log_dir)

    # Create a subdirectory in log dir
    subdir = File.join(@log_dir, 'subdir')
    FileUtils.mkdir_p(subdir)

    # Enter log mode
    @keybind_handler.handle_key('L')

    # Navigate to subdir
    @directory_listing.refresh
    entries = @directory_listing.list_entries
    subdir_index = entries.index { |e| e[:name] == 'subdir' }
    @keybind_handler.instance_variable_set(:@current_index, subdir_index)
    @keybind_handler.handle_key('l')

    # Should be in subdir
    assert_equal subdir, @directory_listing.current_path

    # Should be able to go back to log dir
    @keybind_handler.handle_key('h')
    assert_equal @log_dir, @directory_listing.current_path

    # But not above
    @keybind_handler.handle_key('h')
    assert_equal @log_dir, @directory_listing.current_path,
                 "ログディレクトリより上に移動できてしまいます"
  end

  def test_normal_navigation_not_restricted_outside_log_mode
    # Not in log mode
    refute @keybind_handler.log_viewer_mode?

    # Should be able to navigate normally
    parent_dir = File.dirname(@tmpdir)

    # This should work (not restricted)
    @directory_listing.navigate_to_parent

    # Path should have changed
    refute_equal @tmpdir, @directory_listing.current_path,
                 "通常モードで親ディレクトリに移動できません"
  end
end
