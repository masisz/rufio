# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestProjectCommand < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @project_dir = File.join(@temp_dir, 'test_project')
      FileUtils.mkdir_p(@project_dir)

      @log_dir = File.join(@temp_dir, 'logs')
      @command = ProjectCommand.new(@log_dir)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # コマンドは選択したディレクトリをカレントにして実行される
    def test_execute_command_in_selected_directory
      # テスト用のファイルを作成
      test_file = File.join(@project_dir, 'test.txt')
      File.write(test_file, 'test content')

      # lsコマンドを実行
      result = @command.execute('ls', @project_dir)

      assert result[:success]
      assert_includes result[:output], 'test.txt'
    end

    # コマンドの実行結果は右画面に表示される
    def test_command_output_displayed_on_right_pane
      result = @command.execute('echo "Hello, World!"', @project_dir)

      assert result[:success]
      assert_equal "Hello, World!\n", result[:output]
    end

    # コマンド実行エラーはエラーメッセージが返される
    def test_command_execution_error
      result = @command.execute('invalid_command_xyz', @project_dir)

      assert_equal false, result[:success]
      assert_includes result[:error], 'invalid_command_xyz'
    end

    # あらかじめ登録してあるコマンドを呼び出すことができる
    def test_execute_registered_command
      @command.register('test_cmd', 'echo "Registered command"')

      result = @command.execute_registered('test_cmd', @project_dir)

      assert result[:success]
      assert_equal "Registered command\n", result[:output]
    end

    # 登録されていないコマンドは失敗する
    def test_execute_unregistered_command
      result = @command.execute_registered('nonexistent_cmd', @project_dir)

      assert_equal false, result[:success]
      assert_includes result[:error], 'not found'
    end

    # 複数のコマンドを登録できる
    def test_register_multiple_commands
      @command.register('cmd1', 'echo "Command 1"')
      @command.register('cmd2', 'echo "Command 2"')

      commands = @command.list_registered_commands

      assert_equal 2, commands.length
      assert_includes commands, 'cmd1'
      assert_includes commands, 'cmd2'
    end

    # 登録したコマンドは左画面に一覧表示される
    def test_list_commands_for_left_pane
      @command.register('build', 'npm run build')
      @command.register('test', 'npm test')

      display_data = @command.get_left_pane_data

      assert_equal 2, display_data.length
      assert_includes display_data[0], 'build'
      assert_includes display_data[1], 'test'
    end
  end
end
