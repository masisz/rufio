# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

# minitestのプラグインを無効化してRailsとの競合を回避
ENV['MT_PLUGINS'] = ""
ENV['NO_PLUGINS'] = "true"

require "minitest/autorun"

module Rufio
  class TestCreateWithEscape < Minitest::Test
    def setup
      @test_dir = Dir.mktmpdir("rufio_create_escape_test")
      @original_dir = Dir.pwd
      Dir.chdir(@test_dir)

      @directory_listing = DirectoryListing.new(@test_dir)
      @file_operations = FileOperations.new
      @dialog_renderer = DialogRenderer.new
      @nav_controller = NavigationController.new(@directory_listing, FilterManager.new)
      @selection_manager = SelectionManager.new
      @file_op_controller = FileOperationController.new(
        @directory_listing, @file_operations, @dialog_renderer, @nav_controller, @selection_manager
      )

      # read_line_with_escape のテスト用に keybind_handler も保持
      @handler = KeybindHandler.new
      @handler.set_directory_listing(@directory_listing)
    end

    def teardown
      Dir.chdir(@original_dir)
      FileUtils.rm_rf(@test_dir)
    end

    def test_read_line_with_escape_returns_nil_on_escape
      # Escapeキーが押されたときにnilを返すことをテスト
      STDIN.stub :getch, "\e" do
        result = @handler.send(:read_line_with_escape)
        assert_nil result, "Escapeキーでキャンセルした場合はnilを返すべき"
      end
    end

    def test_read_line_with_escape_returns_string_on_enter
      # Enterキーが押されたときに入力文字列を返すことをテスト
      inputs = ['t', 'e', 's', 't', "\r"]
      input_index = 0

      STDIN.stub :getch, -> { inputs[input_index].tap { input_index += 1 } } do
        _out, _err = capture_io do
          result = @handler.send(:read_line_with_escape)
          assert_equal "test", result, "Enterキーで入力を確定した場合は文字列を返すべき"
        end
      end
    end

    def test_read_line_with_escape_handles_backspace
      # Backspaceキーで文字を削除できることをテスト
      inputs = ['t', 'e', 's', 't', "\u007F", "\r"]
      input_index = 0

      STDIN.stub :getch, -> { inputs[input_index].tap { input_index += 1 } } do
        _out, _err = capture_io do
          result = @handler.send(:read_line_with_escape)
          assert_equal "tes", result, "Backspaceで最後の文字を削除できるべき"
        end
      end
    end

    def test_create_file_cancelled_with_escape
      # ファイル作成がEscapeでキャンセルされることをテスト
      STDIN.stub :getch, "\e" do
        _out, _err = capture_io do
          result = @file_op_controller.create_file
          assert_equal false, result, "Escapeでキャンセルした場合はfalseを返すべき"
        end
      end

      # ファイルが作成されていないことを確認
      entries = @directory_listing.list_entries
      file_entries = entries.reject { |e| e[:name] == '..' }
      assert_empty file_entries, "キャンセルした場合はファイルが作成されないべき"
    end

    def test_create_directory_cancelled_with_escape
      # ディレクトリ作成がEscapeでキャンセルされることをテスト
      STDIN.stub :getch, "\e" do
        _out, _err = capture_io do
          result = @file_op_controller.create_directory
          assert_equal false, result, "Escapeでキャンセルした場合はfalseを返すべき"
        end
      end

      # ディレクトリが作成されていないことを確認
      entries = @directory_listing.list_entries
      dir_entries = entries.reject { |e| e[:name] == '..' }
      assert_empty dir_entries, "キャンセルした場合はディレクトリが作成されないべき"
    end

    def test_create_file_with_valid_input
      # 正常にファイルが作成されることをテスト
      inputs = ['t', 'e', 's', 't', '.', 't', 'x', 't', "\r", 'y']
      input_index = 0

      STDIN.stub :getch, -> { inputs[input_index].tap { input_index += 1 } } do
        _out, _err = capture_io do
          result = @file_op_controller.create_file
          assert result, "正常にファイルが作成されるべき"
        end
      end

      # ファイルが作成されたことを確認
      test_file = File.join(@test_dir, "test.txt")
      assert File.exist?(test_file), "test.txtが作成されているべき"
    end

    def test_create_directory_with_valid_input
      # 正常にディレクトリが作成されることをテスト
      inputs = ['t', 'e', 's', 't', '_', 'd', 'i', 'r', "\r", 'y']
      input_index = 0

      STDIN.stub :getch, -> { inputs[input_index].tap { input_index += 1 } } do
        _out, _err = capture_io do
          result = @file_op_controller.create_directory
          assert result, "正常にディレクトリが作成されるべき"
        end
      end

      # ディレクトリが作成されたことを確認
      test_dir = File.join(@test_dir, "test_dir")
      assert Dir.exist?(test_dir), "test_dirが作成されているべき"
    end
  end
end
