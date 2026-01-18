# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require_relative "../lib/rufio/dsl_command_loader"
require_relative "../lib/rufio/script_executor"
require_relative "../lib/rufio/builtin_commands"
require "minitest/autorun"

# Phase 2: 組み込みコマンドのテスト
class TestBuiltinCommands < Minitest::Test
  def setup
    # 組み込みコマンドをロード
    @commands = Rufio::BuiltinCommands.load
  end

  # === 組み込みコマンドの存在確認 ===

  def test_hello_command_exists
    assert @commands.key?(:hello)
  end

  def test_stop_command_exists
    assert @commands.key?(:stop)
  end

  # === hello コマンドのテスト ===

  def test_hello_command_is_ruby_type
    cmd = @commands[:hello]
    assert_equal :ruby, cmd.command_type
  end

  def test_hello_command_has_description
    cmd = @commands[:hello]
    refute_empty cmd.description
  end

  def test_hello_command_returns_greeting
    cmd = @commands[:hello]
    result = Rufio::ScriptExecutor.execute_command(cmd)

    assert result[:success]
    assert_includes result[:stdout], "Hello"
  end

  # === stop コマンドのテスト ===

  def test_stop_command_is_ruby_type
    cmd = @commands[:stop]
    assert_equal :ruby, cmd.command_type
  end

  def test_stop_command_has_description
    cmd = @commands[:stop]
    refute_empty cmd.description
  end

  # stop コマンドは時間がかかるので実行テストはスキップ

  # === BuiltinCommands API テスト ===

  def test_load_returns_hash
    commands = Rufio::BuiltinCommands.load
    assert_kind_of Hash, commands
  end

  def test_all_commands_are_dsl_command_instances
    @commands.each do |name, cmd|
      assert_kind_of Rufio::DslCommand, cmd, "#{name} should be DslCommand instance"
    end
  end

  def test_all_commands_are_valid
    @commands.each do |name, cmd|
      assert cmd.valid?, "#{name} should be valid: #{cmd.errors.join(', ')}"
    end
  end
end
