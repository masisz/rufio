# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require_relative "../lib/rufio/script_executor"
require "minitest/autorun"
require "tempfile"
require "fileutils"

class TestScriptExecutor < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_dir = File.realpath(@temp_dir)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def test_execute_successful_ruby_script
    script_path = create_script("success.rb", <<~RUBY)
      puts "Hello from Ruby"
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path)

    assert result[:success]
    assert_equal 0, result[:exit_code]
    assert_includes result[:stdout], "Hello from Ruby"
    assert_empty result[:stderr]
  end

  def test_execute_script_with_exit_code
    script_path = create_script("exit_code.rb", <<~RUBY)
      exit 42
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path)

    refute result[:success]
    assert_equal 42, result[:exit_code]
  end

  def test_execute_script_with_stderr_output
    script_path = create_script("stderr.rb", <<~RUBY)
      $stderr.puts "Error message"
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path)

    assert result[:success]
    assert_includes result[:stderr], "Error message"
  end

  def test_execute_script_with_arguments
    script_path = create_script("args.rb", <<~RUBY)
      puts ARGV.join(",")
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path, ["arg1", "arg2"])

    assert result[:success]
    assert_includes result[:stdout], "arg1,arg2"
  end

  def test_execute_returns_structured_result
    script_path = create_script("result.rb", <<~RUBY)
      puts "output"
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path)

    assert_kind_of Hash, result
    assert result.key?(:success)
    assert result.key?(:exit_code)
    assert result.key?(:stdout)
    assert result.key?(:stderr)
  end

  def test_execute_nonexistent_script
    result = Rufio::ScriptExecutor.execute("ruby", "/nonexistent/script.rb")

    refute result[:success]
    # インタープリタがエラーを返すか、例外がキャッチされる
    assert result[:exit_code] != 0 || result[:error]
  end

  def test_execute_with_dsl_command
    script_path = create_script("dsl_cmd.rb", <<~RUBY)
      puts "DSL command executed"
    RUBY

    cmd = Rufio::DslCommand.new(
      name: "test-cmd",
      script: script_path
    )

    result = Rufio::ScriptExecutor.execute_command(cmd)

    assert result[:success]
    assert_includes result[:stdout], "DSL command executed"
  end

  def test_execute_with_timeout
    script_path = create_script("timeout.rb", <<~RUBY)
      sleep 10
      puts "done"
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path, [], timeout: 0.5)

    refute result[:success]
    assert result[:timeout]
  end

  def test_execute_uses_array_based_execution
    # シェルインジェクション防止のためのテスト
    script_path = create_script("safe.rb", <<~RUBY)
      puts "safe"
    RUBY

    # 悪意のある引数を渡してもシェルに解釈されないことを確認
    result = Rufio::ScriptExecutor.execute("ruby", script_path, ["; echo injected"])

    assert result[:success]
    refute_includes result[:stdout], "injected"
  end

  def test_execute_bash_script
    script_path = create_script("test.sh", <<~BASH)
      #!/bin/bash
      echo "Hello from Bash"
    BASH

    result = Rufio::ScriptExecutor.execute("bash", script_path)

    assert result[:success]
    assert_includes result[:stdout], "Hello from Bash"
  end

  def test_execute_with_working_directory
    subdir = File.join(@temp_dir, "subdir")
    FileUtils.mkdir_p(subdir)

    script_path = create_script("pwd.rb", <<~RUBY)
      puts Dir.pwd
    RUBY

    result = Rufio::ScriptExecutor.execute("ruby", script_path, [], chdir: subdir)

    assert result[:success]
    assert_includes result[:stdout], subdir
  end

  def test_execute_with_environment_variables
    script_path = create_script("env.rb", <<~RUBY)
      puts ENV["TEST_VAR"]
    RUBY

    result = Rufio::ScriptExecutor.execute(
      "ruby", script_path, [],
      env: { "TEST_VAR" => "test_value" }
    )

    assert result[:success]
    assert_includes result[:stdout], "test_value"
  end

  private

  def create_script(name, content)
    path = File.join(@temp_dir, name)
    File.write(path, content)
    File.chmod(0o755, path)
    path
  end
end
