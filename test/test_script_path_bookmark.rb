# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestScriptPathBookmarkIntegration < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, 'config.yml')
    @scripts_dir = File.join(@tmpdir, 'scripts')
    FileUtils.mkdir_p(@scripts_dir)

    # 初期設定
    File.write(@config_file, <<~YAML)
      script_paths:
        - #{@scripts_dir}
    YAML
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # ブックマークマネージャーからスクリプトパスを追加
  def test_add_script_path_from_bookmark_manager
    manager = Rufio::ScriptPathManager.new(@config_file)
    new_dir = File.join(@tmpdir, 'new_scripts')
    FileUtils.mkdir_p(new_dir)

    result = manager.add_path(new_dir)

    assert result
    assert_includes manager.paths, new_dir
  end

  # 重複追加の防止
  def test_prevent_duplicate_path
    manager = Rufio::ScriptPathManager.new(@config_file)

    result = manager.add_path(@scripts_dir)

    refute result
  end

  # 設定ファイルへの永続化
  def test_persist_to_config_file
    manager = Rufio::ScriptPathManager.new(@config_file)
    new_dir = File.join(@tmpdir, 'new_scripts')
    FileUtils.mkdir_p(new_dir)

    manager.add_path(new_dir)

    # 設定ファイルを再読み込み
    reloaded = Rufio::ScriptPathManager.new(@config_file)
    assert_includes reloaded.paths, new_dir
  end

  # パスの削除と永続化
  def test_remove_path_and_persist
    manager = Rufio::ScriptPathManager.new(@config_file)

    result = manager.remove_path(@scripts_dir)

    assert result
    refute_includes manager.paths, @scripts_dir

    # 設定ファイルを再読み込み
    reloaded = Rufio::ScriptPathManager.new(@config_file)
    refute_includes reloaded.paths, @scripts_dir
  end
end
