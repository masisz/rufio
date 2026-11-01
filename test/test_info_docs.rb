# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

# info/ のヘルプ文書が現在のキーバインドに追従していることを確認する
class TestInfoDocs < Minitest::Test
  INFO_DIR = File.expand_path('../info', __dir__)

  def read(name)
    File.read(File.join(INFO_DIR, name))
  end

  def test_docs_use_current_mode_keys
    %w[help.md keybindings.md].each do |name|
      doc = read(name)
      assert_includes doc, '| `}` | Jump to bottom of list |', name
      refute_includes doc, '| `G` | Jump to bottom of list |', name
      assert_includes doc, '| `G` | Global search', name
      assert_includes doc, '| `C` | Config mode', name
      assert_includes doc, '| `e` | Open current directory in file explorer |', name
      assert_includes doc, '| `/` | Search file names with fzf (same as `s`) |', name
      assert_includes doc, '| `Tab` | Cycle to next bookmark (Files mode) |', name
      assert_includes doc, '| `Shift+Tab` | Cycle to previous bookmark (Files mode) |', name
      refute_includes doc, 'Switch mode: Files -> Logs -> Jobs -> Help', name
    end
  end

  def test_docs_describe_floating_help_menu
    %w[help.md keybindings.md].each do |name|
      doc = read(name)
      assert_includes doc, '1/2/3', name
      refute_includes doc, 'return to previous directory', name
      refute_includes doc, 'return to your previous directory', name
    end
  end

  def test_docs_describe_zip_features
    %w[help.md keybindings.md].each do |name|
      doc = read(name)
      assert_includes doc, '`.zip` previews list the archive entries', name
      assert_includes doc, '`x`: Cancel', name
    end
  end

  def test_welcome_lists_current_modes
    doc = read('welcome.md')
    assert_includes doc, '| `G` | Global search across bookmarks |'
    assert_includes doc, '| `C` | Config mode |'
    assert_includes doc, '| `Tab` | Next bookmark |'
    refute_includes doc, 'Switch mode (Files / Logs / Jobs / Help)'
    refute_includes doc, 'enter **Help Mode** where you can browse'
  end
end
