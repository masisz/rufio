# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestScriptRunner < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @scripts_dir1 = File.join(@tmpdir, 'scripts1')
    @scripts_dir2 = File.join(@tmpdir, 'scripts2')
    FileUtils.mkdir_p(@scripts_dir1)
    FileUtils.mkdir_p(@scripts_dir2)

    # テスト用スクリプトを作成
    create_script(@scripts_dir1, 'build.sh', '#!/bin/bash\necho "Building..."')
    create_script(@scripts_dir1, 'test.sh', '#!/bin/bash\necho "Testing..."')
    create_script(@scripts_dir2, 'deploy.sh', '#!/bin/bash\necho "Deploying..."')
    create_script(@scripts_dir2, 'build.sh', '#!/bin/bash\necho "Build from dir2"')
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

  # ScriptRunner: スクリプトパスからスクリプトを検索
  def test_script_runner_finds_scripts_in_paths
    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1, @scripts_dir2])

    scripts = runner.available_scripts
    assert_includes scripts.map { |s| s[:name] }, 'build.sh'
    assert_includes scripts.map { |s| s[:name] }, 'test.sh'
    assert_includes scripts.map { |s| s[:name] }, 'deploy.sh'
  end

  # ScriptRunner: 同名スクリプトは最初のパスが優先
  def test_script_runner_first_path_takes_priority
    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1, @scripts_dir2])

    script = runner.find_script('build.sh')
    assert_equal @scripts_dir1, script[:dir]
  end

  # ScriptRunner: スクリプト名で補完候補を取得
  def test_script_runner_completion
    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1, @scripts_dir2])

    # "bu"で始まるスクリプト
    completions = runner.complete('bu')
    assert_includes completions, 'build.sh'
    refute_includes completions, 'test.sh'

    # "de"で始まるスクリプト
    completions = runner.complete('de')
    assert_includes completions, 'deploy.sh'
  end

  # ScriptRunner: スクリプトをジョブとして実行
  def test_script_runner_executes_as_job
    notification_manager = Rufio::NotificationManager.new
    job_manager = Rufio::JobManager.new(notification_manager: notification_manager)
    runner = Rufio::ScriptRunner.new(
      script_paths: [@scripts_dir1],
      job_manager: job_manager
    )

    job = runner.run('test.sh', working_dir: @tmpdir)

    assert_kind_of Rufio::TaskStatus, job
    assert_equal 'test.sh', job.name
    assert job.running?
    assert_equal 1, job_manager.job_count
  end

  # ScriptRunner: 存在しないスクリプトはnilを返す
  def test_script_runner_returns_nil_for_missing_script
    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    job = runner.run('nonexistent.sh', working_dir: @tmpdir)
    assert_nil job
  end

  # ScriptRunner: 拡張子なしでも検索可能
  def test_script_runner_finds_without_extension
    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    script = runner.find_script('build')
    assert_equal 'build.sh', script[:name]
  end

  # ScriptRunner: .rb, .py, .sh などをサポート
  def test_script_runner_supports_multiple_extensions
    create_script(@scripts_dir1, 'setup.rb', '#!/usr/bin/env ruby\nputs "Setup"')
    create_script(@scripts_dir1, 'init.py', '#!/usr/bin/env python3\nprint("Init")')

    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    scripts = runner.available_scripts
    names = scripts.map { |s| s[:name] }
    assert_includes names, 'setup.rb'
    assert_includes names, 'init.py'
  end

  # --- サブディレクトリ再帰検索 ---

  # ScriptRunner: サブディレクトリ内のスクリプトも検索できる
  def test_script_runner_finds_scripts_in_subdirectories
    subdir = File.join(@scripts_dir1, 'utils')
    FileUtils.mkdir_p(subdir)
    create_script(subdir, 'helper.sh', '#!/bin/bash\necho "Helper"')

    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    scripts = runner.available_scripts
    names = scripts.map { |s| s[:name] }
    assert_includes names, 'helper.sh'
  end

  # ScriptRunner: サブディレクトリ内のスクリプトを名前で検索できる
  def test_script_runner_finds_subdirectory_script_by_name
    subdir = File.join(@scripts_dir1, 'utils')
    FileUtils.mkdir_p(subdir)
    create_script(subdir, 'helper.sh', '#!/bin/bash\necho "Helper"')

    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    script = runner.find_script('helper')
    refute_nil script
    assert_equal 'helper.sh', script[:name]
  end

  # ScriptRunner: 深いネストのサブディレクトリも検索できる
  def test_script_runner_finds_deeply_nested_scripts
    deep_dir = File.join(@scripts_dir1, 'a', 'b')
    FileUtils.mkdir_p(deep_dir)
    create_script(deep_dir, 'deep.sh', '#!/bin/bash\necho "Deep"')

    runner = Rufio::ScriptRunner.new(script_paths: [@scripts_dir1])

    scripts = runner.available_scripts
    names = scripts.map { |s| s[:name] }
    assert_includes names, 'deep.sh'
  end
end

class TestConfigLoaderScriptPaths < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # ConfigLoader: YAMLからscript_pathsを読み込む
  def test_config_loader_reads_script_paths_from_yaml
    File.write(@config_file, <<~YAML)
      script_paths:
        - ~/scripts/
        - ~/devs/scripts/
    YAML

    config = Rufio::ConfigLoader.load_yaml_config(@config_file)
    assert_equal ['~/scripts/', '~/devs/scripts/'], config[:script_paths]
  end

  # ConfigLoader: script_pathsのパスを展開
  def test_config_loader_expands_script_paths
    File.write(@config_file, <<~YAML)
      script_paths:
        - ~/scripts/
    YAML

    config = Rufio::ConfigLoader.load_yaml_config(@config_file)
    paths = Rufio::ConfigLoader.expand_script_paths(config[:script_paths])

    assert_equal [File.expand_path('~/scripts/')], paths
  end

  # ConfigLoader: デフォルトのscript_paths
  def test_config_loader_default_script_paths
    paths = Rufio::ConfigLoader.default_script_paths

    assert_includes paths, File.expand_path('~/.config/rufio/scripts')
  end
end
