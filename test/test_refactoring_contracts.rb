# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'rbconfig'
require 'shellwords'
require 'timeout'

class TestRefactoringContracts < Minitest::Test
  class DialogHost
    def initialize(renderer, terminal = nil)
      @dialog_renderer = renderer
      @terminal_ui = terminal
    end
  end

  def dialog_host(renderer, terminal = nil)
    DialogHost.include(Rufio::DialogSupport)
    DialogHost.new(renderer, terminal)
  end

  def test_dialog_delegates_options_and_input_block_to_overlay
    terminal = Minitest::Mock.new
    options = { width: 30, height: 8 }
    terminal.expect(:screen, true)
    terminal.expect(:renderer, true)
    terminal.expect(:show_overlay_dialog, 'y') do |title, lines, passed_options, &block|
      title == 'Confirm' && lines == ['body'] && passed_options == options && block.call == 'y'
    end
    host = dialog_host(nil, terminal)

    assert_equal 'y', host.send(:show_overlay_dialog, 'Confirm', ['body'], options) { 'y' }
    terminal.verify
  end

  def test_dialog_fallback_calculates_dimensions_and_cleans_up
    renderer = Minitest::Mock.new
    renderer.expect(:calculate_dimensions, [40, 6], [['body'], { title: 'Title', min_width: 40, max_width: 80 }])
    renderer.expect(:calculate_center, [2, 3], [40, 6])
    renderer.expect(:draw_floating_window, nil, [2, 3, 40, 6, 'Title', ['body'], {
      border_color: "\e[37m", title_color: "\e[1;33m", content_color: "\e[37m"
    }])
    renderer.expect(:clear_area, nil, [2, 3, 40, 6])
    terminal = Struct.new(:screen, :renderer, :refreshed) do
      def refresh_display
        self.refreshed = true
      end
    end.new(nil, true, false)
    host = dialog_host(renderer, terminal)

    STDIN.stub(:getch, 'q') do
      assert_equal 'q', host.send(:show_overlay_dialog, 'Title', ['body'])
    end
    renderer.verify
    assert terminal.refreshed
  end

  def test_dialog_fallback_preserves_explicit_dimensions_colors_and_block_result
    renderer = Minitest::Mock.new
    colors = { border_color: 'border', title_color: 'title', content_color: 'content' }
    renderer.expect(:calculate_center, [1, 2], [20, 5])
    renderer.expect(:draw_floating_window, nil, [1, 2, 20, 5, 'Title', [], colors])
    renderer.expect(:clear_area, nil, [1, 2, 20, 5])
    host = dialog_host(renderer)

    assert_equal :accepted, host.send(:show_overlay_dialog, 'Title', [], colors.merge(width: 20, height: 5)) { :accepted }
    renderer.verify
  end

  def test_filter_footer_distinguishes_editing_from_applied_filter
    Dir.mktmpdir do |dir|
      handler = Rufio::KeybindHandler.new
      handler.set_directory_listing(Rufio::DirectoryListing.new(dir))
      renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 24, keybind_handler: handler)
      screen = Rufio::Screen.new(100, 24)

      handler.send(:start_filter_mode)
      handler.send(:handle_filter_input, 'a')
      renderer.draw_footer_to_buffer(screen, 0)
      assert_includes screen.row(0).gsub(/\e\[[0-9;]*m/, ''), 'Filter mode: Type to filter'

      handler.send(:exit_filter_mode_keep_filter)
      renderer.draw_footer_to_buffer(screen, 0)
      assert_includes screen.row(0).gsub(/\e\[[0-9;]*m/, ''), 'Filtered view active'
    end
  end

  def test_completion_message_is_consumed_once_after_completion
    executor = Rufio::BackgroundCommandExecutor.new(Object.new.tap { |logger| def logger.log(*); end })
    executor.execute_ruby_async('example') { 'done' }
    Timeout.timeout(3) { sleep 0.01 while executor.running? }

    assert_equal '✓ example 完了', executor.get_completion_message
    assert_equal '✓ example 完了', executor.consume_completion_message
    assert_nil executor.consume_completion_message
    assert_nil executor.get_completion_message
  end

  def test_array_execution_preserves_literal_arguments_with_and_without_timeout
    Dir.mktmpdir do |dir|
      script = File.join(dir, 'script with spaces.rb')
      File.write(script, 'puts ARGV; warn ENV.fetch("RUFIO_CONTRACT"); exit 7')
      [nil, 3].each do |timeout|
        result = Rufio::ScriptExecutor.execute(RbConfig.ruby, script, ['a b', '$(echo expanded)'],
          timeout: timeout, chdir: dir, env: { 'RUFIO_CONTRACT' => 'environment' })
        assert_equal "a b\n$(echo expanded)\n", result[:stdout]
        assert_equal "environment\n", result[:stderr]
        assert_equal 7, result[:exit_code]
        refute result[:success]
        refute result[:timeout]
      end
    end
  end

  def test_shell_execution_preserves_shell_syntax_environment_and_working_directory
    Dir.mktmpdir do |dir|
      command = Rufio::DslCommand.new(name: 'shell', shell_command: 'printf "%s" "$RUFIO_CONTRACT"; pwd; exit 7')
      [nil, 3].each do |timeout|
        result = Rufio::ScriptExecutor.execute_shell(command, timeout: timeout, chdir: dir,
          env: { 'RUFIO_CONTRACT' => 'environment:' })
        assert_equal "environment:#{File.realpath(dir)}\n", result[:stdout]
        assert_equal 7, result[:exit_code]
        refute result[:success]
        refute result[:timeout]
      end
    end
  end

  def test_shell_execution_times_out
    command = Rufio::DslCommand.new(name: 'slow', shell_command: "#{RbConfig.ruby.shellescape} -e 'sleep 5'")
    result = Rufio::ScriptExecutor.execute_shell(command, timeout: 0.1)
    assert result[:timeout]
    refute result[:success]
    assert_nil result[:exit_code]
  end
end
