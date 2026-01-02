# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

class TestBackgroundCommand < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @log_dir = File.join(@tmpdir, '.rufio', 'log')
    FileUtils.mkdir_p(@log_dir)
    @command_logger = Rufio::CommandLogger.new(@log_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_background_command_executor_class_exists
    assert defined?(Rufio::BackgroundCommandExecutor), "Rufio::BackgroundCommandExecutor クラスが定義されていません"
  end

  def test_can_execute_command_in_background
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    command = "echo 'test'"
    executor.execute_async(command)

    # コマンドが実行中であることを確認
    assert executor.running?, "バックグラウンドコマンドが実行されていません"
  end

  def test_background_command_completes
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    command = "echo 'test'"
    executor.execute_async(command)

    # コマンドが完了するまで待つ（最大2秒）
    timeout = 2
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    refute executor.running?, "コマンドが完了していません"
  end

  def test_background_command_saves_output_to_log
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    command = "echo 'hello world'"
    executor.execute_async(command)

    # コマンドが完了するまで待つ
    timeout = 2
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    # ログファイルが作成されていることを確認
    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 1, log_files.size, "ログファイルが作成されていません"

    # ログファイルの内容を確認
    content = File.read(log_files.first)
    assert_includes content, "echo", "ログにコマンドが含まれていません"
    assert_includes content, "hello world", "ログに出力が含まれていません"
  end

  def test_can_get_completion_message
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    command = "echo 'test'"
    executor.execute_async(command)

    # コマンドが完了するまで待つ
    timeout = 2
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    # 完了メッセージを取得
    message = executor.get_completion_message
    assert_match(/✓.*echo.*完了/, message, "完了メッセージの形式が正しくありません")
  end

  def test_handles_command_failure
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    # 存在しないコマンドを実行
    command = "nonexistent_command_xyz"
    executor.execute_async(command)

    # コマンドが完了するまで待つ
    timeout = 2
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    # ログファイルにエラーが記録されていることを確認
    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 1, log_files.size, "ログファイルが作成されていません"

    content = File.read(log_files.first)
    assert_includes content, "Failed", "ログに失敗ステータスが含まれていません"
  end

  def test_multiple_background_commands
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    # 複数のコマンドを実行（ただし同時に1つのみ実行可能とする）
    executor.execute_async("echo 'first'")

    # 最初のコマンドが完了するまで待つ
    timeout = 2
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    # 2つ目のコマンドを実行
    executor.execute_async("echo 'second'")

    # 2つ目のコマンドが完了するまで待つ
    start_time = Time.now
    while executor.running? && (Time.now - start_time) < timeout
      sleep 0.1
    end

    # 2つのログファイルが作成されていることを確認
    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 2, log_files.size, "2つのログファイルが作成されていません"
  end

  def test_cannot_start_new_command_while_running
    executor = Rufio::BackgroundCommandExecutor.new(@command_logger)

    # 長時間実行されるコマンドを開始
    executor.execute_async("sleep 0.5")

    # すぐに別のコマンドを実行しようとする
    result = executor.execute_async("echo 'second'")

    # 2つ目のコマンドは実行できないはず
    refute result, "実行中に新しいコマンドを開始できてしまいます"
  end
end
