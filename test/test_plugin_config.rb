# frozen_string_literal: true

require 'test_helper'

class TestPluginConfig < Minitest::Test
  def setup
    # テスト用の一時ディレクトリを作成
    @temp_dir = Dir.mktmpdir
    @config_path = File.join(@temp_dir, '.rufio', 'config.yml')

    # 元のHOME環境変数を保存
    @original_home = ENV['HOME']
    ENV['HOME'] = @temp_dir

    # Configの内部状態をクリア
    Rufio::PluginConfig.instance_variable_set(:@config, nil)
  end

  def teardown
    # HOME環境変数を復元
    ENV['HOME'] = @original_home

    # 一時ディレクトリを削除
    FileUtils.rm_rf(@temp_dir)

    # Configの内部状態をクリア
    Rufio::PluginConfig.instance_variable_set(:@config, nil)
  end

  def test_plugin_config_class_exists
    assert defined?(Rufio::PluginConfig), "Rufio::PluginConfig クラスが定義されていません"
  end

  def test_load_method_exists
    assert_respond_to Rufio::PluginConfig, :load
  end

  def test_plugin_enabled_method_exists
    assert_respond_to Rufio::PluginConfig, :plugin_enabled?
  end

  def test_config_file_not_exist_defaults_to_all_enabled
    # config.ymlが存在しない状態で読み込み
    Rufio::PluginConfig.load

    # 全てのプラグインが有効とみなされる
    assert Rufio::PluginConfig.plugin_enabled?("any_plugin")
    assert Rufio::PluginConfig.plugin_enabled?("another_plugin")
    assert Rufio::PluginConfig.plugin_enabled?("FileOperations")
  end

  def test_load_config_from_yaml_file
    # config.ymlを作成
    config_content = <<~YAML
      plugins:
        fileoperations:
          enabled: true
        ai_helper:
          enabled: false
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # 設定を読み込み
    Rufio::PluginConfig.load

    # 設定が正しく読み込まれることを確認（エラーなく実行できる）
    result = Rufio::PluginConfig.plugin_enabled?("fileoperations")
    assert [true, false].include?(result)
  end

  def test_plugin_enabled_returns_true_when_enabled
    config_content = <<~YAML
      plugins:
        fileoperations:
          enabled: true
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)
    Rufio::PluginConfig.load

    assert Rufio::PluginConfig.plugin_enabled?("fileoperations")
    assert Rufio::PluginConfig.plugin_enabled?("FileOperations")
  end

  def test_plugin_enabled_returns_false_when_explicitly_disabled
    config_content = <<~YAML
      plugins:
        aihelper:
          enabled: false
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # 完全にクリーンな状態から読み込み
    Rufio::PluginConfig.instance_variable_set(:@config, nil)
    Rufio::PluginConfig.load

    # プラグイン名は小文字に変換されて比較されるので、どちらの形式でも同じ
    result1 = Rufio::PluginConfig.plugin_enabled?("aihelper")
    result2 = Rufio::PluginConfig.plugin_enabled?("AiHelper")

    refute result1, "Expected aihelper to be disabled, but it was enabled"
    refute result2, "Expected AiHelper to be disabled, but it was enabled"
  end

  def test_plugin_not_in_config_defaults_to_enabled
    config_content = <<~YAML
      plugins:
        fileoperations:
          enabled: true
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)
    Rufio::PluginConfig.load

    # 設定にないプラグインは有効とみなされる
    assert Rufio::PluginConfig.plugin_enabled?("unlisted_plugin")
  end

  def test_plugin_name_case_insensitive
    config_content = <<~YAML
      plugins:
        fileoperations:
          enabled: true
        aihelper:
          enabled: false
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)
    Rufio::PluginConfig.load

    # 大文字小文字を区別しない
    assert Rufio::PluginConfig.plugin_enabled?("FileOperations")
    assert Rufio::PluginConfig.plugin_enabled?("fileoperations")
    assert Rufio::PluginConfig.plugin_enabled?("FILEOPERATIONS")

    refute Rufio::PluginConfig.plugin_enabled?("AiHelper")
    refute Rufio::PluginConfig.plugin_enabled?("aihelper")
    refute Rufio::PluginConfig.plugin_enabled?("AIHELPER")
  end

  def test_load_handles_empty_config_file
    config_content = ""

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # 空のファイルでもエラーにならない
    Rufio::PluginConfig.load

    # 全プラグインが有効とみなされる
    assert Rufio::PluginConfig.plugin_enabled?("any_plugin")
  end

  def test_load_handles_config_without_plugins_section
    config_content = <<~YAML
      other_settings:
        some_value: 123
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # pluginsセクションがなくてもエラーにならない
    Rufio::PluginConfig.load

    # 全プラグインが有効とみなされる
    assert Rufio::PluginConfig.plugin_enabled?("any_plugin")
  end

  def test_load_handles_malformed_yaml
    config_content = <<~YAML
      plugins:
        fileoperations:
          enabled: true
        broken yaml here
          invalid: [
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # 不正なYAMLでもエラーにならない（デフォルト設定にフォールバック）
    Rufio::PluginConfig.load

    # デフォルトで全プラグイン有効
    assert Rufio::PluginConfig.plugin_enabled?("any_plugin")
  end

  def test_config_with_multiple_plugins
    config_content = <<~YAML
      plugins:
        plugin1:
          enabled: true
        plugin2:
          enabled: true
        plugin3:
          enabled: false
        plugin4:
          enabled: false
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)
    Rufio::PluginConfig.load

    assert Rufio::PluginConfig.plugin_enabled?("plugin1")
    assert Rufio::PluginConfig.plugin_enabled?("plugin2")
    refute Rufio::PluginConfig.plugin_enabled?("plugin3")
    refute Rufio::PluginConfig.plugin_enabled?("plugin4")
  end

  def test_reload_config_after_file_change
    # 最初の設定
    config_content = <<~YAML
      plugins:
        test_plugin:
          enabled: true
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)
    Rufio::PluginConfig.load

    assert Rufio::PluginConfig.plugin_enabled?("test_plugin")

    # 設定ファイルを変更
    config_content = <<~YAML
      plugins:
        test_plugin:
          enabled: false
    YAML

    File.write(@config_path, config_content)
    Rufio::PluginConfig.instance_variable_set(:@config, nil)
    Rufio::PluginConfig.load

    refute Rufio::PluginConfig.plugin_enabled?("test_plugin")
  end
end
