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

  # シェルコマンド実行機能のテスト
  def test_execute_shell_command_with_exclamation
    command_mode = Rufio::CommandMode.new

    # ! で始まるコマンドはシェルコマンドとして実行される
    result = command_mode.execute("!echo 'Hello Shell'")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    assert_match(/Hello Shell/, result[:output])
  end

  def test_execute_shell_command_returns_output
    command_mode = Rufio::CommandMode.new

    # シェルコマンドの出力を取得できる
    result = command_mode.execute("!pwd")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    refute_empty result[:output]
  end

  def test_execute_shell_command_error_handling
    command_mode = Rufio::CommandMode.new

    # 存在しないコマンドを実行した場合、エラーを返す
    result = command_mode.execute("!nonexistent_command_xyz_123")

    assert_kind_of Hash, result
    assert_equal false, result[:success]
    assert result[:error]
  end

  def test_execute_shell_command_with_arguments
    command_mode = Rufio::CommandMode.new

    # 引数を含むシェルコマンドを実行できる
    result = command_mode.execute("!ls -la")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    refute_empty result[:output]
  end

  def test_normal_command_still_works_after_shell_support
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    command_mode = Rufio::CommandMode.new

    # ! なしの通常のコマンドも引き続き動作する
    result = command_mode.execute("hello")
    assert_equal "Hello from TestPlugin!", result
  end

  # 追加のエラーハンドリングテスト
  def test_execute_shell_command_with_pipe
    command_mode = Rufio::CommandMode.new

    # パイプを使ったコマンドが正しく実行される
    result = command_mode.execute("!echo hello | grep hello")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    assert_match(/hello/, result[:output])
  end

  def test_execute_shell_command_with_quotes
    command_mode = Rufio::CommandMode.new

    # 引用符を含むコマンドが正しく実行される
    result = command_mode.execute('!echo "hello world"')

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    assert_equal "hello world", result[:output]
  end

  def test_execute_shell_command_stderr_output
    command_mode = Rufio::CommandMode.new

    # 標準エラー出力を生成するコマンド
    result = command_mode.execute("!ruby -e 'STDERR.puts \"error message\"'")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    # 標準エラーが分離されている
    assert result.key?(:stderr), "結果にstderrキーが含まれている必要があります"
    assert_match(/error message/, result[:stderr])
  end

  def test_execute_shell_command_only_exclamation
    command_mode = Rufio::CommandMode.new

    # ! のみの場合、エラーを返す
    result = command_mode.execute("!")

    assert_kind_of Hash, result
    assert_equal false, result[:success]
    assert result[:error]
  end

  def test_execute_shell_command_with_exit_code
    command_mode = Rufio::CommandMode.new

    # 終了コード1で終了するコマンド
    result = command_mode.execute("!ruby -e 'exit 1'")

    assert_kind_of Hash, result
    assert_equal false, result[:success]
    assert result[:error]
    assert_match(/終了コード.*1/, result[:error])
  end

  def test_execute_shell_command_separates_stdout_stderr
    command_mode = Rufio::CommandMode.new

    # 標準出力と標準エラーの両方を出力するコマンド
    result = command_mode.execute("!ruby -e 'puts \"stdout\"; STDERR.puts \"stderr\"'")

    assert_kind_of Hash, result
    assert_equal true, result[:success]
    # 標準出力と標準エラーが分離されている
    assert result.key?(:output), "結果にoutputキーが含まれている必要があります"
    assert result.key?(:stderr), "結果にstderrキーが含まれている必要があります"
    assert_equal "stdout", result[:output]
    assert_match(/stderr/, result[:stderr])
  end
end
