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
      assert_includes doc, '| `s` | Fuzzy search file names |', name
      assert_includes doc, '| `/` | Fuzzy search file names (same as `s`) |', name
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
  # s / / / F は内蔵の検索画面を使う。fzf は不要になった
  def test_docs_do_not_require_fzf
    %w[help.md keybindings.md welcome.md].each do |name|
      refute_match(/fzf/i, read(name), name)
    end
    root = File.expand_path('..', __dir__)
    %w[docs/guide.md docs/guide_ja.md README.md README_ja.md].each do |name|
      doc = File.read(File.join(root, name))
      refute_match(/with fzf|fzf でファイル名検索|fzf (file|ファイル)|install fzf|still use fzf|fzf を使用/i, doc, name)
      assert_includes doc, 'file_search', name if name.start_with?('docs/')
    end
  end  
  # 内蔵検索画面の再走査（Ctrl+R）とプレビューを説明する
  def test_docs_describe_fuzzy_cache_and_preview
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => ['Ctrl+R', 'preview'], 'info/keybindings.md' => ['Ctrl+R'],
      'docs/guide.md' => ['Ctrl+R', 'Cached', 'preview'], 'docs/guide_ja.md' => ['Ctrl+R', 'Cached', 'プレビュー'] }.each do |name, words|
      doc = File.read(File.join(root, name))
      words.each { |word| assert_includes doc, word, name }
    end
  end
end
