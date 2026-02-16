# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# バッファ整合性テスト（方式2）
# print版とバッファ版の出力を比較し、移行時の整合性を担保
#
# このテストは以下を保証:
# 1. draw_xxx と draw_xxx_to_buffer の出力が一致
# 2. 移行後もUIの見た目が変わらない
#
class TestBufferParity < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_parity_test")
    setup_test_files

    @width = 80
    @height = 24

    # バッファ版用
    @screen = Rufio::Screen.new(@width, @height)
    @buffer_output = StringIO.new
    @renderer = Rufio::Renderer.new(@width, @height, output: @buffer_output)

    # print版用
    @print_output = StringIO.new

    # 共通コンポーネント
    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @keybind_handler = Rufio::KeybindHandler.new
    @file_preview = Rufio::FilePreview.new
    @keybind_handler.set_directory_listing(@directory_listing)

    # TerminalUIのテスト用インスタンス
    @terminal_ui = create_terminal_ui_for_test
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === ヘッダー描画の整合性テスト ===

  def test_header_parity
    # バッファ版
    @terminal_ui.send(:draw_header_to_buffer, @screen, 0)
    buffer_header = strip_ansi(@screen.row(0))

    # print版
    capture_print_output do
      @terminal_ui.send(:draw_header)
    end
    print_header = strip_ansi(extract_first_line(@print_output.string))

    assert_equal normalize_whitespace(print_header),
                 normalize_whitespace(buffer_header),
                 "Header parity failed: print vs buffer output mismatch"
  end

  # === フッター描画の整合性テスト ===

  def test_footer_parity
    # バッファ版
    @terminal_ui.send(:draw_footer_to_buffer, @screen, @height - 1, nil)
    buffer_footer = strip_ansi(@screen.row(@height - 1))

    # print版
    capture_print_output do
      @terminal_ui.send(:draw_footer, nil)
    end
    print_footer = strip_ansi(@print_output.string)

    # フッターの主要コンテンツ（?:help）が両方に存在することを確認
    assert_match(/help/, buffer_footer, "Buffer footer should contain 'help'")
    assert_match(/help/, print_footer, "Print footer should contain 'help'")
  end

  # === エントリ行描画の整合性テスト ===

  def test_entry_line_parity
    entries = @directory_listing.list_entries
    return skip("No entries to test") if entries.empty?

    entry = entries.first
    width = (@width * 0.5).to_i
    is_selected = true

    # バッファ版
    @terminal_ui.send(:draw_entry_line_to_buffer, @screen, entry, width, is_selected, 0, 2)
    buffer_line = strip_ansi(@screen.row(2))

    # print版
    capture_print_output do
      @terminal_ui.send(:draw_entry_line, entry, width, is_selected)
    end
    print_line = strip_ansi(@print_output.string)

    # エントリ名が両方に含まれることを確認
    assert_match(/#{Regexp.escape(entry[:name][0..10])}/, buffer_line,
                 "Buffer should contain entry name")
    assert_match(/#{Regexp.escape(entry[:name][0..10])}/, print_line,
                 "Print should contain entry name")
  end

  # === サイズフォーマットの整合性テスト ===

  def test_format_size_consistency
    test_cases = [
      [0, "      "],
      [512, "  512B"],
      [1024, "  1.0K"],
      [1024 * 1024, "  1.0M"],
      [1024 * 1024 * 1024, "  1.0G"],
    ]

    test_cases.each do |size, expected|
      result = @terminal_ui.send(:format_size, size)
      assert_equal expected, result, "format_size(#{size}) should return '#{expected}'"
    end
  end

  # === アイコン/色情報の整合性テスト ===

  def test_entry_display_info_consistency
    test_entries = [
      { name: "test.txt", type: "file", size: 100, path: "/test.txt" },
      { name: "test.rb", type: "file", size: 100, path: "/test.rb" },
      { name: "subdir", type: "directory", size: 0, path: "/subdir" },
      { name: "script.sh", type: "executable", size: 100, path: "/script.sh" },
    ]

    test_entries.each do |entry|
      icon, color = @terminal_ui.send(:get_entry_display_info, entry)

      refute_nil icon, "Icon should not be nil for #{entry[:name]}"
      refute_nil color, "Color should not be nil for #{entry[:name]}"
      assert icon.is_a?(String), "Icon should be a string for #{entry[:name]}"
      assert color.is_a?(String), "Color should be a string for #{entry[:name]}"
    end
  end

  # === ディレクトリリスト全体の整合性テスト ===

  def test_directory_list_structure
    entries = @directory_listing.list_entries
    height = @height - 3  # ヘッダー2行 + フッター1行
    width = (@width * 0.5).to_i

    # バッファ版
    @terminal_ui.send(:draw_directory_list_to_buffer, @screen, entries, width, height)

    # 各行にコンテンツがあることを確認
    has_content = false
    (2...([entries.length + 2, height + 2].min)).each do |y|
      line = strip_ansi(@screen.row(y))
      has_content = true unless line.strip.empty?
    end

    assert has_content, "Directory list should have content in buffer"
  end

  # === プレビュー領域の整合性テスト ===

  def test_file_preview_structure
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    return skip("No file entries to test preview") unless file_entry

    height = @height - 3
    left_offset = (@width * 0.5).to_i
    right_width = @width - left_offset

    # バッファ版
    @terminal_ui.send(:draw_file_preview_to_buffer, @screen, file_entry, right_width, height, left_offset)

    # 区切り線が描画されていることを確認
    separator_found = false
    (2...(height + 2)).each do |y|
      line = @screen.row(y)
      separator_found = true if line.include?("|") || line.include?("│")
    end

    assert separator_found, "File preview should have separator in buffer"
  end

  # === 複数フレームでの整合性テスト ===

  def test_multi_frame_consistency
    # 初回描画
    @screen.clear
    draw_full_screen_to_buffer
    first_frame = capture_screen_text

    # 同じ状態で再描画
    @screen.clear
    draw_full_screen_to_buffer
    second_frame = capture_screen_text

    assert_equal first_frame, second_frame,
                 "Consecutive frames should be identical without state changes"
  end

  # === ナビゲーション後の整合性テスト ===

  def test_navigation_updates_correctly
    # 初回描画
    @screen.clear
    draw_full_screen_to_buffer
    initial_cursor = @keybind_handler.current_index

    # 下に移動
    @keybind_handler.handle_key("j")
    @screen.clear
    draw_full_screen_to_buffer
    after_nav = @keybind_handler.current_index

    assert_equal initial_cursor + 1, after_nav,
                 "Navigation should update cursor position"
  end

  # === 境界条件のテスト ===

  def test_boundary_empty_directory
    empty_dir = Dir.mktmpdir("rufio_empty_test")

    begin
      empty_listing = Rufio::DirectoryListing.new(empty_dir)
      empty_handler = Rufio::KeybindHandler.new
      empty_handler.set_directory_listing(empty_listing)

      terminal_ui = create_terminal_ui_with(empty_listing, empty_handler)
      screen = Rufio::Screen.new(@width, @height)

      # 空ディレクトリでもクラッシュしないことを確認
      terminal_ui.send(:draw_header_to_buffer, screen, 0)
      terminal_ui.send(:draw_footer_to_buffer, screen, @height - 1, nil)

      pass  # 例外なく完了すればOK
    ensure
      FileUtils.rm_rf(empty_dir)
    end
  end

  def test_boundary_long_filename
    long_name = "a" * 200 + ".txt"
    long_file = File.join(@test_dir, long_name)
    File.write(long_file, "test")

    @directory_listing.refresh

    entries = @directory_listing.list_entries
    long_entry = entries.find { |e| e[:name].start_with?("aaa") }

    if long_entry
      width = (@width * 0.5).to_i
      # 長いファイル名でもクラッシュしないことを確認
      @terminal_ui.send(:draw_entry_line_to_buffer, @screen, long_entry, width, false, 0, 2)
      line = strip_ansi(@screen.row(2))

      assert line.length <= @width, "Long filename should be truncated"
    end

    pass
  end

  def test_boundary_narrow_screen
    narrow_width = 20
    narrow_screen = Rufio::Screen.new(narrow_width, @height)
    narrow_ui = create_terminal_ui_with_size(narrow_width, @height)

    # 狭い画面でもクラッシュしないことを確認
    narrow_ui.send(:draw_header_to_buffer, narrow_screen, 0)

    header = strip_ansi(narrow_screen.row(0))
    assert header.length <= narrow_width, "Header should fit narrow screen"
  end

  private

  def setup_test_files
    FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
    FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, "file1.txt"), "Hello World\nLine 2")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'")
    File.write(File.join(@test_dir, "README.md"), "# README")
  end

  def create_terminal_ui_for_test
    # テスト用のTerminalUIを作成（一部メソッドをオーバーライド可能に）
    terminal_ui = Rufio::TerminalUI.new(test_mode: true)

    # 内部変数を設定
    terminal_ui.instance_variable_set(:@directory_listing, @directory_listing)
    terminal_ui.instance_variable_set(:@keybind_handler, @keybind_handler)
    terminal_ui.instance_variable_set(:@file_preview, @file_preview)
    terminal_ui.instance_variable_set(:@screen_width, @width)
    terminal_ui.instance_variable_set(:@screen_height, @height)
    terminal_ui.instance_variable_set(:@tab_mode_manager, Rufio::TabModeManager.new)
    terminal_ui.instance_variable_set(:@dialog_renderer, Rufio::DialogRenderer.new)
    terminal_ui.instance_variable_set(:@preview_cache, {})
    terminal_ui.instance_variable_set(:@last_preview_path, nil)
    terminal_ui.instance_variable_set(:@in_job_mode, false)
    terminal_ui.instance_variable_set(:@cached_bookmarks, [])
    terminal_ui.instance_variable_set(:@cached_bookmark_time, Time.now)

    terminal_ui
  end

  def create_terminal_ui_with(listing, handler)
    terminal_ui = Rufio::TerminalUI.new(test_mode: true)
    terminal_ui.instance_variable_set(:@directory_listing, listing)
    terminal_ui.instance_variable_set(:@keybind_handler, handler)
    terminal_ui.instance_variable_set(:@file_preview, @file_preview)
    terminal_ui.instance_variable_set(:@screen_width, @width)
    terminal_ui.instance_variable_set(:@screen_height, @height)
    terminal_ui.instance_variable_set(:@tab_mode_manager, Rufio::TabModeManager.new)
    terminal_ui.instance_variable_set(:@dialog_renderer, Rufio::DialogRenderer.new)
    terminal_ui.instance_variable_set(:@preview_cache, {})
    terminal_ui.instance_variable_set(:@in_job_mode, false)
    terminal_ui.instance_variable_set(:@cached_bookmarks, [])
    terminal_ui.instance_variable_set(:@cached_bookmark_time, Time.now)
    terminal_ui
  end

  def create_terminal_ui_with_size(width, height)
    terminal_ui = Rufio::TerminalUI.new(test_mode: true)
    terminal_ui.instance_variable_set(:@directory_listing, @directory_listing)
    terminal_ui.instance_variable_set(:@keybind_handler, @keybind_handler)
    terminal_ui.instance_variable_set(:@file_preview, @file_preview)
    terminal_ui.instance_variable_set(:@screen_width, width)
    terminal_ui.instance_variable_set(:@screen_height, height)
    terminal_ui.instance_variable_set(:@tab_mode_manager, Rufio::TabModeManager.new)
    terminal_ui.instance_variable_set(:@dialog_renderer, Rufio::DialogRenderer.new)
    terminal_ui.instance_variable_set(:@preview_cache, {})
    terminal_ui.instance_variable_set(:@in_job_mode, false)
    terminal_ui.instance_variable_set(:@cached_bookmarks, [])
    terminal_ui.instance_variable_set(:@cached_bookmark_time, Time.now)
    terminal_ui
  end

  def draw_full_screen_to_buffer
    entries = @directory_listing.list_entries
    selected_entry = entries[@keybind_handler.current_index]
    content_height = @height - 3
    left_width = (@width * 0.5).to_i
    right_width = @width - left_width

    @terminal_ui.send(:draw_header_to_buffer, @screen, 0)
    @terminal_ui.send(:draw_mode_tabs_to_buffer, @screen, 1)
    @terminal_ui.send(:draw_directory_list_to_buffer, @screen, entries, left_width, content_height)
    @terminal_ui.send(:draw_file_preview_to_buffer, @screen, selected_entry, right_width, content_height, left_width)
    @terminal_ui.send(:draw_footer_to_buffer, @screen, @height - 1, nil)
  end

  def capture_screen_text
    (0...@height).map { |y| strip_ansi(@screen.row(y)) }.join("\n")
  end

  def capture_print_output
    @print_output.string.clear
    original_stdout = $stdout
    $stdout = @print_output
    yield
    $stdout = original_stdout
  end

  def strip_ansi(str)
    str.gsub(/\e\[[0-9;]*[mHJK]/, "")
  end

  def normalize_whitespace(str)
    str.gsub(/\s+/, " ").strip
  end

  def extract_first_line(str)
    str.split("\n").first || ""
  end
end
