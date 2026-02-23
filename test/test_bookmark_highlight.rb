# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

module Rufio
  # ブックマークハイライト描画テスト
  # Tab でジャンプした際に上部バーの対象ブックマークが 500ms ハイライトされることを検証
  class TestBookmarkHighlight < Minitest::Test
    SCREEN_WIDTH = 80

    def setup
      @temp_dir = Dir.mktmpdir
      @bookmark_config = File.join(@temp_dir, 'bookmarks.json')

      @dir_a = File.join(@temp_dir, 'dir_a')
      @dir_b = File.join(@temp_dir, 'dir_b')
      FileUtils.mkdir_p(@dir_a)
      FileUtils.mkdir_p(@dir_b)

      @bookmark = Bookmark.new(@bookmark_config)
      @bookmark.add(@dir_a, 'dir_a')
      @bookmark.add(@dir_b, 'dir_b')

      # TerminalUI を最小限の状態でセットアップ
      @ui = TerminalUI.new
      @ui.instance_variable_set(:@screen_width, SCREEN_WIDTH)
      @ui.instance_variable_set(:@test_mode, false)
      @ui.instance_variable_set(:@background_executor, nil)
      @ui.instance_variable_set(:@completion_lamp_message, nil)
      @ui.instance_variable_set(:@completion_lamp_time, nil)

      # ブックマークキャッシュを直接注入（ファイルI/Oを回避）
      bookmarks = @bookmark.list
      @ui.instance_variable_set(:@cached_bookmarks, bookmarks)
      @ui.instance_variable_set(:@cached_bookmark_time, Time.now)

      # keybind_handler スタブ
      keybind_handler = Object.new
      def keybind_handler.filter_active? = false
      def keybind_handler.has_jobs? = false
      @ui.instance_variable_set(:@keybind_handler, keybind_handler)

      # directory_listing スタブ（start_directory = temp_dir）
      temp_dir = @temp_dir
      dir_listing = Object.new
      dir_listing.define_singleton_method(:start_directory) { temp_dir }
      @ui.instance_variable_set(:@directory_listing, dir_listing)

      @screen = Screen.new(SCREEN_WIDTH, 1)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir
    end

    # ハイライトなし → 全て gray (e[90m)
    def test_no_highlight_renders_all_gray
      @ui.instance_variable_set(:@highlighted_bookmark_index, nil)
      @ui.instance_variable_set(:@highlighted_bookmark_time, nil)

      @ui.send(:draw_footer_to_buffer, @screen, 0)

      # "1.dir_a" の先頭文字はグレー
      x = bookmark_x_pos(0)  # "0.tmpdir" の後
      assert_equal "\e[90m", @screen.get_cell(x, 0)[:fg]
    end

    # ハイライト中（500ms 以内）→ ハイライト対象はシアン色
    def test_highlight_within_duration_renders_cyan
      # display_index=1 は "1.dir_a"
      @ui.instance_variable_set(:@highlighted_bookmark_index, 1)
      @ui.instance_variable_set(:@highlighted_bookmark_time, Time.now)

      @ui.send(:draw_footer_to_buffer, @screen, 0)

      x = bookmark_x_pos(1)
      cell = @screen.get_cell(x, 0)
      # ハイライト中はシアン色（下バーと同色）
      assert_equal "\e[1;36m", cell[:fg], "ハイライト中のブックマークはシアン色であるべき"
    end

    # ハイライト期限切れ（500ms 超過）→ gray に戻る
    def test_highlight_expired_renders_gray
      @ui.instance_variable_set(:@highlighted_bookmark_index, 1)
      @ui.instance_variable_set(:@highlighted_bookmark_time, Time.now - 1.0)  # 1秒前

      @ui.send(:draw_footer_to_buffer, @screen, 0)

      x = bookmark_x_pos(1)
      cell = @screen.get_cell(x, 0)
      assert_equal "\e[90m", cell[:fg], "期限切れのハイライトは gray に戻るべき"
    end

    # display_index=0 は "0.start_dir" → ハイライト可能
    def test_highlight_index_zero_renders_start_dir_cyan
      @ui.instance_variable_set(:@highlighted_bookmark_index, 0)
      @ui.instance_variable_set(:@highlighted_bookmark_time, Time.now)

      @ui.send(:draw_footer_to_buffer, @screen, 0)

      cell = @screen.get_cell(0, 0)  # "0.xxx" は x=0 から始まる
      assert_equal "\e[1;36m", cell[:fg], "index=0 のハイライトはシアン色であるべき"
    end

    # ハイライト期限切れ → check_bookmark_highlight_expired? が true を返す
    def test_check_bookmark_highlight_expired_returns_true_when_expired
      @ui.instance_variable_set(:@highlighted_bookmark_index, 1)
      @ui.instance_variable_set(:@highlighted_bookmark_time, Time.now - 1.0)

      assert @ui.send(:bookmark_highlight_expired?), "期限切れ時は true を返すべき"
    end

    # ハイライト中 → check_bookmark_highlight_expired? が false を返す
    def test_check_bookmark_highlight_expired_returns_false_when_active
      @ui.instance_variable_set(:@highlighted_bookmark_index, 1)
      @ui.instance_variable_set(:@highlighted_bookmark_time, Time.now)

      refute @ui.send(:bookmark_highlight_expired?), "ハイライト中は false を返すべき"
    end

    # ハイライトなし → check_bookmark_highlight_expired? が false を返す
    def test_check_bookmark_highlight_expired_returns_false_when_no_highlight
      @ui.instance_variable_set(:@highlighted_bookmark_index, nil)
      @ui.instance_variable_set(:@highlighted_bookmark_time, nil)

      refute @ui.send(:bookmark_highlight_expired?), "ハイライトなし時は false を返すべき"
    end

    private

    # bookmark_parts の display_index 番目のテキスト開始 x 座標を計算
    def bookmark_x_pos(display_index)
      start_dir_name = File.basename(@temp_dir)
      parts = ["0.#{start_dir_name}", "1.dir_a", "2.dir_b"]
      separator_len = 3  # " │ "
      parts[0...display_index].sum { |p| p.length + separator_len }
    end
  end
end
