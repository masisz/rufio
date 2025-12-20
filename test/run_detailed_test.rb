# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"
require "fileutils"
require "tmpdir"

# 詳細テストを手動実行
class DetailedTest
  def initialize
    @test_dir = Dir.mktmpdir("rufio_test")
    @original_dir = Dir.pwd
    Dir.chdir(@test_dir)
    
    # テスト用ファイル・ディレクトリ構造を作成
    FileUtils.mkdir_p("subdir1")
    FileUtils.mkdir_p("subdir2/nested")
    File.write("file1.txt", "content1")
    File.write("file2.rb", "puts 'hello'")
    File.write("executable", "#!/bin/bash\necho test")
    File.chmod(0755, "executable")
    
    puts "テスト環境準備完了: #{@test_dir}"
  end

  def cleanup
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
    puts "テスト環境クリーンアップ完了"
  end

  def test_directory_listing_initialization
    listing = Rufio::DirectoryListing.new(@test_dir)
    if listing.is_a?(Rufio::DirectoryListing) && listing.current_path == @test_dir
      puts "✓ directory_listing_initialization"
    else
      puts "✗ directory_listing_initialization"
    end
  end

  def test_list_entries
    listing = Rufio::DirectoryListing.new(@test_dir)
    entries = listing.list_entries
    
    if entries.is_a?(Array) && entries.length >= 4
      entry = entries.find { |e| e[:name] == "file1.txt" }
      if entry && entry[:type] == "file" && entry[:name] == "file1.txt"
        puts "✓ list_entries"
      else
        puts "✗ list_entries - エントリ構造に問題"
      end
    else
      puts "✗ list_entries - 配列サイズに問題"
    end
  end

  def test_identify_file_types
    listing = Rufio::DirectoryListing.new(@test_dir)
    entries = listing.list_entries
    
    dir_entry = entries.find { |e| e[:name] == "subdir1" }
    file_entry = entries.find { |e| e[:name] == "file1.txt" }
    exec_entry = entries.find { |e| e[:name] == "executable" }
    
    if dir_entry&.[](:type) == "directory" && 
       file_entry&.[](:type) == "file" && 
       exec_entry&.[](:type) == "executable"
      puts "✓ identify_file_types"
    else
      puts "✗ identify_file_types"
      puts "  dir: #{dir_entry&.[](:type)}, file: #{file_entry&.[](:type)}, exec: #{exec_entry&.[](:type)}"
    end
  end

  def test_navigate_to_directory
    listing = Rufio::DirectoryListing.new(@test_dir)
    
    result = listing.navigate_to("subdir1")
    if result && listing.current_path == File.join(@test_dir, "subdir1")
      puts "✓ navigate_to_directory"
    else
      puts "✗ navigate_to_directory"
    end
  end

  def test_navigate_to_parent
    listing = Rufio::DirectoryListing.new(@test_dir)
    listing.navigate_to("subdir1")
    
    result = listing.navigate_to_parent
    if result && listing.current_path == @test_dir
      puts "✓ navigate_to_parent"
    else
      puts "✗ navigate_to_parent"
    end
  end

  def run_all_tests
    puts "=== Rufio DirectoryListing 詳細テスト開始 ==="
    test_directory_listing_initialization
    test_list_entries
    test_identify_file_types
    test_navigate_to_directory
    test_navigate_to_parent
    puts "=== テスト完了 ==="
  end
end

# テスト実行
test = DetailedTest.new
test.run_all_tests
test.cleanup