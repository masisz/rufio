# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestNavigationModeContracts < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio-navigation-modes')
    @child = File.join(@root, 'child')
    FileUtils.mkdir_p(@child)
    @listing = Rufio::DirectoryListing.new(@root)
    @handler = Rufio::KeybindHandler.new
    @handler.set_directory_listing(@listing)
    @logs = File.join(@root, 'logs')
    @config = File.join(@root, 'config')
    @handler.instance_variable_set(:@log_dir, @logs)
    config = @config
    @handler.define_singleton_method(:config_directory) { config }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_all_navigation_routes_reset_selection_and_filter_after_success
    [:absolute, :enter, :parent].each do |route|
      @listing.navigate_to_path(route == :parent ? @child : @root)
      filter = Rufio::FilterManager.new
      filter.start_filter_mode(@listing.list_entries)
      filter.handle_filter_input('child')
      nav = Rufio::NavigationController.new(@listing, filter)
      nav.select_index(2)
      result = case route
               when :absolute then nav.navigate_to_directory(@child)
               when :enter then nav.navigate_enter({ type: 'directory', name: 'child' }, false, false)
               when :parent then nav.navigate_parent
               end
      assert result, route.to_s
      assert_equal 0, nav.current_index
      refute filter.filter_active?
      assert_equal(route == :parent ? @root : @child, @listing.current_path)
    end
  end

  def test_failed_navigation_keeps_selection_filter_and_location
    filter = Rufio::FilterManager.new
    filter.start_filter_mode(@listing.list_entries)
    filter.handle_filter_input('child')
    nav = Rufio::NavigationController.new(@listing, filter)
    nav.select_index(2)
    refute nav.navigate_to_directory(File.join(@root, 'missing'))
    assert_equal 2, nav.current_index
    assert_equal 'child', filter.filter_query
    assert filter.filter_mode
    assert_equal @root, @listing.current_path
  end

  def test_navigation_without_listing_returns_false
    nav = Rufio::NavigationController.new(nil, Rufio::FilterManager.new)
    refute nav.navigate_to_directory(@child)
    refute nav.navigate_enter({ type: 'directory', name: 'child' }, false, false)
  end

  def test_bookmark_navigation_uses_navigation_controller
    nav = Minitest::Mock.new
    nav.expect(:navigate_to_directory, true, [@child])
    controller = Rufio::BookmarkController.new(nil, nil, nil, nav, nil, nil, nil)
    assert controller.navigate_to_directory(@child)
    nav.verify
  end

  def test_logs_to_jobs_and_back_restores_original_directory
    assert @handler.enter_log_viewer_mode
    assert @handler.enter_job_mode
    refute @handler.log_viewer_mode?
    assert @handler.in_job_mode?
    assert_equal @root, @listing.current_path
    assert @handler.switch_mode(:logs)
    refute @handler.in_job_mode?
    assert @handler.log_viewer_mode?
    assert_equal @logs, @listing.current_path
    assert @handler.switch_mode(:files)
    assert_equal @root, @listing.current_path
    refute @handler.log_viewer_mode?
  end

  def test_help_directory_and_jobs_are_mutually_exclusive
    assert @handler.enter_help_mode
    assert @handler.enter_job_mode
    refute @handler.help_mode?
    assert_equal @root, @listing.current_path
    assert @handler.enter_help_mode
    refute @handler.in_job_mode?
    assert @handler.help_mode?
    assert @handler.switch_mode(:files)
    assert_equal @root, @listing.current_path
  end

  def test_config_transition_closes_jobs_and_preview
    File.write(File.join(@root, 'preview.txt'), 'text')
    @listing.refresh
    index = @handler.get_active_entries.index { |entry| entry[:name] == 'preview.txt' }
    @handler.select_index(index)
    @handler.focus_preview_pane
    assert @handler.preview_focused?
    @handler.enter_job_mode
    assert @handler.switch_mode(:config)
    refute @handler.in_job_mode?
    refute @handler.preview_focused?
    assert @handler.config_mode?
    assert_equal @config, @listing.current_path
  end

  def test_failed_config_preparation_preserves_log_mode
    @handler.enter_log_viewer_mode
    File.write(@config, 'not a directory')
    refute @handler.switch_mode(:config)
    assert @handler.log_viewer_mode?
    assert_equal @logs, @listing.current_path
  end

  def test_reentering_jobs_preserves_selected_job
    2.times { |i| @handler.job_manager.add_job(name: "job#{i}", path: @root, command: 'echo') }
    @handler.enter_job_mode
    @handler.job_mode.handle_key('j')
    assert_equal 1, @handler.job_mode.selected_index
    assert @handler.switch_mode(:jobs)
    assert_equal 1, @handler.job_mode.selected_index
  end

  def test_terminal_delegates_mode_changes_to_handler
    [:files, :logs, :jobs, :config, :global, :help].each do |mode|
      handler = Minitest::Mock.new
      handler.expect(:switch_mode, true, [mode])
      terminal = Rufio::TerminalUI.allocate
      terminal.instance_variable_set(:@keybind_handler, handler)
      assert terminal.send(:apply_mode_change, mode)
      handler.verify
    end
  end

  def test_help_overlay_keeps_current_jobs_mode
    terminal = Minitest::Mock.new
    terminal.expect(:set_job_mode, nil, [@handler.job_mode, @handler.job_manager, @handler.notification_manager])
    terminal.expect(:show_help_dialog, true)
    @handler.instance_variable_set(:@terminal_ui, terminal)
    @handler.enter_job_mode
    assert @handler.switch_mode(:help)
    assert @handler.in_job_mode?
    terminal.verify
  end
end
