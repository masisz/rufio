# frozen_string_literal: true

require_relative "test_helper"
require "minitest/autorun"
require "tmpdir"

class TestExitConfirmation < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_exit_test")
    @original_dir = Dir.pwd
    Dir.chdir(@test_dir)

    # テスト用のファイルを作成
    FileUtils.mkdir_p("test_dir")
    File.write("test_file.txt", "test content")
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
  end

  # exit_requestメソッドが'n'入力時にfalseを返すことを確認
  def test_exit_request_returns_false_when_cancelled
    handler = Rufio::KeybindHandler.new
    directory_listing = Rufio::DirectoryListing.new(@test_dir)
    handler.set_directory_listing(directory_listing)

    # DialogRendererとTerminalUIのインスタンスを設定
    dialog_renderer = Rufio::DialogRenderer.new
    terminal_ui = Object.new

    # refresh_displayメソッドを追加
    def terminal_ui.refresh_display; end

    handler.instance_variable_set(:@dialog_renderer, dialog_renderer)
    handler.instance_variable_set(:@terminal_ui, terminal_ui)

    # ユーザー入力をスタブ（'n'を返す = キャンセル）
    STDIN.stub(:getch, 'n') do
      result = handler.send(:exit_request)

      # キャンセルした場合はfalseを返すべき
      assert_equal false, result, "ユーザーが'n'を押したときはfalseを返すべき"
    end
  end

  # ユーザーが'y'を押したときにtrueを返すことを確認
  def test_exit_request_returns_true_when_confirmed
    handler = Rufio::KeybindHandler.new
    directory_listing = Rufio::DirectoryListing.new(@test_dir)
    handler.set_directory_listing(directory_listing)

    # DialogRendererとTerminalUIのインスタンスを設定
    dialog_renderer = Rufio::DialogRenderer.new
    terminal_ui = Object.new

    # refresh_displayメソッドを追加
    def terminal_ui.refresh_display; end

    handler.instance_variable_set(:@dialog_renderer, dialog_renderer)
    handler.instance_variable_set(:@terminal_ui, terminal_ui)

    # ユーザー入力をスタブ（'y'を返す = 確認）
    STDIN.stub(:getch, 'y') do
      result = handler.send(:exit_request)

      # 確認した場合はtrueを返すべき
      assert_equal true, result, "ユーザーが'y'を押したときはtrueを返すべき"
    end
  end

  # ESCキーでキャンセルできることを確認
  def test_exit_request_can_be_cancelled_with_escape
    handler = Rufio::KeybindHandler.new
    directory_listing = Rufio::DirectoryListing.new(@test_dir)
    handler.set_directory_listing(directory_listing)

    # DialogRendererとTerminalUIのインスタンスを設定
    dialog_renderer = Rufio::DialogRenderer.new
    terminal_ui = Object.new

    # refresh_displayメソッドを追加
    def terminal_ui.refresh_display; end

    handler.instance_variable_set(:@dialog_renderer, dialog_renderer)
    handler.instance_variable_set(:@terminal_ui, terminal_ui)

    # ユーザー入力をスタブ（ESCを返す）
    STDIN.stub(:getch, "\e") do
      result = handler.send(:exit_request)

      # ESCでキャンセルした場合はfalseを返すべき
      assert_equal false, result, "ユーザーがESCを押したときはfalseを返すべき"
    end
  end
end
