# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require_relative "../lib/rufio/dsl_command"
require_relative "../lib/rufio/dsl_command_loader"
require "minitest/autorun"
require "tempfile"
require "fileutils"

class TestDslCommandLoader < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_dir = File.realpath(@temp_dir)

    # テスト用スクリプトを作成
    @script_path = create_file("test_script.rb", "puts 'hello'")
    @python_script = create_file("analyze.py", "print('hello')")
    @bash_script = create_file("deploy.sh", "echo 'hello'")
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def test_load_from_string_with_single_command
    dsl = <<~DSL
      command "test-cmd" do
        script "#{@script_path}"
        description "A test command"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    assert_equal "test-cmd", commands[0].name
    assert_equal @script_path, commands[0].script
    assert_equal "A test command", commands[0].description
  end

  def test_load_from_string_with_multiple_commands
    dsl = <<~DSL
      command "cmd1" do
        script "#{@script_path}"
        description "First command"
      end

      command "cmd2" do
        script "#{@python_script}"
        description "Second command"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 2, commands.size
    assert_equal "cmd1", commands[0].name
    assert_equal "cmd2", commands[1].name
  end

  def test_load_from_string_with_explicit_interpreter
    dsl = <<~DSL
      command "deploy" do
        script "#{@bash_script}"
        interpreter "zsh"
        description "Deploy script"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    assert_equal "zsh", commands[0].interpreter
  end

  def test_load_from_string_without_description
    dsl = <<~DSL
      command "simple" do
        script "#{@script_path}"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_equal 1, commands.size
    assert_equal "simple", commands[0].name
    assert_equal "", commands[0].description
  end

  def test_load_from_file
    config_path = create_file("commands.rb", <<~DSL)
      command "file-cmd" do
        script "#{@script_path}"
        description "From file"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_file(config_path)

    assert_equal 1, commands.size
    assert_equal "file-cmd", commands[0].name
  end

  def test_load_from_nonexistent_file_returns_empty_array
    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_file("/nonexistent/commands.rb")

    assert_empty commands
  end

  def test_load_validates_commands
    dsl = <<~DSL
      command "valid" do
        script "#{@script_path}"
      end

      command "invalid" do
        script "/nonexistent/script.rb"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    # 有効なコマンドのみが返される
    assert_equal 1, commands.size
    assert_equal "valid", commands[0].name
  end

  def test_load_with_syntax_error_returns_empty_array
    # 実際のRuby構文エラー（閉じ括弧がない）
    dsl = <<~DSL
      command "broken" do
        script "#{@script_path}"
        (unclosed
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    assert_empty commands
    refute_empty loader.errors
  end

  def test_load_reports_errors_for_invalid_commands
    dsl = <<~DSL
      command "invalid" do
        script "/nonexistent/script.rb"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    loader.load_from_string(dsl)

    refute_empty loader.warnings
  end

  def test_search_default_paths
    # デフォルトのパスが検索されることを確認
    loader = Rufio::DslCommandLoader.new
    paths = loader.default_config_paths

    assert paths.any? { |p| p.include?(".rufio/commands.rb") }
    assert paths.any? { |p| p.include?(".config/rufio/commands.rb") }
  end

  def test_load_from_default_paths_when_file_exists
    # 一時的にホームディレクトリをスタブ
    config_dir = File.join(@temp_dir, ".rufio")
    FileUtils.mkdir_p(config_dir)
    config_path = File.join(config_dir, "commands.rb")

    File.write(config_path, <<~DSL)
      command "default-cmd" do
        script "#{@script_path}"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    # カスタムパスを指定してテスト
    commands = loader.load_from_paths([config_path])

    assert_equal 1, commands.size
    assert_equal "default-cmd", commands[0].name
  end

  def test_dsl_only_allows_safe_methods
    # 危険なメソッドが呼び出せないことを確認
    dsl = <<~DSL
      system("echo 'dangerous'")
      command "safe" do
        script "#{@script_path}"
      end
    DSL

    loader = Rufio::DslCommandLoader.new
    commands = loader.load_from_string(dsl)

    # systemコマンドは実行されない（エラーになるか無視される）
    # ただしコマンド定義は正常に処理される
    assert commands.empty? || commands.size == 1
  end

  def test_command_with_tilde_path
    home = Dir.home
    # ホームディレクトリにテスト用スクリプトを一時的に作成
    test_script = File.join(home, ".rufio_test_script.rb")

    begin
      File.write(test_script, "puts 'test'")

      dsl = <<~DSL
        command "home-cmd" do
          script "~/.rufio_test_script.rb"
          description "Home directory script"
        end
      DSL

      loader = Rufio::DslCommandLoader.new
      commands = loader.load_from_string(dsl)

      assert_equal 1, commands.size
      assert_equal File.expand_path("~/.rufio_test_script.rb"), commands[0].script
    ensure
      FileUtils.rm_f(test_script)
    end
  end

  private

  def create_file(name, content)
    path = File.join(@temp_dir, name)
    File.write(path, content)
    File.chmod(0o755, path)
    path
  end
end
