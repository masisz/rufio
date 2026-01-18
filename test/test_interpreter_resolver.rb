# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/rufio/interpreter_resolver"
require "minitest/autorun"

class TestInterpreterResolver < Minitest::Test
  def test_resolve_ruby
    assert_equal "ruby", Rufio::InterpreterResolver.resolve(".rb")
  end

  def test_resolve_python
    assert_equal "python3", Rufio::InterpreterResolver.resolve(".py")
  end

  def test_resolve_bash
    assert_equal "bash", Rufio::InterpreterResolver.resolve(".sh")
  end

  def test_resolve_javascript
    assert_equal "node", Rufio::InterpreterResolver.resolve(".js")
  end

  def test_resolve_powershell_on_windows
    Rufio::InterpreterResolver.stub(:windows?, true) do
      assert_equal "powershell", Rufio::InterpreterResolver.resolve(".ps1")
    end
  end

  def test_resolve_powershell_on_non_windows
    Rufio::InterpreterResolver.stub(:windows?, false) do
      assert_equal "pwsh", Rufio::InterpreterResolver.resolve(".ps1")
    end
  end

  def test_resolve_perl
    assert_equal "perl", Rufio::InterpreterResolver.resolve(".pl")
  end

  def test_resolve_lua
    assert_equal "lua", Rufio::InterpreterResolver.resolve(".lua")
  end

  def test_resolve_unknown_extension
    assert_nil Rufio::InterpreterResolver.resolve(".xyz")
  end

  def test_resolve_without_dot
    assert_equal "ruby", Rufio::InterpreterResolver.resolve("rb")
  end

  def test_resolve_case_insensitive
    assert_equal "ruby", Rufio::InterpreterResolver.resolve(".RB")
    assert_equal "python3", Rufio::InterpreterResolver.resolve(".PY")
  end

  def test_windows_detection
    # プラットフォーム検出のテスト（現環境がmacOSの場合）
    if RUBY_PLATFORM =~ /darwin/
      refute Rufio::InterpreterResolver.windows?
      assert Rufio::InterpreterResolver.macos?
      refute Rufio::InterpreterResolver.linux?
    end
  end

  def test_resolve_from_path
    assert_equal "ruby", Rufio::InterpreterResolver.resolve_from_path("/path/to/script.rb")
    assert_equal "python3", Rufio::InterpreterResolver.resolve_from_path("~/scripts/analyze.py")
    assert_equal "bash", Rufio::InterpreterResolver.resolve_from_path("./deploy.sh")
  end

  def test_resolve_from_path_with_no_extension
    assert_nil Rufio::InterpreterResolver.resolve_from_path("/path/to/script")
  end

  def test_all_extensions_returns_hash
    extensions = Rufio::InterpreterResolver.all_extensions
    assert_kind_of Hash, extensions
    assert extensions.key?(".rb")
    assert extensions.key?(".py")
    assert extensions.key?(".sh")
  end
end
