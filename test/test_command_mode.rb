# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestCommandMode < Minitest::Test
  def setup
    # プラグインマネージャーをリセット
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを作成
    @test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def description
        "テスト用プラグイン"
      end

      def commands
        {
          hello: method(:say_hello),
          greet: method(:greet_user)
        }
      end

      private

      def say_hello
        "Hello from TestPlugin!"
      end

      def greet_user
        "Greetings, user!"
      end
    end

    # プラグインを登録
    Rufio::Plugins.const_set(:TestPlugin, @test_plugin)
    Rufio::PluginManager.register(@test_plugin)
  end

  def teardown
    # テスト後のクリーンアップ
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを削除
    if Rufio::Plugins.const_defined?(:TestPlugin, false)
      Rufio::Plugins.send(:remove_const, :TestPlugin)
    end
  end

  def test_command_mode_class_exists
    assert defined?(Rufio::CommandMode), "Rufio::CommandMode クラスが定義されていません"
  end

  def test_execute_plugin_command
    # プラグインの有効化リストを強制的に更新
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("hello")

    assert_equal "Hello from TestPlugin!", result
  end

  def test_execute_another_plugin_command
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("greet")

    assert_equal "Greetings, user!", result
  end

  def test_execute_nonexistent_command
    command_mode = Rufio::CommandMode.new

    # 存在しないコマンドを実行した場合、エラーメッセージを返す
    result = command_mode.execute("nonexistent")

    assert_match(/コマンドが見つかりません|not found/i, result)
  end

  def test_list_available_commands
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    commands = command_mode.available_commands

    # TestPlugin の hello と greet コマンドが利用可能
    assert_includes commands, :hello
    assert_includes commands, :greet
  end

  def test_command_with_whitespace
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new

    # 前後の空白を無視する
    result = command_mode.execute("  hello  ")
    assert_equal "Hello from TestPlugin!", result
  end

  def test_empty_command
    command_mode = Rufio::CommandMode.new

    # 空のコマンドは何もしない
    result = command_mode.execute("")
    assert_nil result
  end

  def test_get_command_info
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new
    info = command_mode.command_info(:hello)

    # コマンドの情報を取得できる
    assert_equal :hello, info[:name]
    assert_equal "TestPlugin", info[:plugin]
  end

  def test_command_mode_initialization
    # CommandMode が初期化時にプラグインを読み込む
    command_mode = Rufio::CommandMode.new

    # 初期化後、コマンドが利用可能になっている
    refute_empty command_mode.available_commands
  end
end
