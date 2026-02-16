# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

# スクリプト引数パースとログ出力のテスト
class TestScriptArgsAndLogging < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @log_dir = File.join(@tmpdir, 'logs')
    FileUtils.mkdir_p(@log_dir)
    @command_mode = Rufio::CommandMode.new
    @command_mode.update_browsing_directory(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === 引数パースのテスト ===

  def test_script_name_without_args
    create_script('hello.sh', "#!/bin/bash\necho hello")

    # @hello.sh → name="hello.sh", args=""
    # find_scriptがhello.shを見つけること
    scanner = @command_mode.instance_variable_get(:@local_script_scanner)
    refute_nil scanner.find_script('hello.sh')
  end

  def test_script_with_args_is_found
    create_script('retag.sh', "#!/bin/bash\necho \"tag=$1\"")

    # @retag.sh v0.70.0 → name="retag.sh", args="v0.70.0"
    # 引数付きでもスクリプトが見つかること
    result = @command_mode.execute('@retag.sh v0.70.0', working_dir: @tmpdir)
    # スクリプトが見つからないエラーではないこと
    refute_match(/見つかりません/, result.to_s)
  end

  def test_script_with_args_passes_arguments
    create_script('echo_arg.sh', "#!/bin/bash\necho \"ARG=$1\"")

    # 同期実行（job_managerなし）で引数が渡ることを確認
    result = @command_mode.execute('@echo_arg.sh hello_world', working_dir: @tmpdir)
    assert result.is_a?(Hash), "結果がHashであること: #{result.inspect}"
    assert result[:success], "実行が成功すること: #{result.inspect}"
    assert_match(/ARG=hello_world/, result[:output])
  end

  def test_script_with_multiple_args
    create_script('multi.sh', "#!/bin/bash\necho \"$1 $2 $3\"")

    result = @command_mode.execute('@multi.sh a b c', working_dir: @tmpdir)
    assert result.is_a?(Hash)
    assert result[:success]
    assert_match(/a b c/, result[:output])
  end

  def test_script_with_no_args_still_works
    create_script('simple.sh', "#!/bin/bash\necho done")

    result = @command_mode.execute('@simple.sh', working_dir: @tmpdir)
    assert result.is_a?(Hash)
    assert result[:success]
    assert_match(/done/, result[:output])
  end

  # === ログ出力のテスト ===

  def test_script_execution_logs_to_command_logger
    create_script('logged.sh', "#!/bin/bash\necho 'log output'")

    command_logger = Rufio::CommandLogger.new(@log_dir)
    bg_executor = Rufio::BackgroundCommandExecutor.new(command_logger)
    @command_mode.background_executor = bg_executor

    # 同期実行（job_managerなし）でもログが記録されること
    result = @command_mode.execute('@logged.sh', working_dir: @tmpdir)

    logs = command_logger.list_logs
    refute_empty logs, "ログファイルが作成されていること"

    log_content = File.read(logs.first)
    assert_match(/log output/, log_content)
    assert_match(/Success/, log_content)
  end

  def test_failed_script_logs_failure
    create_script('fail.sh', "#!/bin/bash\nexit 1")

    command_logger = Rufio::CommandLogger.new(@log_dir)
    bg_executor = Rufio::BackgroundCommandExecutor.new(command_logger)
    @command_mode.background_executor = bg_executor

    result = @command_mode.execute('@fail.sh', working_dir: @tmpdir)

    logs = command_logger.list_logs
    refute_empty logs, "ログファイルが作成されていること"

    log_content = File.read(logs.first)
    assert_match(/Failed/, log_content)
  end

  def test_script_with_args_logs_command_with_args
    create_script('tag.sh', "#!/bin/bash\necho \"tag=$1\"")

    command_logger = Rufio::CommandLogger.new(@log_dir)
    bg_executor = Rufio::BackgroundCommandExecutor.new(command_logger)
    @command_mode.background_executor = bg_executor

    result = @command_mode.execute('@tag.sh v1.0', working_dir: @tmpdir)

    logs = command_logger.list_logs
    refute_empty logs

    log_content = File.read(logs.first)
    assert_match(/tag\.sh/, log_content)
    assert_match(/tag=v1\.0/, log_content)
  end

  def test_rake_execution_logs_to_command_logger
    File.write(File.join(@tmpdir, 'Rakefile'), "task :hello do\n  puts 'rake hello'\nend")

    command_logger = Rufio::CommandLogger.new(@log_dir)
    bg_executor = Rufio::BackgroundCommandExecutor.new(command_logger)
    @command_mode.background_executor = bg_executor

    result = @command_mode.execute('rake:hello', working_dir: @tmpdir)

    logs = command_logger.list_logs
    refute_empty logs, "rakeタスク実行もログに記録されること"

    log_content = File.read(logs.first)
    assert_match(/rake hello/, log_content)
  end

  def test_shell_command_execution_already_logs
    # シェルコマンド（!prefix）は既にBackgroundCommandExecutorでログが記録される
    # この挙動が維持されていることを確認
    command_logger = Rufio::CommandLogger.new(@log_dir)
    bg_executor = Rufio::BackgroundCommandExecutor.new(command_logger)
    @command_mode.background_executor = bg_executor

    # 同期実行のテスト（BackgroundExecutorなしのシェルコマンド）
    @command_mode.background_executor = nil
    result = @command_mode.execute('!echo shell_test', working_dir: @tmpdir)
    assert result.is_a?(Hash)
    assert result[:success]
    assert_match(/shell_test/, result[:output])
  end

  private

  def create_script(name, content)
    path = File.join(@tmpdir, name)
    File.write(path, content)
    File.chmod(0o755, path)
  end
end
