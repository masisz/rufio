# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestCommandModeScript < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)

    # テスト用スクリプトを作成
    create_script('hello.sh', "#!/bin/bash\necho 'Hello from script'")
    create_script('slow.sh', "#!/bin/bash\nsleep 2 && echo 'Done'")

    # JobManager を初期化
    @notification_manager = Rufio::NotificationManager.new
    @job_manager = Rufio::JobManager.new(notification_manager: @notification_manager)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def create_script(name, content)
    path = File.join(@scripts_dir, name)
    File.write(path, content)
    File.chmod(0755, path)
  end

  # @ プレフィックスでスクリプトを実行
  def test_execute_script_with_at_prefix
    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [@scripts_dir],
      job_manager: @job_manager
    )

    result = command_mode.execute('@hello.sh', working_dir: @tmpdir)

    assert_match(/ジョブ/, result)
    assert_equal 1, @job_manager.job_count
  end

  # @ プレフィックスでスクリプト名の補完
  def test_script_completion_with_at_prefix
    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [@scripts_dir],
      job_manager: @job_manager
    )

    completions = command_mode.complete_script('@he')

    assert_includes completions, '@hello.sh'
  end

  # 存在しないスクリプトはエラー
  def test_execute_nonexistent_script
    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [@scripts_dir],
      job_manager: @job_manager
    )

    result = command_mode.execute('@nonexistent.sh', working_dir: @tmpdir)

    assert_match(/見つかりません/, result)
    assert_equal 0, @job_manager.job_count
  end

  # ScriptRunnerが設定されていない場合
  def test_script_without_runner_setup
    command_mode = Rufio::CommandMode.new

    result = command_mode.execute('@hello.sh', working_dir: @tmpdir)

    assert_match(/設定されていません/, result)
  end
end
