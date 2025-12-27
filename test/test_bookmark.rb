# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/bookmark'

# 明示的にMinitestを実行
Minitest.autorun

module Rufio
  class TestBookmark < Minitest::Test
    def setup
      @test_config_dir = File.join(Dir.tmpdir, 'rufio_test_config')
      @test_config_file = File.join(@test_config_dir, 'bookmarks.json')
      
      # テスト用の設定ディレクトリを作成
      FileUtils.mkdir_p(@test_config_dir)
      
      # 既存のブックマークファイルがあれば削除
      FileUtils.rm_f(@test_config_file)
      
      @bookmark = Bookmark.new(@test_config_file)
    end

    def teardown
      # テスト後にクリーンアップ
      FileUtils.rm_rf(@test_config_dir) if Dir.exist?(@test_config_dir)
    end

    def test_initialize_creates_empty_bookmarks
      assert_empty @bookmark.list
    end

    def test_add_bookmark
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name = 'Documents'

      result = @bookmark.add(path, name)

      assert result
      assert_equal 1, @bookmark.list.length
      assert_equal File.expand_path(path), @bookmark.list.first[:path]
      assert_equal name, @bookmark.list.first[:name]
    end

    def test_add_bookmark_with_duplicate_name
      # 実際に存在するテスト用ディレクトリを作成
      path1 = File.join(@test_config_dir, 'documents')
      path2 = File.join(@test_config_dir, 'downloads')
      FileUtils.mkdir_p(path1)
      FileUtils.mkdir_p(path2)
      name = 'Documents'

      @bookmark.add(path1, name)
      result = @bookmark.add(path2, name)

      refute result
      assert_equal 1, @bookmark.list.length
    end

    def test_add_bookmark_with_duplicate_path
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name1 = 'Documents'
      name2 = 'Docs'

      @bookmark.add(path, name1)
      result = @bookmark.add(path, name2)

      refute result
      assert_equal 1, @bookmark.list.length
    end

    def test_remove_bookmark_by_name
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name = 'Documents'

      @bookmark.add(path, name)
      result = @bookmark.remove(name)

      assert result
      assert_empty @bookmark.list
    end

    def test_remove_nonexistent_bookmark
      result = @bookmark.remove('NonExistent')

      refute result
      assert_empty @bookmark.list
    end

    def test_get_bookmark_path
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name = 'Documents'

      @bookmark.add(path, name)
      result = @bookmark.get_path(name)

      assert_equal File.expand_path(path), result
    end

    def test_get_nonexistent_bookmark_path
      result = @bookmark.get_path('NonExistent')
      
      assert_nil result
    end

    def test_find_by_number
      # 実際に存在するテスト用ディレクトリを作成
      paths = {}
      names = ['Documents', 'Downloads', 'Desktop']
      names.each do |name|
        path = File.join(@test_config_dir, name.downcase)
        FileUtils.mkdir_p(path)
        paths[name] = path
        @bookmark.add(path, name)
      end

      # 番号は1から始まる、名前順にソートされる: Desktop, Documents, Downloads
      result = @bookmark.find_by_number(1)
      assert_equal File.expand_path(paths['Desktop']), result[:path]
      assert_equal 'Desktop', result[:name]

      result = @bookmark.find_by_number(2)
      assert_equal File.expand_path(paths['Documents']), result[:path]
      assert_equal 'Documents', result[:name]

      result = @bookmark.find_by_number(3)
      assert_equal File.expand_path(paths['Downloads']), result[:path]
      assert_equal 'Downloads', result[:name]
    end

    def test_find_by_invalid_number
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      @bookmark.add(path, 'Documents')

      result = @bookmark.find_by_number(0)
      assert_nil result

      result = @bookmark.find_by_number(10)
      assert_nil result

      result = @bookmark.find_by_number(-1)
      assert_nil result
    end

    def test_save_and_load_persistence
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name = 'Documents'

      @bookmark.add(path, name)
      @bookmark.save

      # 新しいインスタンスを作成して読み込み
      new_bookmark = Bookmark.new(@test_config_file)
      new_bookmark.load

      assert_equal 1, new_bookmark.list.length
      assert_equal File.expand_path(path), new_bookmark.list.first[:path]
      assert_equal name, new_bookmark.list.first[:name]
    end

    def test_load_from_nonexistent_file
      nonexistent_file = File.join(@test_config_dir, 'nonexistent.json')
      bookmark = Bookmark.new(nonexistent_file)
      
      result = bookmark.load
      
      assert result  # load should succeed with empty list
      assert_empty bookmark.list
    end

    def test_load_from_invalid_json
      # 不正なJSONファイルを作成
      File.write(@test_config_file, 'invalid json content')
      
      result = @bookmark.load
      
      assert result  # load should succeed with empty list
      assert_empty @bookmark.list
    end

    def test_max_bookmarks_limit
      # 実際に存在するテスト用ディレクトリを作成して最大9個のブックマークを追加
      9.times do |i|
        path = File.join(@test_config_dir, "path#{i}")
        FileUtils.mkdir_p(path)
        result = @bookmark.add(path, "bookmark#{i}")
        assert result
      end

      # 10個目は追加できない
      path10 = File.join(@test_config_dir, 'path10')
      FileUtils.mkdir_p(path10)
      result = @bookmark.add(path10, 'bookmark10')
      refute result
      assert_equal 9, @bookmark.list.length
    end

    def test_list_returns_sorted_bookmarks
      # 実際に存在するテスト用ディレクトリを作成
      paths = []
      %w[z a m].each do |letter|
        path = File.join(@test_config_dir, "#{letter}_path")
        FileUtils.mkdir_p(path)
        paths << path
      end
      names = ['ZFolder', 'AFolder', 'MFolder']

      # 順序バラバラで追加
      @bookmark.add(paths[0], names[0])
      @bookmark.add(paths[1], names[1])
      @bookmark.add(paths[2], names[2])

      list = @bookmark.list

      # 名前順でソートされている
      assert_equal 'AFolder', list[0][:name]
      assert_equal 'MFolder', list[1][:name]
      assert_equal 'ZFolder', list[2][:name]
    end

    def test_rename_bookmark
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      old_name = 'Documents'
      new_name = 'MyDocs'

      @bookmark.add(path, old_name)
      result = @bookmark.rename(old_name, new_name)

      assert result
      assert_equal 1, @bookmark.list.length
      assert_equal new_name, @bookmark.list.first[:name]
      assert_equal File.expand_path(path), @bookmark.list.first[:path]
    end

    def test_rename_nonexistent_bookmark
      result = @bookmark.rename('NonExistent', 'NewName')

      refute result
    end

    def test_rename_to_existing_name
      # 実際に存在するテスト用ディレクトリを作成
      path1 = File.join(@test_config_dir, 'documents')
      path2 = File.join(@test_config_dir, 'downloads')
      FileUtils.mkdir_p(path1)
      FileUtils.mkdir_p(path2)

      @bookmark.add(path1, 'Documents')
      @bookmark.add(path2, 'Downloads')

      result = @bookmark.rename('Documents', 'Downloads')

      refute result
      assert_equal 2, @bookmark.list.length
    end

    def test_add_bookmark_strips_whitespace
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)
      name_with_spaces = '  Documents  '

      result = @bookmark.add(path, name_with_spaces)

      assert result
      assert_equal 'Documents', @bookmark.list.first[:name]
    end

    def test_rename_strips_whitespace
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)

      @bookmark.add(path, 'OldName')
      result = @bookmark.rename('OldName', '  NewName  ')

      assert result
      assert_equal 'NewName', @bookmark.list.first[:name]
    end

    def test_rename_to_empty_name_after_strip
      # 実際に存在するテスト用ディレクトリを作成
      path = File.join(@test_config_dir, 'documents')
      FileUtils.mkdir_p(path)

      @bookmark.add(path, 'Documents')
      result = @bookmark.rename('Documents', '   ')

      refute result
      assert_equal 'Documents', @bookmark.list.first[:name]
    end
  end
end