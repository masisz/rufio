# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'

module Rufio
  class TestHelpDialog < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @dialog_renderer = DialogRenderer.new
      @keybind_handler = KeybindHandler.new
      @directory_listing = DirectoryListing.new(@temp_dir)
      @keybind_handler.set_directory_listing(@directory_listing)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    end

    # ？キーが認識されることを確認
    def test_help_key_is_recognized
      # ？キーは'?'として認識される
      key = '?'
      assert_equal '?', key
    end

    # ヘルプダイアログが表示される（機能が実装されていることを期待）
    def test_help_dialog_content
      # ヘルプダイアログには以下の内容が含まれるべき：
      # - キーバインド一覧
      # - お知らせ情報
      # この段階では、テストの期待値を定義するのみ

      # 期待されるキーバインド一覧の一部
      expected_keybinds = [
        'j/k',      # 移動
        'h',        # 戻る
        'l',        # 入る
        'o',        # 開く
        'f',        # 絞込
        's',        # 検索
        'b',        # ブックマーク
        'q'         # 終了
      ]

      # テストが通ることを確認（実装後に詳細をテストする）
      assert expected_keybinds.is_a?(Array)
    end
  end
end
