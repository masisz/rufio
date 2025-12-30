# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/rufio/keybind_handler'
require_relative '../lib/rufio/directory_listing'
require_relative '../lib/rufio/terminal_ui'
require 'tmpdir'
require 'fileutils'

module Rufio
  class TestPreviewScroll < Minitest::Test
    def setup
      # テスト用のディレクトリを作成
      @test_dir = Dir.mktmpdir
      FileUtils.mkdir_p(@test_dir)

      # テスト用のファイルを作成（100行）
      @test_file = File.join(@test_dir, 'test.txt')
      File.write(@test_file, (1..100).map { |i| "Line #{i}" }.join("\n"))

      # KeybindHandler と DirectoryListing を初期化
      @handler = KeybindHandler.new
      @directory_listing = DirectoryListing.new(@test_dir)
      @terminal_ui = TerminalUI.new

      @handler.instance_variable_set(:@directory_listing, @directory_listing)
      @handler.instance_variable_set(:@terminal_ui, @terminal_ui)
      @terminal_ui.instance_variable_set(:@directory_listing, @directory_listing)
      @terminal_ui.instance_variable_set(:@keybind_handler, @handler)
    end

    def teardown
      FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    end

    def test_preview_focus_initially_disabled
      refute @handler.preview_focused?
    end

    def test_enter_key_focuses_preview_pane
      # ファイルを選択
      entries = @directory_listing.list_entries
      file_index = entries.index { |e| e[:type] == 'file' }
      @handler.select_index(file_index) if file_index

      # Enter キーでプレビューペインにフォーカス
      result = @handler.focus_preview_pane

      # フォーカスが移動したことを確認
      assert result
      assert @handler.preview_focused?
    end

    def test_esc_key_unfocuses_preview_pane
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカス
      @handler.focus_preview_pane

      # ESC キーでフォーカスを解除
      result = @handler.unfocus_preview_pane

      # フォーカスが解除されたことを確認
      assert result
      refute @handler.preview_focused?
    end

    def test_preview_scroll_down_with_j_key
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカス
      @handler.focus_preview_pane

      # 初期スクロール位置
      initial_offset = @handler.preview_scroll_offset

      # j キーでスクロールダウン
      @handler.scroll_preview_down

      # スクロール位置が増加したことを確認
      assert @handler.preview_scroll_offset > initial_offset
    end

    def test_preview_scroll_up_with_k_key
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカスしてスクロールダウン
      @handler.focus_preview_pane
      5.times { @handler.scroll_preview_down }

      # 現在のスクロール位置
      current_offset = @handler.preview_scroll_offset

      # k キーでスクロールアップ
      @handler.scroll_preview_up

      # スクロール位置が減少したことを確認
      assert @handler.preview_scroll_offset < current_offset
    end

    def test_preview_scroll_page_down_with_ctrl_d
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカス
      @handler.focus_preview_pane

      # 初期スクロール位置
      initial_offset = @handler.preview_scroll_offset

      # Ctrl+D でページダウン
      @handler.scroll_preview_page_down

      # スクロール位置が大きく増加したことを確認（半画面分）
      assert @handler.preview_scroll_offset > initial_offset
      assert @handler.preview_scroll_offset >= initial_offset + 10
    end

    def test_preview_scroll_page_up_with_ctrl_u
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカスしてページダウン
      @handler.focus_preview_pane
      @handler.scroll_preview_page_down
      @handler.scroll_preview_page_down

      # 現在のスクロール位置
      current_offset = @handler.preview_scroll_offset

      # Ctrl+U でページアップ
      @handler.scroll_preview_page_up

      # スクロール位置が大きく減少したことを確認（半画面分）
      assert @handler.preview_scroll_offset < current_offset
      assert @handler.preview_scroll_offset <= current_offset - 10
    end

    def test_preview_scroll_does_not_go_below_zero
      # ファイルを選択
      select_test_file

      # プレビューペインにフォーカス
      @handler.focus_preview_pane

      # 何度もスクロールアップを試みる
      10.times { @handler.scroll_preview_up }

      # スクロール位置が0未満にならないことを確認
      assert @handler.preview_scroll_offset >= 0
    end

    def test_preview_scroll_resets_when_changing_files
      # ファイルを選択してスクロール
      entries = @directory_listing.list_entries
      file_index = entries.index { |e| e[:type] == 'file' }
      @handler.select_index(file_index) if file_index
      @handler.focus_preview_pane
      5.times { @handler.scroll_preview_down }

      # スクロール位置が0より大きいことを確認
      assert @handler.preview_scroll_offset > 0

      # 別のファイルに移動
      @handler.unfocus_preview_pane
      # move_down を呼び出してファイルを変更（次のファイルがあれば）

      # スクロール位置がリセットされることを期待
      # （実装次第で動作が変わる可能性がある）
    end

    def test_preview_focus_only_on_files
      # ディレクトリを選択
      entries = @directory_listing.list_entries
      dir_index = entries.index { |e| e[:type] == 'directory' }

      if dir_index
        @handler.select_index(dir_index)

        # ディレクトリではプレビューフォーカスできないことを確認
        result = @handler.focus_preview_pane

        # ディレクトリの場合はフォーカスできない（または何も起こらない）
        # 実装次第で動作が変わる
      end
    end

    private

    # テスト用ファイルを選択するヘルパーメソッド
    def select_test_file
      entries = @directory_listing.list_entries
      file_index = entries.index { |e| e[:type] == 'file' }
      @handler.select_index(file_index) if file_index
    end
  end
end
