# frozen_string_literal: true

require_relative "test_helper"
require "minitest/autorun"
require "tempfile"
require "fileutils"

# Phase 3: CommandMode 統一後のテスト
# 単一の @commands ストアを使用し、すべてのコマンドがDslCommandとして扱われる
class TestCommandModeUnified < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_dir = File.realpath(@temp_dir)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  # === 組み込みコマンドのテスト ===

  def test_builtin_hello_command_is_available
    command_mode = Rufio::CommandMode.new
    commands = command_mode.available_commands

    assert_includes commands, :hello
  end

  def test_builtin_hello_command_executes
    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("hello")

    # 組み込みコマンドはハッシュ形式で結果を返す
    assert_kind_of Hash, result
    assert result[:success]
    assert_includes result[:stdout], "Hello"
  end

  def test_builtin_command_info
    command_mode = Rufio::CommandMode.new
    info = command_mode.command_info(:hello)

    assert_equal :hello, info[:name]
    assert_equal "builtin", info[:plugin]
    refute_empty info[:description]
  end

  # === ユーザーDSLコマンドのテスト ===

  def test_user_dsl_command_is_available
    config_path = create_dsl_config(<<~DSL)
      command "user-cmd" do
        ruby { "User command result" }
        description "ユーザー定義コマンド"
      end
    DSL

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([config_path])

    commands = command_mode.available_commands
    assert_includes commands, :"user-cmd"
  end

  def test_user_dsl_command_executes
    config_path = create_dsl_config(<<~DSL)
      command "user-cmd" do
        ruby { "User command result" }
        description "ユーザー定義コマンド"
      end
    DSL

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([config_path])

    result = command_mode.execute("user-cmd")

    assert_kind_of Hash, result
    assert result[:success]
    assert_equal "User command result", result[:stdout]
  end

  def test_user_dsl_shell_command_executes
    config_path = create_dsl_config(<<~DSL)
      command "echo-cmd" do
        shell "echo hello"
        description "シェルコマンド"
      end
    DSL

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([config_path])

    result = command_mode.execute("echo-cmd")

    assert_kind_of Hash, result
    assert result[:success]
    assert_equal "hello", result[:stdout].strip
  end

  # === 統一されたコマンド実行のテスト ===

  def test_all_commands_return_hash_format
    config_path = create_dsl_config(<<~DSL)
      command "test-cmd" do
        ruby { "test" }
      end
    DSL

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([config_path])

    # 組み込みコマンド
    hello_result = command_mode.execute("hello")
    assert_kind_of Hash, hello_result

    # ユーザーDSLコマンド
    test_result = command_mode.execute("test-cmd")
    assert_kind_of Hash, test_result
  end

  # === シェルコマンド（!プレフィックス）のテスト ===

  def test_shell_command_with_exclamation
    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("!echo test")

    assert_kind_of Hash, result
    assert result[:success]
    assert_equal "test", result[:output].strip
  end

  # === エラーハンドリングのテスト ===

  def test_nonexistent_command_returns_error_message
    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("nonexistent")

    assert_kind_of String, result
    assert_match(/コマンドが見つかりません/, result)
  end

  def test_empty_command_returns_nil
    command_mode = Rufio::CommandMode.new
    result = command_mode.execute("")

    assert_nil result
  end

  # === コマンド優先順位のテスト ===

  def test_user_command_can_override_builtin
    config_path = create_dsl_config(<<~DSL)
      command "hello" do
        ruby { "Custom Hello!" }
        description "カスタムhelloコマンド"
      end
    DSL

    command_mode = Rufio::CommandMode.new
    command_mode.load_dsl_commands([config_path])

    result = command_mode.execute("hello")

    # ユーザー定義コマンドが優先される
    assert_kind_of Hash, result
    assert result[:success]
    assert_equal "Custom Hello!", result[:stdout]
  end

  private

  def create_dsl_config(content)
    path = File.join(@temp_dir, "commands.rb")
    File.write(path, content)
    path
  end
end
