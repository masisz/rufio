# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

# ローカルスクリプトとrakeタスクの補完テスト
class TestCommandCompletionLocal < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @command_mode = Rufio::CommandMode.new
    @completion = Rufio::CommandCompletion.new(nil, @command_mode)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === ローカルスクリプト補完のテスト ===

  def test_empty_input_includes_local_scripts
    create_script('build.sh', "#!/bin/bash")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('')

    assert_includes candidates, '@build.sh'
  end

  def test_at_prefix_includes_local_scripts
    create_script('deploy.py', "#!/usr/bin/env python3")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('@de')

    assert_includes candidates, '@deploy.py'
  end

  # === rakeタスク補完のテスト ===

  def test_empty_input_includes_rake_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end\ntask :build do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('')

    assert_includes candidates, 'rake:test'
    assert_includes candidates, 'rake:build'
  end

  def test_rake_prefix_completes_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end\ntask :test_unit do; end\ntask :build do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('rake:te')

    assert_includes candidates, 'rake:test'
    assert_includes candidates, 'rake:test_unit'
    refute_includes candidates, 'rake:build'
  end

  def test_rake_prefix_no_match
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('rake:xyz')

    assert_empty candidates
  end

  def test_no_rakefile_returns_no_rake_candidates
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('rake:')

    assert_empty candidates
  end

  # === 統合テスト ===

  def test_empty_input_has_all_types
    create_script('deploy.sh', "#!/bin/bash")
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('')

    # 内部コマンド
    assert_includes candidates, 'hello'
    # ローカルスクリプト
    assert_includes candidates, '@deploy.sh'
    # rakeタスク
    assert_includes candidates, 'rake:test'
  end

  # === 部分入力でのrakeタスク補完テスト ===

  def test_partial_input_r_includes_rake_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('r')

    assert_includes candidates, 'rake:test'
  end

  def test_partial_input_rak_includes_rake_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('rak')

    assert_includes candidates, 'rake:test'
  end

  def test_partial_input_rake_includes_rake_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end\ntask :build do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    candidates = @completion.complete('rake')

    assert_includes candidates, 'rake:test'
    assert_includes candidates, 'rake:build'
  end

  def test_partial_input_common_prefix_completes_to_rake_colon
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end\ntask :build do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    prefix = @completion.common_prefix('rak')

    assert_equal 'rake:', prefix
  end

  def test_common_prefix_with_rake_tasks
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do; end\ntask :test_unit do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    prefix = @completion.common_prefix('rake:te')

    assert_equal 'rake:test', prefix
  end

  def test_common_prefix_with_single_rake_match
    File.write(File.join(@tmpdir, 'Rakefile'), "task :build do; end\ntask :test do; end")
    @command_mode.update_browsing_directory(@tmpdir)

    prefix = @completion.common_prefix('rake:b')

    assert_equal 'rake:build', prefix
  end

  private

  def create_script(name, content)
    path = File.join(@tmpdir, name)
    File.write(path, content)
    File.chmod(0755, path)
  end
end
