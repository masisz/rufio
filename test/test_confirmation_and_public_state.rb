# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestConfirmationAndPublicState < Minitest::Test
  class DialogHost
    include Rufio::DialogSupport

    private

    def show_overlay_dialog(*)
      yield
    end
  end

  def test_shared_confirmation_ignores_unknown_keys_and_accepts_uppercase
    keys = ['?', ' ', 'Y']
    STDIN.stub(:getch, -> { keys.shift || raise('unexpected extra input') }) do
      assert DialogHost.new.send(:confirm_dialog, 'Confirm', [])
    end
    assert_empty keys
  end

  def test_shared_confirmation_accepts_each_cancel_key
    ['n', 'N', "\e", "\x03", 'q'].each do |key|
      STDIN.stub(:getch, key) do
        refute DialogHost.new.send(:confirm_dialog, 'Confirm', [])
      end
    end
  end

  def test_exit_confirmation_preserves_its_distinct_cancel_keys
    controller = Rufio::FileOperationController.new(nil, nil, nil, nil, nil)
    keys = ['q', 'Y']
    controller.stub(:show_overlay_dialog, ->(*, &block) { block.call }) do
      STDIN.stub(:getch, -> { keys.shift || raise('unexpected extra input') }) do
        assert controller.show_exit_confirmation
      end
    end
    assert_empty keys
  end

  def test_move_and_copy_confirmation_preserve_text_colors_and_cancel_behavior
    controller = Rufio::FileOperationController.new(nil, nil, nil, nil, nil)
    { move: '34', copy: '32' }.each do |action, color|
      title = action.to_s.capitalize
      display = ->(dialog_title, lines, options, &block) do
        assert_equal "#{title} Confirmation", dialog_title
        assert_includes lines, "#{title} 2 item(s)?"
        assert_includes lines, 'From: /source'
        assert_includes lines, 'To:   /destination'
        assert_equal "\e[#{color}m", options[:border_color]
        block.call
      end
      controller.stub(:show_overlay_dialog, display) do
        STDIN.stub(:getch, 'q') do
          refute controller.send("show_#{action}_confirmation", 2, '/source', '/destination')
        end
      end
    end
  end

  def test_history_entries_are_independent_snapshots_and_do_not_change_navigation
    Dir.mktmpdir do |dir|
      history = Rufio::CommandHistory.new(File.join(dir, 'history'))
      history.add('!git status'.dup)
      history.add('hello'.dup)
      assert_equal 'hello', history.previous
      entries = history.entries
      entries.first.replace('corrupted')
      entries.clear
      assert_equal ['!git status', 'hello'], history.entries
      assert_equal '!git status', history.previous
    end
  end

  def test_shell_completion_uses_public_history_interface
    history = Struct.new(:entries).new(['!git status', 'git log', '!ls'])
    result = Rufio::ShellCommandCompletion.new.complete_from_history('git', history)
    assert_includes result, 'git status'
    assert_includes result, 'git log'
    refute_includes result, 'ls'
  end

  def test_task_command_is_part_of_its_normal_initialization
    job = Rufio::TaskStatus.new(id: 1, name: 'test', path: '/tmp', command: 'echo test')
    assert_equal 'echo test', job.command
    assert_nil Rufio::TaskStatus.new(id: 2, name: 'legacy', path: '/tmp').command
    managed = Rufio::JobManager.new.add_job(name: 'test', path: '/tmp', command: 'echo managed')
    assert_equal 'echo managed', managed.command
    refute_includes managed.singleton_methods, :command
  end

  def test_input_cursor_uses_public_terminal_height
    handler = Rufio::KeybindHandler.new
    handler.instance_variable_set(:@terminal_ui, Struct.new(:screen_height).new(42))
    output, = capture_io { handler.send(:move_to_input_line) }
    assert_equal "\e[42;1H\e[2K", output
    assert_respond_to Rufio::TerminalUI.new, :screen_height
  end
end
