# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestPluginsHello < Minitest::Test
  def setup
    # プラグインマネージャーをリセット
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # Helloプラグインを登録
    if Rufio::Plugins.const_defined?(:Hello)
      Rufio::PluginManager.register(Rufio::Plugins::Hello)
    end
  end

  def teardown
    # テスト後のクリーンアップ
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)
  end

  def test_hello_plugin_exists
    assert defined?(Rufio::Plugins::Hello), "Rufio::Plugins::Hello クラスが定義されていません"
  end

  def test_hello_plugin_has_name
    plugin = Rufio::Plugins::Hello.new
    assert_equal "Hello", plugin.name
  end

  def test_hello_plugin_has_description
    plugin = Rufio::Plugins::Hello.new
    assert_kind_of String, plugin.description
    refute_empty plugin.description
  end

  def test_hello_plugin_provides_hello_command
    plugin = Rufio::Plugins::Hello.new
    commands = plugin.commands
    assert_includes commands.keys, :hello
  end

  def test_hello_command_returns_greeting
    plugin = Rufio::Plugins::Hello.new
    result = plugin.commands[:hello].call
    assert_kind_of String, result
    assert_includes result, "Hello"
  end

  def test_hello_command_available_in_command_mode
    # プラグインを有効化
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    available_commands = command_mode.available_commands

    assert_includes available_commands, :hello
  end

  def test_hello_command_execution
    # プラグインを有効化
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("hello")

    assert_kind_of String, result
    assert_includes result, "Hello"
  end
end
