# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

# セクション8: 設定ファイルの場所とマージルール
class TestScriptPathConfigLocation < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    @scripts_dir1 = File.join(@tmpdir, 'scripts1')
    @scripts_dir2 = File.join(@tmpdir, 'scripts2')
    @scripts_dir3 = File.join(@tmpdir, 'scripts3')
    FileUtils.mkdir_p(@scripts_dir1)
    FileUtils.mkdir_p(@scripts_dir2)
    FileUtils.mkdir_p(@scripts_dir3)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  # カレントディレクトリのrufio.ymlが最優先
  def test_local_config_takes_priority
    # カレントディレクトリの設定
    local_config = File.join(@tmpdir, 'rufio.yml')
    File.write(local_config, <<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    # ユーザー設定（仮想的に）
    user_config = File.join(@tmpdir, 'user_config.yml')
    File.write(user_config, <<~YAML)
      script_paths:
        - #{@scripts_dir2}
    YAML

    Dir.chdir(@tmpdir)

    loader = Rufio::ScriptConfigLoader.new(
      local_path: local_config,
      user_path: user_config
    )

    paths = loader.script_paths
    # ローカルが最優先
    assert_equal @scripts_dir1, paths.first
  end

  # 複数の設定ファイルからscript_pathsをマージ
  def test_merge_script_paths_from_multiple_configs
    local_config = File.join(@tmpdir, 'rufio.yml')
    File.write(local_config, <<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    user_config = File.join(@tmpdir, 'user_config.yml')
    File.write(user_config, <<~YAML)
      script_paths:
        - #{@scripts_dir2}
        - #{@scripts_dir3}
    YAML

    loader = Rufio::ScriptConfigLoader.new(
      local_path: local_config,
      user_path: user_config
    )

    paths = loader.script_paths
    # すべてのパスがマージされる（ローカルが先）
    assert_equal 3, paths.size
    assert_equal @scripts_dir1, paths[0]
    assert_includes paths, @scripts_dir2
    assert_includes paths, @scripts_dir3
  end

  # 重複パスは除外される
  def test_duplicate_paths_are_removed
    local_config = File.join(@tmpdir, 'rufio.yml')
    File.write(local_config, <<~YAML)
      script_paths:
        - #{@scripts_dir1}
    YAML

    user_config = File.join(@tmpdir, 'user_config.yml')
    File.write(user_config, <<~YAML)
      script_paths:
        - #{@scripts_dir1}
        - #{@scripts_dir2}
    YAML

    loader = Rufio::ScriptConfigLoader.new(
      local_path: local_config,
      user_path: user_config
    )

    paths = loader.script_paths
    # 重複は除外
    assert_equal 2, paths.size
  end

  # 設定ファイルがない場合は空配列
  def test_no_config_returns_empty
    loader = Rufio::ScriptConfigLoader.new(
      local_path: '/nonexistent/rufio.yml',
      user_path: '/nonexistent/config.yml'
    )

    paths = loader.script_paths
    assert_empty paths
  end
end

# セクション9: エラーハンドリング
class TestScriptPathErrorHandling < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def create_script(name, content = "#!/bin/bash\necho 'test'", executable: true)
    path = File.join(@scripts_dir, name)
    File.write(path, content)
    File.chmod(executable ? 0755 : 0644, path)
    path
  end

  # 存在しないディレクトリはスキップ（警告なしで続行）
  def test_nonexistent_directory_is_skipped
    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
        - /nonexistent/directory
    YAML

    create_script('build.sh')

    manager = Rufio::ScriptPathManager.new(@config_file)

    # エラーにならずにスクリプトが見つかる
    result = manager.resolve('build')
    refute_nil result
  end

  # スクリプトが見つからない場合の候補表示
  def test_suggest_similar_scripts_when_not_found
    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    create_script('build.sh')
    create_script('builder.sh')
    create_script('deploy.sh')

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 見つからないスクリプトに対する候補
    suggestions = manager.suggest('buld')  # typo
    assert_includes suggestions, 'build'
    assert_includes suggestions, 'builder'
  end

  # 実行権限がないスクリプトの検出
  def test_detect_non_executable_script
    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    # 実行権限なしのスクリプト
    path = create_script('noexec.sh', "#!/bin/bash\necho 'test'", executable: false)

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 実行権限チェック
    refute manager.executable?(path)
  end

  # 実行権限を修正
  def test_fix_permissions
    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    path = create_script('noexec.sh', "#!/bin/bash\necho 'test'", executable: false)

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 権限を修正
    result = manager.fix_permissions(path)
    assert result
    assert manager.executable?(path)
  end

  # 読み取り権限がないディレクトリはスキップ
  def test_unreadable_directory_is_skipped
    unreadable_dir = File.join(@tmpdir, 'unreadable')
    FileUtils.mkdir_p(unreadable_dir)

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
        - #{unreadable_dir}
    YAML

    create_script('build.sh')

    # 読み取り権限を削除（テスト後に戻す）
    begin
      FileUtils.chmod(0000, unreadable_dir)
      manager = Rufio::ScriptPathManager.new(@config_file)

      # エラーにならずにスクリプトが見つかる
      result = manager.resolve('build')
      refute_nil result
    ensure
      FileUtils.chmod(0755, unreadable_dir)
    end
  end
end

# セクション10: テストケース（エッジケース）
class TestScriptPathEdgeCases < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def create_script(name, content = "#!/bin/bash\necho 'test'")
    path = File.join(@scripts_dir, name)
    File.write(path, content)
    File.chmod(0755, path)
    path
  end

  # 空のscript_paths
  def test_empty_script_paths
    File.write(@config_file, <<~YAML)
      script_paths: []
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    assert_empty manager.all_scripts
  end

  # シンボリックリンク
  def test_symlink_script
    create_script('original.sh')
    symlink_path = File.join(@scripts_dir, 'linked.sh')
    File.symlink(File.join(@scripts_dir, 'original.sh'), symlink_path)

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    scripts = manager.all_scripts

    # 両方見つかる
    assert_includes scripts, 'original'
    assert_includes scripts, 'linked'
  end

  # スペースを含むパス
  def test_path_with_spaces
    space_dir = File.join(@tmpdir, 'my scripts')
    FileUtils.mkdir_p(space_dir)

    script_path = File.join(space_dir, 'build.sh')
    File.write(script_path, "#!/bin/bash\necho 'test'")
    File.chmod(0755, script_path)

    File.write(@config_file, <<~YAML)
      script_paths:
        - "#{space_dir}"
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    result = manager.resolve('build')

    refute_nil result
    assert_equal script_path, result
  end

  # 日本語を含むパス
  def test_path_with_japanese
    jp_dir = File.join(@tmpdir, 'スクリプト')
    FileUtils.mkdir_p(jp_dir)

    script_path = File.join(jp_dir, 'ビルド.sh')
    File.write(script_path, "#!/bin/bash\necho 'test'")
    File.chmod(0755, script_path)

    File.write(@config_file, <<~YAML)
      script_paths:
        - "#{jp_dir}"
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)
    scripts = manager.all_scripts

    assert_includes scripts, 'ビルド'
  end

  # 大文字小文字の違い（case insensitive）
  def test_case_insensitive_match
    create_script('Build.sh')

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    # 小文字でも見つかる
    result = manager.resolve('build')
    refute_nil result

    # 大文字でも見つかる
    result = manager.resolve('BUILD')
    refute_nil result
  end

  # スクリプト名に特殊文字
  def test_script_name_with_special_chars
    create_script('build-project.sh')
    create_script('build_v2.sh')

    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML

    manager = Rufio::ScriptPathManager.new(@config_file)

    result1 = manager.resolve('build-project')
    refute_nil result1

    result2 = manager.resolve('build_v2')
    refute_nil result2
  end
end
