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
      @scripts_dir = File.join(@temp_dir, 'scripts')
      @command = ProjectCommand.new(@log_dir, @scripts_dir)
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

    # スクリプトディレクトリが存在しなければ自動作成される
    def test_scripts_directory_auto_creation
      assert Dir.exist?(@scripts_dir), 'Scripts directory should be auto-created'
    end

    # サンプルスクリプトが自動生成される
    def test_sample_script_creation
      sample_script = File.join(@scripts_dir, 'hello.rb')
      assert File.exist?(sample_script), 'Sample script hello.rb should be created'
      assert File.executable?(sample_script), 'Sample script should be executable'
    end

    # スクリプトディレクトリ内のRubyファイルを一覧表示できる
    def test_list_scripts
      # 追加のスクリプトを作成
      File.write(File.join(@scripts_dir, 'test_script.rb'), '# test script')
      File.write(File.join(@scripts_dir, 'another.rb'), '# another script')

      scripts = @command.list_scripts

      assert_includes scripts, 'hello.rb'
      assert_includes scripts, 'test_script.rb'
      assert_includes scripts, 'another.rb'
      assert_equal 3, scripts.length
    end

    # スクリプト一覧はソートされている
    def test_list_scripts_sorted
      File.write(File.join(@scripts_dir, 'zzz.rb'), '# z script')
      File.write(File.join(@scripts_dir, 'aaa.rb'), '# a script')

      scripts = @command.list_scripts

      assert_equal 'aaa.rb', scripts[0]
      assert scripts.index('aaa.rb') < scripts.index('zzz.rb')
    end

    # スクリプトを実行できる
    def test_execute_script
      # テスト用スクリプトを作成
      test_script = File.join(@scripts_dir, 'test.rb')
      File.write(test_script, 'puts "Script executed"')

      result = @command.execute_script('test.rb', @project_dir)

      assert result[:success]
      assert_equal "Script executed\n", result[:output]
    end

    # 存在しないスクリプトを実行するとエラー
    def test_execute_nonexistent_script
      result = @command.execute_script('nonexistent.rb', @project_dir)

      assert_equal false, result[:success]
      assert_includes result[:error], 'Script not found'
    end

    # スクリプトは選択したディレクトリで実行される
    def test_script_executed_in_selected_directory
      # カレントディレクトリを確認するスクリプト
      test_script = File.join(@scripts_dir, 'pwd.rb')
      File.write(test_script, 'puts Dir.pwd')

      result = @command.execute_script('pwd.rb', @project_dir)

      assert result[:success]
      assert_includes result[:output], @project_dir
    end

    # スクリプトディレクトリのパスを取得できる
    def test_scripts_dir_path
      assert_equal @scripts_dir, @command.scripts_dir
    end
  end
end
