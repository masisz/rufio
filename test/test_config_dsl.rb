# frozen_string_literal: true

require_relative 'test_helper'

Minitest.autorun

class TestConfigDSL < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "rufio_config_dsl_test_#{Process.pid}")
    FileUtils.mkdir_p(@test_dir)

    # テスト用のパスを設定
    @config_rb_path = File.join(@test_dir, 'config.rb')
    @script_paths_yml = File.join(@test_dir, 'script_paths.yml')
    @bookmarks_yml = File.join(@test_dir, 'bookmarks.yml')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    Rufio::Config.reset_config!
  end

  # ========================================
  # パス定数のテスト
  # ========================================

  def test_config_dir_path
    assert_equal File.expand_path('~/.config/rufio'), Rufio::Config::CONFIG_DIR
  end

  def test_config_rb_path
    assert_equal File.expand_path('~/.config/rufio/config.rb'), Rufio::Config::CONFIG_RB_PATH
  end

  def test_script_paths_yml_path
    assert_equal File.expand_path('~/.config/rufio/script_paths.yml'), Rufio::Config::SCRIPT_PATHS_YML
  end

  def test_bookmarks_yml_path
    assert_equal File.expand_path('~/.config/rufio/bookmarks.yml'), Rufio::Config::BOOKMARKS_YML
  end

  # ========================================
  # script_paths.yml の読み書きテスト
  # ========================================

  def test_load_script_paths_returns_empty_array_when_file_not_exists
    result = Rufio::Config.load_script_paths('/nonexistent/script_paths.yml')
    assert_equal [], result
  end

  def test_load_script_paths_reads_yaml_file
    File.write(@script_paths_yml, <<~YAML)
      - /usr/local/scripts
      - ~/my-scripts
      - ./local-scripts
    YAML

    result = Rufio::Config.load_script_paths(@script_paths_yml)

    assert_equal 3, result.length
    assert_includes result, '/usr/local/scripts'
    assert_includes result, File.expand_path('~/my-scripts')
    assert_includes result, File.expand_path('./local-scripts')
  end

  def test_save_script_paths
    paths = ['/test/path1', '/test/path2']
    Rufio::Config.save_script_paths(@script_paths_yml, paths)

    assert File.exist?(@script_paths_yml)
    result = Rufio::Config.load_script_paths(@script_paths_yml)
    assert_equal paths, result
  end

  def test_add_script_path
    File.write(@script_paths_yml, <<~YAML)
      - /existing/path
    YAML

    Rufio::Config.add_script_path(@script_paths_yml, '/new/path')

    result = Rufio::Config.load_script_paths(@script_paths_yml)
    assert_equal 2, result.length
    assert_includes result, '/existing/path'
    assert_includes result, '/new/path'
  end

  def test_remove_script_path
    File.write(@script_paths_yml, <<~YAML)
      - /path1
      - /path2
      - /path3
    YAML

    Rufio::Config.remove_script_path(@script_paths_yml, '/path2')

    result = Rufio::Config.load_script_paths(@script_paths_yml)
    assert_equal 2, result.length
    assert_includes result, '/path1'
    assert_includes result, '/path3'
    refute_includes result, '/path2'
  end

  # ========================================
  # bookmarks.yml の読み書きテスト
  # ========================================

  def test_load_bookmarks_returns_empty_array_when_file_not_exists
    result = Rufio::Config.load_bookmarks_from_yml('/nonexistent/bookmarks.yml')
    assert_equal [], result
  end

  def test_load_bookmarks_reads_yaml_file
    File.write(@bookmarks_yml, <<~YAML)
      - path: /home/user/docs
        name: Documents
      - path: /home/user/projects
        name: Projects
    YAML

    result = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)

    assert_equal 2, result.length
    assert_equal '/home/user/docs', result[0][:path]
    assert_equal 'Documents', result[0][:name]
  end

  def test_save_bookmarks
    bookmarks = [
      { path: '/test/path1', name: 'Bookmark1' },
      { path: '/test/path2', name: 'Bookmark2' }
    ]
    Rufio::Config.save_bookmarks_to_yml(@bookmarks_yml, bookmarks)

    assert File.exist?(@bookmarks_yml)
    result = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)
    assert_equal 2, result.length
    assert_equal '/test/path1', result[0][:path]
  end

  def test_add_bookmark
    File.write(@bookmarks_yml, <<~YAML)
      - path: /existing
        name: Existing
    YAML

    Rufio::Config.add_bookmark(@bookmarks_yml, '/new/path', 'NewBookmark')

    result = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)
    assert_equal 2, result.length
    assert_equal 'NewBookmark', result[1][:name]
  end

  def test_remove_bookmark
    File.write(@bookmarks_yml, <<~YAML)
      - path: /path1
        name: Bookmark1
      - path: /path2
        name: Bookmark2
    YAML

    Rufio::Config.remove_bookmark(@bookmarks_yml, 'Bookmark1')

    result = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)
    assert_equal 1, result.length
    assert_equal 'Bookmark2', result[0][:name]
  end

  # ========================================
  # DSL config.rb のテスト
  # ========================================

  def test_load_config_rb_executes_ruby_file
    File.write(@config_rb_path, <<~RUBY)
      # DSL形式のコンフィグファイル
      LANGUAGE = 'ja'
    RUBY

    # config.rb を読み込む
    Rufio::Config.load_config_rb(@config_rb_path)

    # ファイルが読み込まれたことを確認
    assert File.exist?(@config_rb_path)
  end

  def test_script_paths_uses_script_paths_yml
    # script_paths.yml を作成
    File.write(@script_paths_yml, <<~YAML)
      - /test/scripts
    YAML

    result = Rufio::Config.load_script_paths(@script_paths_yml)
    assert_equal ['/test/scripts'], result
  end

  def test_bookmarks_uses_bookmarks_yml
    # bookmarks.yml を作成
    File.write(@bookmarks_yml, <<~YAML)
      - path: /test/bookmark
        name: Test
    YAML

    result = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)
    assert_equal 1, result.length
    assert_equal '/test/bookmark', result[0][:path]
  end

  # ========================================
  # 後方互換性: config.yml からの移行
  # ========================================

  def test_migrate_from_config_yml
    # 古い形式の config.yml を作成
    old_config_yml = File.join(@test_dir, 'config.yml')
    File.write(old_config_yml, <<~YAML)
      script_paths:
        - /old/script/path
      bookmarks:
        - path: /old/bookmark
          name: OldBookmark
    YAML

    # マイグレーション実行
    Rufio::Config.migrate_from_config_yml(old_config_yml, @script_paths_yml, @bookmarks_yml)

    # script_paths.yml が作成されたことを確認
    script_paths = Rufio::Config.load_script_paths(@script_paths_yml)
    assert_includes script_paths, '/old/script/path'

    # bookmarks.yml が作成されたことを確認
    bookmarks = Rufio::Config.load_bookmarks_from_yml(@bookmarks_yml)
    assert_equal 1, bookmarks.length
    assert_equal 'OldBookmark', bookmarks[0][:name]
  end
end
