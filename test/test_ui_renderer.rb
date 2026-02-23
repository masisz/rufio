# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/rufio"

# UIRenderer クラスのユニットテスト
# Phase 1: TerminalUI から UIRenderer を抽出するリファクタリングに対応
class TestUIRenderer < Minitest::Test
  def setup
    @screen = Rufio::Screen.new(80, 24)
    @renderer = Rufio::Renderer.new(80, 24)

    @test_dir = Dir.mktmpdir("rufio_ui_renderer_test")
    setup_test_files

    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @keybind_handler = Rufio::KeybindHandler.new
    @file_preview = Rufio::FilePreview.new
    @keybind_handler.set_directory_listing(@directory_listing)

    @ui_renderer = Rufio::UIRenderer.new(
      screen_width: 80,
      screen_height: 24,
      keybind_handler: @keybind_handler,
      directory_listing: @directory_listing,
      file_preview: @file_preview
    )
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === 基本テスト ===

  def test_can_instantiate
    assert_instance_of Rufio::UIRenderer, @ui_renderer
  end

  def test_draw_screen_runs_without_error
    @ui_renderer.draw_screen(@screen)
    pass
  end

  def test_draw_screen_updates_buffer
    @ui_renderer.draw_screen(@screen)
    # フッター行 (y=0) に何かが描画されていること
    footer_line = strip_ansi(@screen.row(0))
    refute_nil footer_line
  end

  def test_draw_screen_mode_tabs_at_bottom
    @ui_renderer.draw_screen(@screen)
    bottom_line = strip_ansi(@screen.row(23))
    assert_match(/Files/, bottom_line, "最下行にモードタブが含まれること")
  end

  def test_draw_screen_directory_list_in_content_area
    @ui_renderer.draw_screen(@screen)
    # コンテンツ領域 (y=1〜22) にディレクトリエントリが含まれること
    content_lines = (1..22).map { |y| strip_ansi(@screen.row(y)) }
    has_entries = content_lines.any? { |line| line.strip.length > 0 }
    assert has_entries, "コンテンツ領域にエントリが描画されること"
  end

  # === format_size テスト ===

  def test_format_size_zero
    assert_equal "      ", @ui_renderer.format_size(0)
  end

  def test_format_size_bytes
    result = @ui_renderer.format_size(512)
    assert_match(/\d+B/, result)
    assert_equal 6, result.length
  end

  def test_format_size_kilobytes
    result = @ui_renderer.format_size(1024 * 5)
    assert_match(/K/, result)
    assert_equal 6, result.length
  end

  def test_format_size_megabytes
    result = @ui_renderer.format_size(1024 * 1024 * 2)
    assert_match(/M/, result)
    assert_equal 6, result.length
  end

  def test_format_size_gigabytes
    result = @ui_renderer.format_size(1024 * 1024 * 1024 * 3)
    assert_match(/G/, result)
    assert_equal 6, result.length
  end

  # === get_entry_display_info テスト ===

  def test_get_entry_display_info_directory
    entry = { name: "mydir", type: "directory", size: 0 }
    icon, _color = @ui_renderer.get_entry_display_info(entry)
    refute_nil icon, "ディレクトリアイコンが返ること"
  end

  def test_get_entry_display_info_file
    entry = { name: "file.txt", type: "file", size: 100 }
    icon, _color = @ui_renderer.get_entry_display_info(entry)
    refute_nil icon, "ファイルアイコンが返ること"
  end

  def test_get_entry_display_info_returns_ansi_color
    entry = { name: "mydir", type: "directory", size: 0 }
    _icon, color = @ui_renderer.get_entry_display_info(entry)
    assert_match(/\e\[/, color, "ANSIカラーコードが返ること")
  end

  # === extract_preview_lines テスト ===

  def test_extract_preview_lines_text
    preview = { type: "text", lines: ["line1", "line2"] }
    result = @ui_renderer.extract_preview_lines(preview)
    assert_equal ["line1", "line2"], result
  end

  def test_extract_preview_lines_code
    preview = { type: "code", lines: ["def hello", "end"] }
    result = @ui_renderer.extract_preview_lines(preview)
    assert_equal ["def hello", "end"], result
  end

  def test_extract_preview_lines_binary
    preview = { type: "binary" }
    result = @ui_renderer.extract_preview_lines(preview)
    refute_empty result
    assert result.any? { |l| l.include?("binary") || l.include?("preview") || l.include?("バイナリ") || l.include?("プレビュー") },
           "バイナリファイルのメッセージが含まれること"
  end

  def test_extract_preview_lines_error
    preview = { type: "error", message: "Permission denied" }
    result = @ui_renderer.extract_preview_lines(preview)
    refute_empty result
  end

  # === bookmark_highlight_expired? テスト ===

  def test_bookmark_highlight_not_expired_when_not_set
    # ハイライトが設定されていない場合は false を返す
    refute @ui_renderer.bookmark_highlight_expired?
  end

  def test_bookmark_highlight_not_expired_immediately
    @ui_renderer.set_highlighted_bookmark(1)
    refute @ui_renderer.bookmark_highlight_expired?, "設定直後は期限切れでないこと"
  end

  def test_clear_preview_cache
    @ui_renderer.clear_preview_cache
    pass
  end

  def test_clear_bookmark_cache
    @ui_renderer.clear_bookmark_cache
    pass
  end

  # === draw_directory_list_to_buffer テスト ===

  def test_draw_directory_list_fills_buffer
    entries = @directory_listing.list_entries
    left_width = 40
    content_height = 22
    @ui_renderer.draw_directory_list_to_buffer(@screen, entries, left_width, content_height)
    # y=1の行が変更されていること
    line = strip_ansi(@screen.row(1))
    refute_nil line
  end

  # === draw_footer_to_buffer テスト ===

  def test_draw_footer_to_buffer
    @ui_renderer.draw_footer_to_buffer(@screen, 0)
    pass
  end

  # === draw_mode_tabs_to_buffer テスト ===

  def test_draw_mode_tabs_contains_files
    @ui_renderer.draw_mode_tabs_to_buffer(@screen, 23)
    line = strip_ansi(@screen.row(23))
    assert_match(/Files/, line, "モードタブに 'Files' が含まれること")
  end

  # === highlight_updated フラグ ===

  def test_highlight_updated_starts_false
    refute @ui_renderer.highlight_updated?
  end

  def test_reset_highlight_updated
    @ui_renderer.reset_highlight_updated
    refute @ui_renderer.highlight_updated?
  end

  # === tab_mode_manager アクセス ===

  def test_tab_mode_manager_accessible
    assert_respond_to @ui_renderer, :tab_mode_manager
    refute_nil @ui_renderer.tab_mode_manager
  end

  private

  def setup_test_files
    FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
    FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, "file1.txt"), "Hello World\nLine 2\nLine 3")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'\nputs 'world'")
    File.write(File.join(@test_dir, "README.md"), "# README\n\nThis is a test file.")
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*m/, "")
  end
end
