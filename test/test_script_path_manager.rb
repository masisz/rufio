# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestScriptPathManager < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir1 = File.join(@tmpdir, 'scripts1')
    @scripts_dir2 = File.join(@tmpdir, 'scripts2')
    FileUtils.mkdir_p(@scripts_dir1)
    FileUtils.mkdir_p(@scripts_dir2)

    # テスト用スクリプトを作成
    create_script(@scripts_dir1, 'build.rb', "#!/usr/bin/env ruby\nputs 'Building...'")
    create_script(@scripts_dir1, 'test.py', "#!/usr/bin/env python3\nprint('Testing...')")
    create_script(@scripts_dir2, 'deploy.sh', "#!/bin/bash\necho 'Deploying...'")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def create_script(dir, name, content)
    path = File.join(dir, name)
    File.write(path, content)
    File.chmod(0755, path)
    path
  end

  def write_config(content)
    File.write(@config_file, content)
  end

  # --- Phase 1: 基本のスクリプトパス機能 ---

  # 設定ファイルからスクリプトパスを読み込める
  def test_load_script_paths_from_config
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - #{@scripts_dir2}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    assert_equal 2, manager.paths.size
    assert_includes manager.paths, @scripts_dir1
    assert_includes manager.paths, @scripts_dir2
  end

  # スクリプト名（拡張子なし）でファイルを解決できる
  def test_resolve_script_by_name_without_extension
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # buildでbuild.rbを解決
    script = manager.resolve('build')
    assert_equal File.join(@scripts_dir1, 'build.rb'), script
  end

  # 拡張子付きでも解決できる
  def test_resolve_script_with_extension
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    script = manager.resolve('build.rb')
    assert_equal File.join(@scripts_dir1, 'build.rb'), script
  end

  # 複数パスから検索（最初のパスが優先）
  def test_resolve_first_path_priority
    # 両方のディレクトリにbuild.shを作成
    create_script(@scripts_dir2, 'build.sh', "#!/bin/bash\necho 'Build from dir2'")

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - #{@scripts_dir2}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # scripts_dir1のbuild.rbが優先される
    script = manager.resolve('build')
    assert_equal File.join(@scripts_dir1, 'build.rb'), script
  end

  # 存在しないスクリプトはnilを返す
  def test_resolve_returns_nil_for_missing_script
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    assert_nil manager.resolve('nonexistent')
  end

  # 全スクリプト一覧を取得（タブ補完用）
  def test_all_scripts_for_completion
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - #{@scripts_dir2}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    scripts = manager.all_scripts

    assert_includes scripts, 'build'
    assert_includes scripts, 'test'
    assert_includes scripts, 'deploy'
  end

  # 隠しファイルは除外
  def test_hidden_files_are_excluded
    create_script(@scripts_dir1, '.hidden.rb', "#!/usr/bin/env ruby\nputs 'Hidden'")

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    scripts = manager.all_scripts

    refute_includes scripts, '.hidden'
    refute_includes scripts, '.hidden.rb'
  end

  # パスを動的に追加
  def test_add_path
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    assert_equal 1, manager.paths.size

    result = manager.add_path(@scripts_dir2)
    assert result
    assert_equal 2, manager.paths.size
    assert_includes manager.paths, @scripts_dir2

    # 設定ファイルに保存されている
    reloaded = Rufio::ScriptPathManager.new(@config_file)
    assert_equal 2, reloaded.paths.size
  end

  # 重複パスは追加しない
  def test_add_path_prevents_duplicates
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    result = manager.add_path(@scripts_dir1)

    refute result
    assert_equal 1, manager.paths.size
  end

  # パスを削除
  def test_remove_path
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - #{@scripts_dir2}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    result = manager.remove_path(@scripts_dir1)

    assert result
    assert_equal 1, manager.paths.size
    refute_includes manager.paths, @scripts_dir1

    # 設定ファイルに保存されている
    reloaded = Rufio::ScriptPathManager.new(@config_file)
    assert_equal 1, reloaded.paths.size
  end

  # 存在しないディレクトリはスキップ
  def test_skip_nonexistent_directories
    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - /nonexistent/path
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    scripts = manager.all_scripts

    # エラーにならずにスキップされる
    assert_includes scripts, 'build'
    assert_includes scripts, 'test'
  end

  # チルダ展開が正しく動作する
  def test_tilde_expansion
    write_config(<<~YAML)
      script_paths:
        - ~/scripts/
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    # パスが展開されている
    assert manager.paths.first.start_with?(Dir.home)
  end
end

class TestCommandModeScriptIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)

    create_script('hello.sh', "#!/bin/bash\necho 'Hello'")

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

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

  # コマンドモードで`:スクリプト名`で実行できる（@プレフィックスなし）
  def test_execute_script_without_prefix
    # hello.shをテスト用に作成（組み込みのhelloと被らないように別名）
    create_script('deploy.sh', "#!/bin/bash\necho 'Deploying...'")

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_path_manager(
      config_file: @config_file,
      job_manager: @job_manager
    )

    result = command_mode.execute('deploy', working_dir: @tmpdir)

    assert_kind_of String, result
    assert_match(/ジョブ/, result)
    assert_equal 1, @job_manager.job_count
  end

  # 内部コマンドが優先される
  def test_internal_commands_take_priority
    # helloという名前のスクリプトを作成（組み込みのhelloコマンドと同名）
    create_script('hello.sh', "#!/bin/bash\necho 'Hello script'")

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_path_manager(
      config_file: @config_file,
      job_manager: @job_manager
    )

    # helloは内部コマンドとして処理される（スクリプトは実行されない）
    result = command_mode.execute('hello', working_dir: @tmpdir)

    # スクリプトは実行されていない（内部コマンドが優先）
    assert_equal 0, @job_manager.job_count
    # 内部コマンドの結果が返される（文字列またはハッシュ）
    if result.is_a?(String)
      assert_match(/Hello/, result)
    else
      # 結果がある（nilではない）ことを確認
      refute_nil result
    end
  end
end

class TestScriptEnvironmentVariables < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)

    # 環境変数を出力するスクリプト
    create_script('env_test.sh', <<~BASH)
      #!/bin/bash
      echo "RUFIO_CURRENT_DIR=$RUFIO_CURRENT_DIR"
      echo "RUFIO_SELECTED_FILE=$RUFIO_SELECTED_FILE"
      echo "RUFIO_SELECTED_DIR=$RUFIO_SELECTED_DIR"
    BASH

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

  # 環境変数が正しく設定される
  def test_environment_variables_are_set
    runner = Rufio::ScriptRunner.new(
      script_paths: [@scripts_dir],
      job_manager: @job_manager
    )

    job = runner.run('env_test.sh',
                     working_dir: @tmpdir,
                     selected_file: '/path/to/file.txt',
                     selected_dir: nil)

    assert_kind_of Rufio::TaskStatus, job

    # ジョブが完了するまで少し待つ
    sleep 0.5

    # ログに環境変数が含まれている
    logs = job.logs.join("\n")
    assert_match(/RUFIO_CURRENT_DIR=#{Regexp.escape(@tmpdir)}/, logs)
    assert_match(/RUFIO_SELECTED_FILE=\/path\/to\/file\.txt/, logs)
  end
end
