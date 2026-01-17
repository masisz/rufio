# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/background_command_executor'
require_relative '../lib/rufio/command_logger'
require 'tmpdir'
require 'fileutils'

class TestBackgroundCommandRuby < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @command_logger = Rufio::CommandLogger.new(@temp_dir)
    @executor = Rufio::BackgroundCommandExecutor.new(@command_logger)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_execute_ruby_async_simple
    # シンプルなRubyコードを非同期実行
    result_value = nil
    success = @executor.execute_ruby_async('test_command') do
      result_value = 'hello'
      'result from block'
    end

    assert success, 'execute_ruby_async should return true'
    assert @executor.running?, 'Executor should be running'
    assert_equal 'test_command', @executor.current_command
    assert_equal :ruby, @executor.command_type

    # 完了を待つ
    sleep 0.1 until !@executor.running?

    assert_nil @executor.current_command
    assert_nil @executor.command_type
    assert_match(/完了/, @executor.get_completion_message)
  end

  def test_execute_ruby_async_with_sleep
    # sleepを含むRubyコードを非同期実行
    start_time = Time.now
    success = @executor.execute_ruby_async('sleep_command') do
      sleep 1
      'done'
    end

    assert success, 'execute_ruby_async should return true'
    assert @executor.running?, 'Executor should be running immediately'

    # 非同期なので、すぐに制御が戻る
    elapsed = Time.now - start_time
    assert elapsed < 0.5, "Should return immediately (elapsed: #{elapsed}s)"

    # 完了を待つ
    sleep 0.1 until !@executor.running?

    # 少なくとも1秒は経過している
    total_elapsed = Time.now - start_time
    assert total_elapsed >= 1.0, "Should wait for sleep (elapsed: #{total_elapsed}s)"
    assert_match(/完了/, @executor.get_completion_message)
  end

  def test_execute_ruby_async_with_error
    # エラーが発生するRubyコードを非同期実行
    success = @executor.execute_ruby_async('error_command') do
      raise StandardError, 'test error'
    end

    assert success, 'execute_ruby_async should return true'
    assert @executor.running?, 'Executor should be running'

    # 完了を待つ
    sleep 0.1 until !@executor.running?

    completion_msg = @executor.get_completion_message
    assert_match(/エラー/, completion_msg)
    assert_match(/test error/, completion_msg)
  end

  def test_cannot_execute_while_running
    # 既に実行中の場合は新しいコマンドを実行できない
    success1 = @executor.execute_ruby_async('command1') do
      sleep 1
      'result1'
    end

    assert success1, 'First command should succeed'
    assert @executor.running?, 'Executor should be running'

    success2 = @executor.execute_ruby_async('command2') do
      'result2'
    end

    refute success2, 'Second command should fail while first is running'

    # 完了を待つ
    sleep 0.1 until !@executor.running?
  end

  def test_ruby_and_shell_commands_share_executor
    # Rubyコマンドを実行
    success1 = @executor.execute_ruby_async('ruby_command') do
      sleep 0.5
      'ruby result'
    end

    assert success1, 'Ruby command should succeed'
    assert @executor.running?, 'Executor should be running'
    assert_equal :ruby, @executor.command_type

    # シェルコマンドは実行できない（既に実行中）
    success2 = @executor.execute_async('echo "shell command"')

    refute success2, 'Shell command should fail while Ruby command is running'

    # 完了を待つ
    sleep 0.1 until !@executor.running?

    # 今度はシェルコマンドを実行できる
    success3 = @executor.execute_async('echo "shell command"')
    assert success3, 'Shell command should succeed after Ruby command completes'

    # 完了を待つ
    sleep 0.1 until !@executor.running?
  end

  def test_completion_message_cleared_after_get
    # 完了メッセージは取得後もクリアされない（呼び出し側が管理）
    @executor.execute_ruby_async('test') { 'done' }
    sleep 0.1 until !@executor.running?

    msg1 = @executor.get_completion_message
    assert_match(/完了/, msg1)

    # 同じメッセージが取得できる
    msg2 = @executor.get_completion_message
    assert_equal msg1, msg2
  end

  def test_logging_ruby_command
    # Rubyコマンドの実行がログに記録される
    @executor.execute_ruby_async('logged_command') do
      'output from ruby'
    end

    sleep 0.1 until !@executor.running?

    # ログファイルが作成されている
    log_files = Dir.glob(File.join(@temp_dir, '*.log'))
    refute_empty log_files, 'Log file should be created'

    # ログの内容を確認
    log_content = File.read(log_files.first)
    assert_match(/logged_command/, log_content)
    assert_match(/output from ruby/, log_content)
  end
end
