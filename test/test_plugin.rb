# frozen_string_literal: true

require 'test_helper'

class TestPlugin < Minitest::Test
  def setup
    # テスト用のプラグインクラスを定義する前に、登録済みプラグインをクリア
    if defined?(Rufio::PluginManager)
      Rufio::PluginManager.instance_variable_set(:@plugins, [])
    end
  end

  def teardown
    # テスト後にクリーンアップ
    if defined?(Rufio::PluginManager)
      Rufio::PluginManager.instance_variable_set(:@plugins, [])
    end

    # テスト用に定義したクラスを削除
    cleanup_test_classes
  end

  def test_plugin_base_class_exists
    assert defined?(Rufio::Plugin), "Rufio::Plugin クラスが定義されていません"
  end

  def test_plugin_dependency_error_exists
    assert defined?(Rufio::Plugin::DependencyError), "Rufio::Plugin::DependencyError クラスが定義されていません"
  end

  def test_plugin_auto_registration_on_inheritance
    # プラグインを継承したクラスは自動的に登録される
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPlugin, test_plugin)

    # PluginManagerに登録されていることを確認
    assert_includes Rufio::PluginManager.plugins, Rufio::Plugins::TestPlugin
  end

  def test_plugin_requires_name_method
    # nameメソッドが実装されていない場合、エラーになるか確認
    test_plugin = Class.new(Rufio::Plugin) do
      # nameメソッドを定義しない
    end

    Rufio::Plugins.const_set(:TestPluginNoName, test_plugin)
    plugin = Rufio::Plugins::TestPluginNoName.new

    # nameメソッドが未実装の場合、NotImplementedErrorまたはそれに類するエラーを投げる
    assert_raises(NotImplementedError) do
      plugin.name
    end
  end

  def test_plugin_default_description
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPluginDefaultDesc, test_plugin)
    plugin = Rufio::Plugins::TestPluginDefaultDesc.new
    assert_equal "", plugin.description
  end

  def test_plugin_custom_description
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def description
        "テストプラグインです"
      end
    end

    Rufio::Plugins.const_set(:TestPluginCustomDesc, test_plugin)
    plugin = Rufio::Plugins::TestPluginCustomDesc.new
    assert_equal "テストプラグインです", plugin.description
  end

  def test_plugin_default_version
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPluginDefaultVer, test_plugin)
    plugin = Rufio::Plugins::TestPluginDefaultVer.new
    assert_equal "1.0.0", plugin.version
  end

  def test_plugin_custom_version
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def version
        "2.3.4"
      end
    end

    Rufio::Plugins.const_set(:TestPluginCustomVer, test_plugin)
    plugin = Rufio::Plugins::TestPluginCustomVer.new
    assert_equal "2.3.4", plugin.version
  end

  def test_plugin_default_commands
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPluginDefaultCmd, test_plugin)
    plugin = Rufio::Plugins::TestPluginDefaultCmd.new
    assert_equal({}, plugin.commands)
  end

  def test_plugin_custom_commands
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def commands
        {
          test_command: method(:execute_test),
          another_command: method(:execute_another)
        }
      end

      private

      def execute_test
        "test executed"
      end

      def execute_another
        "another executed"
      end
    end

    Rufio::Plugins.const_set(:TestPluginCustomCmd, test_plugin)
    plugin = Rufio::Plugins::TestPluginCustomCmd.new
    commands = plugin.commands

    assert_equal 2, commands.size
    assert_includes commands.keys, :test_command
    assert_includes commands.keys, :another_command

    # コマンドが実際に実行できることを確認
    assert_equal "test executed", commands[:test_command].call
    assert_equal "another executed", commands[:another_command].call
  end

  def test_plugin_requires_gem_declaration
    test_plugin = Class.new(Rufio::Plugin) do
      requires 'fileutils', 'yaml'

      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPluginRequires, test_plugin)
    assert_equal ['fileutils', 'yaml'], Rufio::Plugins::TestPluginRequires.required_gems
  end

  def test_plugin_dependency_check_with_available_gems
    # 標準ライブラリのgemは常に利用可能
    test_plugin = Class.new(Rufio::Plugin) do
      requires 'fileutils', 'yaml'

      def name
        "PluginWithDependencies"
      end
    end

    Rufio::Plugins.const_set(:PluginWithDependencies, test_plugin)

    # 依存gemが満たされている場合、正常に初期化される
    plugin = Rufio::Plugins::PluginWithDependencies.new
    assert_equal "PluginWithDependencies", plugin.name
  end

  def test_plugin_dependency_check_with_missing_gems
    # 存在しないgemを依存として宣言
    test_plugin = Class.new(Rufio::Plugin) do
      requires 'nonexistent_gem_12345', 'another_missing_gem_67890'

      def name
        "PluginWithMissingDependencies"
      end
    end

    Rufio::Plugins.const_set(:PluginWithMissingDependencies, test_plugin)

    # 依存gemが不足している場合、DependencyErrorを投げる
    error = assert_raises(Rufio::Plugin::DependencyError) do
      Rufio::Plugins::PluginWithMissingDependencies.new
    end

    # エラーメッセージに不足しているgemがリストされていることを確認
    assert_match(/nonexistent_gem_12345/, error.message)
    assert_match(/another_missing_gem_67890/, error.message)
  end

  def test_plugin_dependency_error_message_includes_install_instructions
    test_plugin = Class.new(Rufio::Plugin) do
      requires 'nonexistent_gem_12345'

      def name
        "PluginWithMissingDependency"
      end
    end

    Rufio::Plugins.const_set(:PluginWithMissingDependency, test_plugin)

    error = assert_raises(Rufio::Plugin::DependencyError) do
      Rufio::Plugins::PluginWithMissingDependency.new
    end

    # エラーメッセージにインストール方法が含まれていることを確認
    assert_match(/gem install/, error.message)
  end

  def test_plugin_with_no_dependencies
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end
    end

    Rufio::Plugins.const_set(:TestPluginNoDeps, test_plugin)

    # 依存宣言がない場合、空の配列が返される
    assert_equal [], Rufio::Plugins::TestPluginNoDeps.required_gems

    # 正常に初期化される
    plugin = Rufio::Plugins::TestPluginNoDeps.new
    assert_equal "TestPlugin", plugin.name
  end

  private

  def cleanup_test_classes
    [
      :TestPlugin,
      :TestPluginNoName,
      :TestPluginDefaultDesc,
      :TestPluginCustomDesc,
      :TestPluginDefaultVer,
      :TestPluginCustomVer,
      :TestPluginDefaultCmd,
      :TestPluginCustomCmd,
      :TestPluginRequires,
      :PluginWithDependencies,
      :PluginWithMissingDependencies,
      :PluginWithMissingDependency,
      :TestPluginNoDeps
    ].each do |class_name|
      begin
        if Rufio::Plugins.const_defined?(class_name, false)
          Rufio::Plugins.send(:remove_const, class_name)
        end
      rescue NameError
        # 定数が存在しない場合は無視
      end
    end
  end
end
