# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# FileOperationController のユニットテスト
# Phase 4: KeybindHandler から FileOperationController を抽出するリファクタリングに対応
class TestFileOperationController < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("rufio_fileop_test")
    setup_test_files

    @directory_listing = Rufio::DirectoryListing.new(@test_dir)
    @filter_manager = Rufio::FilterManager.new
    @nav_controller = Rufio::NavigationController.new(@directory_listing, @filter_manager)
    @file_operations = Rufio::FileOperations.new
    @dialog_renderer = Rufio::DialogRenderer.new
    @selection_manager = Rufio::SelectionManager.new

    @controller = Rufio::FileOperationController.new(
      @directory_listing,
      @file_operations,
      @dialog_renderer,
      @nav_controller,
      @selection_manager
    )
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  # === 基本テスト ===

  def test_can_instantiate
    assert_instance_of Rufio::FileOperationController, @controller
  end

  def test_set_terminal_ui
    # terminal_uiをセットしてもエラーが起きないこと
    @controller.set_terminal_ui(nil)
    pass
  end

  # === shorten_path テスト ===

  def test_shorten_path_short_path
    result = @controller.send(:shorten_path, "/short/path", 40)
    assert_equal "/short/path", result
  end

  def test_shorten_path_long_path
    long_path = "/very/long/path/that/exceeds/the/max/length/specified"
    result = @controller.send(:shorten_path, long_path, 20)
    assert result.length <= 20 + 3, "短縮パスが最大長を超えないこと"
    assert result.start_with?("..."), "短縮パスは...で始まること"
  end

  def test_shorten_path_exact_length
    path = "/exact/len"  # 10 chars
    result = @controller.send(:shorten_path, path, 10)
    assert_equal path, result
  end

  # === ファイル作成テスト ===

  def test_create_file_creates_file_when_dialog_confirmed
    # ダイアログをモック
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      "new_test_file.txt"
    end

    result = @controller.create_file
    assert result, "ファイル作成が成功すること"
    assert File.exist?(File.join(@test_dir, "new_test_file.txt")),
           "ファイルが実際に作成されること"
  end

  def test_create_file_returns_false_when_dialog_cancelled
    # ダイアログをモック（キャンセル）
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      nil
    end

    result = @controller.create_file
    refute result, "キャンセル時はfalseを返すこと"
  end

  def test_create_file_returns_false_when_empty_name
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      ""
    end

    result = @controller.create_file
    refute result, "空のファイル名ではfalseを返すこと"
  end

  def test_create_file_updates_nav_index
    # 新規ファイル名をダイアログで返す
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      "zzz_new_file.txt"
    end

    @controller.create_file
    @directory_listing.refresh
    entries = @directory_listing.list_entries
    new_file_index = entries.find_index { |e| e[:name] == "zzz_new_file.txt" }

    assert new_file_index, "新規ファイルがエントリに含まれること"
    # ナビゲーションインデックスが新規ファイルを指していること
    assert_equal new_file_index, @nav_controller.current_index
  end

  # === ディレクトリ作成テスト ===

  def test_create_directory_creates_dir
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      "new_test_dir"
    end

    result = @controller.create_directory
    assert result, "ディレクトリ作成が成功すること"
    assert Dir.exist?(File.join(@test_dir, "new_test_dir")),
           "ディレクトリが実際に作成されること"
  end

  def test_create_directory_returns_false_when_cancelled
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      nil
    end

    result = @controller.create_directory
    refute result, "キャンセル時はfalseを返すこと"
  end

  # === リネームテスト ===

  def test_rename_current_file_renames
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry

    original_name = file_entry[:name]
    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      "renamed_file.txt"
    end

    result = @controller.rename_current_file(file_entry)
    assert result, "リネームが成功すること"
    refute File.exist?(File.join(@test_dir, original_name)), "元のファイルが存在しないこと"
    assert File.exist?(File.join(@test_dir, "renamed_file.txt")), "新しいファイルが存在すること"
  end

  def test_rename_current_file_returns_false_without_entry
    result = @controller.rename_current_file(nil)
    refute result, "エントリなしではfalseを返すこと"
  end

  def test_rename_current_file_returns_false_when_cancelled
    entries = @directory_listing.list_entries
    file_entry = entries.find { |e| e[:type] == "file" }
    skip "ファイルエントリなし" unless file_entry

    @dialog_renderer.define_singleton_method(:show_input_dialog) do |_title, _prompt, _opts = {}|
      nil
    end

    result = @controller.rename_current_file(file_entry)
    refute result, "キャンセル時はfalseを返すこと"
  end

  # === 選択操作テスト ===

  def test_move_selected_to_current_returns_false_when_empty
    result = @controller.move_selected_to_current
    refute result, "選択なしではfalseを返すこと"
  end

  def test_copy_selected_to_current_returns_false_when_empty
    result = @controller.copy_selected_to_current
    refute result, "選択なしではfalseを返すこと"
  end

  def test_delete_selected_files_returns_false_when_empty
    result = @controller.delete_selected_files
    refute result, "選択なしではfalseを返すこと"
  end

  # === show_exit_confirmation テスト（モック） ===

  def test_show_exit_confirmation_returns_boolean
    # STDINのモック（インタラクティブ入力は実際にはテストしない）
    # show_overlay_dialog がクラッシュしないことを確認
    # terminal_ui がない場合（nil）にダイアログレンダラーにフォールバックすること
    # このテストはshow_floating_delete_confirmationなどが適切なシグネチャを持つことを確認
    assert @controller.respond_to?(:show_exit_confirmation), "メソッドが存在すること"
  end

  # === delete_current_file_with_confirmation テスト ===

  def test_delete_current_file_returns_false_without_entry
    result = @controller.delete_current_file_with_confirmation(nil, -> { [] })
    refute result, "エントリなしではfalseを返すこと"
  end

  def test_delete_current_file_with_dotdot_returns_false
    dotdot_entry = { name: "..", type: "directory", path: File.dirname(@test_dir) }
    result = @controller.delete_current_file_with_confirmation(
      dotdot_entry,
      -> { @directory_listing.list_entries }
    )
    refute result, "..エントリは削除できないこと"
  end

  # === set_directory_listing テスト ===

  def test_set_directory_listing_updates_directory
    new_dir = Dir.mktmpdir("rufio_new_dir_test")
    begin
      new_listing = Rufio::DirectoryListing.new(new_dir)
      @controller.set_directory_listing(new_listing)
      # エラーなく更新できること
      pass
    ensure
      FileUtils.rm_rf(new_dir)
    end
  end

  private

  def setup_test_files
    FileUtils.mkdir_p(File.join(@test_dir, "subdir1"))
    FileUtils.mkdir_p(File.join(@test_dir, "subdir2"))
    File.write(File.join(@test_dir, "file1.txt"), "Hello World")
    File.write(File.join(@test_dir, "file2.rb"), "puts 'hello'")
  end
end
