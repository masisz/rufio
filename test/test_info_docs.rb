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
      assert_includes doc, '| `C` | Config mode', name
      assert_includes doc, '| `e` | Open current directory in file explorer |', name
      refute_includes doc, '| `G` | Global search', name
      refute_includes doc, '| `s` | Fuzzy search file names |', name
      refute_match(/\| `F` \| Search file contents with rga/, doc, name)
      refute_includes doc, 'Cycle to next bookmark', name
      refute_includes doc, 'Cycle to previous bookmark', name
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
    assert_includes doc, '| `/` | Search under the current directory |'
    assert_includes doc, '| `C` | Config mode |'
    refute_includes doc, '| `G` | Global search across bookmarks |'
    refute_includes doc, 'Next bookmark'
    refute_includes doc, 'Switch mode (Files / Logs / Jobs / Help)'
    refute_includes doc, 'enter **Help Mode** where you can browse'
  end
  # 表プレビューの / はシート／テーブル一覧を開く
  def test_docs_describe_the_table_list_key
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => 'the list of sheets or tables',
      'info/keybindings.md' => 'the list of sheets or tables',
      'docs/guide.md' => 'the list of sheets or tables',
      'docs/guide_ja.md' => 'シート／テーブル一覧',
      'README.md' => 'the list of sheets or tables',
      'README_ja.md' => 'シート／テーブル一覧' }.each do |name, phrase|
      assert_includes File.read(File.join(root, name)), phrase, name
    end
  end

  # 表プレビューの Space はカラム選択、y は選択カラムをカンマ区切りでコピー
  def test_docs_describe_column_selection
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => 'selects the column',
      'info/keybindings.md' => 'Select / unselect the column',
      'docs/guide.md' => 'Select / unselect the column',
      'docs/guide_ja.md' => 'カラムを選択',
      'README.md' => 'Space` selects columns',
      'README_ja.md' => 'Space` でカラムを選び' }.each do |name, phrase|
      assert_includes File.read(File.join(root, name)), phrase, name
    end
  end

  # プレビューモードの / は、テキストならファイル内検索、表なら行の絞り込み
  def test_docs_describe_the_preview_searches
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => ['searches inside the file', 'filters its rows', 'price > 100'],
      'info/keybindings.md' => ['Search inside the file', 'Filter the rows', 'price > 100'],
      'docs/guide.md' => ['Searching inside a preview', 'Filtering rows', 'price > 100'],
      'docs/guide_ja.md' => ['プレビュー内の検索', '行の絞り込み', 'price > 100'],
      'README.md' => ['price > 100'],
      'README_ja.md' => ['price > 100'] }.each do |name, words|
      doc = File.read(File.join(root, name))
      words.each { |word| assert_includes doc, word, name }
    end
  end

  # 画像プレビュー（Kitty グラフィックスプロトコル、Phase 1 は PNG 直送）
  def test_docs_describe_the_image_preview
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => ['Kitty graphics protocol', 'RUFIO_IMAGE_PREVIEW=0'],
      'info/keybindings.md' => ['Kitty graphics protocol'],
      'docs/guide.md' => ['### Images', 'Kitty graphics protocol'],
      'docs/guide_ja.md' => ['### 画像', 'Kitty グラフィックスプロトコル'],
      'README.md' => ['Kitty graphics protocol'],
      'README_ja.md' => ['Kitty グラフィックスプロトコル'] }.each do |name, words|
      doc = File.read(File.join(root, name))
      words.each { |word| assert_includes doc, word, name }
    end
  end

  # Tab / Shift+Tab のブックマーク巡回は削除した
  def test_docs_do_not_describe_bookmark_cycling
    root = File.expand_path('..', __dir__)
    %w[info/help.md info/keybindings.md info/welcome.md
       docs/guide.md docs/guide_ja.md README.md README_ja.md].each do |name|
      doc = File.read(File.join(root, name))
      refute_match(/Cycle to (next|previous) bookmark|[Nn]ext bookmark|次 \/ 前のブックマーク|次のブックマーク/, doc, name)
    end
  end

  # 検索は内蔵の実装で、fzf も rga も使わない
  def test_docs_do_not_require_external_search_tools
    %w[help.md keybindings.md welcome.md].each do |name|
      refute_match(/fzf/i, read(name), name)
      refute_match(/rga/i, read(name), name)
    end
    root = File.expand_path('..', __dir__)
    %w[docs/guide.md docs/guide_ja.md README.md README_ja.md].each do |name|
      doc = File.read(File.join(root, name))
      refute_match(/with fzf|fzf でファイル名検索|fzf (file|ファイル)|install fzf|still use fzf|fzf を使用/i, doc, name)
      assert_includes doc, '`search` (/)', name if name.start_with?('docs/')
    end
  end

  # 検索キーは / 一本。旧 G モード・s・F とそのキャッシュ設定は説明に残さない
  def test_docs_describe_the_single_search_key
    root = File.expand_path('..', __dir__)
    { 'info/help.md' => ['Search (`/`)', 'fuzzy file names', 'literal content'],
      'info/keybindings.md' => ['`/` is the only search key', 'Tab'],
      'docs/guide.md' => ['Search Screen (`/` in the file list)', 'fuzzy', 'bookmarks are not searched'],
      'docs/guide_ja.md' => ['検索画面（ファイル一覧の `/`）', 'あいまい', 'ブックマークは検索しません'] }.each do |name, words|
      doc = File.read(File.join(root, name))
      words.each { |word| assert_includes doc, word, name }
    end

    %w[info/help.md info/keybindings.md info/welcome.md
       docs/guide.md docs/guide_ja.md README.md README_ja.md].each do |name|
      doc = File.read(File.join(root, name))
      refute_includes doc, 'FUZZY_SEARCH_CACHE', name
      refute_includes doc, 'G mode', name
      refute_includes doc, 'G モード', name
    end
  end
end
