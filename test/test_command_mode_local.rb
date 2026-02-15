# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestCommandModeLocal < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @notification_manager = Rufio::NotificationManager.new
    @job_manager = Rufio::JobManager.new(notification_manager: @notification_manager)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === update_browsing_directory のテスト ===

  def test_update_browsing_directory
    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    # エラーなく呼び出せることを確認
    assert true
  end

  # === ローカルスクリプト実行のテスト ===

  def test_execute_local_script_with_at_prefix
    # ローカルスクリプトを作成
    create_script('hello.sh', "#!/bin/bash\necho 'hello from local'")

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [],
      job_manager: @job_manager
    )
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('@hello.sh', working_dir: @tmpdir)

    # ローカルスクリプトが実行される
    assert_match(/ジョブ/, result)
  end

  def test_local_script_fallback_when_not_in_script_paths
    # script_paths には空の配列を設定（ローカルのみ）
    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [],
      job_manager: @job_manager
    )

    # ローカルスクリプトを作成
    create_script('local_only.sh', "#!/bin/bash\necho 'local'")
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('@local_only.sh', working_dir: @tmpdir)

    # ローカルスクリプトにフォールバック
    assert_match(/ジョブ/, result)
  end

  def test_script_path_takes_priority_over_local
    # script_paths にスクリプトが存在する場合はそちらが優先
    scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(scripts_dir)
    create_script_in(scripts_dir, 'test.sh', "#!/bin/bash\necho 'from path'")
    create_script('test.sh', "#!/bin/bash\necho 'from local'")

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [scripts_dir],
      job_manager: @job_manager
    )
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('@test.sh', working_dir: @tmpdir)

    # ScriptRunnerで見つかるので、ローカルにはフォールバックしない
    assert_match(/ジョブ/, result)
  end

  # === rake: プレフィックスのテスト ===

  def test_execute_rake_task
    write_rakefile("task :test do\n  puts 'test'\nend")

    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('rake:test', working_dir: @tmpdir)

    # rake タスクが実行される（結果はHash）
    assert_kind_of Hash, result
  end

  def test_execute_rake_task_nonexistent
    write_rakefile("task :test do\n  puts 'test'\nend")

    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('rake:nonexistent', working_dir: @tmpdir)

    # 存在しないタスクはエラー
    assert_match(/見つかりません/, result)
  end

  def test_execute_rake_without_rakefile
    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    result = command_mode.execute('rake:test', working_dir: @tmpdir)

    assert_match(/Rakefile.*見つかりません/, result)
  end

  # === ローカルスクリプト補完のテスト ===

  def test_complete_script_includes_local_scripts
    create_script('build.sh', "#!/bin/bash")
    create_script('bundle.rb', "#!/usr/bin/env ruby")

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [],
      job_manager: @job_manager
    )
    command_mode.update_browsing_directory(@tmpdir)

    completions = command_mode.complete_script('@bu')

    assert_includes completions, '@build.sh'
    assert_includes completions, '@bundle.rb'
  end

  def test_complete_script_no_duplicates
    # script_pathsとローカルの両方に同名スクリプトがある場合
    scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(scripts_dir)
    create_script_in(scripts_dir, 'build.sh', "#!/bin/bash")
    create_script('build.sh', "#!/bin/bash")

    command_mode = Rufio::CommandMode.new
    command_mode.setup_script_runner(
      script_paths: [scripts_dir],
      job_manager: @job_manager
    )
    command_mode.update_browsing_directory(@tmpdir)

    completions = command_mode.complete_script('@bu')

    # 重複なし
    assert_equal completions, completions.uniq
  end

  # === rake: 補完のテスト ===

  def test_complete_rake_task
    content = <<~RUBY
      task :test do; end
      task :test_unit do; end
      task :build do; end
    RUBY
    write_rakefile(content)

    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    completions = command_mode.complete_rake_task('te')

    assert_includes completions, 'rake:test'
    assert_includes completions, 'rake:test_unit'
    refute_includes completions, 'rake:build'
  end

  def test_complete_rake_task_empty_prefix
    content = <<~RUBY
      task :test do; end
      task :build do; end
    RUBY
    write_rakefile(content)

    command_mode = Rufio::CommandMode.new
    command_mode.update_browsing_directory(@tmpdir)

    completions = command_mode.complete_rake_task('')

    assert_equal 2, completions.size
  end

  private

  def create_script(name, content)
    create_script_in(@tmpdir, name, content)
  end

  def create_script_in(dir, name, content)
    path = File.join(dir, name)
    File.write(path, content)
    File.chmod(0755, path)
  end

  def write_rakefile(content)
    File.write(File.join(@tmpdir, 'Rakefile'), content)
  end
end
