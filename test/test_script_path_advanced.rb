# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestScriptPathAdvanced < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir1 = File.join(@tmpdir, 'scripts1')
    @scripts_dir2 = File.join(@tmpdir, 'scripts2')
    FileUtils.mkdir_p(@scripts_dir1)
    FileUtils.mkdir_p(@scripts_dir2)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def create_script(dir, name, content = "#!/bin/bash\necho 'test'")
    path = File.join(dir, name)
    File.write(path, content)
    File.chmod(0755, path)
    path
  end

  def write_config(content)
    File.write(@config_file, content)
  end

  # --- Phase 4: 複数マッチ時の選択プロンプト ---

  # 同じディレクトリに同名スクリプト（拡張子違い）がある場合
  def test_multiple_match_same_directory
    create_script(@scripts_dir1, 'build.rb', "#!/usr/bin/env ruby\nputs 'Ruby'")
    create_script(@scripts_dir1, 'build.py', "#!/usr/bin/env python3\nprint('Python')")

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
      script_options:
        on_multiple_match: 'prompt'
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 複数のマッチを取得
    matches = manager.find_all_matches('build')
    assert_equal 2, matches.size
    assert matches.any? { |m| m.end_with?('build.rb') }
    assert matches.any? { |m| m.end_with?('build.py') }
  end

  # on_multiple_match: 'first' の場合は最初のものを返す
  def test_multiple_match_first_option
    create_script(@scripts_dir1, 'build.rb', "#!/usr/bin/env ruby\nputs 'Ruby'")
    create_script(@scripts_dir1, 'build.py', "#!/usr/bin/env python3\nprint('Python')")

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
      script_options:
        on_multiple_match: 'first'
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # resolveは最初のマッチを返す
    result = manager.resolve('build')
    refute_nil result
  end

  # --- Phase 4: タブ補完 ---

  # 部分一致で補完候補を取得
  def test_tab_completion_partial_match
    create_script(@scripts_dir1, 'build.sh')
    create_script(@scripts_dir1, 'build_test.sh')
    create_script(@scripts_dir1, 'deploy.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # "bu"で始まるスクリプト
    completions = manager.complete('bu')
    assert_includes completions, 'build'
    assert_includes completions, 'build_test'
    refute_includes completions, 'deploy'

    # "b"で始まるスクリプト
    completions = manager.complete('b')
    assert_includes completions, 'build'
    assert_includes completions, 'build_test'
  end

  # 空文字列の場合は全スクリプトを返す
  def test_tab_completion_empty_string
    create_script(@scripts_dir1, 'build.sh')
    create_script(@scripts_dir1, 'deploy.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    completions = manager.complete('')
    assert_equal 2, completions.size
  end

  # --- Phase 4: fuzzy matching ---

  # fuzzy matchingで候補を取得
  def test_fuzzy_matching
    create_script(@scripts_dir1, 'build_project.sh')
    create_script(@scripts_dir1, 'backup_database.sh')
    create_script(@scripts_dir1, 'deploy_production.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # "bldprj"でbuild_projectにマッチ
    matches = manager.fuzzy_match('bldprj')
    assert matches.any? { |m| m.include?('build_project') }

    # "dplprd"でdeploy_productionにマッチ
    matches = manager.fuzzy_match('dplprd')
    assert matches.any? { |m| m.include?('deploy_production') }
  end

  # --- Phase 4: スクリプトキャッシュ ---

  # キャッシュが有効であること
  def test_script_cache_works
    create_script(@scripts_dir1, 'build.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 最初の呼び出し
    result1 = manager.resolve('build')
    # キャッシュからの呼び出し
    result2 = manager.resolve('build')

    assert_equal result1, result2
  end

  # キャッシュのクリア
  def test_cache_invalidation
    create_script(@scripts_dir1, 'build.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 最初の解決
    result1 = manager.resolve('build')

    # 新しいスクリプトを追加
    create_script(@scripts_dir1, 'test.sh')

    # キャッシュをクリア
    manager.invalidate_cache

    # 新しいスクリプトが見つかる
    result2 = manager.resolve('test')
    refute_nil result2
  end

  # --- Phase 4: スクリプト実行履歴 ---

  # 実行履歴の記録
  def test_script_execution_history
    create_script(@scripts_dir1, 'build.sh')
    create_script(@scripts_dir1, 'deploy.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 実行を記録
    manager.record_execution('build')
    manager.record_execution('deploy')
    manager.record_execution('build')

    # 履歴を取得（最近のものが先）
    history = manager.execution_history
    assert_equal 'build', history.first
  end

  # 実行履歴に基づく並び替え
  def test_sort_by_execution_frequency
    create_script(@scripts_dir1, 'build.sh')
    create_script(@scripts_dir1, 'deploy.sh')
    create_script(@scripts_dir1, 'test.sh')

    write_config(<<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 実行を記録
    manager.record_execution('deploy')
    manager.record_execution('build')
    manager.record_execution('build')
    manager.record_execution('build')

    # 頻度順で取得
    sorted = manager.scripts_by_frequency
    assert_equal 'build', sorted.first
    assert_equal 'deploy', sorted[1]
  end
end
