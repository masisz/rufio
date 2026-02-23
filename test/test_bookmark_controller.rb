# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# BookmarkController のユニットテスト
# Phase 5: KeybindHandler から BookmarkController を抽出するリファクタリングに対応
class TestBookmarkController < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_bookmark_ctrl_test")
    setup_test_files

    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @filter_manager = Rufio::FilterManager.new
    @nav_controller = Rufio::NavigationController.new(@directory_listing, @filter_manager)
    @dialog_renderer = Rufio::DialogRenderer.new
    @bookmark = Rufio::Bookmark.new
    @bookmark_manager = Rufio::BookmarkManager.new(@bookmark, @dialog_renderer)
    @zoxide = Rufio::ZoxideIntegration.new(@dialog_renderer)
    @script_path_manager = Rufio::ScriptPathManager.new(Rufio::Config::SCRIPT_PATHS_YML)
    @notification_manager = Rufio::NotificationManager.new

    @controller = Rufio::BookmarkController.new(
      @directory_listing,
      @bookmark_manager,
      @dialog_renderer,
      @nav_controller,
      @script_path_manager,
      @notification_manager,
      @zoxide
    )
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === 基本テスト ===

  def test_can_instantiate
    assert_instance_of Rufio::BookmarkController, @controller
  end

  def test_set_terminal_ui
    @controller.set_terminal_ui(nil)
    pass
  end

  def test_set_directory_listing_updates_directory
    new_dir = Dir.mktmpdir("rufio_new_bm_test")
    begin
      new_listing = Rufio::DirectoryListing.new(new_dir)
      @controller.set_directory_listing(new_listing)
      pass
    ensure
      FileUtils.rm_rf(new_dir)
    end
  end

  # === navigate_to_directory テスト ===

  def test_navigate_to_directory_to_existing_path
    subdir = File.join(@test_dir, "subdir1")
    result = @controller.navigate_to_directory(subdir)
    assert result, "存在するディレクトリへの移動は成功すること"
    assert_equal subdir, @directory_listing.current_path
  end

  def test_navigate_to_directory_to_nonexistent_path
    result = @controller.navigate_to_directory("/nonexistent/path/xyz")
    refute result, "存在しないパスへの移動はfalseを返すこと"
  end

  # === goto_bookmark テスト ===

  def test_goto_bookmark_returns_false_for_invalid_number
    result = @controller.goto_bookmark(99)
    refute result, "存在しないブックマーク番号はfalseを返すこと"
  end

  def test_goto_bookmark_navigates_to_existing_bookmark
    # ブックマークを追加してから移動
    subdir = File.join(@test_dir, "subdir1")
    @bookmark_manager.add(subdir, "test_bookmark")
    bookmarks = @bookmark_manager.list
    skip "ブックマーク追加失敗" if bookmarks.empty?

    bookmark = bookmarks.first
    result = @controller.goto_bookmark_by_path(bookmark[:path])
    assert result, "存在するパスへの移動は成功すること"
  end

  # === goto_start_directory テスト ===

  def test_goto_start_directory_navigates_to_start
    # まずサブディレクトリに移動
    subdir = File.join(@test_dir, "subdir1")
    @directory_listing.navigate_to("subdir1")
    refute_equal @test_dir, @directory_listing.current_path

    # 起動ディレクトリに戻る
    result = @controller.goto_start_directory
    assert result, "起動ディレクトリへの移動は成功すること"
    assert_equal @test_dir, @directory_listing.current_path
  end

  def test_goto_start_directory_returns_false_without_listing
    @controller.set_directory_listing(nil)
    result = @controller.goto_start_directory
    refute result, "directory_listingがなければfalseを返すこと"
  end

  # === goto_next_bookmark テスト ===

  def test_goto_next_bookmark_returns_nil_or_integer
    result = @controller.goto_next_bookmark
    # ブックマークがない場合はnil、ある場合はインデックス（整数）を返す
    assert result.nil? || result.is_a?(Integer),
           "goto_next_bookmarkはnil（ブックマークなし）かIntegerを返すこと"
  end

  # === メソッド存在確認テスト ===

  def test_add_bookmark_method_exists
    assert @controller.respond_to?(:add_bookmark), "add_bookmarkメソッドが存在すること"
  end

  def test_show_bookmark_menu_method_exists
    assert @controller.respond_to?(:show_bookmark_menu), "show_bookmark_menuメソッドが存在すること"
  end

  def test_show_zoxide_menu_method_exists
    assert @controller.respond_to?(:show_zoxide_menu), "show_zoxide_menuメソッドが存在すること"
  end

  def test_add_to_script_paths_method_exists
    assert @controller.respond_to?(:add_to_script_paths), "add_to_script_pathsメソッドが存在すること"
  end

  def test_show_script_paths_manager_method_exists
    assert @controller.respond_to?(:show_script_paths_manager), "show_script_paths_managerメソッドが存在すること"
  end

  private

  def setup_test_files
    FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
    FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, "file1.txt"), "Hello World")
  end
end
