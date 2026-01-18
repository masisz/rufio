# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require_relative "../lib/rufio/script_executor"
require_relative "../lib/rufio/dsl_command_loader"
require "minitest/autorun"
require "tempfile"
require "fileutils"

# テスト用にCommandModeをロードする
# DSL統合機能をテストするため、rufioのメインモジュールの一部を直接ロード
require_relative "../lib/rufio"

class TestDslIntegration < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_dir = File.realpath(@temp_dir)

    # プラグインマネージャーをリセット
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用スクリプトを作成
    @hello_script = create_script("hello.rb", <<~RUBY)
      puts "Hello from DSL command!"
    RUBY

    @echo_script = create_script("echo_args.rb", <<~RUBY)
      puts ARGV.join(" ")
    RUBY

    @failing_script = create_script("fail.rb", <<~RUBY)
      exit 1
    RUBY

    # テスト用DSL設定ファイルを作成
    @config_path = File.join(@temp_dir, "commands.rb")
    File.write(@config_path, <<~DSL)
      command "hello-dsl" do
        script "#{@hello_script}"
        description "Hello from DSL"
      end

      command "echo-dsl" do
        script "#{@echo_script}"
        description "Echo arguments"
      end

      command "fail-dsl" do
        script "#{@failing_script}"
        description "A failing command"
      end
    DSL
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)
  end

  def test_command_mode_loads_dsl_commands
    command_mode = create_command_mode_with_dsl

    commands = command_mode.available_commands
    assert_includes commands, :"hello-dsl"
    assert_includes commands, :"echo-dsl"
  end

  def test_command_mode_executes_dsl_command
    command_mode = create_command_mode_with_dsl

    result = command_mode.execute("hello-dsl")

    assert_kind_of Hash, result
    assert result[:success], "DSL command should succeed"
    assert_includes result[:stdout], "Hello from DSL command!"
  end

  def test_command_mode_dsl_command_info
    command_mode = create_command_mode_with_dsl

    info = command_mode.command_info(:"hello-dsl")

    assert_equal :"hello-dsl", info[:name]
    assert_equal "Hello from DSL", info[:description]
    assert_equal "dsl", info[:plugin]
  end

  def test_command_mode_dsl_command_failure
    command_mode = create_command_mode_with_dsl

    result = command_mode.execute("fail-dsl")

    assert_kind_of Hash, result
    refute result[:success], "Failing DSL command should fail"
    assert_equal 1, result[:exit_code]
  end

  def test_plugin_and_dsl_commands_coexist
    # プラグインコマンドを登録
    test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def description
        "テスト用プラグイン"
      end

      def commands
        {
          plugin_cmd: method(:plugin_method)
        }
      end

      private

      def plugin_method
        "Plugin result"
      end
    end

    Rufio::Plugins.const_set(:TestDslPlugin, test_plugin) unless Rufio::Plugins.const_defined?(:TestDslPlugin)
    Rufio::PluginManager.register(test_plugin)

    command_mode = create_command_mode_with_dsl

    commands = command_mode.available_commands

    # プラグインコマンドとDSLコマンドの両方が利用可能
    assert_includes commands, :plugin_cmd
    assert_includes commands, :"hello-dsl"
  ensure
    if Rufio::Plugins.const_defined?(:TestDslPlugin, false)
      Rufio::Plugins.send(:remove_const, :TestDslPlugin)
    end
  end

  def test_command_mode_with_empty_dsl_config
    empty_config = File.join(@temp_dir, "empty_commands.rb")
    File.write(empty_config, "")

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([empty_config])

    # 空の設定でもエラーにならない
    assert_kind_of Array, command_mode.available_commands
  end

  def test_command_mode_with_nonexistent_dsl_config
    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands(["/nonexistent/commands.rb"])

    # 存在しない設定ファイルでもエラーにならない
    assert_kind_of Array, command_mode.available_commands
  end

  def test_dsl_command_is_executable_from_command_mode
    command_mode = create_command_mode_with_dsl

    # コマンドが実行可能であることを確認
    result = command_mode.execute("hello-dsl")

    assert result.is_a?(Hash) || result.is_a?(String)
    if result.is_a?(Hash)
      assert result.key?(:success)
      assert result.key?(:stdout) || result.key?(:output)
    end
  end

  def test_dsl_command_not_confused_with_shell_command
    command_mode = create_command_mode_with_dsl

    # ! で始まらないDSLコマンドはシェルコマンドとして解釈されない
    result = command_mode.execute("hello-dsl")

    # DSLコマンドとして実行され、シェルコマンドとしては実行されない
    assert_kind_of Hash, result
    assert result[:success]
  end

  private

  def create_script(name, content)
    path = File.join(@temp_dir, name)
    File.write(path, content)
    File.chmod(0o755, path)
    path
  end

  def create_command_mode_with_dsl
    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([@config_path])
    command_mode
  end
end
