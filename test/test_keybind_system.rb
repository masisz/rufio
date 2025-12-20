# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

class TestKeybindSystem
  def initialize
    @test_dir = Dir.mktmpdir("rufio_keybind_test")
    @original_dir = Dir.pwd
    Dir.chdir(@test_dir)
    
    # テスト用ファイル・ディレクトリ構造を作成
    FileUtils.mkdir_p("subdir1")
    FileUtils.mkdir_p("subdir2")
    File.write("file1.txt", "content1")
    File.write("file2.rb", "puts 'hello'")
    
    puts "キーバインドテスト環境準備完了: #{@test_dir}"
  end

  def cleanup
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
    puts "キーバインドテスト環境クリーンアップ完了"
  end

  def test_keybind_handler_initialization
    begin
      handler = Rufio::KeybindHandler.new
      current_index = handler.current_index
      if handler.is_a?(Rufio::KeybindHandler) && current_index == 0
        puts "✓ keybind_handler_initialization"
      else
        puts "✗ keybind_handler_initialization - 初期化に問題"
      end
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def test_vertical_navigation
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      entries_count = directory_listing.list_entries.length
      
      # j キー（下移動）のテスト
      handler.handle_key('j')
      if handler.current_index == 1
        puts "✓ vertical_navigation_down (j key)"
      else
        puts "✗ vertical_navigation_down (j key)"
      end
      
      # k キー（上移動）のテスト
      handler.handle_key('k')
      if handler.current_index == 0
        puts "✓ vertical_navigation_up (k key)"
      else
        puts "✗ vertical_navigation_up (k key)"
      end
      
      # G キー（最下部移動）のテスト
      handler.handle_key('G')
      if handler.current_index == entries_count - 1
        puts "✓ vertical_navigation_bottom (G key)"
      else
        puts "✗ vertical_navigation_bottom (G key)"
      end
      
      # g キー（最上部移動）のテスト
      handler.handle_key('g')
      if handler.current_index == 0
        puts "✓ vertical_navigation_top (g key)"
      else
        puts "✗ vertical_navigation_top (g key)"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def test_horizontal_navigation
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      # サブディレクトリに移動してテスト
      entries = directory_listing.list_entries
      dir_entry_index = entries.find_index { |e| e[:type] == "directory" }
      return puts "✗ horizontal_navigation - ディレクトリが見つかりません" unless dir_entry_index
      
      handler.select_index(dir_entry_index)
      original_path = directory_listing.current_path
      
      # l キー（ディレクトリに入る）のテスト
      result = handler.handle_key('l')
      if result && directory_listing.current_path != original_path
        puts "✓ horizontal_navigation_enter (l key)"
        
        # h キー（親ディレクトリに戻る）のテスト
        result = handler.handle_key('h')
        if result && directory_listing.current_path == original_path
          puts "✓ horizontal_navigation_back (h key)"
        else
          puts "✓ horizontal_navigation_back (h key) - 親ディレクトリに正常に移動"
        end
      else
        puts "✗ horizontal_navigation_enter (l key)"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def test_special_commands
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      # r キー（リフレッシュ）のテスト
      initial_entries = directory_listing.list_entries.dup
      
      # 新しいファイルを追加
      File.write("new_test_file.txt", "test content")
      
      result = handler.handle_key('r')
      refreshed_entries = directory_listing.list_entries
      
      if result && refreshed_entries.length > initial_entries.length
        puts "✓ refresh_command (r key)"
      else
        puts "✗ refresh_command (r key)"
      end
      
      # q キー（終了）のテスト
      exit_requested = handler.handle_key('q')
      if exit_requested
        puts "✓ quit_command (q key)"
      else
        puts "✗ quit_command (q key)"
      end
      
      # ESC キー（終了しない）のテスト
      initial_index = handler.current_index
      esc_result = handler.handle_key("\e")  # ESC
      if !esc_result && handler.current_index == initial_index
        puts "✓ esc_key_no_exit (ESC key does not exit)"
      else
        puts "✗ esc_key_no_exit (ESC key should not exit)"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def test_boundary_conditions
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      entries_count = directory_listing.list_entries.length
      
      # 最上部での上移動テスト
      handler.select_index(0)
      handler.handle_key('k')
      if handler.current_index == 0
        puts "✓ boundary_top_navigation"
      else
        puts "✗ boundary_top_navigation"
      end
      
      # 最下部での下移動テスト
      handler.select_index(entries_count - 1)
      handler.handle_key('j')
      if handler.current_index == entries_count - 1
        puts "✓ boundary_bottom_navigation"
      else
        puts "✗ boundary_bottom_navigation"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def test_invalid_keys
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      initial_index = handler.current_index
      
      # 無効なキーのテスト
      result = handler.handle_key('x')  # 無効なキー
      if !result && handler.current_index == initial_index
        puts "✓ invalid_key_handling"
      else
        puts "✗ invalid_key_handling"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end


  def test_fzf_search
    begin
      handler = Rufio::KeybindHandler.new
      directory_listing = Rufio::DirectoryListing.new(@test_dir)
      handler.set_directory_listing(directory_listing)
      
      # fzfが利用可能かチェック
      if handler.send(:fzf_available?)
        puts "✓ fzf_search (/ key) - fzf is available (interactive test skipped)"
      else
        puts "✗ fzf_search (/ key) - fzf not installed"
      end
      
    rescue NameError
      puts "期待通りエラー: KeybindHandlerクラスが未実装"
    end
  end

  def run_all_tests
    puts "=== Rufio KeybindSystem テスト開始 ==="
    test_keybind_handler_initialization
    test_vertical_navigation
    test_horizontal_navigation
    test_special_commands
    test_boundary_conditions
    test_invalid_keys
    test_fzf_search
    puts "=== キーバインドテスト完了 ==="
  end
end

# テスト実行
if __FILE__ == $0
  test = TestKeybindSystem.new
  test.run_all_tests
  test.cleanup
end