# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/bookmark_storage'
require_relative '../lib/rufio/bookmark'

Minitest.autorun

module Rufio
  class TestBookmarkStorage < Minitest::Test
    def setup
      @test_config_dir = File.join(Dir.tmpdir, 'rufio_test_storage')
      FileUtils.mkdir_p(@test_config_dir)
    end

    def teardown
      FileUtils.rm_rf(@test_config_dir) if Dir.exist?(@test_config_dir)
    end

    # ========================================
    # JsonBookmarkStorage のテスト
    # ========================================

    def test_json_storage_save_and_load
      json_file = File.join(@test_config_dir, 'bookmarks.json')
      storage = JsonBookmarkStorage.new(json_file)

      bookmarks = [
        { path: '/path/to/dir1', name: 'dir1' },
        { path: '/path/to/dir2', name: 'dir2' }
      ]

      storage.save(bookmarks)
      loaded = storage.load

      assert_equal 2, loaded.length
      assert_equal '/path/to/dir1', loaded[0][:path]
      assert_equal 'dir1', loaded[0][:name]
      assert_equal '/path/to/dir2', loaded[1][:path]
      assert_equal 'dir2', loaded[1][:name]
    end

    def test_json_storage_load_from_nonexistent_file
      json_file = File.join(@test_config_dir, 'nonexistent.json')
      storage = JsonBookmarkStorage.new(json_file)

      loaded = storage.load

      assert_equal [], loaded
    end

    def test_json_storage_load_from_invalid_json
      json_file = File.join(@test_config_dir, 'invalid.json')
      File.write(json_file, 'invalid json content')
      storage = JsonBookmarkStorage.new(json_file)

      loaded = storage.load

      assert_equal [], loaded
    end

    def test_json_storage_validates_bookmark_structure
      json_file = File.join(@test_config_dir, 'bookmarks.json')
      # 不正な構造のデータを含むJSONファイルを作成
      File.write(json_file, '[{"path": "/valid", "name": "valid"}, {"invalid": true}, "string"]')
      storage = JsonBookmarkStorage.new(json_file)

      loaded = storage.load

      # 有効なブックマークのみがロードされる
      assert_equal 1, loaded.length
      assert_equal '/valid', loaded[0][:path]
    end

    def test_json_storage_creates_directory_if_not_exists
      nested_dir = File.join(@test_config_dir, 'nested', 'dir')
      json_file = File.join(nested_dir, 'bookmarks.json')
      storage = JsonBookmarkStorage.new(json_file)

      bookmarks = [{ path: '/path', name: 'name' }]
      storage.save(bookmarks)

      assert Dir.exist?(nested_dir)
      assert File.exist?(json_file)
    end

    # ========================================
    # YamlBookmarkStorage のテスト
    # ========================================

    def test_yaml_storage_save_and_load
      yaml_file = File.join(@test_config_dir, 'config.yml')
      storage = YamlBookmarkStorage.new(yaml_file)

      bookmarks = [
        { path: '/path/to/dir1', name: 'dir1' },
        { path: '/path/to/dir2', name: 'dir2' }
      ]

      storage.save(bookmarks)
      loaded = storage.load

      assert_equal 2, loaded.length
      assert_equal '/path/to/dir1', loaded[0][:path]
      assert_equal 'dir1', loaded[0][:name]
    end

    def test_yaml_storage_load_from_nonexistent_file
      yaml_file = File.join(@test_config_dir, 'nonexistent.yml')
      storage = YamlBookmarkStorage.new(yaml_file)

      loaded = storage.load

      assert_equal [], loaded
    end

    def test_yaml_storage_load_from_file_without_bookmarks_section
      yaml_file = File.join(@test_config_dir, 'config.yml')
      File.write(yaml_file, "script_paths:\n  - /path/to/scripts\n")
      storage = YamlBookmarkStorage.new(yaml_file)

      loaded = storage.load

      assert_equal [], loaded
    end

    def test_yaml_storage_preserves_other_sections
      yaml_file = File.join(@test_config_dir, 'config.yml')
      # 他のセクションを含むYAMLファイルを作成
      File.write(yaml_file, <<~YAML)
        script_paths:
          - /path/to/scripts
        plugins:
          fileoperations:
            enabled: true
      YAML

      storage = YamlBookmarkStorage.new(yaml_file)
      bookmarks = [{ path: '/path/to/dir', name: 'mydir' }]
      storage.save(bookmarks)

      # YAMLファイルを再読み込みして他のセクションが保持されていることを確認
      content = YAML.safe_load(File.read(yaml_file), symbolize_names: true)
      assert_equal ['/path/to/scripts'], content[:script_paths]
      assert_equal true, content.dig(:plugins, :fileoperations, :enabled)
      assert_equal 1, content[:bookmarks].length
    end

    def test_yaml_storage_creates_directory_if_not_exists
      nested_dir = File.join(@test_config_dir, 'nested', 'dir')
      yaml_file = File.join(nested_dir, 'config.yml')
      storage = YamlBookmarkStorage.new(yaml_file)

      bookmarks = [{ path: '/path', name: 'name' }]
      storage.save(bookmarks)

      assert Dir.exist?(nested_dir)
      assert File.exist?(yaml_file)
    end

    def test_yaml_storage_validates_bookmark_structure
      yaml_file = File.join(@test_config_dir, 'config.yml')
      # 不正な構造のデータを含むYAMLファイルを作成
      File.write(yaml_file, <<~YAML)
        bookmarks:
          - path: /valid
            name: valid
          - invalid: true
          - just_a_string
      YAML
      storage = YamlBookmarkStorage.new(yaml_file)

      loaded = storage.load

      # 有効なブックマークのみがロードされる
      assert_equal 1, loaded.length
      assert_equal '/valid', loaded[0][:path]
    end

    def test_yaml_format_is_human_readable
      yaml_file = File.join(@test_config_dir, 'config.yml')
      storage = YamlBookmarkStorage.new(yaml_file)

      bookmarks = [
        { path: '/Users/miso/devs/project1', name: 'proj1' },
        { path: '/Users/miso/devs/project2', name: 'proj2' }
      ]
      storage.save(bookmarks)

      content = File.read(yaml_file)
      # YAMLは人間が読みやすいフォーマット
      assert_includes content, 'bookmarks:'
      assert_includes content, '/Users/miso/devs/project1'
      assert_includes content, 'proj1'
    end

    # ========================================
    # マイグレーションのテスト
    # ========================================

    def test_migrate_json_to_yaml
      json_file = File.join(@test_config_dir, 'bookmarks.json')
      yaml_file = File.join(@test_config_dir, 'config.yml')

      # JSONファイルにブックマークを保存
      json_storage = JsonBookmarkStorage.new(json_file)
      bookmarks = [
        { path: '/path/to/dir1', name: 'dir1' },
        { path: '/path/to/dir2', name: 'dir2' }
      ]
      json_storage.save(bookmarks)

      # マイグレーション実行
      result = BookmarkMigrator.migrate(json_file, yaml_file)

      assert result
      # YAMLファイルにブックマークが移行されている
      yaml_storage = YamlBookmarkStorage.new(yaml_file)
      loaded = yaml_storage.load
      assert_equal 2, loaded.length
      assert_equal '/path/to/dir1', loaded[0][:path]

      # JSONファイルはバックアップされている
      assert File.exist?("#{json_file}.bak")
      refute File.exist?(json_file)
    end

    def test_migrate_skips_if_json_not_exists
      json_file = File.join(@test_config_dir, 'nonexistent.json')
      yaml_file = File.join(@test_config_dir, 'config.yml')

      result = BookmarkMigrator.migrate(json_file, yaml_file)

      refute result
      refute File.exist?(yaml_file)
    end

    def test_migrate_merges_with_existing_yaml
      json_file = File.join(@test_config_dir, 'bookmarks.json')
      yaml_file = File.join(@test_config_dir, 'config.yml')

      # 既存のYAMLファイルを作成
      File.write(yaml_file, <<~YAML)
        script_paths:
          - /path/to/scripts
      YAML

      # JSONファイルにブックマークを保存
      json_storage = JsonBookmarkStorage.new(json_file)
      bookmarks = [{ path: '/path/to/dir', name: 'mydir' }]
      json_storage.save(bookmarks)

      # マイグレーション実行
      BookmarkMigrator.migrate(json_file, yaml_file)

      # YAMLファイルの内容を確認
      content = YAML.safe_load(File.read(yaml_file), symbolize_names: true)
      assert_equal ['/path/to/scripts'], content[:script_paths]
      assert_equal 1, content[:bookmarks].length
    end

    # ========================================
    # Bookmark クラスとストレージの統合テスト
    # ========================================

    def test_bookmark_with_yaml_storage
      yaml_file = File.join(@test_config_dir, 'config.yml')
      test_dir = File.join(@test_config_dir, 'test_dir')
      FileUtils.mkdir_p(test_dir)

      yaml_storage = YamlBookmarkStorage.new(yaml_file)
      bookmark = Bookmark.new(yaml_file, storage: yaml_storage)

      # ブックマークを追加
      result = bookmark.add(test_dir, 'TestDir')
      assert result
      assert_equal 1, bookmark.list.length

      # 新しいインスタンスで読み込み
      new_yaml_storage = YamlBookmarkStorage.new(yaml_file)
      new_bookmark = Bookmark.new(yaml_file, storage: new_yaml_storage)
      assert_equal 1, new_bookmark.list.length
      assert_equal 'TestDir', new_bookmark.list.first[:name]
    end

    def test_bookmark_with_yaml_storage_preserves_other_config
      yaml_file = File.join(@test_config_dir, 'config.yml')
      test_dir = File.join(@test_config_dir, 'test_dir')
      FileUtils.mkdir_p(test_dir)

      # 既存の設定ファイルを作成
      File.write(yaml_file, <<~YAML)
        script_paths:
          - /path/to/scripts
        plugins:
          hello:
            enabled: true
      YAML

      yaml_storage = YamlBookmarkStorage.new(yaml_file)
      bookmark = Bookmark.new(yaml_file, storage: yaml_storage)

      # ブックマークを追加
      bookmark.add(test_dir, 'TestDir')

      # 他の設定が保持されていることを確認
      content = YAML.safe_load(File.read(yaml_file), symbolize_names: true)
      assert_equal ['/path/to/scripts'], content[:script_paths]
      assert_equal true, content.dig(:plugins, :hello, :enabled)
      assert_equal 1, content[:bookmarks].length
    end
  end
end
