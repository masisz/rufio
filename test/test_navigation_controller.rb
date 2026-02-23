# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# NavigationController のユニットテスト
# Phase 3: KeybindHandler から NavigationController を抽出するリファクタリングに対応
class TestNavigationController < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_nav_test")
    setup_test_files

    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @filter_manager = Rufio::FilterManager.new
    @nav = Rufio::NavigationController.new(@directory_listing, @filter_manager)
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === 基本テスト ===

  def test_can_instantiate
    assert_instance_of Rufio::NavigationController, @nav
  end

  def test_initial_index_is_zero
    assert_equal 0, @nav.current_index
  end

  def test_initial_preview_not_focused
    refute @nav.preview_focused?
  end

  def test_initial_preview_scroll_offset_is_zero
    assert_equal 0, @nav.preview_scroll_offset
  end

  # === 移動テスト ===

  def test_move_down_increments_index
    entries = @directory_listing.list_entries
    @nav.move_down(entries)
    assert_equal 1, @nav.current_index
  end

  def test_move_down_does_not_exceed_last_entry
    entries = @directory_listing.list_entries
    entries.length.times { @nav.move_down(entries) }
    assert_equal entries.length - 1, @nav.current_index
  end

  def test_move_up_decrements_index
    entries = @directory_listing.list_entries
    @nav.move_down(entries)
    @nav.move_up
    assert_equal 0, @nav.current_index
  end

  def test_move_up_does_not_go_below_zero
    @nav.move_up
    assert_equal 0, @nav.current_index
  end

  def test_move_to_top_sets_index_to_zero
    entries = @directory_listing.list_entries
    3.times { @nav.move_down(entries) }
    @nav.move_to_top
    assert_equal 0, @nav.current_index
  end

  def test_move_to_bottom_sets_index_to_last
    entries = @directory_listing.list_entries
    @nav.move_to_bottom(entries)
    assert_equal entries.length - 1, @nav.current_index
  end

  def test_move_down_resets_preview_scroll
    @nav.instance_variable_set(:@preview_scroll_offset, 5)
    entries = @directory_listing.list_entries
    @nav.move_down(entries)
    assert_equal 0, @nav.preview_scroll_offset
  end

  # === ナビゲーションテスト ===

  def test_navigate_enter_directory
    entries = @directory_listing.list_entries
    dir_entry = entries.find { |e| e[:type] == "directory" && e[:name] != ".." }
    skip "ディレクトリエントリなし" unless dir_entry

    result = @nav.navigate_enter(dir_entry, false, false)
    assert result, "ディレクトリへの移動が成功すること"
    assert_equal 0, @nav.current_index, "移動後はインデックスが0にリセットされること"
  end

  def test_navigate_enter_file_returns_false
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry

    result = @nav.navigate_enter(file_entry, false, false)
    refute result, "ファイルへのナビゲーションはfalseを返すこと"
  end

  def test_navigate_enter_blocked_in_help_mode
    entries = @directory_listing.list_entries
    dir_entry = entries.find { |e| e[:type] == "directory" && e[:name] != ".." }
    skip "ディレクトリエントリなし" unless dir_entry

    result = @nav.navigate_enter(dir_entry, true, false)
    refute result, "ヘルプモード中はナビゲーションがブロックされること"
  end

  def test_navigate_parent_moves_up
    # サブディレクトリに移動してから親に戻る
    entries = @directory_listing.list_entries
    dir_entry = entries.find { |e| e[:type] == "directory" && e[:name] != ".." }
    skip "ディレクトリエントリなし" unless dir_entry

    @nav.navigate_enter(dir_entry, false, false)
    result = @nav.navigate_parent
    assert result, "親ディレクトリへの移動が成功すること"
    assert_equal 0, @nav.current_index
  end

  # === フィルタテスト ===

  def test_start_filter_mode
    @nav.start_filter_mode
    assert @filter_manager.filter_active?, "フィルタモードが有効になること"
    assert_equal 0, @nav.current_index
  end

  def test_clear_filter_mode
    @nav.start_filter_mode
    @nav.clear_filter_mode
    refute @filter_manager.filter_active?, "フィルタがクリアされること"
    assert_equal 0, @nav.current_index
  end

  def test_exit_filter_mode_is_alias_for_clear
    @nav.start_filter_mode
    @nav.exit_filter_mode
    refute @filter_manager.filter_active?
  end

  # === プレビューフォーカステスト ===

  def test_focus_preview_pane_with_file
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry

    result = @nav.focus_preview_pane(file_entry)
    assert result, "ファイルでフォーカスできること"
    assert @nav.preview_focused?
    assert_equal 0, @nav.preview_scroll_offset
  end

  def test_focus_preview_pane_with_directory_fails
    entries = @directory_listing.list_entries
    dir_entry = entries.find { |e| e[:type] == "directory" }
    skip "ディレクトリエントリなし" unless dir_entry

    result = @nav.focus_preview_pane(dir_entry)
    refute result, "ディレクトリではフォーカスできないこと"
  end

  def test_unfocus_preview_pane
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry

    @nav.focus_preview_pane(file_entry)
    @nav.unfocus_preview_pane
    refute @nav.preview_focused?
  end

  # === スクロールテスト ===

  def test_scroll_preview_down
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)

    @nav.scroll_preview_down
    assert_equal 1, @nav.preview_scroll_offset
  end

  def test_scroll_preview_up_does_not_go_negative
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)

    @nav.scroll_preview_up
    assert_equal 0, @nav.preview_scroll_offset
  end

  def test_scroll_preview_page_down
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)

    @nav.scroll_preview_page_down
    assert_equal 20, @nav.preview_scroll_offset
  end

  def test_reset_preview_scroll
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)
    @nav.scroll_preview_down
    @nav.scroll_preview_down

    @nav.reset_preview_scroll
    assert_equal 0, @nav.preview_scroll_offset
  end

  # === handle_preview_focus_key テスト ===

  def test_handle_preview_focus_key_j_scrolls_down
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)

    @nav.handle_preview_focus_key("j")
    assert_equal 1, @nav.preview_scroll_offset
  end

  def test_handle_preview_focus_key_escape_unfocuses
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry
    @nav.focus_preview_pane(file_entry)

    @nav.handle_preview_focus_key("\e")
    refute @nav.preview_focused?
  end

  # === set_directory_listing テスト ===

  def test_set_directory_listing_resets_index
    entries = @directory_listing.list_entries
    3.times { @nav.move_down(entries) }

    new_listing = Rufio::DirectoryListing.new(@test_dir)
    @nav.set_directory_listing(new_listing)
    assert_equal 0, @nav.current_index
  end

  # === select_index テスト ===

  def test_select_index
    @nav.select_index(2)
    assert_equal 2, @nav.current_index
  end

  private

  def setup_test_files
    FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
    FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, "file1.txt"), "Hello World")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'")
  end
end
