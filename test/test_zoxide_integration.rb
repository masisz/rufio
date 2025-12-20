# frozen_string_literal: true

require_relative 'test_helper'

module Rufio
  class TestZoxideIntegration < Minitest::Test
    def setup
      @dialog_renderer = DialogRenderer.new
      @zoxide_integration = ZoxideIntegration.new(@dialog_renderer)
      @temp_dir = Dir.mktmpdir
      @keybind_handler = KeybindHandler.new
      @directory_listing = DirectoryListing.new(@temp_dir)
      @keybind_handler.set_directory_listing(@directory_listing)
      @mock_terminal_ui = Object.new
      def @mock_terminal_ui.refresh_display; end
      @keybind_handler.set_terminal_ui(@mock_terminal_ui)
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if Dir.exist?(@temp_dir)
    end

    def test_zoxide_available_check
      # zoxideが利用可能かどうかをテスト
      result = @zoxide_integration.available?
      assert_includes [true, false], result
    end

    def test_get_zoxide_history_when_zoxide_available
      # zoxideが利用可能な場合の履歴取得をテスト
      skip "zoxide not available" unless @zoxide_integration.available?

      history = @zoxide_integration.get_history
      assert_respond_to history, :each
      assert history.all? { |entry| entry.is_a?(Hash) && entry.key?(:path) && entry.key?(:score) }

      # 各エントリが正しいスコアを持っていることを確認
      history.each do |entry|
        assert entry[:score].is_a?(Float), "Score should be a Float, got #{entry[:score].class}"
        assert entry[:score] >= 0, "Score should be non-negative"
        assert !entry[:path].empty?, "Path should not be empty"
        assert Dir.exist?(entry[:path]), "Path should exist: #{entry[:path]}"
      end
    end

    def test_get_zoxide_history_when_zoxide_not_available
      # zoxideが利用できない場合は空の配列を返すことをテスト
      @zoxide_integration.define_singleton_method(:available?) { false }

      history = @zoxide_integration.get_history
      assert_equal [], history
    end

    def test_show_zoxide_menu_with_empty_history
      # 履歴が空の場合のメニュー表示をテスト
      @zoxide_integration.define_singleton_method(:get_history) { [] }

      # STDINをモック化してgetchをシミュレート
      result = nil
      STDIN.stub :getch, "\e" do
        result = @zoxide_integration.show_menu
      end

      # 何も選択されない場合はnilを返す
      assert_nil result
    end

    def test_navigate_to_zoxide_directory_valid_path
      # 有効なパスへの移動をテスト（KeybindHandlerを通じて）
      valid_path = @temp_dir

      # show_zoxide_menuをモックして、パスを返すようにする
      @keybind_handler.instance_variable_get(:@zoxide_integration).define_singleton_method(:show_menu) { valid_path }

      result = @keybind_handler.send(:show_zoxide_menu)
      assert_equal true, result
      assert_equal valid_path, @directory_listing.current_path
    end

    def test_navigate_to_zoxide_directory_invalid_path
      # 無効なパスへの移動をテスト
      invalid_path = "/nonexistent/path"

      # show_zoxide_menuをモックして、無効なパスを返すようにする
      @keybind_handler.instance_variable_get(:@zoxide_integration).define_singleton_method(:show_menu) { invalid_path }

      result = @keybind_handler.send(:show_zoxide_menu)
      assert_equal false, result
    end

    def test_z_key_binding_calls_zoxide_menu
      # zキーがzoxideメニューを呼び出すことをテスト
      @keybind_handler.define_singleton_method(:show_zoxide_menu) { true }

      result = @keybind_handler.handle_key('z')
      assert_equal true, result
    end
  end
end