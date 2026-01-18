# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require "minitest/autorun"
require "tempfile"
require "fileutils"

class TestDslCommand < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @test_script = File.join(@temp_dir, "test_script.rb")
    File.write(@test_script, "#!/usr/bin/env ruby\nputs 'hello'")
    File.chmod(0o755, @test_script)
    # macOSでは/var → /private/varにrealpathで変換されるため正規化
    @test_script = File.realpath(@test_script)
    @temp_dir = File.realpath(@temp_dir)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def test_create_command_with_basic_attributes
    cmd = Rufio::DslCommand.new(
      name: "test-cmd",
      script: @test_script,
      description: "A test command"
    )

    assert_equal "test-cmd", cmd.name
    assert_equal @test_script, cmd.script
    assert_equal "A test command", cmd.description
  end

  def test_auto_resolve_interpreter_from_extension
    cmd = Rufio::DslCommand.new(
      name: "ruby-cmd",
      script: @test_script
    )

    assert_equal "ruby", cmd.interpreter
  end

  def test_explicit_interpreter_overrides_auto_resolve
    cmd = Rufio::DslCommand.new(
      name: "custom-cmd",
      script: @test_script,
      interpreter: "jruby"
    )

    assert_equal "jruby", cmd.interpreter
  end

  def test_expand_tilde_in_script_path
    home_script = "~/test_script.rb"
    expected_path = File.expand_path(home_script)

    cmd = Rufio::DslCommand.new(
      name: "home-cmd",
      script: home_script
    )

    assert_equal expected_path, cmd.script
  end

  def test_valid_command_with_existing_script
    cmd = Rufio::DslCommand.new(
      name: "valid-cmd",
      script: @test_script
    )

    assert cmd.valid?
    assert_empty cmd.errors
  end

  def test_invalid_command_with_nonexistent_script
    cmd = Rufio::DslCommand.new(
      name: "invalid-cmd",
      script: "/nonexistent/script.rb"
    )

    refute cmd.valid?
    assert cmd.errors.any? { |e| e.include?("not found") }
  end

  def test_invalid_command_with_missing_name
    cmd = Rufio::DslCommand.new(
      name: "",
      script: @test_script
    )

    refute cmd.valid?
    assert cmd.errors.any? { |e| e.include?("name") }
  end

  def test_invalid_command_with_missing_script
    cmd = Rufio::DslCommand.new(
      name: "no-script-cmd",
      script: ""
    )

    refute cmd.valid?
    assert cmd.errors.any? { |e| e.downcase.include?("script") }
  end

  def test_command_with_non_executable_script_is_valid
    # スクリプトはインタープリタ経由で実行されるため、実行権限は不要
    non_exec_script = File.join(@temp_dir, "non_exec.rb")
    File.write(non_exec_script, "puts 'hello'")
    File.chmod(0o644, non_exec_script)

    cmd = Rufio::DslCommand.new(
      name: "non-exec-cmd",
      script: non_exec_script
    )

    assert cmd.valid?
  end

  def test_to_execution_args_returns_array
    cmd = Rufio::DslCommand.new(
      name: "exec-cmd",
      script: @test_script
    )

    args = cmd.to_execution_args
    assert_kind_of Array, args
    assert_equal "ruby", args[0]
    assert_equal @test_script, args[1]
  end

  def test_to_execution_args_with_custom_interpreter
    cmd = Rufio::DslCommand.new(
      name: "custom-exec-cmd",
      script: @test_script,
      interpreter: "jruby"
    )

    args = cmd.to_execution_args
    assert_equal "jruby", args[0]
    assert_equal @test_script, args[1]
  end

  def test_to_h_returns_hash_representation
    cmd = Rufio::DslCommand.new(
      name: "hash-cmd",
      script: @test_script,
      description: "Hash test",
      interpreter: "ruby"
    )

    hash = cmd.to_h
    assert_kind_of Hash, hash
    assert_equal "hash-cmd", hash[:name]
    assert_equal @test_script, hash[:script]
    assert_equal "Hash test", hash[:description]
    assert_equal "ruby", hash[:interpreter]
  end

  def test_path_traversal_prevention
    # パストラバーサルを含むパスは正規化される
    traversal_script = File.join(@temp_dir, "..", File.basename(@temp_dir), "test_script.rb")

    cmd = Rufio::DslCommand.new(
      name: "traversal-cmd",
      script: traversal_script
    )

    # パスが正規化されていることを確認
    refute cmd.script.include?("..")
    assert_equal File.realpath(@test_script), cmd.script
  end

  def test_default_description_is_empty_string
    cmd = Rufio::DslCommand.new(
      name: "no-desc-cmd",
      script: @test_script
    )

    assert_equal "", cmd.description
  end
end
