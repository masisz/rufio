# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestProjectMode < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @config_file = File.join(@temp_dir, 'bookmarks.json')
      @log_dir = File.join(@temp_dir, 'logs')
      @bookmark = Bookmark.new(@config_file)
      @project_mode = ProjectMode.new(@bookmark, @log_dir)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # pキーでプロジェクトモードに入る
    def test_enter_project_mode
      assert_equal false, @project_mode.active?
      @project_mode.activate
      assert_equal true, @project_mode.active?
    end

    # プロジェクトモードでブックマーク一覧が表示される
    def test_list_bookmarks_in_project_mode
      @bookmark.add('/path/to/project1', 'project1')
      @bookmark.add('/path/to/project2', 'project2')

      @project_mode.activate
      bookmarks = @project_mode.list_bookmarks

      assert_equal 2, bookmarks.length
      assert_equal 'project1', bookmarks[0][:name]
      assert_equal 'project2', bookmarks[1][:name]
    end

    # spaceキーでディレクトリを選択
    def test_select_bookmark
      @bookmark.add('/path/to/project', 'project')

      @project_mode.activate
      result = @project_mode.select_bookmark(1)

      assert_equal true, result
      assert_equal '/path/to/project', @project_mode.selected_path
      assert_equal 'project', @project_mode.selected_name
    end

    # 無効な番号での選択は失敗する
    def test_select_invalid_bookmark
      @project_mode.activate
      result = @project_mode.select_bookmark(99)

      assert_equal false, result
      assert_nil @project_mode.selected_path
    end

    # escキーで元のモードに戻る
    def test_deactivate_project_mode
      @project_mode.activate
      assert_equal true, @project_mode.active?

      @project_mode.deactivate
      assert_equal false, @project_mode.active?
      assert_nil @project_mode.selected_path
    end

    # プロジェクトモードが非アクティブの時にブックマーク選択は失敗する
    def test_cannot_select_when_inactive
      @bookmark.add('/path/to/project', 'project')
      result = @project_mode.select_bookmark(1)

      assert_equal false, result
      assert_nil @project_mode.selected_path
    end
  end
end
