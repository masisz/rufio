# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require_relative "../lib/rufio/dsl_command_loader"
require_relative "../lib/rufio/script_executor"
require "minitest/autorun"
require "tempfile"
require "fileutils"

# Phase 1: DSL拡張（inline Ruby/Shell対応）のテスト
class TestDslCommandInline < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_dir = File.realpath(@temp_dir)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  # === DslCommand: ruby_block 属性のテスト ===

  def test_create_command_with_ruby_block
    ruby_block = proc { "Hello from Ruby!" }
    cmd = Rufio::DslCommand.new(
      name: "hello",
      ruby_block: ruby_block,
      description: "挨拶コマンド"
    )

    assert_equal "hello", cmd.name
    assert_equal ruby_block, cmd.ruby_block
    assert_equal "挨拶コマンド", cmd.description
    assert_nil cmd.script
  end

  def test_command_type_returns_ruby_for_ruby_block
    cmd = Rufio::DslCommand.new(
      name: "ruby-cmd",
      ruby_block: proc { "test" }
    )

    assert_equal :ruby, cmd.command_type
  end

  def test_ruby_block_command_is_valid_without_script
    cmd = Rufio::DslCommand.new(
      name: "ruby-cmd",
      ruby_block: proc { "test" },
      description: "Ruby block command"
    )

    assert cmd.valid?
    assert_empty cmd.errors
  end

  # === DslCommand: shell_command 属性のテスト ===

  def test_create_command_with_shell_command
    cmd = Rufio::DslCommand.new(
      name: "gitlog",
      shell_command: "git log --oneline -10",
      description: "Git履歴を表示"
    )

    assert_equal "gitlog", cmd.name
    assert_equal "git log --oneline -10", cmd.shell_command
    assert_nil cmd.script
  end

  def test_command_type_returns_shell_for_shell_command
    cmd = Rufio::DslCommand.new(
      name: "shell-cmd",
      shell_command: "echo hello"
    )

    assert_equal :shell, cmd.command_type
  end

  def test_shell_command_is_valid_without_script
    cmd = Rufio::DslCommand.new(
      name: "shell-cmd",
      shell_command: "echo hello",
      description: "Shell command"
    )

    assert cmd.valid?
    assert_empty cmd.errors
  end

  # === DslCommand: script（従来の外部スクリプト）のテスト ===

  def test_command_type_returns_script_for_script_path
    script_path = File.join(@temp_dir, "test.rb")
    File.write(script_path, "puts 'hello'")

    cmd = Rufio::DslCommand.new(
      name: "script-cmd",
      script: script_path
    )

    assert_equal :script, cmd.command_type
  end

  # === DslCommandLoader: ruby DSL対応のテスト ===

  def test_load_command_with_ruby_block_from_dsl
    dsl = <<~DSL
      command "hello" do
        ruby { "Hello, World!" }
        description "挨拶メッセージを返す"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    cmd = commands[0]
    assert_equal "hello", cmd.name
    assert_equal :ruby, cmd.command_type
    assert_equal "挨拶メッセージを返す", cmd.description
  end

  def test_load_command_with_multiline_ruby_block
    dsl = <<~DSL
      command "stop" do
        ruby do
          sleep 0.01
          "done"
        end
        description "短い待機"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    cmd = commands[0]
    assert_equal "stop", cmd.name
    assert_equal :ruby, cmd.command_type
  end

  # === DslCommandLoader: shell DSL対応のテスト ===

  def test_load_command_with_shell_from_dsl
    dsl = <<~DSL
      command "gitlog" do
        shell "git log --oneline -10"
        description "Git履歴を表示"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    cmd = commands[0]
    assert_equal "gitlog", cmd.name
    assert_equal :shell, cmd.command_type
    assert_equal "git log --oneline -10", cmd.shell_command
  end

  # === 複合テスト: 複数タイプのコマンドを混在 ===

  def test_load_mixed_command_types
    script_path = File.join(@temp_dir, "test.rb")
    File.write(script_path, "puts 'hello'")

    dsl = <<~DSL
      command "ruby-cmd" do
        ruby { "Ruby result" }
        description "Ruby command"
      end

      command "shell-cmd" do
        shell "echo hello"
        description "Shell command"
      end

      command "script-cmd" do
        script "#{script_path}"
        description "Script command"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 3, commands.size
    assert_equal :ruby, commands[0].command_type
    assert_equal :shell, commands[1].command_type
    assert_equal :script, commands[2].command_type
  end

  # === ScriptExecutor: タイプ別実行のテスト ===

  def test_execute_ruby_command
    cmd = Rufio::DslCommand.new(
      name: "hello",
      ruby_block: proc { "Hello, World!" }
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    assert result[:success]
    assert_equal "Hello, World!", result[:stdout]
  end

  def test_execute_ruby_command_with_error
    cmd = Rufio::DslCommand.new(
      name: "error-cmd",
      ruby_block: proc { raise "Test error" }
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    refute result[:success]
    assert_includes result[:error], "Test error"
  end

  def test_execute_shell_command
    cmd = Rufio::DslCommand.new(
      name: "echo-cmd",
      shell_command: "echo hello"
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    assert result[:success]
    assert_equal "hello", result[:stdout].strip
  end

  def test_execute_shell_command_with_failure
    cmd = Rufio::DslCommand.new(
      name: "fail-cmd",
      shell_command: "exit 1"
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    refute result[:success]
  end

  def test_execute_script_command
    script_path = File.join(@temp_dir, "test.rb")
    File.write(script_path, "puts 'from script'")

    cmd = Rufio::DslCommand.new(
      name: "script-cmd",
      script: script_path
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    assert result[:success]
    assert_equal "from script", result[:stdout].strip
  end

  # === to_h のテスト ===

  def test_to_h_includes_ruby_block_indicator
    cmd = Rufio::DslCommand.new(
      name: "ruby-cmd",
      ruby_block: proc { "test" },
      description: "Ruby command"
    )

    hash = cmd.to_h

    assert_equal "ruby-cmd", hash[:name]
    assert_equal "Ruby command", hash[:description]
    assert hash[:has_ruby_block]
  end

  def test_to_h_includes_shell_command
    cmd = Rufio::DslCommand.new(
      name: "shell-cmd",
      shell_command: "echo hello",
      description: "Shell command"
    )

    hash = cmd.to_h

    assert_equal "shell-cmd", hash[:name]
    assert_equal "echo hello", hash[:shell_command]
  end
end
