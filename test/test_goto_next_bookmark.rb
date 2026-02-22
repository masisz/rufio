# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

module Rufio
  class TestGotoNextBookmark < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @bookmark_config = File.join(@temp_dir, 'bookmarks.json')

      # テスト用ディレクトリを作成
      @dir_a = File.join(@temp_dir, 'dir_a')
      @dir_b = File.join(@temp_dir, 'dir_b')
      @dir_c = File.join(@temp_dir, 'dir_c')
      FileUtils.mkdir_p(@dir_a)
      FileUtils.mkdir_p(@dir_b)
      FileUtils.mkdir_p(@dir_c)

      # KeybindHandlerを初期化
      @handler = KeybindHandler.new

      # DirectoryListingを設定
      @directory_listing = DirectoryListing.new(@temp_dir)
      @handler.set_directory_listing(@directory_listing)

      # BookmarkManagerを一時設定ファイルで置き換え
      @bookmark = Bookmark.new(@bookmark_config)
      @bookmark_manager = BookmarkManager.new(@bookmark)
      @handler.instance_variable_set(:@bookmark_manager, @bookmark_manager)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir
    end

    # ブックマークがない場合は何も起きない（nilを返す）
    def test_goto_next_bookmark_with_no_bookmarks
      result = @handler.goto_next_bookmark
      assert_nil result
      # ディレクトリが変わっていないことを確認
      assert_equal @temp_dir, @directory_listing.current_path
    end

    # 現在ディレクトリがブックマーク外の場合、最初のブックマークへ移動
    def test_goto_next_bookmark_from_unregistered_dir
      @bookmark.add(@dir_a, 'dir_a')
      @bookmark.add(@dir_b, 'dir_b')

      # 現在のディレクトリ(@temp_dir)はブックマーク外
      @handler.goto_next_bookmark

      assert_equal @dir_a, @directory_listing.current_path
    end

    # 現在ディレクトリが最後のブックマークの場合、最初に循環
    def test_goto_next_bookmark_wraps_from_last_to_first
      @bookmark.add(@dir_a, 'dir_a')
      @bookmark.add(@dir_b, 'dir_b')
      @bookmark.add(@dir_c, 'dir_c')

      # dir_cに移動して、最後のブックマークにいる状態を作る
      @directory_listing.navigate_to_path(@dir_c)

      @handler.goto_next_bookmark

      assert_equal @dir_a, @directory_listing.current_path
    end

    # 中間のブックマークから次のブックマークへ移動
    def test_goto_next_bookmark_advances_to_next
      @bookmark.add(@dir_a, 'dir_a')
      @bookmark.add(@dir_b, 'dir_b')
      @bookmark.add(@dir_c, 'dir_c')

      # dir_aに移動してテスト
      @directory_listing.navigate_to_path(@dir_a)

      @handler.goto_next_bookmark

      assert_equal @dir_b, @directory_listing.current_path
    end

    # 1つのブックマークのみ存在する場合、自身に循環
    def test_goto_next_bookmark_single_bookmark_cycles_to_itself
      @bookmark.add(@dir_a, 'dir_a')

      @directory_listing.navigate_to_path(@dir_a)

      @handler.goto_next_bookmark

      assert_equal @dir_a, @directory_listing.current_path
    end
  end
end
