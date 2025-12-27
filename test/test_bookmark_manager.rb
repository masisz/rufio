# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestBookmarkManager < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @config_file = File.join(@temp_dir, 'bookmarks.json')

      # テスト用のプロジェクトディレクトリを作成
      @project1_dir = File.join(@temp_dir, 'project1')
      @project2_dir = File.join(@temp_dir, 'project2')
      @myproject_dir = File.join(@temp_dir, 'myproject')
      FileUtils.mkdir_p(@project1_dir)
      FileUtils.mkdir_p(@project2_dir)
      FileUtils.mkdir_p(@myproject_dir)

      @bookmark = Bookmark.new(@config_file)
      @bookmark_manager = BookmarkManager.new(@bookmark)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # ブックマーク一覧が左画面に表示される
    def test_display_bookmarks_on_left_pane
      @bookmark.add(@project1_dir, 'project1')
      @bookmark.add(@project2_dir, 'project2')

      display_data = @bookmark_manager.get_left_pane_data

      assert_equal 2, display_data.length
      assert_equal '1. project1', display_data[0]
      assert_equal '2. project2', display_data[1]
    end

    # ブックマークが存在しない場合は空の配列を返す
    def test_empty_bookmarks_returns_empty_array
      display_data = @bookmark_manager.get_left_pane_data

      assert_equal 0, display_data.length
    end

    # 選択したブックマークの詳細が右画面に表示される
    def test_display_bookmark_detail_on_right_pane
      @bookmark.add(@myproject_dir, 'myproject')

      detail = @bookmark_manager.get_right_pane_data(1)

      assert_includes detail, 'myproject'
      assert_includes detail, @myproject_dir
    end

    # 無効な番号の場合は空文字列を返す
    def test_invalid_bookmark_number_returns_empty_string
      detail = @bookmark_manager.get_right_pane_data(99)

      assert_equal '', detail
    end

    # ブックマークの総数を取得
    def test_get_bookmark_count
      @bookmark.add(@project1_dir, 'project1')
      @bookmark.add(@project2_dir, 'project2')

      count = @bookmark_manager.count

      assert_equal 2, count
    end
  end
end
