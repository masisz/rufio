# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestBackgroundStatus < Minitest::Test
  class Executor
    attr_accessor :running, :completion
    attr_reader :consumed

    def initialize
      @running = false
      @consumed = 0
    end

    def running?
      @running
    end

    def consume_completion_message
      @consumed += 1
      return nil if running?

      message = @completion
      @completion = nil
      message
    end
  end

  def test_polling_and_expiration_request_redraw_only_when_state_changes
    status = Rufio::BackgroundStatus.new(now: Time.at(0))
    executor = Executor.new
    refute status.update(executor, now: Time.at(0.05))
    assert_equal 0, executor.consumed
    executor.running = true
    assert status.update(executor, now: Time.at(0.06))
    refute status.update(executor, now: Time.at(0.07))
    executor.running = false
    executor.completion = 'done'
    assert status.update(executor, now: Time.at(0.2))
    assert_equal 'done', status.message
    refute status.update(executor, now: Time.at(3.19))
    assert_equal 'done', status.message
    assert status.update(executor, now: Time.at(3.2))
    assert_nil status.message
    refute status.update(executor, now: Time.at(3.3))
  end

  def test_new_completion_restarts_display_duration
    status = Rufio::BackgroundStatus.new(now: Time.at(0))
    executor = Executor.new
    executor.completion = 'first'
    status.update(executor, now: Time.at(1))
    executor.completion = 'second'
    assert status.update(executor, now: Time.at(3))
    refute status.update(executor, now: Time.at(4))
    assert_equal 'second', status.message
    assert status.update(nil, now: Time.at(6))
    assert_nil status.message
  end

  def test_footer_uses_completion_state_without_consuming_it
    Dir.mktmpdir do |dir|
      handler = Rufio::KeybindHandler.new
      handler.set_directory_listing(Rufio::DirectoryListing.new(dir))
      executor = Executor.new
      executor.completion = 'completed'
      renderer = Rufio::UIRenderer.new(screen_width: 160, screen_height: 24,
        keybind_handler: handler, directory_listing: Rufio::DirectoryListing.new(dir), background_executor: executor)
      now = Time.now
      renderer.background_status.update(executor, now: now + 1)
      screen = Rufio::Screen.new(160, 24)
      2.times { renderer.draw_footer_to_buffer(screen, 0) }
      assert_includes screen.row(0).gsub(/\e\[[0-9;]*m/, ''), 'completed'
      assert_equal 'completed', renderer.background_status.message
      renderer.background_status.update(executor, now: now + 4)
      renderer.draw_footer_to_buffer(screen, 0)
      refute_includes screen.row(0).gsub(/\e\[[0-9;]*m/, ''), 'completed'
    end
  end

  def test_terminal_shares_tab_state_and_refresh_invalidates_renderer_caches
    terminal = Rufio::TerminalUI.new
    assert_same terminal.ui_renderer.tab_mode_manager, terminal.instance_variable_get(:@tab_mode_manager)
    assert_same terminal.ui_renderer.background_status, terminal.instance_variable_get(:@background_status)
    renderer = Minitest::Mock.new
    renderer.expect(:clear_preview_cache, nil)
    renderer.expect(:clear_bookmark_cache, nil)
    terminal.stub(:update_screen_size, nil) do
      terminal.instance_variable_set(:@ui_renderer, renderer)
      terminal.refresh_display
    end
    renderer.verify
  end
end
