# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

class TestCommandLogger < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @log_dir = File.join(@tmpdir, 'log')
    @logger = Rufio::CommandLogger.new(@log_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_command_logger_class_exists
    assert defined?(Rufio::CommandLogger), "Rufio::CommandLogger クラスが定義されていません"
  end

  def test_initialize_creates_log_directory
    assert File.directory?(@log_dir), "ログディレクトリが作成されていません"
  end

  def test_log_command_creates_log_file
    command = "ls -la"
    output = "total 0\ndrwxr-xr-x  2 user user 4096 Jan  1 00:00 ."

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 1, log_files.size, "ログファイルが作成されていません"
  end

  def test_log_filename_format
    command = "echo test"
    output = "test"

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    filename = File.basename(log_files.first)

    # Format: yyyymmddhhmmss-command.log
    assert_match(/^\d{14}-.+\.log$/, filename, "ログファイル名の形式が正しくありません")
  end

  def test_log_content_includes_command
    command = "echo hello"
    output = "hello"

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    content = File.read(log_files.first)

    assert_includes content, "echo hello", "ログにコマンドが含まれていません"
  end

  def test_log_content_includes_output
    command = "echo hello"
    output = "hello\nworld"

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    content = File.read(log_files.first)

    assert_includes content, "hello", "ログに出力が含まれていません"
    assert_includes content, "world", "ログに出力が含まれていません"
  end

  def test_log_content_includes_timestamp
    command = "date"
    output = "Fri Jan  1 00:00:00 UTC 2021"

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    content = File.read(log_files.first)

    # Should include some kind of timestamp
    assert_match(/\d{4}-\d{2}-\d{2}/, content, "ログにタイムスタンプが含まれていません")
  end

  def test_log_includes_success_status
    command = "true"
    output = ""

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    content = File.read(log_files.first)

    assert_includes content, "Success", "ログに成功ステータスが含まれていません"
  end

  def test_log_includes_failure_status
    command = "false"
    output = ""

    @logger.log(command, output, success: false, error: "Command failed")

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    content = File.read(log_files.first)

    assert_includes content, "Failed", "ログに失敗ステータスが含まれていません"
    assert_includes content, "Command failed", "ログにエラーメッセージが含まれていません"
  end

  def test_sanitize_command_for_filename
    command = "ls -la /path/to/directory"
    output = "result"

    @logger.log(command, output, success: true)

    log_files = Dir.glob(File.join(@log_dir, "*.log"))
    filename = File.basename(log_files.first)

    # Should not contain / or spaces in the command part
    refute_includes filename, "/", "ファイル名にスラッシュが含まれています"
  end

  def test_list_logs_returns_all_log_files
    @logger.log("cmd1", "output1", success: true)
    @logger.log("cmd2", "output2", success: true)
    @logger.log("cmd3", "output3", success: true)

    logs = @logger.list_logs

    assert_equal 3, logs.size, "全てのログファイルが返されていません"
  end

  def test_list_logs_sorted_by_timestamp_desc
    # Create logs with different timestamps
    sleep 0.01
    @logger.log("cmd1", "output1", success: true)
    sleep 0.01
    @logger.log("cmd2", "output2", success: true)
    sleep 0.01
    @logger.log("cmd3", "output3", success: true)

    logs = @logger.list_logs

    # Most recent first
    assert logs[0] > logs[1], "ログが新しい順にソートされていません"
    assert logs[1] > logs[2], "ログが新しい順にソートされていません"
  end

  def test_cleanup_old_logs_keeps_max_logs
    # Create 15 log files
    15.times do |i|
      @logger.log("cmd#{i}", "output#{i}", success: true)
      sleep 0.01
    end

    # Keep only 10
    @logger.cleanup_old_logs(max_logs: 10)

    remaining_logs = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 10, remaining_logs.size, "古いログが削除されていません"
  end

  def test_cleanup_deletes_oldest_logs
    # Create some logs
    3.times do |i|
      @logger.log("old_cmd#{i}", "output#{i}", success: true)
      sleep 0.01
    end

    # Record the newest log
    @logger.log("new_cmd", "new_output", success: true)
    newest_logs = Dir.glob(File.join(@log_dir, "*.log")).max

    # Cleanup keeping only 1
    @logger.cleanup_old_logs(max_logs: 1)

    remaining_logs = Dir.glob(File.join(@log_dir, "*.log"))
    assert_equal 1, remaining_logs.size
    assert_equal File.basename(newest_logs), File.basename(remaining_logs.first), "最新のログが残されていません"
  end
end
