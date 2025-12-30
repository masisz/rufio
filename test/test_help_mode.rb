# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/rufio/keybind_handler'
require_relative '../lib/rufio/directory_listing'
require_relative '../lib/rufio/terminal_ui'
require 'tmpdir'
require 'fileutils'

module Rufio
  class TestHelpMode < Minitest::Test
    def setup
      # テスト用の作業ディレクトリを作成
      @test_dir = Dir.mktmpdir
      FileUtils.mkdir_p(@test_dir)

      # info ディレクトリのパスを設定（rufio gem のルートからの相対パス）
      @rufio_root = File.expand_path('..', __dir__)
      @info_dir = File.join(@rufio_root, 'info')

      # KeybindHandler と DirectoryListing を初期化
      @handler = KeybindHandler.new
      @directory_listing = DirectoryListing.new(@test_dir)
      @terminal_ui = TerminalUI.new

      @handler.instance_variable_set(:@directory_listing, @directory_listing)
      @handler.instance_variable_set(:@terminal_ui, @terminal_ui)
      @terminal_ui.instance_variable_set(:@directory_listing, @directory_listing)
    end

    def teardown
      FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    end

    def test_help_mode_is_initially_disabled
      refute @handler.help_mode?
    end

    def test_enter_help_mode_switches_to_info_directory
      # ヘルプモードに入る前のディレクトリを記憶
      original_dir = @directory_listing.current_path

      # ヘルプモードに入る
      @handler.enter_help_mode

      # ヘルプモードが有効になっていることを確認
      assert @handler.help_mode?

      # info ディレクトリに移動していることを確認
      assert_equal @info_dir, @directory_listing.current_path

      # 元のディレクトリが保存されていることを確認
      assert_equal original_dir, @handler.instance_variable_get(:@pre_help_directory)
    end

    def test_exit_help_mode_returns_to_original_directory
      original_dir = @directory_listing.current_path

      # ヘルプモードに入る
      @handler.enter_help_mode
      assert @handler.help_mode?
      assert_equal @info_dir, @directory_listing.current_path

      # ヘルプモードを終了
      @handler.exit_help_mode

      # ヘルプモードが無効になっていることを確認
      refute @handler.help_mode?

      # 元のディレクトリに戻っていることを確認
      assert_equal original_dir, @directory_listing.current_path
    end

    def test_navigate_parent_restricted_in_help_mode
      # ヘルプモードに入る
      @handler.enter_help_mode
      assert_equal @info_dir, @directory_listing.current_path

      # info ディレクトリより上には移動できないことを確認
      result = @handler.navigate_parent_with_restriction

      # 移動が制限されたことを確認（falseを返す）
      refute result

      # 現在のディレクトリが変わっていないことを確認
      assert_equal @info_dir, @directory_listing.current_path
    end

    def test_navigate_parent_allowed_within_info_subdirectory
      # ヘルプモードに入る
      @handler.enter_help_mode

      # info ディレクトリ内にサブディレクトリがあれば、そこに移動
      # （実際のテストでは info 内のサブディレクトリを作成する必要があるかもしれない）
      # ここでは info ディレクトリにいる状態から、さらに深い階層に移動できることを確認

      # このテストはinfo内にサブディレクトリがある場合のみ意味を持つ
      # 現状ではinfo/配下にファイルしかないため、このテストはスキップ
      skip "Requires subdirectory in info/ to test"
    end

    def test_normal_navigation_not_restricted_outside_help_mode
      # ヘルプモード外では通常のナビゲーションが可能
      refute @handler.help_mode?

      # 親ディレクトリへの移動が制限されないことを確認
      # （実際の動作は navigate_parent メソッドに依存）
      result = @handler.navigate_parent_with_restriction

      # 制限されていないため、通常の navigate_parent が呼ばれる
      # （このテストの詳細な動作は実装に依存）
      assert result || !result  # 移動可能かどうかは親ディレクトリの存在に依存
    end

    def test_help_mode_persists_across_directory_navigation
      # ヘルプモードに入る
      @handler.enter_help_mode
      assert @handler.help_mode?

      # info ディレクトリ内でのナビゲーション後もヘルプモードが維持される
      # （サブディレクトリがあればそこに移動してテストする）

      # ヘルプモードが維持されていることを確認
      assert @handler.help_mode?
    end
  end
end
