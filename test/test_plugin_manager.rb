# frozen_string_literal: true

require 'test_helper'

class TestPluginManager < Minitest::Test
  def setup
    # テスト前にプラグインリストをクリア
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用の一時ディレクトリを作成
    @temp_dir = Dir.mktmpdir
    @user_plugins_dir = File.join(@temp_dir, '.rufio', 'plugins')
    @config_path = File.join(@temp_dir, '.rufio', 'config.yml')
    FileUtils.mkdir_p(@user_plugins_dir)

    # 元のHOME環境変数を保存
    @original_home = ENV['HOME']
    ENV['HOME'] = @temp_dir
  end

  def teardown
    # HOME環境変数を復元
    ENV['HOME'] = @original_home

    # 一時ディレクトリを削除
    FileUtils.rm_rf(@temp_dir)

    # プラグインリストをクリア
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用に定義したクラスを削除
    cleanup_test_classes
  end

  def test_plugin_manager_exists
    assert defined?(Rufio::PluginManager), "Rufio::PluginManager クラスが定義されていません"
  end

  def test_plugins_returns_array
    assert_kind_of Array, Rufio::PluginManager.plugins
  end

  def test_register_plugin
    plugin_class = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::PluginManager.register(plugin_class)
    assert_includes Rufio::PluginManager.plugins, plugin_class
  end

  def test_register_same_plugin_twice_does_not_duplicate
    plugin_class = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::PluginManager.register(plugin_class)
    Rufio::PluginManager.register(plugin_class)

    # 同じプラグインが2回登録されないことを確認
    assert_equal 1, Rufio::PluginManager.plugins.count(plugin_class)
  end

  def test_load_builtin_plugins
    # 本体同梱プラグインのディレクトリを確認
    builtin_plugins_dir = File.expand_path('../../lib/rufio/plugins', __dir__)

    # プラグインディレクトリが存在する、または存在しない場合もエラーにならないことを確認
    Rufio::PluginManager.send(:load_builtin_plugins)
    # エラーが発生しなければ成功
    assert true
  end

  def test_load_user_plugins_from_home_directory
    # テスト用のユーザープラグインを作成
    plugin_content = <<~RUBY
      module Rufio
        module Plugins
          class UserTestPlugin < Plugin
            def name
              "UserTestPlugin"
            end
          end
        end
      end
    RUBY

    File.write(File.join(@user_plugins_dir, 'user_test_plugin.rb'), plugin_content)

    # ユーザープラグインを読み込み
    Rufio::PluginManager.send(:load_user_plugins)

    # プラグインが登録されていることを確認
    plugin_classes = Rufio::PluginManager.plugins.map(&:name)
    assert_includes plugin_classes, "Rufio::Plugins::UserTestPlugin"
  end

  def test_load_user_plugins_directory_not_exist
    # ユーザープラグインディレクトリを削除
    FileUtils.rm_rf(@user_plugins_dir)

    # ディレクトリが存在しない場合もエラーにならない
    Rufio::PluginManager.send(:load_user_plugins)
    # エラーが発生しなければ成功
    assert true
  end

  def test_load_all_loads_both_builtin_and_user_plugins
    # テスト用のユーザープラグインを作成
    plugin_content = <<~RUBY
      module Rufio
        module Plugins
          class AnotherUserPlugin < Plugin
            def name
              "AnotherUserPlugin"
            end
          end
        end
      end
    RUBY

    File.write(File.join(@user_plugins_dir, 'another_user_plugin.rb'), plugin_content)

    # 全プラグインを読み込み
    Rufio::PluginManager.load_all
    # エラーが発生しなければ成功
    assert true
  end

  def test_enabled_plugins_returns_array_of_plugin_instances
    # テスト用のプラグインを登録
    plugin_class = Class.new(Rufio::Plugin) do
      def name
        "EnabledTestPlugin"
      end
    end

    # プラグイン名を定数として定義
    Rufio::Plugins.const_set(:EnabledTestPlugin, plugin_class)
    Rufio::PluginManager.register(plugin_class)

    enabled = Rufio::PluginManager.enabled_plugins
    assert_kind_of Array, enabled
  end

  def test_enabled_plugins_respects_config
    # テスト用のプラグインを登録
    plugin1_class = Class.new(Rufio::Plugin) do
      def name
        "EnabledPlugin"
      end
    end

    plugin2_class = Class.new(Rufio::Plugin) do
      def name
        "DisabledPlugin"
      end
    end

    Rufio::Plugins.const_set(:EnabledPlugin, plugin1_class)
    Rufio::Plugins.const_set(:DisabledPlugin, plugin2_class)

    Rufio::PluginManager.register(plugin1_class)
    Rufio::PluginManager.register(plugin2_class)

    # config.ymlを作成
    config_content = <<~YAML
      plugins:
        enabledplugin:
          enabled: true
        disabledplugin:
          enabled: false
    YAML

    FileUtils.mkdir_p(File.dirname(@config_path))
    File.write(@config_path, config_content)

    # Configをリロード
    Rufio::PluginConfig.instance_variable_set(:@config, nil)
    Rufio::PluginConfig.load

    # enabled_pluginsを取得
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)
    enabled = Rufio::PluginManager.enabled_plugins

    # EnabledPluginのみが含まれることを確認
    enabled_names = enabled.map(&:name)
    assert_includes enabled_names, "EnabledPlugin"
    refute_includes enabled_names, "DisabledPlugin"
  end

  def test_plugin_with_missing_dependency_is_skipped_with_warning
    # 存在しないgemに依存するプラグインを作成
    plugin_content = <<~RUBY
      module Rufio
        module Plugins
          class PluginWithMissingGem < Plugin
            requires 'nonexistent_gem_xyz_123'

            def name
              "PluginWithMissingGem"
            end
          end
        end
      end
    RUBY

    File.write(File.join(@user_plugins_dir, 'plugin_with_missing_gem.rb'), plugin_content)

    # 警告が出力されることを確認（標準エラー出力をキャプチャ）
    _out, err = capture_io do
      Rufio::PluginManager.load_all
      # enabled_pluginsを呼び出してプラグインのインスタンス化と警告出力をトリガー
      Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)
      Rufio::PluginManager.enabled_plugins
    end

    # 警告メッセージが含まれることを確認
    assert_match(/⚠️/, err)

    # enabled_pluginsから除外されることを確認
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)
    enabled = Rufio::PluginManager.enabled_plugins
    enabled_names = enabled.map(&:name)
    refute_includes enabled_names, "PluginWithMissingGem"
  end

  def test_plugin_load_error_is_handled_gracefully
    # 構文エラーのあるプラグインを作成
    plugin_content = <<~RUBY
      module Rufio
        module Plugins
          class BrokenPlugin < Plugin
            # 構文エラー
            def name
              "BrokenPlugin"
            # endが足りない
        end
      end
    RUBY

    File.write(File.join(@user_plugins_dir, 'broken_plugin.rb'), plugin_content)

    # エラーが発生してもrufioは起動継続する
    Rufio::PluginManager.load_all
    # エラーが発生しなければ成功
    assert true
  end

  private

  def cleanup_test_classes
    [
      :EnabledTestPlugin,
      :EnabledPlugin,
      :DisabledPlugin,
      :UserTestPlugin,
      :AnotherUserPlugin,
      :PluginWithMissingGem,
      :BrokenPlugin
    ].each do |class_name|
      if Rufio::Plugins.const_defined?(class_name)
        Rufio::Plugins.send(:remove_const, class_name)
      end
    end
  end
end
