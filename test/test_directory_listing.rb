# frozen_string_literal: true

require_relative "test_helper"
require "minitest/test"

class TestDirectoryListing < Minitest::Test
  def setup
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
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_dir)
  end

  def test_directory_listing_initialization
    listing = Rufio::DirectoryListing.new(@test_dir)
    assert_instance_of Rufio::DirectoryListing, listing
    assert_equal @test_dir, listing.current_path
  end

  def test_list_entries
    listing = Rufio::DirectoryListing.new(@test_dir)
    entries = listing.list_entries
    
    assert_instance_of Array, entries
    assert entries.length >= 4  # 少なくとも作成したファイル・ディレクトリが含まれる
    
    # エントリの基本構造をテスト
    entry = entries.find { |e| e[:name] == "file1.txt" }
    refute_nil entry
    assert_equal "file", entry[:type]
    assert_equal "file1.txt", entry[:name]
    assert entry.key?(:size)
    assert entry.key?(:modified)
  end

  def test_identify_file_types
    listing = Rufio::DirectoryListing.new(@test_dir)
    entries = listing.list_entries
    
    # ディレクトリの識別
    dir_entry = entries.find { |e| e[:name] == "subdir1" }
    assert_equal "directory", dir_entry[:type]
    
    # 通常ファイルの識別
    file_entry = entries.find { |e| e[:name] == "file1.txt" }
    assert_equal "file", file_entry[:type]
    
    # 実行ファイルの識別
    exec_entry = entries.find { |e| e[:name] == "executable" }
    assert_equal "executable", exec_entry[:type]
  end

  def test_sort_entries
    listing = Rufio::DirectoryListing.new(@test_dir)
    entries = listing.list_entries
    
    # ディレクトリが最初に来ることを確認
    dir_entries = entries.select { |e| e[:type] == "directory" }
    file_entries = entries.select { |e| e[:type] != "directory" }
    
    # ディレクトリのインデックスがファイルのインデックスより小さいことを確認
    unless dir_entries.empty? || file_entries.empty?
      first_dir_index = entries.index(dir_entries.first)
      first_file_index = entries.index(file_entries.first)
      assert first_dir_index < first_file_index
    end
  end

  def test_navigate_to_directory
    listing = Rufio::DirectoryListing.new(@test_dir)
    
    # サブディレクトリに移動
    result = listing.navigate_to("subdir1")
    assert result
    assert_equal File.join(@test_dir, "subdir1"), listing.current_path
    
    # 存在しないディレクトリに移動を試行
    result = listing.navigate_to("nonexistent")
    refute result
    assert_equal File.join(@test_dir, "subdir1"), listing.current_path  # パスは変わらない
  end

  def test_navigate_to_parent
    listing = Rufio::DirectoryListing.new(@test_dir)
    
    # まずサブディレクトリに移動
    listing.navigate_to("subdir1")
    original_path = listing.current_path
    
    # 親ディレクトリに移動
    result = listing.navigate_to_parent
    assert result
    assert_equal @test_dir, listing.current_path
    
    # ルートディレクトリでの親移動（制限されるべき）
    root_listing = Rufio::DirectoryListing.new("/")
    result = root_listing.navigate_to_parent
    refute result
    assert_equal "/", root_listing.current_path
  end

  def test_refresh
    listing = Rufio::DirectoryListing.new(@test_dir)
    initial_entries = listing.list_entries
    
    # 新しいファイルを追加
    File.write("new_file.txt", "new content")
    
    # リフレッシュ前は新しいファイルが見えない
    entries_before_refresh = listing.list_entries
    assert_equal initial_entries.length, entries_before_refresh.length
    
    # リフレッシュ後は新しいファイルが見える
    listing.refresh
    entries_after_refresh = listing.list_entries
    assert_equal initial_entries.length + 1, entries_after_refresh.length
    
    new_file_entry = entries_after_refresh.find { |e| e[:name] == "new_file.txt" }
    refute_nil new_file_entry
  end
end

# テストを実行
if __FILE__ == $0
  ENV['MT_PLUGINS'] = ""
  require "minitest/autorun"
end