# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

class TestCommandCompletionInitialization < Minitest::Test
  def test_single_command_mode_argument_is_used_as_command_source
    mode = Rufio::CommandMode.new
    def mode.available_commands
      [:custom_command]
    end
    completion = Rufio::CommandCompletion.new(mode)
    assert_equal ['custom_command'], completion.complete('custom')
  end

  def test_history_and_command_mode_arguments_keep_history_completion
    Dir.mktmpdir do |dir|
      history = Rufio::CommandHistory.new(File.join(dir, 'history'))
      history.add('!rufio_unique_test_command --flag')
      completion = Rufio::CommandCompletion.new(history, Rufio::CommandMode.new)
      assert_includes completion.complete('!rufio_unique_test_command'), '!rufio_unique_test_command --flag'
    end
  end
end
