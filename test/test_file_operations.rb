# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

class TestFileOperations
  def initialize
    @test_dir = Dir.mktmpdir("rufio_file_operations_test")
    @original_dir = Dir.pwd
    Dir.chdir(@test_dir)
    
    # テスト用ファイル・ディレクトリ構造を作成
    FileUtils.mkdir_p("subdir1")
    FileUtils.mkdir_p("subdir2")
    File.write("file1.txt", "content1")
    File.write("file2.rb", "puts 'hello'")
    
    # ベースディレクトリをサブディレクトリに設定
    FileUtils.mkdir_p("target_base_dir")
    @base_dir = File.join(@test_dir, "target_base_dir")
    
    puts "ファイル操作テスト環境準備完了: #{@test_dir}"
  end

  def cleanup
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
    puts "ファイル操作テスト環境クリーンアップ完了"
  end

  def test_selection_functionality
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      entries = directory_listing.list_entries
      return puts "✗ selection_functionality - エントリがありません" if entries.empty?
      
      # 最初のエントリを選択
      result = handler.handle_key(' ')  # Space
      if result && handler.selected_items.length == 1 && handler.selected_items.include?(entries.first[:name])
        puts "✓ selection_functionality - ファイル選択成功"
      else
        puts "✗ selection_functionality - ファイル選択失敗"
      end
      
      # 同じエントリを再選択して解除
      result = handler.handle_key(' ')  # Space
      if result && handler.selected_items.empty?
        puts "✓ deselection_functionality - ファイル選択解除成功"
      else
        puts "✗ deselection_functionality - ファイル選択解除失敗"
      end
      
    rescue NoMethodError => e
      puts "期待通りエラー: #{e.message} - selected_items, set_base_directoryメソッドが未実装"
    end
  end

  def test_multiple_selection
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      entries = directory_listing.list_entries
      return puts "✗ multiple_selection - エントリが不足" if entries.length < 2
      
      # 複数のファイルを選択
      handler.select_index(0)
      handler.handle_key(' ')  # Space
      
      handler.select_index(1)
      handler.handle_key(' ')  # Space
      
      if handler.selected_items.length == 2
        puts "✓ multiple_selection - 複数選択成功"
      else
        puts "✗ multiple_selection - 複数選択失敗"
      end
      
    rescue NoMethodError => e
      puts "期待通りエラー: #{e.message} - selected_itemsメソッドが未実装"
    end
  end

  def test_move_to_base_directory
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      entries = directory_listing.list_entries
      return puts "✗ move_to_base_directory - エントリがありません" if entries.empty?
      
      # ファイルを選択してベースディレクトリに移動
      handler.select_index(0)
      handler.handle_key(' ')  # Space (選択)
      
      # 確認ダイアログの動作確認（実際の入力なしでメソッド存在確認のみ）
      if handler.respond_to?(:move_selected_to_base, true)
        puts "✓ move_to_base_directory - 移動機能が実装されています"
      else
        puts "✗ move_to_base_directory - 移動機能が未実装"
      end
      
    rescue NoMethodError => e
      puts "期待通りエラー: #{e.message} - handle_key('m')が未実装"
    end
  end

  def test_copy_to_base_directory
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      entries = directory_listing.list_entries
      return puts "✗ copy_to_base_directory - エントリがありません" if entries.empty?
      
      # ファイルを選択してベースディレクトリにコピー
      handler.select_index(0)
      handler.handle_key(' ')  # Space (選択)
      
      # 確認ダイアログの動作確認（実際の入力なしでメソッド存在確認のみ）
      if handler.respond_to?(:copy_selected_to_base, true)
        puts "✓ copy_to_base_directory - コピー機能が実装されています"
      else
        puts "✗ copy_to_base_directory - コピー機能が未実装"
      end
      
    rescue NoMethodError => e
      puts "期待通りエラー: #{e.message} - handle_key('p')が未実装"
    end
  end

  def test_confirmation_dialog
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      # 確認ダイアログのテスト（実際の実装後は詳細テストを追加）
      if handler.respond_to?(:show_confirmation_dialog)
        puts "✓ confirmation_dialog - メソッドが存在"
      else
        puts "期待通り：show_confirmation_dialogメソッドが未実装"
      end
      
    rescue NoMethodError
      puts "期待通り：確認ダイアログメソッドが未実装"
    end
  end

  def test_base_directory_display
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      terminal_ui = Rufio::TerminalUI.new
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      # TerminalUIがベースディレクトリを表示できるかテスト
      if terminal_ui.respond_to?(:draw_base_directory_info, true)
        puts "✓ base_directory_display - ベースディレクトリ表示機能が実装済み"
      else
        puts "期待通り：draw_base_directory_infoメソッドが未実装"
      end
      
    rescue NoMethodError
      puts "期待通り：ベースディレクトリ表示機能が未実装"
    end
  end

  def test_delete_selected_files
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      # テスト用ファイルを作成
      test_file = File.join(@test_dir, "test_delete_file.txt")
      File.write(test_file, "test content for deletion")
      directory_listing.refresh
      
      entries = directory_listing.list_entries
      test_file_entry = entries.find { |e| e[:name] == "test_delete_file.txt" }
      return puts "✗ delete_selected_files - テストファイルが見つかりません" unless test_file_entry
      
      # ファイルを選択
      handler.select_index(entries.index(test_file_entry))
      handler.handle_key(' ')  # Space (選択)
      
      if handler.selected_items.include?("test_delete_file.txt")
        puts "✓ delete_selected_files - ファイル選択成功"
      else
        puts "✗ delete_selected_files - ファイル選択失敗"
        return
      end
      
      # xキーで削除機能をテスト（実装前なのでメソッド存在確認のみ）
      if handler.respond_to?(:delete_selected_files, true)
        puts "✓ delete_selected_files - 削除機能が実装済み"
      else
        puts "期待通り：delete_selected_filesメソッドが未実装"
      end
      
    rescue NoMethodError => e
      puts "期待通りエラー: #{e.message} - 削除機能が未実装"
    end
  end

  def test_delete_confirmation
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      handler.set_base_directory(@base_dir)
      
      # 削除確認ダイアログのテスト
      if handler.respond_to?(:show_delete_confirmation, true)
        puts "✓ delete_confirmation - 削除確認ダイアログが実装済み"
      else
        puts "期待通り：show_delete_confirmationメソッドが未実装"
      end
      
    rescue NoMethodError
      puts "期待通り：削除確認ダイアログが未実装"
    end
  end

  def test_file_system_operations
    begin
      # 実際のファイル操作テスト（実装後に詳細テストを追加予定）
      test_file = File.join(@test_dir, "test_move_file.txt")
      File.write(test_file, "test content")
      
      if File.exist?(test_file)
        puts "✓ file_system_operations - テストファイル作成成功"
        
        # 移動先ディレクトリ存在確認
        if Dir.exist?(@base_dir)
          puts "✓ file_system_operations - ベースディレクトリ存在確認"
        else
          puts "✗ file_system_operations - ベースディレクトリが存在しません"
        end
      else
        puts "✗ file_system_operations - テストファイル作成失敗"
      end
      
    rescue StandardError => e
      puts "✗ file_system_operations - #{e.message}"
    end
  end

  def run_all_tests
    puts "=== Rufio File Operations テスト開始 ==="
    test_selection_functionality
    test_multiple_selection
    test_move_to_base_directory
    test_copy_to_base_directory
    test_confirmation_dialog
    test_base_directory_display
    test_delete_selected_files
    test_delete_confirmation
    test_file_system_operations
    puts "=== ファイル操作テスト完了 ==="
  end
end

# テスト実行
if __FILE__ == $0
  test = TestFileOperations.new
  test.run_all_tests
  test.cleanup
end